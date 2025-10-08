// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'navigation_screen.dart';
import '../utils/notification_scheduler.dart';
import '../utils/date_utils.dart';
import 'package:my_flutter_app_pro/config/purchase_config.dart';
import 'package:my_flutter_app_pro/services/purchase_service.dart';
import 'package:my_flutter_app_pro/widgets/paywall_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart'; // HapticFeedback 用
import 'package:my_flutter_app_pro/widgets/paywall_sheet.dart'
    show openPaywall, PaywallMode;




class HomeScreen extends StatefulWidget {
  final List<List<dynamic>> csvData;
  const HomeScreen({super.key, required this.csvData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  // === Typography knobs (調整ノブ) ===
  static const double kCatchLine1Size = 15.5;   // 見出し「心と身体…」
  static const double kCatchLine2Size = 12.5;   // 強調「約¥10/日で…」

  static const double kCardTitleSize  = 14.5;   // カードのタイトル「Pro機能の有効化 / 復元」
  static const double kCardBodySize   = 12.0;   // カード本文
  static const double kCardLineHeight = 1.45;   // カード本文の行間

  bool _isPro = false;
  bool _showProBanner = true;


  @override
  void initState() {
    super.initState();
    debugPrint('[home] ENABLED=${PurchaseConfig.ENABLED}');
    // Pro状態も見たい時
    debugPrint('[home] hasPro=${PurchaseService.I.hasPro.value}');

    () async {
      _isPro = await PurchaseService.I.isPro(); // Pro購入済み？
      if (mounted) setState(() {});

      // 初期スケジュール（従来の microtask はここに移動）
      await scheduleWeeklyReminderOnSunday();
      await scheduleMonthlyReminderOnLastDay();
      final existing = await loadExistingDataDates();
      debugPrint('[DEBUG] existing dates: ${existing.map(fmtYMD).toList()}');

      final sp = await SharedPreferences.getInstance();
      _showProBanner = !(sp.getBool('dismiss_pro_banner') ?? false);
      if (mounted) setState(() {});

    }();
  }






  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 少しだけ高さを足して下段キャッチを表示
        toolbarHeight: 80,
        title: const Text('幸せ感ナビPro'),
        // ▼ここがキャッチ
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1行目：説明
                Text(
                  '心と身体の“健康習慣”づくりをサポート',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: kCatchLine1Size,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    color: (Theme.of(context).appBarTheme.foregroundColor
                        ?? Theme.of(context).colorScheme.onSurface)
                        .withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 2),
                // 2行目+注釈（3行目）
                // 2行目のみ（注釈行は削除）
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'AIパートナーが、あなたの毎日にそっと伴走',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: kCatchLine2Size,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                            color: (Theme.of(context).appBarTheme.foregroundColor
                                ?? Theme.of(context).colorScheme.onSurface)
                                .withValues(alpha: 0.90),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _showPricingNote(context),
                          child: Icon(
                            Icons.info_outline,
                            size: 16,
                            color: (Theme.of(context).appBarTheme.foregroundColor
                                ?? Theme.of(context).colorScheme.onSurface)
                                .withValues(alpha: 0.70),
                          ),
                        ),
                      ],
                    ),
                    // ※ 「（Proで…）」の行は削除（2025-09-22）
                  ],
                ),

              ],
            ),
          ),
        ),


        actions: [
          if (PurchaseConfig.ENABLED)
            ValueListenableBuilder<bool>(
              valueListenable: PurchaseService.I.hasPro,
              builder: (_, hasPro, __) {
                if (hasPro) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'アプリ内課金の管理',
                  icon: const Icon(Icons.workspace_premium_outlined),

                  onPressed: () => openPaywall(context, mode: PaywallMode.manage),
                );
              },
            ),
        ],
      ),


      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '幸せ感ナビProに\nようこそ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NavigationScreen(csvData: widget.csvData),
                    ),
                  );
                },
                child: const Text('ナビゲーション画面へ'),
              ),
            ],
          ),
        ),
      ),

      // テストを楽にするため、DEV_FORCE_PRO でもカードを出す
      bottomNavigationBar: (PurchaseConfig.ENABLED || PurchaseConfig.DEV_FORCE_PRO)
          ? ValueListenableBuilder<bool>(
        valueListenable: PurchaseService.I.hasPro,
        builder: (context, hasPro, _) {
          // Pro未購入 もしくは DEV_FORCE_PRO のときに表示
          final showCard = (!hasPro) || PurchaseConfig.DEV_FORCE_PRO;
          if (!showCard) return const SizedBox.shrink();

          return SafeArea(
            minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(
                  'Pro機能の有効化 / 復元',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: kCardTitleSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                subtitle: Text(
                  '「AIパートナーのひとこと」を使うにはProが必要です。\n'
                      '機種変更・再インストール時は「過去の購入を復元」をご利用ください（重複課金なし）。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: kCardBodySize,
                    height: kCardLineHeight,
                    color: Theme.of(context).colorScheme.onSurface..withValues(alpha: 0.78),
                  ),
                ),
                trailing: TextButton(
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    await Future.microtask(() {}); // まれな描画直後のタップ潰れ対策
                    if (!context.mounted) return;
                    openPaywall(context, mode: PaywallMode.enable);
                  },
                  child: const Text('有効化'),
                ),
                onTap: () async { /* 既存のまま */ },
              ),
            ),

          );
        },
      )
          : null,




    );
  }
  void _showPricingNote(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('AIパートナーのひとこと'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Bullet('気持ちに寄り添うひとことで心を整える後押し'),
            const _Bullet('その日の記録に合わせた短いヒントで一緒に振り返り'),
            const _Bullet('“続ける”を支える軽い読み心地と適度な頻度'),
            const SizedBox(height: 8),
            Text(
              'この機能は Pro でご利用いただけます。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Opacity(
              opacity: 0.70,
              child: Text(
                '料金：月額¥500（自動更新／月単位で解約可）。'
                    '買い切りプラン¥5,100です。',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

}
// 箇条書き用の小さな補助ウィジェット（同ファイルのどこでもOK）
class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}