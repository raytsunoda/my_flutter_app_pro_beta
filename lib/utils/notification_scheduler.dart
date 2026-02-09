// lib/utils/notification_scheduler.dart
import 'dart:developer' as dev;
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';

class NotificationScheduler {
  NotificationScheduler._();

  static const String _channelKey = 'basic_channel';

  static bool _isJaByCode(String? code) => (code ?? 'ja').toLowerCase().startsWith('ja');
  static String _tx(String? code, {required String ja, required String en}) {
    return _isJaByCode(code) ? ja : en;
  }

  /// 共通：毎日指定時刻（repeats=true）で作る。payloadも必ず入れる。
  static Future<void> _scheduleDailyAt({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
    required Map<String, String> payload,
  }) async {
    // 古いpayload事故防止：同じIDは必ず消してから作る
    await AwesomeNotifications().cancel(id);

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: _channelKey,
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
        actionType: ActionType.Default,
        payload: payload,
      ),
      schedule: NotificationCalendar(
        hour: time.hour,
        minute: time.minute,
        second: 0,
        repeats: true,
      ),
    );
  }

  /// ✅ 朝（入力へ）
  static Future<void> scheduleMorningReminder({required String appLocaleCode}) async {
    final prefs = await SharedPreferences.getInstance();
    final h = prefs.getInt('morning_hour') ?? 8;
    final m = prefs.getInt('morning_minute') ?? 0;

    await _scheduleDailyAt(
      id: 1,
      time: TimeOfDay(hour: h, minute: m),
      title: _tx(appLocaleCode, ja: 'おはようございます☀️', en: 'Good morning ☀️'),
      body: _tx(appLocaleCode, ja: '今日の記録✏️をつけましょう', en: 'Let’s log today ✏️'),
      payload: const {
        'navigate': 'nav',
        'target': 'input',
      },
    );
  }

  /// ✅ 夕（日本語=tips / 英語=home）
  static Future<void> scheduleEveningReminder({required String appLocaleCode}) async {
    final prefs = await SharedPreferences.getInstance();
    final h = prefs.getInt('evening_hour') ?? 20;
    final m = prefs.getInt('evening_minute') ?? 0;

    final target = _isJaByCode(appLocaleCode) ? 'tips' : 'home';

    await _scheduleDailyAt(
      id: 2,
      time: TimeOfDay(hour: h, minute: m),
      title: _tx(appLocaleCode, ja: '今日も1日お疲れ様でした🌙', en: 'Great job today 🌙'),
      body: _tx(
        appLocaleCode,
        ja: '気持ちを整えるヒント💡をチェックしてみませんか？',
        en: 'Want a quick tip to unwind? 💡',
      ),
      payload: {
        'navigate': 'nav',
        'target': target,
      },
    );
  }

  /// ✅ 朝/夕をまとめて再予約（アプリlocaleを渡す）
  static Future<void> rescheduleMorningEvening({required String appLocaleCode}) async {
    // 権限チェック（ここで落ちないようにする）
    final allowed = await AwesomeNotifications().isNotificationAllowed();
    if (!allowed) {
      dev.log('[notif] permission not allowed, skip morning/evening schedule');
      return;
    }

    await scheduleMorningReminder(appLocaleCode: appLocaleCode);
    await scheduleEveningReminder(appLocaleCode: appLocaleCode);
  }

  /// ✅ 全通知を再予約（設定の「通知を再予約する」ボタン用）
  /// - 朝/夕：basic_channel
  /// - 週次/月次：NotificationService 側（ai_comments チャンネル）
  static Future<void> rescheduleAll({required String appLocaleCode}) async {
    await rescheduleMorningEvening(appLocaleCode: appLocaleCode);

    // AI履歴（週次/月次）も再予約：main側で確定した appLocaleCode をそのまま使う
    await NotificationService.clearAiCommentSchedules();
    await NotificationService.scheduleWeeklyOnMonday10(localeCode: appLocaleCode);
    await NotificationService.scheduleMonthlyOnFirstDay10(localeCode: appLocaleCode);
  }


}

/// ------------------------------------------------------------
/// 互換ラッパ（既存コードが呼んでいる名前を残して “未定義エラー” を消す）
/// ※ 徐々に NotificationScheduler.xxx に置き換えてOK
/// ------------------------------------------------------------
Future<void> scheduleMorningReminder({required String appLocaleCode}) =>
    NotificationScheduler.scheduleMorningReminder(appLocaleCode: appLocaleCode);

Future<void> scheduleEveningReminder({required String appLocaleCode}) =>
    NotificationScheduler.scheduleEveningReminder(appLocaleCode: appLocaleCode);

Future<void> rescheduleNotifications({required String appLocaleCode}) =>
    NotificationScheduler.rescheduleAll(appLocaleCode: appLocaleCode);
