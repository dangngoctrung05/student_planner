
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'auth_page.dart';
import 'notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.initialize();

  runApp(const StudentPlannerApp());
}

class StudentPlannerApp extends StatelessWidget {
  const StudentPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Student Planner',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6266F1),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7FC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F7FC),
          elevation: 0,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasData) {
            return const PlannerHomePage();
          }

          return const AuthPage();
        },
      ),
    );
  }
}

class Task {
  String? id;
  String title;
  String subject;
  DateTime deadline;
  bool completed;

  Task({
    this.id,
    required this.title,
    required this.subject,
    required this.deadline,
    this.completed = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subject': subject,
      'deadline': deadline,
      'completed': completed,
    };
  }

  factory Task.fromMap(Map<String, dynamic> data, String documentId) {
    return Task(
      id: documentId,
      title: data['title'] ?? '',
      subject: data['subject'] ?? '',
      deadline: (data['deadline'] as dynamic).toDate(),
      completed: data['completed'] ?? false,
    );
  }
}

// Tạo ID thông báo ổn định từ ID công việc trên Firestore.
int taskNotificationId(String taskId) {
  return taskId.codeUnits.fold<int>(
    0,
        (previous, character) =>
    (previous * 31 + character) & 0x7fffffff,
  );
}

class PlannerHomePage extends StatefulWidget {
  const PlannerHomePage({super.key});

  @override
  State<PlannerHomePage> createState() => _PlannerHomePageState();
}

class _PlannerHomePageState extends State<PlannerHomePage> {
  final List<Task> tasks = [];

  final TextEditingController searchController = TextEditingController();

  String filter = 'Tất cả';

  // Đồng bộ thông báo của một công việc.
  Future<void> syncTaskNotification(Task task) async {
    if (task.id == null) return;

    final notificationId = taskNotificationId(task.id!);

    try {
      if (task.completed) {
        await NotificationService.cancelTaskNotification(notificationId);
      } else {
        await NotificationService.scheduleTaskNotification(
          id: notificationId,
          title: task.title,
          deadline: task.deadline,
        );
      }
    } catch (e) {
      debugPrint('Không thể đồng bộ thông báo: $e');
    }
  }

  // Hủy thông báo theo ID công việc.
  Future<void> cancelTaskNotification(String taskId) async {
    try {
      await NotificationService.cancelTaskNotification(
        taskNotificationId(taskId),
      );
    } catch (e) {
      debugPrint('Không thể hủy thông báo: $e');
    }
  }

  // Tải công việc và đồng bộ lại thông báo khi mở ứng dụng.
  Future<void> loadTasks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .get();

      if (!mounted) return;

      final loadedTasks = snapshot.docs.map((doc) {
        return Task.fromMap(doc.data(), doc.id);
      }).toList();

      setState(() {
        tasks
          ..clear()
          ..addAll(loadedTasks);
      });

