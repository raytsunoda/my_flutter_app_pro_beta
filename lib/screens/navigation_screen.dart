import 'package:flutter/material.dart';
import 'package:my_flutter_app_pro/screens/manual_input_view.dart';
import 'package:my_flutter_app_pro/screens/one_day_view.dart';
import 'package:my_flutter_app_pro/screens/period_selection_screen.dart';
import 'package:my_flutter_app_pro/screens/settings_screen.dart';
import 'package:my_flutter_app_pro/screens/tips_screen.dart';
import 'package:my_flutter_app_pro/screens/quotes_screen.dart';
import 'package:my_flutter_app_pro/utils/csv_loader.dart';

import 'package:my_flutter_app_pro/screens/ai_partner_screen.dart';
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:my_flutter_app_pro/services/purchase_service.dart';
import 'package:my_flutter_app_pro/widgets/paywall_sheet.dart';
import 'package:my_flutter_app_pro/widgets/paywall_sheet.dart'
    show openPaywall, PaywallMode;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final csvData = await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv');

    debugPrint('✅ loadLatestCsvData rows=${csvData.length}');

    if (csvData.length <= 1) {
      debugPrint('⚠️ データ行が無いため空データで遷移');
      final headers = csvData.isNotEmpty
          ? csvData.first.map((e) => e.toString()).toList()
          : List<String>.from(CsvLoader.header);
      final emptyRow = List<String>.filled(headers.length, "");
      final selectedRow = Map<String, dynamic>.fromIterables(headers, emptyRow);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ManualInputView(
            csvData: [headers, emptyRow],
            selectedRow: selectedRow,
          ),
        ),
      );
      return;
    }

    final headers = csvData.first.map((e) => e.toString()).toList();
    final lastRow = csvData.last.map((e) => e.toString()).toList();
    final selectedRow = Map<String, dynamic>.fromIterables(headers, lastRow);

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

  void _goToOneDayView(BuildContext context) async {
    debugPrint('🔔 _goToOneDayView tapped');
    final csvData = await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv');


    if (csvData.length <= 1) {
      debugPrint('⚠️ データ行が無いため空データで遷移');
      final headers = csvData.isNotEmpty
          ? csvData.first.map((e) => e.toString()).toList()
          : List<String>.from(CsvLoader.header);
      final emptyRow = List<String>.filled(headers.length, "");
      final selectedRow = Map<String, String>.fromIterables(headers, emptyRow);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OneDayView(
            csvData: [selectedRow],
            selectedRow: selectedRow,
            selectedDate: DateTime.now(),
          ),
        ),
      );
      return;
    }

    final headers = csvData.first.map((e) => e.toString()).toList();
    final rows = csvData.skip(1).map((row) {
      return Map<String, String>.fromIterables(headers, row.map((e) => e.toString()));
    }).toList();

    rows.sort((a, b) {
      final dateA = DateTime.tryParse(a['日付']!.replaceAll('"', '').replaceAll('/', '-')) ?? DateTime(1970);
      final dateB = DateTime.tryParse(b['日付']!.replaceAll('"', '').replaceAll('/', '-')) ?? DateTime(1970);
      return dateB.compareTo(dateA);
    });

    final selectedRow = rows.first;
    final selectedDate = DateTime.tryParse(selectedRow['日付']!.replaceAll('"', '').replaceAll('/', '-')) ?? DateTime.now();

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
    final csvData = await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv');

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PeriodSelectionScreen(csvData: csvData)),
    );
  }

  //------------------------------------------------------------------
  // 4. Settings
  //------------------------------------------------------------------
  void _goToSettings(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

//------------------------------------------------------------------
  // UI
  //------------------------------------------------------------------

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

            ElevatedButton.icon(
              onPressed: () async {

                if (!kReleaseMode) {
                  // Debug/TestFlightで「購入ボタン付きPaywall」を強制確認したいとき用
                  await openPaywall(context, mode: PaywallMode.enable);
                  return;
                }

                // isPro() を正として扱う（ValueNotifierがズレてても判定が安定）
                final isProBefore = await PurchaseService.I.isPro();
                debugPrint('[nav] AI button: isPro(before)=$isProBefore hasProVN=${PurchaseService.I.hasPro.value}');

                // 未購入なら必ずPaywall（await必須）
                if (!isProBefore) {
                  await openPaywall(context, mode: PaywallMode.enable);

                  // 閉じた後に再判定。未購入なら先へ進ませない
                  final isProAfter = await PurchaseService.I.isPro();
                  debugPrint('[nav] AI button: isPro(after)=$isProAfter hasProVN=${PurchaseService.I.hasPro.value}');
                  if (!isProAfter) return;
                }

                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AIPartnerScreen()),
                );
              },



              onLongPress: () => _showAiInfo(context), // ★ 長押しで説明
              label: const Text('🧡 AIパートナーのひとこと'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
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

  void _showAiInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('AIパートナーのひとこと'),
          content: const Text(
              'あなたの「3つの感謝」や「今日のひとことメモ」、直近のグラフ推移をもとに、'
                  '毎日・週・月の短いコメントを表示します。'
                  '\n\n・Proで利用できます\n・提案は参考情報です\n・医療/法律など重要事項は専門家に確認してください'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }


}
// ===== CSV ローダ（BOM対応・UTF8）========================================

Future<List<List<dynamic>>> _loadCsvRows() async {
  final dir = await getApplicationDocumentsDirectory();
  final f = File('${dir.path}/HappinessLevelDB1_v2.csv');
  if (!await f.exists()) return const [];

  final raw = await f.readAsBytes();
  // BOM除去してデコード
  const bom = [0xEF, 0xBB, 0xBF];
  List<int> body = raw;
  if (raw.length >= 3 && raw[0] == bom[0] && raw[1] == bom[1] && raw[2] == bom[2]) {
    body = raw.sublist(3);
  }
  final text = utf8.decode(body);

  final rows = const CsvToListConverter(eol: '\n').convert(text);
  // 1行も無ければ空を返す
  if (rows.isEmpty) return const [];

  // 先頭行はヘッダ想定、以降データ
  return rows;
}


