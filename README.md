\# Student Planner – Ứng dụng quản lý công việc sinh viên



\## 1. Giới thiệu

Student Planner là ứng dụng di động được phát triển bằng Flutter, giúp sinh viên quản lý công việc học tập, theo dõi tiến độ và nhắc nhở thời hạn hoàn thành.



\## 2. Chức năng chính

\- Đăng ký, đăng nhập và đăng xuất bằng Firebase Authentication.

\- Thêm, chỉnh sửa và xóa công việc.

\- Đánh dấu công việc đã hoàn thành.

\- Tìm kiếm và lọc công việc.

\- Thống kê tiến độ hoàn thành công việc.

\- Nhận thông báo nhắc nhở trước hạn hoàn thành.



\## 3. Công nghệ sử dụng

\- Flutter

\- Dart

\- Firebase Authentication

\- Cloud Firestore

\- Local Notifications



\## 4. Cấu trúc lưu trữ dữ liệu

Dữ liệu công việc được lưu trên Cloud Firestore theo từng tài khoản người dùng:



`users/{userId}/tasks/{taskId}`



\## 5. Hướng dẫn cài đặt



Clone dự án:



```bash

git clone https://github.com/dangngoctrung05/student\_planner.git

```



Di chuyển vào thư mục dự án:



```bash

cd student\_planner

```



Cài đặt các thư viện:



```bash

flutter pub get

```



Chạy ứng dụng:



```bash

flutter run

```



\## 6. Mã nguồn

GitHub: https://github.com/dangngoctrung05/student\_planner

