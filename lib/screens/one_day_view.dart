import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_flutter_app_pro/widgets/donut_chart.dart';
import 'package:my_flutter_app_pro/widgets/radar_chart_widget.dart';
import 'package:my_flutter_app_pro/l10n/strings_ja.dart';
import '../utils/history_data.dart';

/// ---- レーダー用スコア算出：CSV優先（空のときだけ簡易計算にフォールバック）----
List<double> _calcRadarScoresFromRow(Map<String, String>? row) {
  if (row == null || row.isEmpty) return const [0, 0, 0, 0];

  double _num(String? v) {
    if (v == null) return 0;
    final t = v.trim();
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? 0;
  }

  // 1) 睡眠の質：CSV「睡眠の質」をそのまま 0–100（無ければ3点の平均×25）
  double sleepQ = _num(row['睡眠の質']);
  if (sleepQ <= 0) {
    final n1 = _num(row['寝付き満足度']); // 1..4
    final n2 = _num(row['深い睡眠感']);   // 1..4
    final n3 = _num(row['目覚め感']);     // 1..4
    final cnt = [n1, n2, n3].where((e) => e > 0).length;
    sleepQ = (cnt > 0) ? ((n1 + n2 + n3) / cnt) * 25.0 : 0;
  }
  sleepQ = sleepQ.clamp(0, 100);

  // 2) 感謝：入力件数（感謝1〜3）→ 0/34/67/100
  int gCount = 0;
  for (final key in ['感謝1', 'gratitude1', '感謝2', 'gratitude2', '感謝3', 'gratitude3']) {
    final t = (row[key] ?? '').trim();
    if (t.isNotEmpty) gCount++;
  }
  final double gratitude = (gCount <= 0) ? 0.0 : (gCount == 1) ? 34.0 : (gCount == 2) ? 67.0 : 100.0;

  // 3) ウォーキング：90分で満点
  final walkMin = _num(row['ウォーキング時間']);
  final double walkScore = (walkMin <= 0) ? 0.0 : (walkMin / 90.0 * 100.0).clamp(0, 100);

  // 4) ストレッチ：30分で満点
  final stretchMin = _num(row['ストレッチ時間']);
  final double stretchScore = (stretchMin <= 0) ? 0.0 : (stretchMin / 30.0 * 100.0).clamp(0, 100);

  return <double>[sleepQ, gratitude, walkScore, stretchScore];
}

/// yyyy/MM/dd で正規化
String _normYmd(DateTime d) => DateFormat('yyyy/MM/dd').format(d);
String _normYmdStr(String s) {
  s = s.trim();
  if (s.isEmpty) return s;
  final p = s.split('/');
  if (p.length != 3) return s;
  return '${p[0].padLeft(4, '0')}/${p[1].padLeft(2, '0')}/${p[2].padLeft(2, '0')}';
}

class OneDayView extends StatefulWidget {
  final List<Map<String, String>> csvData;     // 設定＞保存データの管理 と同じ配列
  final Map<String, String>? selectedRow;      // 呼び出し元から渡るなら使用（無ければ内部で当日/最新日を選ぶ）
  final DateTime? selectedDate;                // 同上

  const OneDayView({
    super.key,
    required this.csvData,
    this.selectedRow,
    this.selectedDate,
  });

  @override
  State<OneDayView> createState() => _OneDayViewState();
}

class _OneDayViewState extends State<OneDayView> {
  late HistoryData _hist;
  late DateTime _selectedDate;
  Map<String, String>? _selectedRow;

  // === ひとことメモ ===
  String _memoText = '';

  @override
  void initState() {
    super.initState();
    _hist = HistoryData.fromCsv(widget.csvData);

    // 基準日（当日が無ければ CSV の最新日）
    final today = DateTime.now();
    final hasToday = widget.csvData.any((r) => _normYmdStr(r['日付'] ?? '') == _normYmd(today));
    _selectedDate = widget.selectedDate ?? (hasToday ? today : (_latestDateInCsv() ?? today));

    // 選択日の行を厳密一致で取得してセット
    _updateSelectedRow(_selectedDate);

    // 先にメモを確定（←「今日のひとことメモが表示されない」症状の原因箇所）
    _loadMemoFor(_selectedDate);
  }

  DateTime? _latestDateInCsv() {
    final dates = widget.csvData
        .map((r) => _normYmdStr(r['日付'] ?? ''))
        .where((s) => s.contains('/'))
        .map((s) {
      final p = s.split('/');
      return DateTime.tryParse('${p[0]}-${p[1]}-${p[2]}');
    })
        .whereType<DateTime>()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return dates.isEmpty ? null : dates.first;
  }

  void _updateSelectedRow(DateTime date) {
    final wanted = _normYmd(date);
    final row = widget.csvData.firstWhere(
          (r) => _normYmdStr(r['日付'] ?? '') == wanted,
      orElse: () => <String, String>{},
    );
    setState(() {
      _selectedDate = date;
      _selectedRow = row.isEmpty ? null : Map<String, String>.from(row);
    });
  }

  void _loadMemoFor(DateTime date) {
    final memo = _hist.memoAt(date);
    setState(() {
      _memoText = memo.isEmpty ? J.memoNone : memo;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _updateSelectedRow(picked);
      _loadMemoFor(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _normYmd(_selectedDate);

    if (_selectedRow == null || _selectedRow!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('1日グラフ')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('📅 $dateStr'),
              const SizedBox(height: 8),
              const Text('指定の日のデータが未入力のため、表示されません。'),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _pickDate, child: const Text('別の日付を選ぶ')),
            ],
          ),
        ),
      );
    }

    final row = _selectedRow!;
    final happinessLevel = double.tryParse((row['幸せ感レベル'] ?? '').toString()) ?? 0.0;
    final scores = _calcRadarScoresFromRow(row)
        .map((s) => (s.isNaN || s.isInfinite) ? 0.0 : s)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('1日グラフ'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(children: [Icon(Icons.calendar_month), SizedBox(width: 8), Text('幸せ感レベル')]),
                InkWell(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.purple),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(dateStr),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(height: 200, child: DonutChart(happinessLevel: happinessLevel)),

            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: 250,
                height: 250,
                // RadarChartWidget の引数が scores: List<double> の場合はこの行 ↓ を使う
                child: RadarChartWidget(
                  labels: const ['睡眠の質', '感謝', 'ウォーキング', 'ストレッチ'],
                  scores: scores,
                ),
                // もし data: List<List<double>> を要求する版なら、↑を消して↓に置き換え
                // child: RadarChartWidget(labels: const ['睡眠の質','感謝','ウォーキング','ストレッチ'], data: [scores]),
              ),
            ),

            const SizedBox(height: 24),
            const Text('🙏 3つの感謝', style: TextStyle(fontWeight: FontWeight.bold)),
            for (int i = 1; i <= 3; i++)
              Align(alignment: Alignment.centerLeft, child: Text('$i. ${row['感謝$i'] ?? ''}')),

            const SizedBox(height: 16),
            const Text('🌱 今日のひとことメモ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.sticky_note_2_outlined),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _memoText.isEmpty ? J.memoNone : _memoText,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
