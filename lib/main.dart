// lib/main.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/home_screen.dart';
import 'screens/ai_comment_history_screen.dart';
import 'utils/csv_loader.dart';
import 'services/notification_service.dart';
import 'package:my_flutter_app_pro/screens/data_migration_screen.dart'; // 追加
import 'package:my_flutter_app_pro/config/purchase_config.dart';

import 'services/purchase_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'gen_l10n/app_localizations.dart';
import 'utils/notification_scheduler.dart';
//import 'package:my_flutter_app_pro/utils/notification_scheduler.dart';
import 'screens/navigation_screen.dart'; // ← NavigationScreen を使っているなら必須



// 通知タップ遷移用のグローバル NavigatorKey（既にあれば重複不要）
final GlobalKey<NavigatorState> notificationNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final p = await PackageInfo.fromPlatform();
  debugPrint('[iap] BUNDLE=${p.packageName}');
  // 既存の初期化（プロジェクトの内容に合わせてそのまま残す）
  await CsvLoader().ensureCsvSeeded('HappinessLevelDB1_v2.csv');
  await CsvLoader.getAiCommentLogFile();
  // .env は存在しない環境もあるので任意読み込み（無ければ無視）
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    // 起動を止めない（ログだけ）
    // ignore: avoid_print
    print("[dotenv] .env 読み込みスキップ/失敗: $e");
  }
  // ←ココに追加
  debugPrint('[boot] ENABLED=${PurchaseConfig.ENABLED}, DEV_FORCE_PRO=${PurchaseConfig.DEV_FORCE_PRO}');


  await AwesomeNotifications().initialize(
    null,
    [
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
  await NotificationService.init(notificationNavigatorKey);
  //await NotificationService.listenNotificationActions(notificationNavigatorKey);

  // ✅ 課金の初期化は main() の中で1回だけ
  await PurchaseService.I.init();

  // 既存のスケジュール系（そのまま）
  // await scheduleMorningReminder();
  // await scheduleEveningReminder();
  // await rescheduleNotifications();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);



  runApp(MyApp(navigatorKey: notificationNavigatorKey));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // 1) cold start の通知アクション
    await NotificationService.handleInitialAction();

    // 2) ✅ アプリの locale を拾って “朝/夕” を再予約
    final ctx = notificationNavigatorKey.currentContext;
    final code = (ctx != null)
        ? Localizations.localeOf(ctx).languageCode
        : WidgetsBinding.instance.platformDispatcher.locale.languageCode;

    await NotificationScheduler.rescheduleMorningEvening(appLocaleCode: code);
  });

// ✅ 週次/月次は main() 起動時に1回でOK（残すならここ）
  await NotificationService.clearAiCommentSchedules();
  await NotificationService.scheduleWeeklyOnMonday10();
  await NotificationService.scheduleMonthlyOnFirstDay10();

  if (kDebugMode) {
    await NotificationService.debugOneShotToHistory(
      delay: const Duration(seconds: 10),
    );
  }
}

  // void openPaywall(BuildContext context) {
  //   showModalBottomSheet(
  //     context: context,
  //     showDragHandle: true,
  //     builder: (_) => const PaywallSheet(),
  //   );
  // }





class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.navigatorKey});
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,

      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,

      theme: ThemeData(useMaterial3: true),

      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja'),
        Locale('en'),
      ],

      //✅⬇️ 確認用：一度だけ英語強制（確認できたらコメントアウトでOK）
       //locale: const Locale('en'),
      //✅⬆️locale: const Locale('en'), // ← テストが終わったら固定は外す（端末/ユーザーに追従）
      routes: {
        '/': (_) => const HomeScreen(csvData: []),
        '/nav': (_) => const NavigationScreen(csvData: []),
        '/history': (_) => const AiCommentHistoryScreen(),
        '/data-migration': (_) => const DataMigrationScreen(),
      },
      initialRoute: '/',
    );
  }

}

/// 既存：朝/夕の時刻（SharedPreferences に保存済み）でリマインダーを再設定
/// 🔧 修正版：通知権限がない場合は何もせず、例外も飲み込んでアプリは普通に起動させる
Future<void> _rescheduleMorningEvening() async {
  // 1) まず通知権限の有無を確認（ダイアログは出さない）
  try {
    final allowed = await AwesomeNotifications().isNotificationAllowed();
    if (!allowed) {
      debugPrint('[notif] permission not allowed, skip morning/evening schedule');
      return; // 権限なければ何もしないで終了
    }
  } catch (e) {
    debugPrint('[notif] error while checking permission: $e');
    return; // ここでコケてもアプリ本体は起動させたいので終了
  }

  // 2) ここから先は、権限がある場合だけ実行
  final prefs = await SharedPreferences.getInstance();
  final int? morningHour = prefs.getInt('morning_hour');
  final int? morningMinute = prefs.getInt('morning_minute');
  final int? eveningHour = prefs.getInt('evening_hour');
  final int? eveningMinute = prefs.getInt('evening_minute');

  // 朝の通知
  if (morningHour != null && morningMinute != null) {
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: 1,
          channelKey: 'basic_channel',
          title: 'おはようございます☀️',
          body: '今日の記録✏️を始めましょう',
          actionType: ActionType.Default,
          payload: {'route': '/'},
        ),
        schedule: NotificationCalendar(
          hour: morningHour,
          minute: morningMinute,
          second: 0,
          repeats: true,
        ),
      );
    } catch (e) {
      debugPrint('[notif] failed to schedule morning notification: $e');
    }
  }

  // 夜の通知
  if (eveningHour != null && eveningMinute != null) {
    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: 2,
          channelKey: 'basic_channel',
          title: '今日も1日お疲れ様でした🌙',
          body: '気持ちを整えるヒント💡をチェックしてみませんか？',
          actionType: ActionType.Default,
          payload: {'route': '/'},
        ),
        schedule: NotificationCalendar(
          hour: eveningHour,
          minute: eveningMinute,
          second: 0,
          repeats: true,
        ),
      );
    } catch (e) {
      debugPrint('[notif] failed to schedule evening notification: $e');
    }
  }
}

