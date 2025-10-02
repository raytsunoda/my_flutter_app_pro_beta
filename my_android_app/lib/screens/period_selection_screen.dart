import 'package:flutter/material.dart';
import '../widgets/one_week_chart.dart';
import '../widgets/four_weeks_chart.dart';
import '../widgets/one_year_chart.dart';

class PeriodSelectionScreen extends StatefulWidget {
  final List<List<dynamic>> csvData;

  const PeriodSelectionScreen({super.key, required this.csvData});

  @override
  State<PeriodSelectionScreen> createState() => _PeriodSelectionScreenState();
}

class _PeriodSelectionScreenState extends State<PeriodSelectionScreen> {
  String selectedPeriod = '1週間';

  final List<String> periodOptions = ['1日', '1週間', '4週間', '1年'];

  void _navigateToChart() {
    if (selectedPeriod == '1週間') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OneWeekChart(csvData: widget.csvData),
        ),
      );
    } else if (selectedPeriod == '4週間') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FourWeeksChart(csvData: widget.csvData),
        ),
      );
    } else if (selectedPeriod == '1年') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OneYearChart(csvData: widget.csvData),
        ),
      );
    } else {
      // 1日分グラフ未実装時の通知など
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("1日グラフはナビゲーション画面の１日グラフ画面へボタンで表示してください")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('期間選択')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '表示する期間を選んでください',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: selectedPeriod,
                onChanged: (newValue) {
                  setState(() {
                    selectedPeriod = newValue!;
                  });
                },
                items: <String>['1日', '1週間', '4週間', '1年']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _navigateToChart, // ← あなたの遷移関数
                  child: const Text(
                    '保存データを読み込み📊を表示',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

    );
  }
}
