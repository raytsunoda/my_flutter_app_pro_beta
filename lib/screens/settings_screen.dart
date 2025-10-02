import 'dart:convert'; // 先頭に追加// Utf8Encoder 用
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:my_flutter_app_pro/utils/csv_loader.dart';
import 'package:my_flutter_app_pro/screens/developer_tools_screen.dart';
import 'package:path/path.dart' as p; // ファイル名表示用
import 'package:my_flutter_app_pro/services/ai_comment_exporter.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:my_flutter_app_pro/services/legacy_import_service.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ───────── 通知時刻 ─────────
  TimeOfDay _morningTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _eveningTime = const TimeOfDay(hour: 20, minute: 0);
  bool _isEditing = false;

  // ───────── 重み設定 ─────────
  double _weightSleep = 0.3;
  double _weightStretch = 0.1;
  double _weightWalking = 0.3;
  double _weightAppreciation = 0.3;

  // ───────── 保存 CSV 一覧 ─────────
  List<List<dynamic>> _csvData = [];
  List<bool> _expanded = [];
  List<bool> _selected = [];

  /// （開発用）この端末ローカルの Pro 状態をリセット
  Future<void> _debugClearLocalPurchaseState() async {
      final prefs = await SharedPreferences.getInstance();
      // 端末ローカルで保持している可能性がある Pro 関連キーを念のため削除
      // （存在しなければ無視されます）
      for (final k in const [
        'hasPro',
        'purchaseHasPro',
        'proPurchaseDate',
        'proExpiryDate',
        'pro_receipt_json',
        'iap_last_products_json',
      ]) {
        await prefs.remove(k);
      }
    }




  @override
  void initState() {
    super.initState();
    _loadNotificationTimes();
    _loadPreferences();
    _loadCSV();
  }

  // ──────────────────────────────────── 通知
  Future<void> _loadNotificationTimes() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _morningTime = TimeOfDay(
        hour: prefs.getInt('morning_hour') ?? 8,
        minute: prefs.getInt('morning_minute') ?? 0,
      );
      _eveningTime = TimeOfDay(
        hour: prefs.getInt('evening_hour') ?? 20,
        minute: prefs.getInt('evening_minute') ?? 0,
      );
    });
  }

  Future<void> _saveNotificationTimes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('morning_hour', _morningTime.hour);
    await prefs.setInt('morning_minute', _morningTime.minute);
    await prefs.setInt('evening_hour', _eveningTime.hour);
    await prefs.setInt('evening_minute', _eveningTime.minute);

    await _scheduleNotification(
      id: 1,
      time: _morningTime,
      title: 'おはようございます☀️',
      body: '今日の記録✏️をつけましょう',
    );
    await _scheduleNotification(
      id: 2,
      time: _eveningTime,
      title: '今日も1日お疲れ様でした🌙',
      body: '気持ちを整えるヒント💡をチェックしてみませんか？',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('通知時刻を保存・再スケジュールしました')),
    );
  }

  Future<void> _scheduleNotification({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
  }) async {
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'basic_channel',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
      ),
      schedule: NotificationCalendar(
        hour: scheduledDate.hour,
        minute: scheduledDate.minute,
        second: 0,
        repeats: true,
      ),
    );
  }

  Future<void> _pickTime({required bool isMorning}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isMorning ? _morningTime : _eveningTime,
    );
    if (picked != null) {
      setState(() {
        if (isMorning) {
          _morningTime = picked;
        } else {
          _eveningTime = picked;
        }
      });
    }
  }

  Widget _buildTimePickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('通知時刻設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ListTile(
          title: const Text('朝の通知時間'),
          trailing: Text(_morningTime.format(context)),
          onTap: () => _pickTime(isMorning: true),
        ),
        ListTile(
          title: const Text('夜の通知時間'),
          trailing: Text(_eveningTime.format(context)),
          onTap: () => _pickTime(isMorning: false),
        ),
        Center(
          child: ElevatedButton(
            onPressed: _saveNotificationTimes,
            child: const Text('保存'),
          ),
        )
      ],
    );
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _weightSleep = prefs.getDouble('weightSleep') ?? _weightSleep;
      _weightStretch = prefs.getDouble('weightStretch') ?? _weightStretch;
      _weightWalking = prefs.getDouble('weightWalking') ?? _weightWalking;
      _weightAppreciation = prefs.getDouble('weightAppreciation') ?? _weightAppreciation;
    });
  }

  Future<void> _saveWeightPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('weightSleep', _weightSleep);
    await prefs.setDouble('weightStretch', _weightStretch);
    await prefs.setDouble('weightWalking', _weightWalking);
    await prefs.setDouble('weightAppreciation', _weightAppreciation);
  }

  Widget _buildSlider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      children: [
        Text('$label: ${value.toStringAsFixed(1)}'),
        Slider(
          min: 0.0,
          max: 1.0,
          divisions: 10,
          value: value,
          label: value.toStringAsFixed(1),
          onChanged: _isEditing ? (v) => setState(() => onChanged(double.parse(v.toStringAsFixed(1)))) : null,
        ),
      ],
    );
  }

  Widget _buildWeightSection() {
    final total = _weightSleep + _weightStretch + _weightWalking + _weightAppreciation;
    return ExpansionTile(
      title: const Text('重み設定'),
      children: [
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('合計は1.0にしてください。'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('合計: ${total.toStringAsFixed(1)} / 1.0'),
              TextButton(
                onPressed: () => setState(() => _isEditing = !_isEditing),
                child: Text(_isEditing ? '編集中' : '編集'),
              ),
            ],
          ),
        ),
        _buildSlider('睡眠', _weightSleep, (v) => _weightSleep = v),
        _buildSlider('ストレッチ', _weightStretch, (v) => _weightStretch = v),
        _buildSlider('ウォーキング', _weightWalking, (v) => _weightWalking = v),
        _buildSlider('感謝', _weightAppreciation, (v) => _weightAppreciation = v),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            onPressed: () {
              if (total.toStringAsFixed(1) == '1.0') {
                _saveWeightPreferences();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('重みを保存しました')));
                setState(() => _isEditing = false);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('合計が1.0ではありません')));
              }
            },
            child: const Text('保存'),
          ),
        )
      ],
    );
  }

  // 既出ならこのまま流用OK
  String _normYmd(String s) {
    s = (s).trim();
    if (s.isEmpty) return s;
    final p = s.split('/');
    if (p.length != 3) return s;
    return '${p[0].padLeft(4, '0')}/${p[1].padLeft(2, '0')}/${p[2].padLeft(2, '0')}';
  }

  DateTime? _parseYmd(String s) {
    final n = _normYmd(s);
    try {
      final p = n.split('/');
      return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) {
      return null;
    }
  }

