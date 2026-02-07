
import 'dart:ui' show PlatformDispatcher;
import 'package:awesome_notifications/awesome_notifications.dart';

bool _isJa() => PlatformDispatcher.instance.locale.languageCode == 'ja';

String _tx({required String ja, required String en}) => _isJa() ? ja : en;

bool _isJaLocale() {
  // 端末言語で分岐（アプリのLocaleを見たい場合は別途context経由にする）
  final code = PlatformDispatcher.instance.locale.languageCode;
  return code == 'ja';
}

String _t(String ja, String en) => _isJaLocale() ? ja : en;


/// 毎月末の通知（正確に月末を計算）
Future<void> scheduleMonthlyReminderOnLastDay() async {
  final now = DateTime.now();
  final lastDay = DateTime(now.year, now.month + 1, 0); // 翌月1日 - 1日 = 今月末

  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: 1001,
      channelKey: 'basic_channel',
      title: _tx(
        ja: '🧡 今月を振り返りませんか？',
        en: '🧡 Time to reflect on your month?',
      ),
      body: _tx(
        ja: 'AIパートナーからの月次フィードバックを確認してみましょう！',
        en: 'Check your AI partner’s monthly feedback.',
      ),
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
      title: _tx(
        ja: '🧡 今週の振り返りメッセージが届いています',
        en: '🧡 Your weekly reflection is ready',
      ),
      body: _tx(
        ja: 'AIパートナーからの週次コメントを確認してみましょう！',
        en: 'Check your AI partner’s weekly comment.',
      ),
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
Future<void> rescheduleNotifications() async {
  // 既存予約をキャンセル（あなたのIDに合わせて必要分だけ）
  await AwesomeNotifications().cancel(1001);
  await AwesomeNotifications().cancel(1002);

  // 朝/夜もID固定ならここでキャンセル（例）
  // await AwesomeNotifications().cancel(2001);
  // await AwesomeNotifications().cancel(2002);

  // 再予約
  await scheduleMonthlyReminderOnLastDay();
  await scheduleWeeklyReminderOnSunday();

  // 朝/夜も再予約（関数があるなら呼ぶ）
  // await scheduleMorningReminder();
  // await scheduleEveningReminder();
}
