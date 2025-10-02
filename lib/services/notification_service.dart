// lib/services/notification_service.dart
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';

import '../screens/ai_comment_history_screen.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  // ====== NavigatorKey を保持（通知 → 任意画面へ遷移）======
  static GlobalKey<NavigatorState>? _navKey;

  // チャンネルキー（この1箇所のみ）
  static const String _channelKey = 'ai_comments';

  // スケジュールID（重複防止）
  static const int _idWeekly = 900101;
  static const int _idMonthly = 900102;

  // Cold start 時に一旦キューしておく
  static ReceivedAction? _pendingAction;

    // ====== Permission / Safety helpers ======
    /// 通知権限があるか確認し、なければ（許可されれば）要求する
    static Future<bool> _ensureAllowed({bool requestIfDenied = true}) async {
        try {
          final allowed = await AwesomeNotifications().isNotificationAllowed();
          if (allowed) return true;
          if (!requestIfDenied) return false;
          // iOS/Android どちらも OK（ユーザーが拒否したら false）
          return await AwesomeNotifications().requestPermissionToSendNotifications();
        } catch (_) {
          return false;
        }
      }

    /// 例外でアプリが落ちないように包む
    static Future<T?> _safe<T>(Future<T> Function() block) async {
        try {
          return await block();
        } catch (e) {
          dev.log('[notif] ignored error: $e');
          return null;
        }
      }




  /// 初期化：**runApp の前**に1度だけ呼び出す
  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navKey = navigatorKey;

    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: _channelKey,
          channelName: 'AI Comments',
          channelDescription: 'AIコメントの振り返りリマインダー',
          importance: NotificationImportance.High,
        ),
      ],
      debug: kDebugMode,
    );

    // v0.10+ は setListeners を使う
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onActionReceivedMethod,
      onNotificationCreatedMethod: _onCreated,
      onNotificationDisplayedMethod: _onDisplayed,
      onDismissActionReceivedMethod: _onDismissed,
    );
  }

  /// 互換用（既存の main.dart が呼んでいても OK）
  static Future<void> listenNotificationActions(
      GlobalKey<NavigatorState> navigatorKey) async {
    await init(navigatorKey);
  }

  /// kill → 通知タップ起動（cold start）の初回アクションを処理
  /// ※ **runApp の後**で呼ぶ
  static Future<void> handleInitialAction() async {
    final initial = await AwesomeNotifications().getInitialNotificationAction(
      removeFromActionEvents: true,
    );
    final action = initial ?? _pendingAction;
    if (action == null) return;

    _pendingAction = null;
    _goByPayload(action.payload ?? const {});
  }

  // ====================== Listeners ======================

  @pragma('vm:entry-point')
  static Future<void> _onActionReceivedMethod(ReceivedAction action) async {
    dev.log('[notif] onAction route=${action.payload?['route']} tab=${action.payload?['tab']}');

    // Navigator 準備前（runApp 前）は一旦保留
    if (_navKey?.currentState == null) {
      _pendingAction = action;
      return;
    }
    _goByPayload(action.payload ?? const {});
  }

  @pragma('vm:entry-point')
  static Future<void> _onCreated(ReceivedNotification n) async {
    dev.log('[notif] created id=${n.id}');
  }

  @pragma('vm:entry-point')
  static Future<void> _onDisplayed(ReceivedNotification n) async {
    dev.log('[notif] displayed id=${n.id}');
  }

  @pragma('vm:entry-point')
  static Future<void> _onDismissed(ReceivedAction a) async {
    dev.log('[notif] dismissed id=${a.id}');
  }

  // ====================== Navigation ======================

  static void _goByPayload(Map<String, String?> payload) {
    final nav = _navKey?.currentState;
    if (nav == null) return;

    final route = payload['route'] ?? '/history';
    final tab = (payload['tab'] ?? 'daily').toLowerCase();

    // ルート名不一致で失敗しないよう、画面を直接 push
    if (route == '/history') {
      int initialIndex = 0;
      if (tab == 'weekly') initialIndex = 1;
      if (tab == 'monthly') initialIndex = 2;

      nav.push(MaterialPageRoute(
        builder: (_) => AiCommentHistoryScreen(initialTab: initialIndex),
      ));
      return;
    }

    // 万一別ルートを使う場合のフォールバック
    nav.pushNamed(route, arguments: {'initialTab': tab});
  }

  // ====================== デバッグ用 ======================

  /// デバッグ：数秒後にワンショット通知（タップで履歴へ）
  static Future<void> debugOneShotToHistory({
    Duration? delay,
    String tab = 'weekly',
  }) async {
    if (!kDebugMode) return;
    if (!await _ensureAllowed(requestIfDenied: true)) return;
    final d = delay ?? const Duration(seconds: 10);
    Future.delayed(d, () async {
      await _safe(() => AwesomeNotifications().createNotification(
            content: NotificationContent(
              id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
              channelKey: _channelKey,
              title: 'デバッグ通知',
              body: 'タップでAIコメント履歴へ移動',
              payload: {'route': '/history', 'tab': tab},
              category: NotificationCategory.Reminder,
              displayOnForeground: true,
              wakeUpScreen: true,
              autoDismissible: false,
            ),
          ));
    });


  }

  // ====================== スケジュール ======================

  /// 週次（先週の振り返り）…毎週 **月曜 10:00**
  static Future<void> scheduleWeeklyOnMonday10() async {

    if (!await _ensureAllowed(requestIfDenied: true)) return;
    await _safe(() => AwesomeNotifications().cancel(_idWeekly));
    await _safe(() => AwesomeNotifications().createNotification(
          content: NotificationContent(
            id: _idWeekly,
            channelKey: _channelKey,
            title: '週次のAIコメントを確認しましょう',
            body: 'タップで履歴（週次）へ',
            payload: {'route': '/history', 'tab': 'weekly'},
            category: NotificationCategory.Reminder,
          ),
          schedule: NotificationCalendar(
            weekday: DateTime.monday,
            hour: 10,
            minute: 0,
            second: 0,
            repeats: true,
            preciseAlarm: true,
          ),
        ));
  }

  /// 月次（前月の振り返り）…毎月 **1日 10:00**
  static Future<void> scheduleMonthlyOnFirstDay10() async {

  if (!await _ensureAllowed(requestIfDenied: true)) return;
      await _safe(() => AwesomeNotifications().cancel(_idMonthly));
      await _safe(() => AwesomeNotifications().createNotification(
                content: NotificationContent(
                  id: _idMonthly,
                  channelKey: _channelKey,
                  title: '月次のAIコメントを見直しましょう',
                  body: 'タップで履歴（月次）へ',
                  payload: {'route': '/history', 'tab': 'monthly'},
                  category: NotificationCategory.Reminder,
                ),
                schedule: NotificationCalendar(
                  day: 1,
                  hour: 10,
                  minute: 0,
                  second: 0,
                  repeats: true,
                  preciseAlarm: true,
                ),
          ));


  }

  /// 旧スケジュールの残骸がある場合に自分のIDだけ掃除
  static Future<void> clearAiCommentSchedules() async {
    await _safe(() => AwesomeNotifications().cancel(_idWeekly));
    await _safe(() => AwesomeNotifications().cancel(_idMonthly));
  }
}
