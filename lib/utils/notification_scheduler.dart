import 'package:awesome_notifications/awesome_notifications.dart';

/// 毎月末の通知（正確に月末を計算）
Future<void> scheduleMonthlyReminderOnLastDay() async {
  final now = DateTime.now();
  final lastDay = DateTime(now.year, now.month + 1, 0); // 翌月1日 - 1日 = 今月末

  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: 1001,
      channelKey: 'basic_channel',
      title: '🧡 今月を振り返りませんか？',
      body: 'AIパートナーからの月次フィードバックを確認してみましょう！',
      notificationLayout: NotificationLayout.Default,
      actionType: ActionType.Default,
      payload: {"navigate": "home"},
    ),
    schedule: NotificationCalendar(
      year: lastDay.year,
      month: lastDay.month,
      day: lastDay.day,
      hour: 20,
      minute: 0,
      second: 0,
      repeats: true,
    ),
  );
}

/// 毎週日曜の夜に通知
Future<void> scheduleWeeklyReminderOnSunday() async {
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: 1002,
      channelKey: 'basic_channel',
      title: '🧡 今週の振り返りメッセージが届いています',
      body: 'AIパートナーからの週次コメントを確認してみましょう！',
      notificationLayout: NotificationLayout.Default,
      actionType: ActionType.Default,
      payload: {"navigate": "home"},
    ),
    schedule: NotificationCalendar(
      weekday: DateTime.sunday,
      hour: 20,
      minute: 0,
      second: 0,
      repeats: true,
    ),
  );
}
