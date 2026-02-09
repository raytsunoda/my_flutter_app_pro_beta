// lib/services/notification_service.dart
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import '../screens/ai_comment_history_screen.dart';
import 'dart:ui' show PlatformDispatcher; // ★追加

// ★追加：端末言語で出し分け（context不要）
// bool _isJa() => PlatformDispatcher.instance.locale.languageCode == 'ja';
// String _tx({required String ja, required String en}) => _isJa() ? ja : en;
// 端末言語ではなく「アプリが決めた言語コード」で出し分け
bool _isJaCode(String? code) => (code ?? 'ja').toLowerCase().startsWith('ja');

String _txByCode({
  required String? localeCode,
  required String ja,
  required String en,
}) =>
    _isJaCode(localeCode) ? ja : en;

// 互換用：既存コードが _tx(...) を呼んでも落ちないようにする
// ※ここは端末言語で分岐（週次/月次は schedule 側で localeCode を渡すので英語化は維持）
String _tx({required String ja, required String en}) => _txByCode(
  localeCode: PlatformDispatcher.instance.locale.languageCode,
  ja: ja,
  en: en,
);





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
  /// 通知権限があるか確認し、必要なら要求する
  static Future<bool> _ensureAllowed({bool requestIfDenied = false}) async {
    try {
      final allowed = await AwesomeNotifications().isNotificationAllowed();
      if (allowed) return true;
      if (!requestIfDenied) return false;

      // ユーザー操作から呼ばれた場合だけダイアログを出す
      return await AwesomeNotifications()
          .requestPermissionToSendNotifications();
    } catch (_) {
      return false;
    }
  }
  /// 設定画面のボタンなど「ユーザー操作」からだけ呼ぶことを想定
  static Future<bool> requestPermissionFromUser() async {
    return _ensureAllowed(requestIfDenied: true);
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
          channelDescription: _tx(
            ja: 'AIコメントの振り返りリマインダー',
            en: 'Reminders to review your AI comments',
          ),
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

    // ★ 0) payloadが空なら「履歴」ではなく「ホーム」に倒す（事故防止）
    if (payload.isEmpty) {
      nav.pushNamedAndRemoveUntil('/', (r) => false);
      return;
    }

    // ★ 1) 新形式：navigate/target/tab を優先処理（朝/夕がこれ）
    final navigate = (payload['navigate'] ?? '').toLowerCase().trim();
    if (navigate.isNotEmpty) {
      switch (navigate) {
        case 'home':
          nav.pushNamedAndRemoveUntil('/', (r) => false);
          return;

        case 'nav':
          final target = (payload['target'] ?? '').toLowerCase().trim();

          // ✅ ルート未定義事故を避ける：必ずホーム('/')へ戻す
          // nav.pushNamedAndRemoveUntil(
          //   '/',
          //       (r) => false,
          //   arguments: {'target': target},
          // );
           nav.pushNamedAndRemoveUntil(
                 '/nav',
                 (r) => false,
                 arguments: {'target': target},
               );
          return;


        case 'history':
          final tab = (payload['tab'] ?? 'daily').toLowerCase().trim();
          int initialIndex = 0;
          if (tab == 'weekly') initialIndex = 1;
          if (tab == 'monthly') initialIndex = 2;
          nav.push(MaterialPageRoute(
            builder: (_) => AiCommentHistoryScreen(initialTab: initialIndex),
          ));
          return;

        default:
        // 不明ならホームへ
          nav.pushNamedAndRemoveUntil('/', (r) => false);
          return;
      }
    }

    // ★ 2) 旧形式：route/tab（週次・月次がこれ）
    final route = (payload['route'] ?? '').trim();
    final tab = (payload['tab'] ?? 'daily').toLowerCase().trim();

    // route が無いならホーム
    if (route.isEmpty) {
      nav.pushNamedAndRemoveUntil('/', (r) => false);
      return;
    }

    if (route == '/history') {
      int initialIndex = 0;
      if (tab == 'weekly') initialIndex = 1;
      if (tab == 'monthly') initialIndex = 2;
      nav.push(MaterialPageRoute(
        builder: (_) => AiCommentHistoryScreen(initialTab: initialIndex),
      ));
      return;
    }

    nav.pushNamed(route, arguments: {'initialTab': tab});
  }


  // ====================== デバッグ用 ======================

  /// デバッグ：数秒後にワンショット通知（タップで履歴へ）
  static Future<void> debugOneShotToHistory({
    Duration? delay,
    String tab = 'weekly',
  }) async {
    if (!kDebugMode) return;
    if (!await _ensureAllowed(requestIfDenied: false)) return;
    final d = delay ?? const Duration(seconds: 10);
    Future.delayed(d, () async {
      await _safe(() => AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
          channelKey: _channelKey,
          title: _tx(ja: 'デバッグ通知', en: 'Debug notification'),
          body: _tx(ja: 'タップでAIコメント履歴へ移動', en: 'Tap to open AI comment history'),
          payload: {'route': '/history', 'tab': tab},
          category: NotificationCategory.Reminder,
          displayOnForeground: true,
          wakeUpScreen: true,
          autoDismissible: false,
        ),
      ));
    });
  }

  // ==============================
