// lib/services/notification_service.dart
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import '../screens/ai_comment_history_screen.dart';
import 'dart:ui' show PlatformDispatcher; // ★追加
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        // } catch (e) {
        //   dev.log('[notif] ignored error: $e');
        } catch (e, st) {
          print('[notif] ignored error: $e');
          print('[notif] stack: $st');

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
          defaultRingtoneType: DefaultRingtoneType.Notification,
        ),
        NotificationChannel(
          channelKey: 'basic_channel',
          channelName: '基本通知',
          channelDescription: '一般的なお知らせ用',
          importance: NotificationImportance.High,
          defaultRingtoneType: DefaultRingtoneType.Notification,
        ),
      ],
      debug: kDebugMode,
    );


    // v0.10+ は setListeners を使う
    await AwesomeNotifications().setListeners(
      onActionReceivedMethod: onActionReceivedMethod,
      onNotificationCreatedMethod: onCreated,
      onNotificationDisplayedMethod: onDisplayed,
      onDismissActionReceivedMethod: onDismissed,
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
    print('[notif] handleInitialAction called');

    final initial = await AwesomeNotifications().getInitialNotificationAction(
      removeFromActionEvents: true,
    );

    print('[notif] initial action payload=${initial?.payload}');
    print('[notif] pending action payload=${_pendingAction?.payload}');

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'last_initial_action_payload',
      initial?.payload.toString() ?? '(null)',
    );
    await prefs.setString(
      'last_initial_action_route',
      initial?.payload?['route'] ?? '',
    );
    await prefs.setString(
      'last_initial_action_tab',
      initial?.payload?['tab'] ?? '',
    );
    await prefs.setString(
      'last_initial_action_checked_at',
      DateTime.now().toIso8601String(),
    );
    await prefs.setString(
      'last_pending_action_payload',
      _pendingAction?.payload.toString() ?? '(null)',
    );

    final action = initial ?? _pendingAction;
    if (action == null) {
      print('[notif] no initial/pending action');
      return;
    }

    _pendingAction = null;
    _goByPayload(action.payload ?? const {});
  }

  // ====================== Listeners ======================

  @pragma('vm:entry-point')
  static Future<void> onActionReceivedMethod(ReceivedAction action) async {
    print('[notif] onAction route=${action.payload?['route']} tab=${action.payload?['tab']}');
    print('[notif] onAction payload=${action.payload}');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_notification_payload', action.payload.toString());
    await prefs.setString('last_notification_route', action.payload?['route'] ?? '');
    await prefs.setString('last_notification_tab', action.payload?['tab'] ?? '');
    await prefs.setString('last_notification_tapped_at', DateTime.now().toIso8601String());


    // Navigator 準備前（runApp 前）は一旦保留
    if (_navKey?.currentState == null) {
      print('[notif] nav not ready, pending action saved');
      _pendingAction = action;
      return;
    }
    _goByPayload(action.payload ?? const {});
  }

  @pragma('vm:entry-point')
  static Future<void> onCreated(ReceivedNotification n) async {
    dev.log('[notif] created id=${n.id}');
  }

  @pragma('vm:entry-point')
  static Future<void> onDisplayed(ReceivedNotification n) async {
    print('[notif] displayed id=${n.id}');
  }

  @pragma('vm:entry-point')
  static Future<void> onDismissed(ReceivedAction a) async {
    dev.log('[notif] dismissed id=${a.id}');
  }

  // ====================== Navigation ======================

  /// DEV用：通知payload遷移をアプリ内から直接テストする
  static void debugGoByPayloadForTest({
    required String tab,
  }) {
    print('[notif-test] debugGoByPayloadForTest tab=$tab');

    _goByPayload({
      'route': '/history',
      'tab': tab,
    });
  }

  static Future<bool> debugConsumeWeeklyDateFallbackForTest() async {
    if (kReleaseMode) return false;

    print('[notif-test] debugConsumeWeeklyDateFallbackForTest');

    _goByPayload({
      'route': '/history',
      'tab': 'weekly',
    });

    return true;
  }

  static Future<bool> debugConsumeMonthlyDateFallbackForTest() async {
    if (kReleaseMode) return false;

    print('[notif-test] debugConsumeMonthlyDateFallbackForTest');

    _goByPayload({
      'route': '/history',
      'tab': 'monthly',
    });

    return true;
  }




  static void _goByPayload(Map<String, String?> payload) {
    print('[notif] _goByPayload payload=$payload');

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

        case 'history':
          final tab = (payload['tab'] ?? 'daily').toLowerCase().trim();
          int initialIndex = 0;
          if (tab == 'weekly') initialIndex = 1;
          if (tab == 'monthly') initialIndex = 2;

          print('[notif] navigate history(new format) initialIndex=$initialIndex');

          WidgetsBinding.instance.addPostFrameCallback((_) {
            final currentNav = _navKey?.currentState;
            if (currentNav == null) {
              print('[notif] navigation failed: nav is null after frame');
              return;
            }

            currentNav.push(
              MaterialPageRoute(
                builder: (_) => AiCommentHistoryScreen(initialTab: initialIndex),
              ),
            );
          });

          return;

        // case 'history':
        //   final tab = (payload['tab'] ?? 'daily').toLowerCase().trim();
        //   int initialIndex = 0;
        //   if (tab == 'weekly') initialIndex = 1;
        //   if (tab == 'monthly') initialIndex = 2;
        //   nav.push(MaterialPageRoute(
        //     builder: (_) => AiCommentHistoryScreen(initialTab: initialIndex),
        //   ));
        //   return;

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

      print('[notif] navigate to history initialIndex=$initialIndex');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentNav = _navKey?.currentState;
        if (currentNav == null) {
          print('[notif] navigation failed: nav is null after frame');
          return;
        }

        currentNav.push(
          MaterialPageRoute(
            builder: (_) => AiCommentHistoryScreen(initialTab: initialIndex),
          ),
        );
      });

      return;
    }

    nav.pushNamed(route, arguments: {'initialTab': tab});
  }


  static const String _fallbackRouteKey = 'pending_notification_route';
  static const String _fallbackTabKey = 'pending_notification_tab';
  static const String _fallbackUntilKey = 'pending_notification_until';

  static Future<void> _saveNotificationFallback({
    required String route,
    required String tab,
    required DateTime validUntil,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_fallbackRouteKey, route);
    await prefs.setString(_fallbackTabKey, tab);
    await prefs.setString(_fallbackUntilKey, validUntil.toIso8601String());

    print('[notif] saved fallback route=$route tab=$tab until=$validUntil');
  }

  static Future<bool> consumeNotificationFallbackIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    final route = prefs.getString(_fallbackRouteKey);
    final tab = prefs.getString(_fallbackTabKey);
    final untilText = prefs.getString(_fallbackUntilKey);

    print('[notif] fallback check route=$route tab=$tab until=$untilText');

    if (route == null || route.isEmpty || tab == null || tab.isEmpty || untilText == null) {
      return false;
    }

    final until = DateTime.tryParse(untilText);
    if (until == null) {
      return false;
    }

    final now = DateTime.now();
    if (now.isAfter(until)) {
      print('[notif] fallback expired');

      await prefs.remove(_fallbackRouteKey);
      await prefs.remove(_fallbackTabKey);
      await prefs.remove(_fallbackUntilKey);

      return false;
    }

    await prefs.remove(_fallbackRouteKey);
    await prefs.remove(_fallbackTabKey);
    await prefs.remove(_fallbackUntilKey);

    print('[notif] fallback consume route=$route tab=$tab');

    _goByPayload({
      'route': route,
      'tab': tab,
    });

    return true;
  }




  static const String _lastWeeklyDateFallbackKey =
      'last_weekly_date_based_fallback_date';
  static const String _lastMonthlyDateFallbackKey =
      'last_monthly_date_based_fallback_month';

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static String _monthKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  /// 本番用フォールバック：
  /// iOSで通知タップイベントがDart側に届かない場合でも、
  /// アプリ起動/復帰時に「通知対象日・通知時刻後」なら履歴タブへ遷移する。
  ///
  /// - 毎週月曜10:00以降 → 週次タブへ
  /// - 毎月1日10:00以降 → 月次タブへ
  /// - 同じ日/同じ月には1回だけ
  static Future<bool> consumeDateBasedAiCommentFallbackIfNeeded() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    print('[notif] date fallback check now=$now');

    // 月次を先に判定：
    // 1日が月曜日の場合、週次と月次が同時に成立するため、
    // 月初の特別感を優先して月次タブへ飛ばす。
    //if (now.day == 1 && now.hour >= 10) {
    if (now.day == 1 && now.hour >= 10 && now.hour < 13) {
      final monthKey = _monthKey(now);
      final lastMonthly = prefs.getString(_lastMonthlyDateFallbackKey);

      print(
        '[notif] date fallback monthly month=$monthKey last=$lastMonthly',
      );

      if (lastMonthly != monthKey) {
        await prefs.setString(_lastMonthlyDateFallbackKey, monthKey);

        print('[notif] date fallback consume monthly month=$monthKey');

        _goByPayload({
          'route': '/history',
          'tab': 'monthly',
        });

        return true;
      }
    }

    //if (now.weekday == DateTime.monday && now.hour >= 10) {
    if (now.weekday == DateTime.monday && now.hour >= 10 && now.hour < 13) {
      final todayKey = _dateKey(now);
      final lastWeekly = prefs.getString(_lastWeeklyDateFallbackKey);

      print(
        '[notif] date fallback weekly date=$todayKey last=$lastWeekly',
      );

      if (lastWeekly != todayKey) {
        await prefs.setString(_lastWeeklyDateFallbackKey, todayKey);

        print('[notif] date fallback consume weekly date=$todayKey');

        _goByPayload({
          'route': '/history',
          'tab': 'weekly',
        });

        return true;
      }
    }

    return false;
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
  static Future<void> debugScheduleWeeklyIn60s({required String localeCode}) async {
    print('[notif] debugScheduleWeeklyIn60s ENTER');

    final allowed = await _ensureAllowed(requestIfDenied: true);
    print('[notif] debugScheduleWeeklyIn60s allowed=$allowed');

    if (!allowed) {
      print('[notif] debugScheduleWeeklyIn60s stopped: notification not allowed');
      return;
    }

    final fireAt = DateTime.now().add(const Duration(seconds: 60));
    final uniqueId = DateTime.now().millisecondsSinceEpoch.remainder(1000000000);

    print('[notif] debugScheduleWeeklyIn60s fireAt=$fireAt');

    await _saveNotificationFallback(
      route: '/history',
      tab: 'weekly',
      validUntil: fireAt.add(const Duration(hours: 3)),
    );


    await _safe(() => AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: uniqueId,
        channelKey: _channelKey,
        title: _txByCode(
          localeCode: localeCode,
          ja: '【テスト】週次のAIコメントを確認しましょう',
          en: '[TEST] Your weekly AI comment is ready',
        ),
        body: _txByCode(
          localeCode: localeCode,
          ja: 'タップで履歴（週次）へ',
          en: 'Tap to open history (Weekly)',
        ),
        payload: const {
          'route': '/history',
          'tab': 'weekly',
          'debug': '1',
        },
        category: NotificationCategory.Reminder,
        actionType: ActionType.Default,
        displayOnForeground: true,
        wakeUpScreen: true,
        autoDismissible: false,
      ),
      schedule: NotificationCalendar.fromDate(
        date: fireAt,
        preciseAlarm: true,
      ),
    ));

    print('[notif] debugScheduleWeeklyIn60s createNotification end');
  }

  static Future<void> debugScheduleMonthlyIn60s({required String localeCode}) async {
    print('[notif] debugScheduleMonthlyIn60s ENTER');

    final allowed = await _ensureAllowed(requestIfDenied: true);
    print('[notif] debugScheduleMonthlyIn60s allowed=$allowed');

    if (!allowed) {
      print('[notif] debugScheduleMonthlyIn60s stopped: notification not allowed');
      return;
    }

    final fireAt = DateTime.now().add(const Duration(seconds: 60));
    final uniqueId = DateTime.now().millisecondsSinceEpoch.remainder(1000000000);

    print('[notif] debugScheduleMonthlyIn60s fireAt=$fireAt');

    await _saveNotificationFallback(
      route: '/history',
      tab: 'monthly',
      validUntil: fireAt.add(const Duration(hours: 3)),
    );

    await _safe(() => AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: uniqueId,
        channelKey: _channelKey,
        title: _txByCode(
          localeCode: localeCode,
          ja: '【テスト】月次のAIコメントを見直しましょう',
          en: '[TEST] Your monthly AI comment is ready',
        ),
        body: _txByCode(
          localeCode: localeCode,
          ja: 'タップで履歴（月次）へ',
          en: 'Tap to open history (Monthly)',
        ),
        payload: const {
          'route': '/history',
          'tab': 'monthly',
          'debug': '1',
        },
        category: NotificationCategory.Reminder,
        actionType: ActionType.Default,
        displayOnForeground: true,
        wakeUpScreen: true,
        autoDismissible: false,
      ),
      schedule: NotificationCalendar.fromDate(
        date: fireAt,
        preciseAlarm: true,
      ),
    ));

    print('[notif] debugScheduleMonthlyIn60s createNotification end');
  }





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
    // // ✅ Debugボタンは「許可が無ければその場で許可を取りに行く」
    // if (!await _ensureAllowed(requestIfDenied: true)) return;
    print('[notif] debugFireNow ENTER');

