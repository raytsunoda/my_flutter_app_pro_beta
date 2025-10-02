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




// 通知タップ遷移用のグローバル NavigatorKey（既にあれば重複不要）
final GlobalKey<NavigatorState> notificationNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  await NotificationService.listenNotificationActions(notificationNavigatorKey);

  // ✅ 課金の初期化は main() の中で1回だけ
  await PurchaseService.I.init();

  // 既存のスケジュール系（そのまま）
  await _rescheduleMorningEvening();
  await NotificationService.clearAiCommentSchedules();
  await NotificationService.scheduleWeeklyOnMonday10();
  await NotificationService.scheduleMonthlyOnFirstDay10();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);



  runApp(MyApp(navigatorKey: notificationNavigatorKey));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService.handleInitialAction();
  });

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
      title: '幸せ感ナビ',
      theme: ThemeData(useMaterial3: true),
      routes: {
        '/': (_) => const HomeScreen(csvData: []),
        '/history': (_) => const AiCommentHistoryScreen(),
        '/data-migration': (_) => const DataMigrationScreen(), // ★追加
      },
      initialRoute: '/',
    );
  }
}

/// 既存：朝/夕の時刻（SharedPreferences に保存済み）でリマインダーを再設定
Future<void> _rescheduleMorningEvening() async {
  final prefs = await SharedPreferences.getInstance();
  final int? morningHour = prefs.getInt('morning_hour');
  final int? morningMinute = prefs.getInt('morning_minute');
  final int? eveningHour = prefs.getInt('evening_hour');
  final int? eveningMinute = prefs.getInt('evening_minute');

  if (morningHour != null && morningMinute != null) {
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
        hour: morningHour, minute: morningMinute, second: 0, repeats: true,
      ),
    );
  }

  if (eveningHour != null && eveningMinute != null) {
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
        hour: eveningHour, minute: eveningMinute, second: 0, repeats: true,
      ),
    );
  }
}
