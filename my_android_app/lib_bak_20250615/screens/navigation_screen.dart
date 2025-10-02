import 'package:flutter/material.dart';
import 'package:my_android_app/screens/manual_input_view.dart';
import 'package:my_android_app/screens/one_day_view.dart';
import 'package:my_android_app/screens/period_selection_screen.dart';
import 'package:my_android_app/screens/settings_screen.dart';
import 'package:my_android_app/screens/tips_screen.dart';
import 'package:my_android_app/screens/quotes_screen.dart';
import 'package:my_android_app/utils/csv_loader.dart';

class NavigationScreen extends StatefulWidget {
  final List<List<dynamic>> csvData;

  const NavigationScreen({super.key, required this.csvData});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}
class _NavigationScreenState extends State<NavigationScreen> {
  late List<List<dynamic>> csvData;

  @override
  void initState() {
    super.initState();
    csvData = widget.csvData;
  }

  Widget _buildNavButton({
    required String label,
    required VoidCallback onPressed,
    required Color color,
    required String contextText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        onLongPress: () {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('このボタンの説明'),
              content: Text(contextText),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

//------------------------------------------------------------------
  // 1. 毎日の入力
  //------------------------------------------------------------------



  void _goToManualInputView(BuildContext context) async {
    debugPrint('🔔 _goToManualInputView tapped');
    final csvData = await loadLatestCsvData('HappinessLevelDB1_v2.csv');
    debugPrint('✅ loadLatestCsvData rows=${csvData.length}');

    if (csvData.length <= 1) {
      debugPrint('⚠️ csvData has no data rows, returning');
      return;
    }

    final headers = csvData.first.map((e) => e.toString()).toList();
    final lastRow = csvData.last.map((e) => e.toString()).toList();
    final selectedRow = Map<String, dynamic>.fromIterables(headers, lastRow);

    print("✅ Navigating to ManualInputView with latest row: $selectedRow");

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManualInputView(
          csvData: csvData,
          selectedRow: selectedRow,
        ),
      ),
    );
  }
//------------------------------------------------------------------
  // 2. 1日グラフ
  //------------------------------------------------------------------

  void _goToOneDayView(BuildContext context) async {
    final csvData = await loadLatestCsvData('HappinessLevelDB1_v2.csv');
    if (csvData.length <= 1) return;

    // ── Map 化
    final headers = csvData.first.map((e) => e.toString()).toList();
    final rows = csvData.skip(1).map((row) {
      return Map<String, String>.fromIterables(headers, row.map((e) => e.toString()).toList());
    }).toList();

    // ── 日付でソート（正規化してから）
    rows.sort((a, b) {
      final dateA = DateTime.tryParse(a['日付']!.replaceAll('"', '').replaceAll('/', '-')) ?? DateTime(1970);
      final dateB = DateTime.tryParse(b['日付']!.replaceAll('"', '').replaceAll('/', '-')) ?? DateTime(1970);
      return dateB.compareTo(dateA);
    });

    final selectedRow  = rows.first;
    final selectedDate = DateTime.tryParse(selectedRow['日付']!.replaceAll('"', '').replaceAll('/', '-'));
    if (selectedDate == null) return;

    print("✅ Navigating to OneDayView with selectedRow: $selectedRow");

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OneDayView(
          csvData: rows,
          selectedRow: selectedRow,
          selectedDate: selectedDate,
        ),
      ),
    );
  }

  //------------------------------------------------------------------
  // 3. 週・月・年グラフ
  //------------------------------------------------------------------

  void _goToPeriodSelectionView(BuildContext context) async {
    final csvData = await loadLatestCsvData('HappinessLevelDB1_v2.csv');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PeriodSelectionScreen(csvData: csvData),
      ),
    );
  }

  void _goToSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ナビゲーション画面")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildNavButton(
                label: "毎日の入力画面へ 📝",
                onPressed: () => _goToManualInputView(context),
                color: Colors.blue,
                contextText: "ストレッチ/ウォーキング/睡眠/３つの感謝を記録📝"
            ),
            _buildNavButton(
                label: "1日グラフで見る 🍩",
                onPressed: () => _goToOneDayView(context),
                color: Colors.blue,
                contextText: "幸せ感/睡眠/運動/感謝を1日単位でグラフ化📊"
            ),
            _buildNavButton(
                label: "1週・4週・1年グラフで見る 📊",
                onPressed: () => _goToPeriodSelectionView(context),
                color: Colors.blue,
                contextText: "1週・4週・1年の傾向を確認できる📊"
            ),
            _buildNavButton(
                label: "気持ちが少し楽になるヒント 🔍✨",
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TipsScreen()),
                ),
                color: Colors.green,
                contextText: "ネガティブな気持ちの時、視点を変えてみると🔍✨"
            ),
            _buildNavButton(
                label: "名言をチェック 📜✨",
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QuotesScreen()),
                ),
                color: Colors.green,
                contextText: "やる気向上、ストレス・不安軽減のヒントに🔍✨"
            ),
            _buildNavButton(
                label: "⚙️ 設定",
                onPressed: () => _goToSettings(context),
                color: Colors.grey,
                contextText: "通知、重み設定などを変更、保存データの管理ができます⚙️"
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                "※ 長押しで説明を表示します",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),










      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) {
            Navigator.pop(context); // ホームへ戻る
          } else if (index == 2) {
            // ナビ画面なので何もしない
          } else if (index == 1) {
            Navigator.of(context).pop(); // 終了
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "ホーム"),
          BottomNavigationBarItem(icon: Icon(Icons.close, color: Colors.red), label: "終了"),
          BottomNavigationBarItem(icon: Icon(Icons.menu), label: "ナビ"),
        ],
      ),




    );
  }

}
