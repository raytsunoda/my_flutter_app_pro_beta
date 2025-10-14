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
import 'dart:ui' show FontFeature;// 等幅数字用
import 'package:my_flutter_app_pro/utils/user_prefs.dart';
import 'package:file_picker/file_picker.dart';


// ==== helpers (robust cell access) ====
int _findIndexByNames(List<String> names, List<String> header) {
  for (final n in names) {
    final i = header.indexOf(n);
    if (i >= 0) return i;
  }
  return -1;
}

String _cellByIdx(List<dynamic> row, int idx) {
  if (idx < 0 || idx >= row.length) return '';
  final v = row[idx];
  return (v ?? '').toString().trim();
}

String _cellByName(List<dynamic> row, List<String> header, List<String> names) {
  final i = _findIndexByNames(names, header);
  return _cellByIdx(row, i);
}
// =====================================




// === DEBUG HELPERS (once) ===
String _runes(String s) => s.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase()}').join(' ');
void _dumpHeaderWithCodes(List<String> header) {
  debugPrint('[HEADER:CODES] count=${header.length}');
  for (int i = 0; i < header.length; i++) {
    final h = header[i];
    debugPrint('  [$i] "$h" (${_runes(h)})');
  }
}
void _dumpRowWithCodes(List<dynamic> r) {
  debugPrint('[ROW:CODES] len=${r.length}');
  for (int i = 0; i < r.length; i++) {
    final v = (r[i] ?? '').toString();
    debugPrint('  [$i] "$v" (${_runes(v)})');
  }
}



// ===== CSV helpers (safe cell access) =====
int _headerIndexOfAny(List<String> header, List<String> candidates) {
    for (var i = 0; i < header.length; i++) {
      if (candidates.contains(header[i])) return i;
    }
    return -1;
  }

String _cellOr(List<String> row, List<String> header, List<String> candidates) {
    final idx = _headerIndexOfAny(header, candidates);
    if (idx < 0) return '';
    return idx < row.length ? row[idx] : '';
  }


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();




}

class _SettingsScreenState extends State<SettingsScreen> {
  // ← 既存の state フィールド群の下に追加
  List<String> _header = [];
  List<String> _headerNorm = []; // 追加：正規化版ヘッダー
// 数字を等幅で表示するための共通スタイル
  final TextStyle _numStyle = const TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );

// 呼びかけ名（表示名）
  final _displayNameCtrl = TextEditingController();


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

// 安全にセルを取り出す（候補ヘッダを上から順に試す＋空ならフォールバック）
  String _cellOr(List<String> header, List<String> row, List<String> candidates, {String? fallback}) {
    int _idxFor(String name) => header.indexWhere((h) => h.contains(name));
    for (final cand in candidates) {
      final idx = _idxFor(cand);
      if (idx >= 0 && idx < row.length) {
        final v = row[idx].trim();
        if (v.isNotEmpty) return v;
      }
    }
    return (fallback ?? '').trim();
  }
// 見出し（左にアイコン・太字タイトル）を出す共通ウィジェット
  Widget _sectionHeader(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }



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
    // ▼ 呼びかけ名の初期値
    UserPrefs.getDisplayName().then((v) {
      if (!mounted) return;
      _displayNameCtrl.text = (v ?? '').trim();
      setState(() {});
    });
  }
  @override
  void dispose() {
    _displayNameCtrl.dispose();
    super.dispose();
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

// 重み設定：ExpansionTile なしで中身だけ描く版
  Widget _buildWeightSectionBody() {
    final total = _weightSleep + _weightStretch + _weightWalking + _weightAppreciation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        ),
      ],
    );
  }

// 見出し→折りたたみ可能な共通セクション
  Widget _sectionTile({
    required IconData icon,
    required String title,
    required Widget child,
    bool initiallyExpanded = true,
  }) {
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: Icon(icon),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600), // 見出しは太字
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: child,
        ),
      ],
    );
  }
  Widget _buildCallNameEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('呼びかけ名（さん付けで呼びます）'),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.person, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _displayNameCtrl, // 既存のControllerを利用
                decoration: const InputDecoration(
                  hintText: '例：太郎（空なら「ユーザーさん」）',
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                final name = _displayNameCtrl.text.trim();
                await UserPrefs.setDisplayName(name); // 既存の保存関数
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('呼びかけ名を保存しました')));
                  setState(() {}); // 再描画
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _importCsv() async {
    // 0) ユーザーにCSVを選んでもらう
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (res == null || res.files.single.path == null) return;

    final file = File(res.files.single.path!);

    // 1) CsvLoader 側の“安全マージ”で取り込み（空で上書きしない・感謝数は再計算）
    debugPrint('[IMPORT] importCsvSafely: begin file=${file.path}');
    await CsvLoader.importCsvSafely(file);

    // 2) 端末ログ（安心ログ）
    debugPrint('[IMPORT] importCsvSafely: done');

    // 3) UIを最新化
    await _loadCSV();
    if (!mounted) return;

    // 4) ユーザー向けにも完了ダイアログ
    await showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('取り込み完了'),
        content: Text('CSVを安全マージで取り込みました（既存の非空は維持・感謝数は再計算）。'),
      ),
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
        _header = [];
      });
      return;
    }


