import 'package:awesome_notifications/awesome_notifications.dart';

void sendTestNotification() {
  AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: 1,
      channelKey: 'basic_channel',
      title: 'テスト通知',
      body: 'これはiOSでのテスト通知です 🚀',
    ),
  );
}