// Debug one-shot notifications
// ==============================

  static Future<void> debugFireWeeklyNow({required String localeCode}) async {
    await _debugFireNow(
      id: 99901,
      localeCode: localeCode,
      titleJa: '【テスト】週次のAIコメントを確認しましょう',
      titleEn: '[TEST] Your weekly AI comment is ready',
      bodyJa: 'タップで履歴（週次）へ',
      bodyEn: 'Tap to open history (Weekly)',
      payload: {'route': '/history', 'tab': 'weekly'},
    );
  }

  static Future<void> debugFireMonthlyNow({required String localeCode}) async {
    await _debugFireNow(
      id: 99902,
      localeCode: localeCode,
      titleJa: '【テスト】月次のAIコメントを見直しましょう',
      titleEn: '[TEST] Your monthly AI comment is ready',
      bodyJa: 'タップで履歴（月次）へ',
      bodyEn: 'Tap to open history (Monthly)',
      payload: {'route': '/history', 'tab': 'monthly'},
    );
  }

  /// Morning reminder (daily input) - payloadはあなたの既存ルーティングに合わせて調整可
  static Future<void> debugFireMorningNow({required String localeCode}) async {
    await _debugFireNow(
      id: 99903,
      localeCode: localeCode,
      titleJa: '【テスト】記録の時間です',
      titleEn: '[TEST] Time to log your day',
      bodyJa: 'タップして「毎日の入力」へ',
      bodyEn: 'Tap to open Daily Input',
      payload: {'route': '/daily_input'},
    );
  }

  /// Evening reminder (tips/quotes etc.) - payloadはあなたの既存ルーティングに合わせて調整可
  static Future<void> debugFireEveningNow({required String localeCode}) async {
    await _debugFireNow(
      id: 99904,
      localeCode: localeCode,
      titleJa: '【テスト】ヒント/名言をチェック',
      titleEn: '[TEST] Check a tip/quote',
      bodyJa: 'タップして開きます',
      bodyEn: 'Tap to open',
      payload: {'route': '/home'}, // 迷う場合は home に着地が安全
    );
  }

  static Future<void> _debugFireNow({
    required int id,
    required String localeCode,
    required String titleJa,
    required String titleEn,
    required String bodyJa,
    required String bodyEn,
    required Map<String, String> payload,
  }) async {
    // 権限が無ければ何もしない（テストなので requestIfDenied=false）
    if (!await _ensureAllowed(requestIfDenied: false)) return;

    await _safe(() => AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: _channelKey,
        title: _txByCode(localeCode: localeCode, ja: titleJa, en: titleEn),
        body: _txByCode(localeCode: localeCode, ja: bodyJa, en: bodyEn),
        payload: payload,
        category: NotificationCategory.Reminder,
      ),
      // 3秒後に1回だけ
      schedule: NotificationInterval(
        interval: const Duration(seconds: 3),
        repeats: false,
        preciseAlarm: true,
      ),
    ));
  }



  // ====================== スケジュール ======================

  /// 週次（先週の振り返り）…毎週 **月曜 10:00**
  static Future<void> scheduleWeeklyOnMonday10({required String localeCode}) async {
    if (!await _ensureAllowed(requestIfDenied: false)) return;

    await _safe(() => AwesomeNotifications().cancel(_idWeekly));
    await _safe(() => AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _idWeekly,
        channelKey: _channelKey,
        title: _txByCode(
          localeCode: localeCode,
          ja: '週次のAIコメントを確認しましょう',
          en: 'Your weekly AI comment is ready',
        ),
        body: _txByCode(
          localeCode: localeCode,
          ja: 'タップで履歴（週次）へ',
          en: 'Tap to open history (Weekly)',
        ),
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

  static Future<void> scheduleMonthlyOnFirstDay10({required String localeCode}) async {
    if (!await _ensureAllowed(requestIfDenied: false)) return;

    await _safe(() => AwesomeNotifications().cancel(_idMonthly));
    await _safe(() => AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _idMonthly,
        channelKey: _channelKey,
        title: _txByCode(
          localeCode: localeCode,
          ja: '月次のAIコメントを見直しましょう',
          en: 'Your monthly AI comment is ready',
        ),
        body: _txByCode(
          localeCode: localeCode,
          ja: 'タップで履歴（月次）へ',
          en: 'Tap to open history (Monthly)',
        ),
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