// // ▼ ヘッダー名の正規化：空白/タブを除去し、「の」を落として比較の揺れを吸収
//   String _normalizeHeaderName(String s) {
//     return s
//         .replaceAll(RegExp(r'\s+'), '')  // 全/半角スペース・タブ除去
//         .replaceAll('の', '')            // 「寝付きの満足度」⇔「寝付き満足度」を同一視
//         .trim();
//   }


// ▼ 追加：ヘッダーを保持（文字列化）
    _header = rows.first.map((c) => c.toString().trim()).toList();

    // ▼ 追加：正規化版ヘッダーも保持
    _headerNorm = _header.map(_normalizeHeaderName).toList();


// デバッグ: 取り込んだヘッダー確認
    debugPrint('[SETTINGS] header: ${_header.join(",")}');

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


// ▼ ヘッダー名の正規化：空白/タブを除去し、「の」を落として比較の揺れを吸収
  String _normalizeHeaderName(String s) {
    return s
        .replaceAll(RegExp(r'\s+'), '')  // 全/半角スペース・タブ除去
        .replaceAll('の', '')            // 「寝付きの満足度」⇔「寝付き満足度」を同一視
        .trim();
  }







// === SETTINGS: helpers begin ===
  /// ヘッダー候補から列indexを引く（表記ゆれに強い・正規化比較）
  /// ※ List<String> 固定だと呼び出し側が List<dynamic> の時に型エラーになるため、動的受けに変更
  int _findIndexByNames(List names) { // ← ここを List<String> から List に変更
    for (final n in names) {
      final key = _normalizeHeaderName(n.toString()); // ← toStringで吸収
      final idx = _headerNorm.indexOf(key);
      if (idx >= 0) return idx;
    }
    return -1;
  }
  // --- PATCH: helper (index fallback) ---
  int _indexOrFallback(List<String> candidates, int fallbackIndex) {
    final idx = _findIndexByNames(candidates);
    if (idx >= 0 && idx < _header.length) return idx;
    // ヘッダー長を越えない範囲なら既知の列位置（0起算）でフォールバック
    return (fallbackIndex >= 0 && fallbackIndex < _header.length)
        ? fallbackIndex
        : -1;
  }

  /// indexが-1なら空文字、そうでなければ値を返す（dynamic行に対応）
  String _cellByIdx(List<dynamic> row, int idx) {
    if (idx < 0 || idx >= row.length) return '';
    final v = row[idx];
    // 数値/文字/空白の混在に備えて厳密にトリム
    return v == null ? '' : v.toString().trim();
  }
