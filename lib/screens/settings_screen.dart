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
import 'package:my_flutter_app_pro/services/ai_comment_service.dart';
import 'package:my_flutter_app_pro/ui/common_error_dialog.dart'; // 先頭の import 群に追加
import '../widgets/paywall_sheet.dart' show openPaywall, PaywallMode;
import 'package:flutter/foundation.dart'; // ← 追加（kDebugMode用）
import 'package:my_flutter_app_pro/services/purchase_service.dart';
import 'package:my_flutter_app_pro/widgets/migration_guide_modal.dart';

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



// ===== ADD: 何が来ても安全に String 化 + trim するヘルパ =====
String _s(dynamic v) => (v ?? '').toString().trim();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MigrationGuideModal.showIfNeeded(context);
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

// ▼ 追加：保存データ一覧を再読込する小ヘルパ
  Future<void> _reloadSavedDates() async {
    await _loadCSV();
    if (!mounted) return;
    setState(() {});
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
    // ▼ 追加: 同日付のAIコメント（daily/weekly/月次）をまとめて削除
      try {
        await AiCommentService.deleteCommentsForDates(datesToDelete.toList());
      } catch (e) {
        debugPrint('[DELETE AI COMMENT] failed: $e');
      }
      // ▼ 一覧を再読込してUI反映（setStateだけでなくCSVも再読み込み）
      await _reloadSavedDates();

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

// ＝＝ AIコメント（週次／月次）再生成 ＝＝
// 本番（リリース）では非表示。デバッグビルドのみ表示する
        if (kDebugMode)
        _sectionTile(
          icon: Icons.auto_fix_high_outlined,
          title: 'AIコメント（日次/週次/月次）再生成',
          initiallyExpanded: false,
          child: _AiRegeneratePanel(onDone: () async {
            // CSV/一覧の再読み込み（あなたの既存ヘルパ）
            await _reloadSavedDates();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('AIコメントを更新しました')),
            );
          }),
        ),
        if (kDebugMode)
          _sectionTile(
          icon: Icons.developer_mode,
          title: '開発者メニュー',
          child: _buildDeveloperPatches(),
          initiallyExpanded: false,
        ),