// 追加①: CSVの中で一番新しい日付を取る
//   DateTime? _latestDateInCsv() {
//     final dates = widget.csvData
//         .map((r) => _parseYmd((r['日付'] ?? '').toString()))
//         .whereType<DateTime>()
//         .toList();
//     if (dates.isEmpty) return null;
//     dates.sort((a, b) => b.compareTo(a)); // desc
//     return dates.first;
//   }

  Future<void> _loadCSV() async {
    // CSV(ヘッダー込み) 読み込み
    final rows = await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv');

    if (rows.length <= 1) {
      setState(() {
        _csvData = [];
        _expanded = [];
        _selected = [];
      });
      return;
    }

    // データ行 → 空行除外 → 日付を正規化 → DateTime で降順ソート
    final data = rows
        .skip(1)
        .where((r) => r.any((c) => c.toString().trim().isNotEmpty))
        .map((r) {
      final copy = List<dynamic>.from(r);
      copy[0] = _normYmd(copy[0].toString()); // ← ここで yyyy/MM/dd に揃える
      return copy;
    })
        .toList()
      ..sort((a, b) {
        final da = _parseYmd(a[0].toString());
        final db = _parseYmd(b[0].toString());
        if (da == null && db == null) return 0;
        if (da == null) return 1; // 日付不明は後ろ
        if (db == null) return -1;
        return db.compareTo(da);   // 新しい→古い
      });

    setState(() {
      _csvData  = data;
      _expanded = List.filled(data.length, false);
      _selected = List.generate(_csvData.length, (_) => false);
    });
  }


  Future<void> _saveCsvData() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/HappinessLevelDB1_v2.csv'); // ファイル名統一
    const header = [
      '日付',
      '幸せ感レベル',
      'ストレッチ時間',
      'ウォーキング時間',
      '睡眠の質',
      //'睡眠時間（時間換算）',
      //'睡眠時間（分換算）',
      '睡眠時間（時間）',
      '睡眠時間（分）',
      '寝付き満足度',
      '深い睡眠感',
      '目覚め感',
      'モチベーション',
      '感謝数',
      '感謝1',
      '感謝2',
      '感謝3'
    ];

    final csvString = const ListToCsvConverter().convert([header, ..._csvData]);
    await file.writeAsBytes(const Utf8Encoder().convert('\u{FEFF}$csvString'));
  }

  /// チェックされた行を削除
  Future<void> _deleteSelectedRows() async {
    final datesToDelete = <String>{};
    for (int i = 0; i < _selected.length; i++) {
      if (_selected[i]) {
        final date = _csvData[i][0]?.toString().trim();
        if (date != null && date.isNotEmpty) {
          datesToDelete.add(date);
        }
      }
    }

    if (datesToDelete.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認'),
        content: const Text('選択した日付のデータを削除します。よろしいですか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('実行')),
        ],
      ),
    );
    if (ok != true) return;

    _csvData = _csvData.where((row) {
      final normalizedDate = row[0]?.toString().trim();
      return !datesToDelete.contains(normalizedDate);
    }).toList();

    _selected = List<bool>.filled(_csvData.length, false);
    await _saveCsvData();
    setState(() {});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${datesToDelete.length} 件のデータを削除しました'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteAll() async {
    setState(() {
      for (int i = 0; i < _selected.length; i++) {
        _selected[i] = true;
      }
    });

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('全件削除の確認'),
        content: Text('${_csvData.length} 件すべてのデータを削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );

    if (ok != true) return;

    await _deleteSelectedRows();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('全件削除しました'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("設定")),
      body: ListView(
        children: [
          ExpansionTile(title: const Text('通知設定'), children: [_buildTimePickerSection()]),
          _buildWeightSection(),
          ExpansionTile(title: const Text('保存データの管理'), children: [
            if (_csvData.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('保存データが存在しません。'),
              )
            else
              Column(
                children: [
                  for (int i = 0; i < _csvData.length; i++)
                    Column(
                      children: [
                        ListTile(
                          leading: Checkbox(
                            value: _selected[i],
                            onChanged: (v) => setState(() => _selected[i] = v ?? false),
                          ),
                          title: Text(_csvData[i][0].toString()),
                          trailing: IconButton(
                            icon: Icon(_expanded[i] ? Icons.expand_less : Icons.expand_more),
                            onPressed: () => setState(() => _expanded[i] = !_expanded[i]),
                          ),
                        ),
                        if (_expanded[i])
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [for (var cell in _csvData[i]) Text(cell.toString())],
                            ),
                          ),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(onPressed: _deleteSelectedRows, child: const Text('選択削除')),
                      ElevatedButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('すべてのデータを削除しますか？'),
                              content: const Text('この操作は元に戻せません。'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          _deleteAll();
                        },
                        child: const Text('全削除'),
                      ),
                    ],
                  ),
                ],
              ),
          ]),





    // 本番導線（常時表示）
    ListTile(
    leading: const Icon(Icons.settings_backup_restore),
    title: const Text('データ移行'),
    subtitle: const Text('旧アプリのCSVを取り込む'),

    onTap: () async {
    final summary = await LegacyImportService.importFromFilePicker(context);
    if (summary == null) return;
    // 取り込み後、画面をリフレッシュしたい場合は setState() 等で再読込

                  },
            ),

          // ここは本番では非表示。開発時のみ使います。
          if (kDebugMode)
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('AIコメント履歴を書き出す（CSV）'),
              subtitle: const Text('今日のひとこと／週次／月次の全履歴をCSVにバックアップ'),

              onTap: () async {
                await AiCommentExporter.exportCsv(context);
              },
            ),