      // Đồng bộ lịch nhắc cho tất cả công việc.
      for (final task in loadedTasks) {
        await syncTaskNotification(task);
      }
    } catch (e) {
      debugPrint('Không thể tải công việc: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể tải công việc: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    loadTasks();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Task> get filteredTasks {
    return tasks.where((task) {
      final matchesSearch =
          task.title.toLowerCase().contains(
            searchController.text.toLowerCase(),
          ) ||
              task.subject.toLowerCase().contains(
                searchController.text.toLowerCase(),
              );

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final deadlineDate = DateTime(
        task.deadline.year,
        task.deadline.month,
        task.deadline.day,
      );

      final isOverdue =
          !task.completed && deadlineDate.isBefore(today);

      final matchesFilter =
          filter == 'Tất cả' ||
              (filter == 'Chưa xong' && !task.completed) ||
              (filter == 'Hoàn thành' && task.completed) ||
              (filter == 'Quá hạn' && isOverdue);

      return matchesSearch && matchesFilter;
    }).toList()
      ..sort((a, b) => a.deadline.compareTo(b.deadline));
  }

  String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // Thêm công việc.
  Future<void> addTask() async {
    final result = await showDialog<Task>(
      context: context,
      builder: (_) => const AddTaskDialog(),
    );

    if (!mounted || result == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .add(result.toMap());

      // Gán ID Firestore cho công việc để quản lý thông báo.
      result.id = doc.id;

      await syncTaskNotification(result);

      await loadTasks();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã thêm công việc thành công'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể thêm công việc: $e')),
      );
    }
  }

  // Thay đổi trạng thái hoàn thành.
  Future<void> updateTaskStatus(Task task, bool value) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || task.id == null) return;

    final oldValue = task.completed;

    setState(() {
      task.completed = value;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(task.id)
          .update({'completed': value});

      await syncTaskNotification(task);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        task.completed = oldValue;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể cập nhật trạng thái: $e'),
        ),
      );
    }
  }

  // Xóa công việc.
  Future<void> deleteTask(Task task) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || task.id == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(task.id)
          .delete();

      await cancelTaskNotification(task.id!);

      if (!mounted) return;

      setState(() {
        tasks.remove(task);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã xóa công việc'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể xóa công việc: $e')),
      );
    }
  }

  // Chỉnh sửa công việc.
  Future<void> editTask(Task task) async {
    final result = await showDialog<Task>(
      context: context,
      builder: (_) => AddTaskDialog(task: task),
    );

    if (!mounted || result == null) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null || task.id == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .doc(task.id)
          .update(result.toMap());

      // Giữ nguyên ID của công việc.
      result.id = task.id;

      // Đồng bộ lại lịch thông báo theo thông tin mới.
      await syncTaskNotification(result);

      await loadTasks();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã cập nhật công việc thành công'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể cập nhật công việc: $e'),
        ),
      );
    }
  }
  Future<void> openNotificationSettings() async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cài đặt thông báo'),
        content: const Text(
          'Kiểm tra khả năng gửi thông báo của Student Planner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.notifications_active),
            label: const Text('Gửi thông báo thử'),
            onPressed: () async {
              Navigator.pop(dialogContext);

              try {
                await NotificationService.showTestNotification();

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã gửi thông báo thử!'),
                  ),
                );
              } catch (e) {
                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lỗi gửi thông báo: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completed = tasks.where((task) => task.completed).length;
    final total = tasks.length;
    final progress = total == 0 ? 0.0 : completed / total;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7FC),
        title: const Row(
          children: [
            Icon(
              Icons.school_rounded,
              color: Color(0xFF6266F1),
              size: 30,
            ),
            SizedBox(width: 10),
            Text(
              'Student Planner',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cài đặt thông báo',
            icon: const Icon(
              Icons.settings_outlined,
              color: Color(0xFF5267E8),
            ),
            onPressed: openNotificationSettings,
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(
              Icons.logout,
              color: Color(0xFF5267E8),
            ),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addTask,
        icon: const Icon(Icons.add),
        label: const Text('Thêm công việc'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Xin chào, sinh viên! 👋',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Lên kế hoạch tốt, học tập hiệu quả hơn.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 22),

            // Thẻ tiến độ.

            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF5146D8),
                    Color(0xFF7168F5),
                    Color(0xFF9298FF),
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7168F5).withOpacity(0.25),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 9),
                      const Text(
                        'TIẾN ĐỘ CÔNG VIỆC',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        '$completed/$total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 11,
                      backgroundColor: Colors.white.withOpacity(0.25),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Cố gắng hoàn thành mục tiêu hôm nay nhé!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),


            const SizedBox(height: 18),

            // Các thẻ thống kê.

            Row(
              children: [
                Expanded(
                  child: _statCard(
                    'Tổng việc',
                    '$total',
                    Icons.assignment_outlined,
                    const Color(0xFF6266F1),
                    const Color(0xFFEEEEFF),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    'Chưa xong',
                    '${total - completed}',
                    Icons.pending_actions_rounded,
                    const Color(0xFFE99A36),
                    const Color(0xFFFFF3E3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    'Đã xong',
                    '$completed',
                    Icons.task_alt_rounded,
                    const Color(0xFF21A67A),
                    const Color(0xFFE4F7EF),
                  ),
                ),
              ],
            ),


            const SizedBox(height: 26),

            const Text(
              'Danh sách công việc',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 14),

            // Tìm kiếm.
            TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Tìm tên công việc hoặc môn học...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Bộ lọc công việc.
            Wrap(
              spacing: 8,
              children: [
                'Tất cả',
                'Chưa xong',
                'Hoàn thành',
                'Quá hạn',
              ].map((item) {
                return ChoiceChip(
                  label: Text(item),
                  selected: filter == item,
                  onSelected: (_) {
                    setState(() {
                      filter = item;
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            if (filteredTasks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('Không tìm thấy công việc nào.'),
                ),
              ),

            ...filteredTasks.map((task) {
              final now = DateTime.now();

              final today = DateTime(
                now.year,
                now.month,
                now.day,
              );

              final deadlineDate = DateTime(
                task.deadline.year,
                task.deadline.month,
                task.deadline.day,
              );

              final isOverdue =
                  !task.completed && deadlineDate.isBefore(today);


              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: task.completed
                        ? const Color(0xFFE4F3EC)
                        : const Color(0xFFEEEEF5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.035),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 110,
                      decoration: BoxDecoration(
                        color: task.completed
                            ? const Color(0xFF21A67A)
                            : isOverdue
                            ? Colors.redAccent
                            : const Color(0xFF7168F5),
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(22),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: task.completed,
                              activeColor: const Color(0xFF21A67A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                              onChanged: (value) async {
                                if (value == null) return;
                                await updateTaskStatus(task, value);
                              },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    task.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      decoration: task.completed
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                      color: task.completed
                                          ? Colors.grey
                                          : const Color(0xFF25263A),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.menu_book_rounded,
                                        size: 14,
                                        color: Color(0xFF85859A),
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          task.subject,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF85859A),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_month_rounded,
                                        size: 14,
                                        color: isOverdue
                                            ? Colors.redAccent
                                            : const Color(0xFF85859A),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        formatDate(task.deadline),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isOverdue
                                              ? Colors.redAccent
                                              : const Color(0xFF85859A),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isOverdue || task.completed) ...[
                                    const SizedBox(height: 7),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: task.completed
                                            ? const Color(0xFFE4F7EF)
                                            : const Color(0xFFFFEEEE),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        task.completed ? 'ĐÃ HOÀN THÀNH' : 'QUÁ HẠN',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: task.completed
                                              ? const Color(0xFF21A67A)
                                              : Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                color: Color(0xFF85859A),
                              ),
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await editTask(task);
                                } else if (value == 'delete') {
                                  await deleteTask(task);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 19),
                                      SizedBox(width: 9),
                                      Text('Chỉnh sửa'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                        size: 19,
                                      ),
                                      SizedBox(width: 9),
                                      Text('Xóa công việc'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 70),
          ],
        ),
      ),
    );
  }


  Widget _statCard(
      String label,
      String value,
      IconData icon,
      Color color,
      Color backgroundColor,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 17,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: color,
              size: 23,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class AddTaskDialog extends StatefulWidget {
  final Task? task;

  const AddTaskDialog({super.key, this.task});

  @override
  State<AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<AddTaskDialog> {
  final titleController = TextEditingController();
  final subjectController = TextEditingController();

  DateTime deadline = DateTime.now().add(
    const Duration(days: 1),
  );

  @override
  void initState() {
    super.initState();

    final task = widget.task;

    if (task != null) {
      titleController.text = task.title;
      subjectController.text = task.subject;
      deadline = task.deadline;
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    subjectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.task == null
            ? 'Thêm công việc'
            : 'Chỉnh sửa công việc',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Tên công việc',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: subjectController,
              decoration: const InputDecoration(
                labelText: 'Môn học',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: Text(
                'Hạn: ${deadline.day}/${deadline.month}/${deadline.year}',
              ),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: deadline,
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2035),
                );

                if (picked != null && mounted) {
                  setState(() {
                    deadline = picked;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Hủy'),
        ),

        FilledButton(
          onPressed: () {
            final title = titleController.text.trim();
            final subject = subjectController.text.trim();

            if (title.isEmpty || subject.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Vui lòng nhập tên công việc và môn học.',
                  ),
                ),
              );
              return;
            }

            Navigator.of(context).pop(
              Task(
                title: title,
                subject: subject,
                deadline: deadline,
              ),
            );
          },
          child: Text(
            widget.task == null ? 'Thêm' : 'Lưu thay đổi',
          ),
        ),
      ],
    );
  }
}
