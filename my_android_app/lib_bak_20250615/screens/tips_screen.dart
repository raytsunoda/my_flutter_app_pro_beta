
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:my_android_app/utils/csv_loader.dart';
import 'package:my_android_app/widgets/load_more_button.dart';

class TipsScreen extends StatefulWidget {
  const TipsScreen({Key? key}) : super(key: key);

  @override
  _TipsScreenState createState() => _TipsScreenState();
}

class _TipsScreenState extends State<TipsScreen> {
  List<Map<String, String>> tipsData = [];
  List<Map<String, String>> currentTips = [];
  List<int> steps = [];
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    loadCSV();
  }

  Future<void> loadCSV() async {
    final data = await loadCsvAsMapList('daily_insights.csv');
    setState(() {
      tipsData = data;
      currentTips = getNextThreeRandomTips();
      steps = List<int>.filled(currentTips.length, 0);
    });
  }

  List<Map<String, String>> getNextThreeRandomTips() {
    final random = Random();
    final remaining = List<Map<String, String>>.from(tipsData)..shuffle(random);
    final count = min(3, remaining.length);
    return remaining.take(count).toList();
  }

  void showNextThreeTips() {
    setState(() {
      currentTips = getNextThreeRandomTips();
      steps = List<int>.filled(currentTips.length, 0);
    });
  }

  String _getDisplayText(Map<String, String> item, int step) {
    switch (step) {
      case 0:
        return item['ネガティブ表現'] ?? '';
      case 1:
        return item['ポジティブ表現'] ?? '';
      case 2:
        final episode = item['エピソード']?.trim();
        print('🟡 エピソードの内容: $episode'); // ← ここを追加
        return episode ?? '';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("気持ちが少し楽になるヒント"),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: currentTips.length,
              itemBuilder: (context, index) {
                final item = currentTips[index];
                final step = steps[index];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      steps[index] = (steps[index] + 1) % 3;
                    });
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("No.${item['No.']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),

                          const SizedBox(height: 8),
                          Text(
                            _getDisplayText(item, step),
                            style: const TextStyle(fontSize: 16),



                          ),
                          const SizedBox(height: 4),
                          Text(
                            step == 0
                                ? "📕 タップしてポジティブ表現を見る"
                                : step == 1
                                ? "📗 タップしてエピソードを見る"

                                : "📘 タップしてネガ表現に戻る",
                            style: const TextStyle(fontSize: 14, color: Colors.purple),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          LoadMoreButton(onPressed: showNextThreeTips),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