// === SETTINGS: helpers end ===



  Future<void> _saveCsvData() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/HappinessLevelDB1_v2.csv'); // ファイル名統一
    const header = [
      '日付',
      '幸せ感レベル',
      'ストレッチ時間',
      'ウォーキング時間',
      '睡眠の質',
      '睡眠時間（時間換算）',
      '睡眠時間（分換算）',
      '睡眠時間（時間）',
      '睡眠時間（分）',
      '寝付きの満足度',
      '深い睡眠感',
      '目覚め感',
      'モチベーション',
      '感謝数',
      '感謝1',
      '感謝2',
      '感謝3',
      'memo',
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
      body: ListView(children: [
        // 見出し → 内容：通知設定
        // 折りたたみ：通知設定
        _sectionTile(
          icon: Icons.notifications,
          title: '通知設定',
          child: _buildTimePickerSection(),
          initiallyExpanded: false, // ← 初期は閉じる
        ),

// 折りたたみ：重み設定
        _sectionTile(
          icon: Icons.tune,
          title: '重み設定',
          child: _buildWeightSectionBody(),
          initiallyExpanded: false,
        ),

// 折りたたみ：呼びかけ名
        _sectionTile(
          icon: Icons.badge,
          title: '呼びかけ名',
          child: _buildCallNameEditor(), // ← 入力UIの本体を使う
          initiallyExpanded: false,
        ),


        ExpansionTile(
          leading: const Icon(Icons.folder_copy_outlined),
          title: const Text(
          '保存データの管理',
          style: TextStyle(fontWeight: FontWeight.w600),
          ),
          children: [
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
                            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: () {
                            // ---------------------- PATCH B2: begin (robust details mapper) ----------------------
                                final r = _csvData[i];

                                final rowDate = _cellByIdx(r, _findIndexByNames(['日付']));
                                debugPrint('[DETAIL] date=$rowDate cols=${r.length} header=${_header.join("|")}');
                                debugPrint('[DETAIL:rowDump] len=${r.length} row=${r.map((e) => '"${(e ?? '').toString()}"').join('|')}');

// 追加（先頭の1レコードだけで十分）
                                if (rowDate == '2025/03/07') {
                                  _dumpHeaderWithCodes(_header);
                                  _dumpRowWithCodes(r);
                                }

                                // 表示したい列（表記ゆれに強い）
                                final fields = <MapEntry<String, List<String>>>[

                                  MapEntry('幸せ感レベル', ['幸せ感レベル']),
                                  MapEntry('ストレッチ時間', ['ストレッチ時間']),
                                  MapEntry('ウォーキング時間', ['ウォーキング時間']),
                                  MapEntry('睡眠の質', ['睡眠の質']),
                                  MapEntry('睡眠時間（時間）', ['睡眠時間（時間）']),
                                  MapEntry('睡眠時間（分）', ['睡眠時間（分）']),

                                  // ★「寝付きの満足度 / 寝付き満足度」どちらでも対応
                                  MapEntry('寝付きの満足度', ['寝付きの満足度', '寝付き満足度']),

                                  MapEntry('深い睡眠感', ['深い睡眠感']),
                                  MapEntry('目覚め感', ['目覚め感']),
                                  MapEntry('モチベーション', ['モチベーション']),
                                  MapEntry('感謝数', ['感謝数']),
                                  MapEntry('感謝1', ['感謝1']),
                                  MapEntry('感謝2', ['感謝2']),
                                  MapEntry('感謝3', ['感謝3']),
                                  // ▼ これを追加（表記ゆれ想定）
                                  MapEntry('今日のひとことメモ', ['memo', 'メモ', '今日のひとことメモ']),
                                ];

                                // ループ外にバッファ（ループ中に UI リストを直接いじらない）
                                final widgets = <Widget>[];

                                // 「寝付き満足度」専用デバッグは 1 回だけ
                                var _loggedFallAsleep = false;

                                for (final f in fields) {

                                  int idx = _findIndexByNames(f.value);
                                  String val = _cellByIdx(r, idx);


                                 // SPECIAL CASE: fallAsleep (robust) — 列名ゆれ & 空欄救済
                                 if (f.key == '寝付きの満足度') {
                                   // 1) ヘッダー配列（null ではない想定）
                                   final headers = _header;

                                   // 2) 列名で安全に取得（"寝付きの満足度" / "寝付き満足度" の両対応）
                                   int _idxByNames(List<String> names) {
                                     for (final n in names) {
                                       final i = headers.indexOf(n);
                                       if (i >= 0) return i;
                                     }
                                     return -1;
                                   }
                                   String _cell(List row, int i) {
                                     if (i >= 0 && i < row.length) {
                                       return (row[i] ?? '').toString().trim();
                                     }
                                     return '';
                                   }

                                   final idxA = _idxByNames(['寝付きの満足度', '寝付き満足度']); // CSV #10 想定
                                   var raw = _cell(r, idxA);

                                   // 3) 空欄救済：深い睡眠感の直前列を予備値として採用
                                   if (raw.isEmpty) {
                                     final deepIdx = headers.indexOf('深い睡眠感'); // CSV #11 想定
                                     final guessIdx = (deepIdx > 0) ? deepIdx - 1 : -1; // = fallAsleep 列のはず
                                     final guess = _cell(r, guessIdx);
                                     if (guess.isNotEmpty) {
                                       debugPrint('[DETAIL:fallAsleep][fallback-prev] deepIdx=$deepIdx guessIdx=$guessIdx guess="$guess"');
                                       raw = guess;
                                     }
                                   }

                                   // 4) デバッグ（1行のみ）
                                   final usedName = (idxA >= 0 && headers[idxA] == '寝付き満足度')
                                       ? '寝付き満足度' : (idxA >= 0 ? '寝付きの満足度' : 'N/A');
                                   debugPrint('[DETAIL:fallAsleep] name=$usedName idx=${idxA >= 0 ? idxA : (headers.indexOf("深い睡眠感") - 1)} val="$raw"');

                                   // 5) 最終代入（空なら後続の _addIfNotEmpty で弾かれる）
                                   val = raw;
                                 }



                                else {

                                    // それ以外は従来通り
                                    if (val.isEmpty) {
                                      // 万一に備えて一般フォールバック（既知列へ）も使っておくと堅い
                                      final fallbackMap = {
                                        '幸せ感レベル': 1,
                                        'ストレッチ時間': 2,
                                        'ウォーキング時間': 3,
                                        '睡眠の質': 4,
                                        '睡眠時間（時間）': 7,
                                        '睡眠時間（分）': 8,
                                        '深い睡眠感': 10,
                                        '目覚め感': 11,
                                        'モチベーション': 12,
                                        '感謝数': 13,
                                        '感謝1': 14,
                                        '感謝2': 15,
                                        '感謝3': 16,
                                      };
                                      final fb = fallbackMap[f.key];
                                      if (fb != null) {
                                        idx = _indexOrFallback(f.value, fb);
                                        val = _cellByIdx(r, idx);
                                      }
                                    }
                                  }

                                          if (val.isEmpty) continue;
                                          // 幸せ感レベルは小数1桁に整形してから表示
                                          if (f.key == '幸せ感レベル') {
                                            final d = double.tryParse(val);
                                            if (d != null) val = d.toStringAsFixed(1);
                                          }
                                          // 左右整列用の _kv を使って描画
                                          widgets.add(_kv(f.key, val));
                                }

                                return widgets;
// ---------------------- PATCH B2: end ----------------------

                              }(),
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
    // ListTile(
    // leading: const Icon(Icons.settings_backup_restore),
    // title: const Text('データ移行'),
    // subtitle: const Text('旧アプリのCSVを取り込む'),
    //
    // onTap: () async {
    // final summary = await LegacyImportService.importFromFilePicker(context);
    // if (summary == null) return;
    // // 取り込み後、画面をリフレッシュしたい場合は setState() 等で再読込
    //
    //               },
    //         ),
        ListTile(
          leading: const Icon(Icons.refresh),               // 左端アイコン追加
          title: const Text(
            'データ移行',
            style: TextStyle(fontWeight: FontWeight.w600),  // タイトルを太字
          ),
          subtitle: const Text('旧アプリのCSVを取り込む'),
          onTap: _importCsv, // ← 既存の処理に合わせて
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
// 任意の候補名のうち最初に一致したヘッダのインデックスを返す。なければ -1。
  int _headerIndexOfAny(List<String> header, List<String> candidates) {
    for (final c in candidates) {
      final idx = header.indexOf(c);
      if (idx >= 0) return idx;
    }
    return -1;
  }

  Widget _kv(String label, String value) {
// ①「今日のひとことメモ」は複数行で折り返し表示（左寄せ）
    if (label == '今日のひとことメモ') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('今日のひとことメモ', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              value,
              softWrap: true,
              // maxLines: null を指定したい場合は Text.rich 等だと不要。通常 Text は改行可能です。
            ),
          ],
        ),
      );
    }



    // 感謝1/2/3 は右寄せにせず、左寄せで「感謝1：xxx」の1行表示にする
    if (label.startsWith('感謝')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$label：$value',
            softWrap: true,
          ),
        ),
      );
    }

    // それ以外は従来どおり（数値は等幅フォント＋右寄せ）
    final v = value.trim();
    final isNumeric = double.tryParse(v) != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左：ラベル（左寄せ・改行可）
          Expanded(
            child: Text(
              label,
              softWrap: true,
            ),
          ),
          const SizedBox(width: 8),
          // 右：値（右寄せ・数字は等幅）
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: isNumeric ? _numStyle : null,
                softWrap: true,
              ),
            ),
          ),
        ],
      ),
    );


  }
  Widget _callNameTile() {
    return ListTile(
      leading: const Icon(Icons.person),
      title: const Text('呼びかけ名（さん付けで呼びます）'),
      subtitle: TextField(
        controller: _displayNameCtrl,
        decoration: const InputDecoration(
          hintText: '例：太郎（空なら「ユーザー」）',
        ),
      ),
      trailing: ElevatedButton(
        onPressed: () async {
          await UserPrefs.setDisplayName(_displayNameCtrl.text);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('呼びかけ名を保存しました')),
          );
          setState(() {});
        },
        child: const Text('保存'),
      ),
    );
  }



}