// ✅ Debugボタンは「許可が無ければその場で許可を取りに行く」
    final allowed = await _ensureAllowed(requestIfDenied: true);
    print('[notif] debugFireNow allowed=$allowed');

    if (!allowed) {
      print('[notif] debugFireNow stopped: notification not allowed');
      return;
    }


    //// ✅ iOSで確実に出すため「3秒後の日時」を Calendar で予約する
    // ✅ iOSで確実に出すため「15秒後の日時」を Calendar で予約する
    final fireAt = DateTime.now().add(const Duration(seconds: 15));
    print('[notif] debugFireNow scheduled fireAt=$fireAt payload=$payload');

    // ✅ 既存予約（weekly/monthly等）と衝突しないように、毎回ユニークIDにする
    final uniqueId = DateTime.now().millisecondsSinceEpoch.remainder(1000000000);


    print('[notif] debugFireNow createNotification start');
    await _safe(() => AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: uniqueId, // ←固定id(id)は使わない（衝突回避）
        channelKey: _channelKey,
        title: _txByCode(localeCode: localeCode, ja: titleJa, en: titleEn),
        body: _txByCode(localeCode: localeCode, ja: bodyJa, en: bodyEn),
        payload: <String, String>{
          ...payload,
          'debug': '1',
          'fireAt': fireAt.toIso8601String(),
        },
        category: NotificationCategory.Reminder,
        actionType: ActionType.Default,
        displayOnForeground: true,
        wakeUpScreen: true,
        autoDismissible: false,
      ),
      //
      // schedule: NotificationCalendar.fromDate(
      //   date: fireAt,
      //   preciseAlarm: false,
      //   allowWhileIdle: true,
      // ),

    ));
    print('[notif] debugFireNow createNotification end');

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
        actionType: ActionType.Default,
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
        actionType: ActionType.Default,

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
  static Future<void> debugClearAllNotificationsOnly() async {
    print('[notif] debugClearAllNotificationsOnly start');

    await _safe(() => AwesomeNotifications().cancelAll());
    await _safe(() => AwesomeNotifications().dismissAllNotifications());

    print('[notif] debugClearAllNotificationsOnly end');
  }

}
