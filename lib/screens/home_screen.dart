// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'navigation_screen.dart';
import '../utils/notification_scheduler.dart';
import '../utils/date_utils.dart';
import 'package:my_flutter_app_pro/config/purchase_config.dart';
import 'package:my_flutter_app_pro/services/purchase_service.dart';
//import 'package:my_flutter_app_pro/widgets/paywall_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart'; // HapticFeedback 用
import 'package:my_flutter_app_pro/widgets/paywall_sheet.dart'
    show openPaywall, PaywallMode;
import 'package:flutter/foundation.dart';
import 'package:my_flutter_app_pro/widgets/paywall_sheet.dart' show openPaywall, PaywallMode;
import '../gen_l10n/app_localizations.dart';
import 'package:my_flutter_app_pro/utils/notification_scheduler.dart';
import 'package:package_info_plus/package_info_plus.dart';

class HomeScreen extends StatefulWidget {
  final List<List<dynamic>> csvData;
  const HomeScreen({super.key, required this.csvData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  // === Typography knobs (調整ノブ) ===
  static const double kCatchLine1Size = 15.0;
  static const double kCatchLine2Size = 12.0;

  static const double kCardTitleSize  = 14.5;   // カードのタイトル「Pro機能の有効化 / 復元」
  static const double kCardBodySize   = 12.0;   // カード本文
  static const double kCardLineHeight = 1.45;   // カード本文の行間

  bool _isPro = false;
  bool _showProBanner = true;
  bool _paywallShownOnce = false;
  String _versionText = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();

    debugPrint('[home] ENABLED=${PurchaseConfig.ENABLED}');
    // Pro状態も見たい時
    debugPrint('[home] hasPro=${PurchaseService.I.hasPro.value}');

    () async {
      _isPro = await PurchaseService.I.isPro(); // Pro購入済み？
      if (mounted) setState(() {});

      // 初期スケジュール（従来の microtask はここに移動）
      // await scheduleWeeklyReminderOnSunday();
      // await scheduleMonthlyReminderOnLastDay();
     // 週次/月次は main.dart → NotificationService/NotificationScheduler で一元管理

      final existing = await loadExistingDataDates();
      debugPrint('[DEBUG] existing dates: ${existing.map(fmtYMD).toList()}');

      final sp = await SharedPreferences.getInstance();
      _showProBanner = !(sp.getBool('dismiss_pro_banner') ?? false);
      if (mounted) setState(() {});

      // // ▼ Apple指摘確認用：起動直後に1回だけPaywallを出す（確認後に削除OK）
      // WidgetsBinding.instance.addPostFrameCallback((_) async {
      //   if (!mounted || _paywallShownOnce) return;
      //   _paywallShownOnce = true;
      //
      //   // すでにProなら出さない（復元済みの人に出ないように）
      //   final hasProNow = PurchaseService.I.hasPro.value;
      //   if (hasProNow) return;
      //
      //   await openPaywall(context, mode: PaywallMode.enable);
      // });


    }();
  }


  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;

    setState(() {
      _versionText = 'v${info.version} (${info.buildNumber})';
    });
  }



  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        // 少しだけ高さを足して下段キャッチを表示
        toolbarHeight: 76,
      //  title: const Text('幸せ感ナビPro'),
        title: Text(
          t.homeAppTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.black87,
          ),
        ),

        // ▼ここがキャッチ
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1行目：説明
                Text(
                //  '心と身体の“健康習慣”づくりをサポート',

                    t.homeTagline,


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
                        //  'AIパートナーが、あなたの毎日にそっと伴走',
                          t.homeHeroCopy,


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

                      ],
                    ),
                    // ※ 「（Proで…）」の行は削除（2025-09-22）
                  ],
                ),

              ],
            ),
          ),
        ),


        //


        actions: [
          if (PurchaseConfig.ENABLED)
            IconButton(
            //  tooltip: 'アプリ内課金の管理',
              tooltip: t.homeIapManageTooltip,

              icon: const Icon(Icons.manage_accounts),
              onPressed: () async {
                await openPaywall(context, mode: PaywallMode.manage);
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
              Text(
                t.homeWelcomeTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NavigationScreen(csvData: widget.csvData),
                    ),
                  );
                },
                child: Text(t.goToNavigation),
              ),

              const SizedBox(height: 12),

              ValueListenableBuilder<bool>(
                valueListenable: PurchaseService.I.hasPro,
                builder: (context, hasPro, _) {
                  if (hasPro) return const SizedBox.shrink();
                  return ElevatedButton(
                    onPressed: () async {
                      await openPaywall(context, mode: PaywallMode.enable);
                    },
                    child: Text(t.homeEnableProButton),
                  );
                },
              ),

              const SizedBox(height: 16),

              if (_versionText.isNotEmpty)
                Text(
                  _versionText,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
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
          final showCard = (!hasPro) || PurchaseConfig.DEV_FORCE_PRO || !kReleaseMode;

          if (!showCard) return const SizedBox.shrink();

          return SafeArea(
            minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(
             //     'Pro機能の有効化 / 復元',
                  t.homeProCardTitle,

                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: kCardTitleSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                subtitle: Text(
              //    '「AIパートナーのひとこと」を使うにはProが必要です。\n'
              //        '機種変更・再インストール時は「過去の購入を復元」をご利用ください（重複課金なし）。',
                  t.homeProCardDesc,

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
                    await openPaywall(context, mode: PaywallMode.enable);

                  },
               //   child: const Text('有効化'),
                  child: Text(t.proEnableAction),

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