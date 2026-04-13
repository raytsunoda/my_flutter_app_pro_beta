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
import 'package:my_flutter_app_pro/screens/favorite_words_screen.dart';

import '../gen_l10n/app_localizations.dart';
import 'package:my_flutter_app_pro/config/purchase_config.dart';


class NavigationScreen extends StatefulWidget {
  final List<List<dynamic>> csvData;

 // const NavigationScreen({super.key, required this.csvData});
    final int initialIndex;
    const NavigationScreen({
      Key? key,
      required this.csvData,
      this.initialIndex = 0,
    }) : super(key: key);

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}
class _NavigationScreenState extends State<NavigationScreen> {
  late List<List<dynamic>> csvData;
  int _selectedIndex = 0;


  @override
  void initState() {
    super.initState();
    csvData = widget.csvData;
    _selectedIndex = widget.initialIndex;
  }

  Widget _buildNavButton({
    required String label,
    required VoidCallback onPressed,
    required Color color,
    required String contextText,
    IconData? icon,
  }) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        onLongPress: () {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(t.navDetailDialogTitle),
              content: Text(contextText),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t.commonClose),
                ),
              ],
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
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
    final t = AppLocalizations.of(context)!;
    // final lang = Localizations.localeOf(context).languageCode;
    // final isEn = lang == 'en';
    //
    // // Tips/Quotes は当面「日本語のみ」なので、英語UIのときだけ注記を出す（B案：丁寧）
    // final localeCode = Localizations.localeOf(context).languageCode;
    // final tipsJaOnlyNote = (localeCode == 'ja')
    //     ? ''
    //     : '\n\nNote: Tips are currently available only in Japanese. An English version is in preparation.';
    // final quotesJaOnlyNote = (localeCode == 'ja')
    //     ? ''
    //     : '\n\nNote: Quotes are currently available only in Japanese. An English version is in preparation.';

    return Scaffold(

      //appBar: AppBar(title: const Text("ナビゲーション画面")),
      appBar: AppBar(title: Text(t.navTitle)),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildNavButton(
             //   label: "毎日の入力画面へ 📝",
                label: t.navDailyInput,

                onPressed: () => _goToManualInputView(context),
                color: Colors.blue,
                //contextText: "ストレッチ/ウォーキング/睡眠/３つの感謝を記録📝"
                contextText: t.navDailyInputDesc,
            ),
            _buildNavButton(
                //label: "1日グラフで見る 🍩",
                label: t.navOneDayGraph,

                onPressed: () => _goToOneDayView(context),
                color: Colors.blue,
                //contextText: "幸せ感/睡眠/運動/感謝を1日単位でグラフ化📊"
                contextText: t.navOneDayGraphDesc,
            ),
            _buildNavButton(
               // label: "1週・4週・1年グラフで見る 📊",
                label: t.navPeriodGraphs,

                onPressed: () => _goToPeriodSelectionView(context),
                color: Colors.blue,
                //contextText: "1週・4週・1年の傾向を確認できる📊"
                contextText: t.navPeriodGraphsDesc,
            ),
            // _buildNavButton(
            //     //label: "気持ちが少し楽になるヒント 🔍✨",
            //     label: t.navHints,
            //
            //     onPressed: () => Navigator.push(
            //       context,
            //       MaterialPageRoute(builder: (_) => const TipsScreen()),
            //     ),
            //     color: Colors.green,
            //     contextText: "ネガティブな気持ちの時、視点を変えてみると🔍✨"
            // ),

            _buildNavButton(
              label: t.navHints,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TipsScreen()),
              ),
              color: Colors.green,
              contextText: t.navHintsDesc,
            ),

            _buildNavButton(
              label: t.navQuotes,
              icon: Icons.format_quote,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QuotesScreen()),
              ),
              color: Colors.green,
              contextText: t.navQuotesDesc,
            ),

            // ✅ 追加：Favorite Words
            _buildNavButton(
              // 既存の日本語ボタン「あなたのお気に入りの言葉」の復活
              // ※ラベル/説明は l10n に寄せる（下でキーを追加）
              label: t.navFavoriteWords,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FavoriteWordsScreen()),
              ),
              color: Colors.green,
              contextText: t.navFavoriteWordsDesc,
            ),







            ElevatedButton.icon(
              onPressed: () async {

                // if (!kReleaseMode) {
                //   // Debug/TestFlightで「購入ボタン付きPaywall」を強制確認したいとき用
                //   await openPaywall(context, mode: PaywallMode.enable);
                //   return;
                // }
                //
                //
                // //final devForcePro = PurchaseConfig.DEV_FORCE_PRO;
                // final allowAiBefore = PurchaseService.I.isProEffective;

                // ✅ isProEffective に統一（await排除）
                final allowAiBefore = PurchaseService.I.isProEffective;

                debugPrint(
                     '[nav] AI button: allow(before)=$allowAiBefore '
                    //     'hasProVN=${PurchaseService.I.hasPro.value} isProEffective=${PurchaseService.I.isProEffective}',
                         'hasProVN=${PurchaseService.I.hasPro.value} isProEffective=${PurchaseService.I.isProEffective}',
                );

                    if (!allowAiBefore) {
                      await openPaywall(context, mode: PaywallMode.enable);
                      final allowAiAfter = PurchaseService.I.isProEffective;

                  debugPrint(
                     '[nav] AI button: allow(after)=$allowAiAfter '
                     //    'hasProVN=${PurchaseService.I.hasPro.value} isProEffective=${PurchaseService.I.isProEffective}',
                         'hasProVN=${PurchaseService.I.hasPro.value} isProEffective=${PurchaseService.I.isProEffective}',
                  );
                      if (!allowAiAfter) return;
                }

                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AIPartnerScreen()),
                );
              },



              onLongPress: () => _showAiInfo(context), // ★ 長押しで説明
              //label: const Text('🧡 AIパートナーのひとこと'),
              label: Text(t.navAiPartnerButton),

              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),


            _buildNavButton(
              //  label: "⚙️ 設定",
                label: t.navSettingsButton,

                onPressed: () => _goToSettings(context),
                color: Colors.grey,
                //contextText: "通知、重み設定などを変更、保存データの管理ができます⚙️"
                contextText: t.navSettingsDesc

            ),
            const SizedBox(height: 20),
             Center(
              child: Text(
              //  "※ 長押しで説明を表示します",
                t.navLongPressHint,

                style: TextStyle(fontSize: 14, color: Colors.grey),
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
        //items: const [
          items: [
          //BottomNavigationBarItem(icon: Icon(Icons.home), label: "ホーム"),
          //BottomNavigationBarItem(icon: Icon(Icons.close, color: Colors.red), label: "終了"),
          //BottomNavigationBarItem(icon: Icon(Icons.menu), label: "ナビ"),
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: t.bottomHome),
          BottomNavigationBarItem(icon: const Icon(Icons.close, color: Colors.red), label: t.bottomExit),
          BottomNavigationBarItem(icon: const Icon(Icons.menu), label: t.bottomNav),



        ],
      ),

    );
  }

  void _showAiInfo(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          //title: const Text('AIパートナーのひとこと'),
          title: Text(t.navAiPartnerTitle),

          content: Text(t.navAiPartnerInfoBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.commonClose),
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


