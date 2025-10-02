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

Future<void> _loadCSV() async {
  // 最新の保存CSV（ヘッダー込み）
  final rows = await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv');

  if (rows.length <= 1) {
    setState(() {
      _csvData = [];
      _expanded = [];
      _selected = [];
    });
    return;
  }

  final header = rows.first.map((e) => e.toString().trim()).toList();
  final memoIdx = header.indexOf('memo');

  // データ行だけ抜き出し → 同日重複は memo ありを優先して 1 件に絞る
  final byDate = <String, List<dynamic>>{};
  for (final raw in rows.skip(1)) {
    final r = raw.map((e) => e?.toString() ?? '').toList();
    if (r.every((c) => c.trim().isEmpty)) continue;

    final date = r[0].toString().trim();
    if (date.isEmpty) continue;

    final cur = byDate[date];
    if (cur == null) {
      byDate[date] = r;
    } else {
      final curHasMemo = memoIdx >= 0 && cur.length > memoIdx && cur[memoIdx].toString().trim().isNotEmpty;
      final newHasMemo = memoIdx >= 0 && r.length > memoIdx && r[memoIdx].toString().trim().isNotEmpty;
      if (newHasMemo && !curHasMemo) {
        byDate[date] = r;
      }
    }
  }

  // 降順（日付新しい→古い）
  DateTime _p(dynamic v) {
    final s = v.toString().trim().replaceAll('-', '/');
    final sp = s.split('/');
    return DateTime(int.parse(sp[0]), int.parse(sp[1]), int.parse(sp[2]));
  }

  final data = byDate.values.toList()
    ..sort((a, b) => _p(b[0]).compareTo(_p(a[0])));

  setState(() {
    _csvData  = data;
    _expanded = List.filled(data.length, false);
    _selected = List.generate(data.length, (_) => false);
  });
}