// （開発）この端末ローカルの課金状態だけ初期化
          if (kDebugMode)
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('課金のローカル状態をリセット（開発用）'),
              subtitle: const Text('この端末の Pro 購入フラグ/キャッシュのみを消去（Sandboxの購入履歴は保持）'),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('確認'),
                    content: const Text('この端末ローカルの Pro 状態を初期化します。アプリ削除は行いません。続行しますか？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('実行')),
                    ],
                  ),
                );
                if (ok != true) return;
                await _debugClearLocalPurchaseState();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('端末ローカルの課金状態をリセットしました。再起動後に「Proを有効化」から再検証してください。')),
                );
              },
            ),




// 開発限定タイル（既にありますが '_' が未定義になる箇所は context に統一）
          if (kDebugMode)
            ListTile(
              leading: const Icon(Icons.restore_page),
              title: const Text('CSV復元（.bak）【開発用】'),
              subtitle: const Text('Documents 内の .bak/.csv を読み込んで Pro 形式へ取り込み'),
              onTap: () async {
                final candidates = await LegacyImportService.findBakFilesInDocuments();
                if (candidates.isEmpty) {
                  if (!context.mounted) return;
                  showDialog(context: context, builder: (_) => const AlertDialog(
                    title: Text('ファイルが見つかりません'),
                    content: Text('アプリの Documents に .bak/.csv を配置してください。'),
                  ));
                  return;
                }

                final selected = await showModalBottomSheet<File>(
                  context: context,
                  builder: (ctx) => ListView(
                    children: candidates.map((f) => ListTile(
                      title: Text(p.basename(f.path)),
                      subtitle: Text(f.path),
                      onTap: () => Navigator.pop(ctx, f),
                    )).toList(),
                  ),
                );
                if (selected == null) return;

                final overwrite = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('上書きモードで取り込みますか？'),
                    content: const Text('同じ日付が既に存在する場合、上書きするかスキップするかを選べます。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('スキップ')),
                      FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('上書き')),
                    ],
                  ),
                ) ?? false;

                final report = await LegacyImportService.importLegacyCsv(
                  source: selected,
                  overwrite: overwrite,
                );
                if (!context.mounted) return;

// 型差異に依存しない安全表示（toString だけ）
                await showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('取り込み結果'),
                    content: SingleChildScrollView(
                      child: Text(report.toString()),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );


              // 取り込み後に一覧を再読込（UI反映）
              await _loadCSV();

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CSVの取り込みが完了しました（一覧を更新）')),
                );

              },
            ),







          // 🔧 デバッグモード限定 開発者ツール遷移ボタン
          if (kDebugMode) ...[
            const Divider(),
            ListTile(
              title: const Text('🛠 開発者ツール'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DeveloperToolsScreen()),
                );
              },
            ),
          ],




        ],
      ),
    );
  }
}