// --- 課金（管理・復元） -----------------------------------------
// 本番では非表示。開発ビルドのみ表示する
        if (kDebugMode) ...[
          ExpansionTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text(
              '課金（管理・復元）',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            children: [
              ListTile(
                title: const Text('サブスクリプションを管理'),
                subtitle: const Text('「購入を復元」「購読管理（App Store）」を開く'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openPaywall(context, mode: PaywallMode.manage),
              ),
              // ※デバッグでワンタップ復元も残したい場合は、ここにもう1個 ListTile 追加可
            ],
          ),
        ],
        if (kDebugMode) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              PurchaseService.I.debugRevokeProLocal();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('DEBUG: Pro 状態をローカルで無効化しました')),
                );
                setState(() {}); // その場でUI更新
              }
            },
            child: const Text('DEBUG: Pro状態を一旦無効化'),
          ),
        ],


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

                                    // 取り出し用のインデックス（表記ゆれに強い検索）
                                    int idxOf(List names, int fallback) {
                                      final idx = _findIndexByNames(names);
                                      if (idx >= 0 && idx < r.length) return idx;
                                      return (fallback >= 0 && fallback < r.length) ? fallback : -1;
                                    }

                                    String v(List names, int fb) => _cellByIdx(r, idxOf(names, fb));

                                    final ymd        = v(['日付'], 0);
                                    final happy      = v(['幸せ感レベル'], 1);
                                    final stretch    = v(['ストレッチ時間'], 2);
                                    final walk       = v(['ウォーキング時間','ウォーキング'], 3);                                final sleepQ     = v(['睡眠の質'], 4);
                                    final sleepHour  = v(['睡眠時間（時間換算）'], 5);
                                    final sleepMinQ  = v(['睡眠時間（分換算）'], 6);
                                    final sleepHourCol = v(['睡眠時間（時間）'], 7);
                                    final sleepMinCol  = v(['睡眠時間（分）'], 8);
                                    final sleepEase  = v(['寝付きの満足度','寝付き満足度'], 9);
                                    final deepSleep  = v(['深い睡眠感'], 10);
                                    final wakeFeel   = v(['目覚め感'], 11);
                                    final motive     = v(['モチベーション'], 12);
                                    final thanksCnt  = v(['感謝数'], 13);
                                    final g1         = v(['感謝1'], 14);
                                    final g2         = v(['感謝2'], 15);
                                    final g3         = v(['感謝3'], 16);
                                    final memo       = v(['memo','メモ','今日のひとことメモ'], 17);

                                    final fields = <Map<String,String>>[
                                      {'key':'幸せ感レベル', 'val': happy},
                                      {'key':'ストレッチ時間', 'val': stretch},
                                      {'key':'ウォーキング時間', 'val': walk},
                                      {'key':'睡眠の質', 'val': sleepQ},
                                      {'key':'睡眠時間（時間換算）', 'val': sleepHour},
                                      {'key':'睡眠時間（分換算）', 'val': sleepMinQ},
                                      {'key':'睡眠時間（時間）', 'val': sleepHourCol},
                                      {'key':'睡眠時間（分）', 'val': sleepMinCol},
                                      {'key':'寝付きの満足度', 'val': sleepEase},
                                      {'key':'深い睡眠感', 'val': deepSleep},
                                      {'key':'目覚め感', 'val': wakeFeel},
                                      {'key':'モチベーション', 'val': motive},
                                      {'key':'感謝数', 'val': thanksCnt},
                                      {'key':'感謝1', 'val': g1},
                                      {'key':'感謝2', 'val': g2},
                                      {'key':'感謝3', 'val': g3},
                                      {'key':'今日のひとことメモ', 'val': memo},
                                    ];

                                    final widgets = <Widget>[
                                      Text(ymd, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 8),
                                    ];

                                    for (final f in fields) {
                                      final k = _s(f['key']);      // ← どんな型でも安全に String 化 + trim
                                      final rawVal = _s(f['val']); // ← 同上
                                      final val = _formatDisplayValue(k, rawVal);

                                      if (k == '今日のひとことメモ') {
                                        widgets.add(
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54)),
                                                const SizedBox(height: 2),
                                                Text(val.isEmpty ? '（未入力）' : val, softWrap: true),
                                              ],
                                            ),
                                          ),
                                        );
                                      } else {
                                        widgets.add(
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54)),
                                                const SizedBox(width: 8),
                                                Expanded(child: Text(val.isEmpty ? '—' : val)),
                                              ],
                                            ),
                                          ),
                                        );
                                      }
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


        ListTile(
          leading: const Icon(Icons.refresh),               // 左端アイコン追加
          title: const Text(
            'データ移行',
            style: TextStyle(fontWeight: FontWeight.w600),  // タイトルを太字
          ),
          subtitle: const Text('旧アプリのCSVを取り込む'),
            onTap: () async {
              await MigrationGuideModal.show(context);  // ← まずガイドを表示
              // その後、実際の取り込み画面へ遷移させたい場合は、show の直後に push する
              // Navigator.push(context, MaterialPageRoute(builder: (_) => const DataImportScreen()));

              // 既存の「上書き保存」実装は全削除してOK。安全マージを直呼び。
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['csv'],
              );
              if (result == null || result.files.single.path == null) return;

              final file = File(result.files.single.path!);
              await CsvLoader.importCsvSafely(file);

              // 再読込（既存の関数を呼ぶ）
              await _reloadSavedDates();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CSVを安全に取り込みました')),
              );
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
// 任意の候補名のうち最初に一致したヘッダのインデックスを返す。なければ -1。
  int _headerIndexOfAny(List<String> header, List<String> candidates) {
    for (final c in candidates) {
      final idx = header.indexOf(c);
      if (idx >= 0) return idx;
    }
    return -1;
  }

  // どんな型が来ても安全に文字列化して扱う
  Widget _kv(String label, dynamic value) {
    // まずは安全に toString → trim
    final v = _s(value);    // ← 何が来ても安全

    // ①「今日のひとことメモ」は複数行で折り返し表示（左寄せ）
    if (label == '今日のひとことメモ') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('今日のひとことメモ', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(v.isEmpty ? '（未入力）' : v, softWrap: true),
          ],
        ),
      );
    }

    // それ以外は従来どおり（数値は等幅フォント＋右寄せ）
    final isNumeric = double.tryParse(v) != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, softWrap: true)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                v.isEmpty ? '—' : v,
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
// 表示用フォーマッタ：幸せ感レベルだけ小数1桁に丸める
  String _formatDisplayValue(String key, String raw) {
    if (key == '幸せ感レベル') {
      final d = double.tryParse(raw);
      if (d != null) return d.toStringAsFixed(1); // 例: 77.5
    }
    return raw;
  }
  Widget _buildDeveloperPatches() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('データ修復ユーティリティ（開発用）', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.build),
          label: const Text('AIコメントCSVを後処理（追伸テンプレ除去）'),
          onPressed: () async {
            final n = await CsvLoader.fixAiLogTailPhrases();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('修復完了：$n 件を処理しました')),
            );
            // 必要なら履歴の再読込を促す
          },
        ),
      ],
    );
  }




}


class _AiRegeneratePanel extends StatefulWidget {
  final Future<void> Function() onDone;
  const _AiRegeneratePanel({required this.onDone});

  @override
  State<_AiRegeneratePanel> createState() => _AiRegeneratePanelState();
}

