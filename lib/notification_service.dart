
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(settings);

    await _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // Gửi thông báo thử ngay lập tức.
  static Future<void> showTestNotification() async {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'student_planner_channel',
      'Student Planner',
      channelDescription: 'Thông báo nhắc hạn công việc',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      999999,
      'Student Planner',
      'Thông báo thử đã hoạt động thành công!',
      details,
    );
  }

  // Nhắc trước hạn công việc 1 ngày lúc 8 giờ sáng.
  static Future<void> scheduleTaskNotification({
    required int id,
    required String title,
    required DateTime deadline,
  }) async {
    final reminderDate = DateTime(
      deadline.year,
      deadline.month,
      deadline.day,
    ).subtract(const Duration(days: 1));

    final reminderTime = tz.TZDateTime(
      tz.local,
      reminderDate.year,
      reminderDate.month,
      reminderDate.day,
      8,
    );

    if (!reminderTime.isAfter(tz.TZDateTime.now(tz.local))) {
      return;
    }

    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'student_planner_channel',
      'Student Planner',
      channelDescription: 'Thông báo nhắc hạn công việc',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.zonedSchedule(
      id,
      'Nhắc nhở công việc',
      'Ngày mai đến hạn: $title',
      reminderTime,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  // Hủy thông báo của công việc.
  static Future<void> cancelTaskNotification(int id) async {
    await _notifications.cancel(id);
  }
}
