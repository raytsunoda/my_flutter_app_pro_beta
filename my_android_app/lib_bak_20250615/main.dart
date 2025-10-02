import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

import 'package:provider/provider.dart';
import 'package:my_android_app/utils/csv_loader.dart';
import 'package:my_android_app/providers/selected_row_provider.dart';
import 'package:my_android_app/screens/home_screen.dart'; // ✅ 最初の画面はHomeScreenに
import 'notification_service.dart'; // 必ずインポート
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:awesome_notifications/awesome_notifications.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print("🔥 main() 開始");
  await AwesomeNotifications().initialize(
    null,
    [
      NotificationChannel(
        channelKey: 'basic_channel',
        channelName: 'Basic Notifications',
        channelDescription: 'Notification channel for basic tests',
        defaultColor: Colors.teal,
        ledColor: Colors.white,
        importance: NotificationImportance.High,
      )
    ],
    debug: true,
  );

  await AwesomeNotifications().requestPermissionToSendNotifications(); // 🔔 ここ！


  await NotificationService.initialize(); // ←ここで初期化
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
  final csvData = await loadCsvData(); // 起動時にCSVを読み込む
  print("📂 CSV読み込み完了：${csvData.length}行");
  runApp(
    ChangeNotifierProvider(
      create: (_) => SelectedRowProvider(),
      child: MyApp(csvData: csvData),
    ),
  );
  print("🚀 runApp 呼び出し済み");
}

class MyApp extends StatelessWidget {
  final List<List<dynamic>> csvData;

  const MyApp({super.key, required this.csvData});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '幸せ感ナビ',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: HomeScreen(csvData: csvData), // ✅ HomeScreen に遷移
    );
  }
}

Future<List<List<dynamic>>> loadCsvData() async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/HappinessLevelDB1_v2.csv');

  if (await file.exists()) {
    final content = await file.readAsString();
    final lines = const LineSplitter().convert(content);
    final values = lines.map((line) => line.split(',')).toList();
    print("📂 ローカルCSV読み込み成功 (${values.length}行)");
    return values;
  } else {
    // 初回起動時：assets からコピー
    final rawData = await rootBundle.loadString('assets/HappinessLevelDB1_v2.csv');
    await file.writeAsString(rawData);  // 書き出し
    final lines = const LineSplitter().convert(rawData);
    final values = lines.map((line) => line.split(',')).toList();
    print("📦 assetsから初期CSVコピー (${values.length}行)");
    return values;
  }
}

