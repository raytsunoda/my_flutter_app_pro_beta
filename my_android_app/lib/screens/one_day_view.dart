import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_android_app/widgets/donut_chart.dart';
import 'package:my_android_app/widgets/radar_chart_widget.dart';

class OneDayView extends StatefulWidget {
  final List<Map<String, String>> csvData;
  final Map<String, String> selectedRow;
  final DateTime selectedDate;
  const OneDayView({
    Key? key,
    required this.csvData,
    required this.selectedRow,
    required this.selectedDate,
  }) : super(key: key);

  @override
  State<OneDayView> createState() => _OneDayViewState();
}

class _OneDayViewState extends State<OneDayView> {
  DateTime selectedDate = DateTime.now();
  Map<String, String>? selectedRow;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.selectedDate;       // 親からの初期日付を使用
    selectedRow = widget.selectedRow;         // 親からの初期行を使用
 //   _updateSelectedRow(selectedDate);
  }







  void _updateSelectedRow(DateTime date) {
    final dateString = DateFormat('yyyy/MM/dd').format(date);
    final row = widget.csvData.firstWhere(
          (row) => row['日付'] == dateString,
      orElse: () => {},
    );

    setState(() {
      selectedDate = date;
      selectedRow = row.isNotEmpty ? row : null;
    });

    debugPrint('[DEBUG] 選択されたCSV行: $row');
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('yyyy/MM/dd');
    final selectedDateString = dateFormatter.format(selectedDate);
    final row = selectedRow;

    double tryParseOrZero(String? value) => double.tryParse(value ?? '') ?? 0.0;
    double normalizeScore(double value, double max) => max == 0 ? 0.0 : (value.clamp(0, max) / max) * 100;

    double stretch = 0, walking = 0, appreciation = 0, sleepQuality = 0, happinessLevel = 0;

    if (row != null && row.isNotEmpty) {
      print('[DEBUG] row 該当日データ: $row');

      happinessLevel = double.tryParse(row['幸せ感レベル'] ?? '0.0') ?? 0.0;
      final sleepHours = int.tryParse(row['睡眠時間（時間）'] ?? '') ?? 0;
      final fallingAsleepSatisfaction = int.tryParse(row['寝付き満足度'] ?? '') ?? 0;
      final deepSleepFeeling = int.tryParse(row['深い睡眠感'] ?? '') ?? 0;
      final wakeUpFeeling = int.tryParse(row['目覚め感'] ?? '') ?? 0;
      final motivation = int.tryParse(row['モチベーション'] ?? '') ?? 0;

      final appreciation1 = row['感謝1'] ?? '';
      final appreciation2 = row['感謝2'] ?? '';
      final appreciation3 = row['感謝3'] ?? '';
      final appreciationCount = [appreciation1, appreciation2, appreciation3].where((e) => e.trim().isNotEmpty).length;

      stretch = normalizeScore(tryParseOrZero(row['ストレッチ時間']), 30);
      walking = normalizeScore(tryParseOrZero(row['ウォーキング時間']), 90);
      appreciation = normalizeScore(appreciationCount.toDouble(), 3);

      final f1 = (sleepHours / 8) * 100 * 0.2;
      final f2 = (fallingAsleepSatisfaction / 5) * 100 * 0.2;
      final f3 = (deepSleepFeeling / 5) * 100 * 0.2;
      final f4 = (wakeUpFeeling / 5) * 100 * 0.2;
      final f5 = (motivation / 5) * 100 * 0.2;
      sleepQuality = f1 + f2 + f3 + f4 + f5;

      print('[DEBUG] --- RadarChart用スコア抽出開始 ---');
      print('[DEBUG] selectedRow = $row');
      print('[DEBUG] 睡眠の質 = $sleepQuality');
      print('[DEBUG] 感謝スコア = $appreciation');
      print('[DEBUG] ウォーキングスコア = $walking');
      print('[DEBUG] ストレッチスコア = $stretch');
      print('[DEBUG] --- 抽出完了 ---');
    }

   // final scores = [sleepQuality, appreciation, walking, stretch];
    final rawScores = [sleepQuality, appreciation, walking, stretch];

// NaNや無限大があれば全て0に置き換え（描画クラッシュ回避）
    final scores = rawScores.map((s) =>
    (s.isNaN || s.isInfinite) ? 0.0 : s
    ).toList();


    print('[DEBUG] RadarChartに渡す scores = $scores');

    return Scaffold(
      appBar: AppBar(
        title: const Text('1日グラフ'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
    //    automaticallyImplyLeading: true,
    //  ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.calendar_month),
                      SizedBox(width: 8),
                      Text('幸せ感レベル'),
                    ],
                  ),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2024, 1, 1),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        _updateSelectedRow(picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.purple),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(selectedDateString),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: DonutChart(happinessLevel: happinessLevel),
              ),
              const SizedBox(height: 24),
              Center(
                child: SizedBox(
                  width: 250,
                  height: 250,
                  child: RadarChartWidget(
                    labels: ['睡眠の質', '感謝', 'ウォーキング', 'ストレッチ'],
                    scores: scores,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('🙏 3つの感謝', style: TextStyle(fontWeight: FontWeight.bold)),
              for (int i = 1; i <= 3; i++)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('$i. ${selectedRow?['感謝$i'] ?? ''}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