class _AiRegeneratePanelState extends State<_AiRegeneratePanel> {
  DateTime _picked = DateTime.now();
  String _kind = 'daily'; // 'daily' | 'weekly' | 'monthly'
  bool _busy = false;

  // ▼▼▼ これを _AiRegeneratePanelState クラス内に「新規追加」してください ▼▼▼
  Future<T> _withRetry<T>(
      Future<T> Function() body, {
        int maxAttempts = 3,
        Duration delay = const Duration(milliseconds: 600),
      }) async {
    Object? lastErr;
    for (var i = 0; i < maxAttempts; i++) {
      try {
        return await body();
      } catch (e) {
        lastErr = e;
        if (i < maxAttempts - 1) {
          await Future.delayed(delay);
          continue;
        }
        rethrow; // 規定回数失敗で投げる
      }
    }
    // ここには来ないが型満たし
    throw lastErr ?? Exception('unknown error');
  }


  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 3, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);
    final d = await showDatePicker(
      context: context,
      initialDate: _picked,
      firstDate: first,
      lastDate: last,
    );
    if (d != null) setState(() => _picked = d);
  }

  DateTime _toSunday(DateTime d) {
    final wd = d.weekday % 7; // Sun=0
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: wd));
  }

  DateTime _toEom(DateTime d) => DateTime(d.year, d.month + 1, 0);

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4,'0')}/${d.month.toString().padLeft(2,'0')}/${d.day.toString().padLeft(2,'0')}';

  Future<void> _deleteOnly() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_kind == 'daily') {
        await AiCommentService.hardDeleteByDateType(_fmt(_picked), 'daily');
      } else if (_kind == 'weekly') {
        final sun = _toSunday(_picked);
        await AiCommentService.hardDeleteByDateType(_fmt(sun), 'weekly');
      } else {
        final eom = _toEom(_picked);
        await AiCommentService.hardDeleteByDateType(_fmt(eom), 'monthly');
      }

      await widget.onDone();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('削除しました')),
      );
    } catch (e) {
      debugPrint('[AI REGEN] deleteOnly error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('削除に失敗しました（${e.runtimeType}）')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _deleteThenRegen() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      bool ok = false;
      String userMsg = '再生成しました';

      if (_kind == 'daily') {
        final day = DateTime(_picked.year, _picked.month, _picked.day);
        final key = _fmt(day);
        await AiCommentService.hardDeleteByDateType(key, 'daily');
        final resText = await AiCommentService.ensureDailySaved(day);
        ok = _s(resText).isNotEmpty;

      } else if (_kind == 'weekly') {
        final sun = _toSunday(_picked);
        final key = _fmt(sun);
        await AiCommentService.hardDeleteByDateType(key, 'weekly');
        final res = await AiCommentService.ensureWeeklySaved(sun);
        ok = ((res['comment'] ?? '').toString().trim().isNotEmpty);
      } else {
        final eom = _toEom(_picked);
        final key = _fmt(eom);
        await AiCommentService.hardDeleteByDateType(key, 'monthly');
        final res = await AiCommentService.ensureMonthlySaved(eom);
        ok = ((res['comment'] ?? '').toString().trim().isNotEmpty);
      }


      await widget.onDone();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMsg)),
      );
    } catch (e) {
      debugPrint('[AI REGEN] deleteThenRegen error: $e');
      if (!mounted) return;
      // ここは「通信・サーバ」系の失敗とみなして伝える
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('再生成に失敗しました（${e.runtimeType}）')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final hint = (_kind == 'daily')
        ? '日次: 選択日その日が対象（yyyy/MM/dd）'
        : (_kind == 'weekly')
        ? '週次: 選択日の属する「日曜日」が対象（その週のキー）'
        : '月次: 選択日の「月末」が対象（その月のキー）';


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('対象を選択（週次はその週の日曜／月次は月末がキー）'),
        const SizedBox(height: 8),
        Row(
          children: [
            DropdownButton<String>(
              value: _kind,
              items: const [
                DropdownMenuItem(value: 'daily',   child: Text('日次')),
                DropdownMenuItem(value: 'weekly',  child: Text('週次')),
                DropdownMenuItem(value: 'monthly', child: Text('月次')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _kind = v ?? 'daily'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickDate,
              icon: const Icon(Icons.date_range),
              label: Text(_fmt(_picked)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(hint, style: const TextStyle(fontSize: 12, color: Colors.black54)),

        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _busy ? null : _deleteOnly,
              icon: const Icon(Icons.delete_outline),
              label: const Text('対象タイプのみ削除'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _busy ? null : _deleteThenRegen,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('削除 → 再生成'),
            ),
          ],
        ),
        if (_busy) const Padding(
          padding: EdgeInsets.only(top: 8.0),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ],
    );
  }
}
