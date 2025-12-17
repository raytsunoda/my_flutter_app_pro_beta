import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:my_flutter_app_pro/config/purchase_config.dart';
import 'package:my_flutter_app_pro/services/purchase_service.dart';
import 'package:my_flutter_app_pro/widgets/safety_notice.dart';
import 'package:my_flutter_app_pro/ui/common_error_dialog.dart';
import 'package:url_launcher/url_launcher.dart';



enum PaywallMode { enable, manage }
//
// Future<void> openPaywall(BuildContext context, {required PaywallMode mode}) async {
//   debugPrint('[paywall] openPaywall mode=$mode ENABLED=${PurchaseConfig.ENABLED}');
//   if (!PurchaseConfig.ENABLED) {
//     if (!context.mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('課金は現在準備中です')),
//     );
//     return;
//   }
//   if (!context.mounted) return;
//   await showModalBottomSheet<void>(
//     context: context,
//     isScrollControlled: true,
//     builder: (_) => PaywallSheet(mode: mode),
//   );
// }

// Future<void> openPaywall(BuildContext context, {required PaywallMode mode}) async {
//   debugPrint('[paywall] openPaywall(mode=$mode)');
//
//   if (!context.mounted) {
//     debugPrint('[paywall] context not mounted -> return');
//     return;
//   }
//
//   try {
//     await showModalBottomSheet<void>(
//       context: context,
//       useRootNavigator: true, // ★ これが効くケースが多い
//       isScrollControlled: true,
//       builder: (_) => PaywallSheet(mode: mode),
//     );
//   } catch (e, st) {
//     debugPrint('[paywall] showModalBottomSheet error: $e\n$st');
//   }
// }

Future<void> openPaywall(BuildContext context, {required PaywallMode mode}) async {
  debugPrint('[paywall] openPaywall PUSH mode=$mode');

  if (!context.mounted) {
    debugPrint('[paywall] context not mounted -> return');
    return;
  }

  // BottomSheetではなく「画面遷移」で確実に見せる（Apple確認にも十分）
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text(mode == PaywallMode.enable ? 'Proを有効化' : 'アプリ内課金の管理'),
        ),
        body: PaywallSheet(mode: mode),
      ),
    ),
  );
}








/// ここを StatefulWidget に変更
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key, this.mode = PaywallMode.enable});
  final PaywallMode mode;

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  /// ← ここが質問の `_restoring` の置き場所
  bool _restoring = false;

  // 「この画面について」ダイアログ
  void _showHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('この画面について'),
        content: Text(
          '・Proを有効化：AIパートナーのひとこと等の機能を使えるようにします。\n'
              '月額プランは¥500/月（自動更新）、年額プランは¥4,800/年（自動更新）です。\n'
              '購入を復元：機種変更や再インストール時に、過去の購入を端末に戻します（重複課金なし）。\n'
              '購読管理：端末のサブスクリプション管理画面を開きます',
        ),
      ),
    );
  }
/*
  // ※ restore はサービス側に一本化しました（UI進捗＆結果ダイアログ付き）。
// Future<void> _onRestore() async { /* unused */ }
    setState(() => _restoring = true);
    bool restored = false;
    try {
      restored = await PurchaseService.I.restore();
    } catch (e, st) {
      debugPrint('[restore] ui error: $e\n$st');
    } finally {
      if (!mounted) return;
      setState(() => _restoring = false);
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('購入を復元'),
        content: Text(restored ? '購入情報を復元しました。' : '復元対象が見つかりませんでした。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
*/
  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final title = mode == PaywallMode.enable ? 'Proを有効化' : 'アプリ内課金の管理';
    final desc = mode == PaywallMode.enable
        ? 'Proを有効化すると「AIパートナーのひとこと」が使えるようになります。\n'
        '料金：月額プランは¥500/月（自動更新）、年額プランは¥4,800/年（自動更新）です。'
        : '機種変更・再インストール時は「購入を復元」をご利用ください（重複課金は発生しません）。'
        '購読の解約・切替は「購読管理」から行えます。';

    // ストアから必要な ProductDetails をまとめて取得
    final ids = <String>{ PurchaseIds.monthly, PurchaseIds.yearly };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: FutureBuilder<ProductDetailsResponse>(
          future: InAppPurchase.instance.queryProductDetails(ids),
          builder: (context, snap) {
            // ★ まずはログに必ず出す（何も起きていないのを防ぐ）
            debugPrint('[paywall] FB state=${snap.connectionState} '
                'items=${snap.data?.productDetails.length ?? 0} '
                'notFound=${snap.data?.notFoundIDs}');

            // ★ 読み込み中はインジケータを返す（“準備中”と区別）
            if (snap.connectionState == ConnectionState.waiting &&
                (snap.data?.productDetails.isEmpty ?? true)) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            // 取得できた ProductDetails 一覧
            final products = (snap.data?.productDetails ?? <ProductDetails>[]);

            // id => details
            final byId = { for (final d in products) d.id: d };
            final monthly = byId[PurchaseIds.monthly];
            final yearly  = byId[PurchaseIds.yearly];

            // デバッグ用：通貨 / 取得ID / 見つからないID（空でもテキスト化）
            final currencyDebug = [
              if (monthly != null) monthly.currencyCode,
              if (yearly  != null) yearly.currencyCode,
            ].toSet().join(' / ');
            final gotIds   = products.map((e) => e.id).join(', ');
            final notFound = (snap.data?.notFoundIDs ?? const <String>[]).join(', ');

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ヘッダー
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: '説明',
                      icon: const Icon(Icons.help_outline),
                      onPressed: () => _showHelpDialog(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  desc,
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 12),

// ▼ Apple必須：サブスクリプション条件 + 法的リンク（購入前に確認できること）
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'サブスクリプションについて',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),




                    const SizedBox(height: 4),
                    const Text(
                      '・月額プラン：¥500 / 月（自動更新）\n'
                          '・年額プラン：¥4,800 / 年（自動更新）\n'
                          '・購入確定後、Apple ID に請求されます\n'
                          '・期間終了の24時間前までに解約しない限り自動更新されます',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse('https://www.happiness-h3.com/terms');
                            final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                            if (!ok) {
                              debugPrint('[paywall] could not launch $uri');
                            }
                          },

                          child: const Text(
                            '利用規約',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse('https://www.happiness-h3.com/privacy-policy');
                            final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                            if (!ok) {
                              debugPrint('[paywall] could not launch $uri');
                            }
                          },


                          child: const Text(
                            'プライバシーポリシー',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),







                const SizedBox(height: 16),


                // 有効化モードのときだけ購入ボタンを表示
                if (mode == PaywallMode.enable) ...[

                  // 月額ボタン
                  ElevatedButton(
                    onPressed: monthly == null
                        ? null
                        : () {
                      PLog.info('tap: monthly');
                      PurchaseService.I.buy(monthly);  // ← これだけでOK（内部でUI/結果処理）
                    },
                    child: Text(
                      monthly == null ? '¥500 / 月（準備中）' : '${monthly.price} / 月で月額プラン有効化',
                    ),
                  ),

                  // 年額プランボタン
                  ElevatedButton(
                    onPressed: yearly == null
                        ? null
                        : () {
                      PLog.info('tap: yearly');
                      PurchaseService.I.buy(yearly);   // ← 同上
                    },
                    child: Text(
                      yearly == null ? '¥4,800（年額プラン・準備中）' : '${yearly.price} /年で年額プラン有効化',
                    ),
                  ),

                  const SizedBox(height: 8),
                ],

                // 共通：復元／購読管理
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 「購入を復元」
                    TextButton(
                      onPressed: () async {
                        if (!mounted) return;
                        try {
                          setState(() => _restoring = true);
                          await PurchaseService.I.restoreWithUI(context);
                        } catch (e, st) {
                          debugPrint('[restore] ui error: $e\n$st');
                          if (mounted) await showCommonErrorDialog(context);
                        } finally {
                          if (!mounted) return;
                          setState(() => _restoring = false);
                        }
                      },

                      child: const Text('購入を復元'),
                    ),
                    // 「購読管理」
                    TextButton(
                      onPressed: () async {
                        try {
                          await PurchaseService.I.openManage();
                        } catch (e, st) {
                          debugPrint('[manage] ui error: $e\n$st');
                          if (mounted) await showCommonErrorDialog(context);
                        }
                      },

                      child: const Text('購読管理'),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                if (PurchaseConfig.ENABLED)
                  ValueListenableBuilder<bool>(
                    valueListenable: PurchaseService.I.hasPro,
                    builder: (_, hasPro, __) => AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: hasPro ? 1.0 : 0.0,
                      child: hasPro
                          ? const Text('購入情報が確認できました。Pro が有効です。',
                          style: TextStyle(color: Colors.green))
                          : const SizedBox.shrink(),
                    ),
                  ),
                const SizedBox(height: 12),                  // ★ 少し余白
                const SafetyNotice(padding: EdgeInsets.all(8)), // ★ 注意喚起を下部に
              ],
            );
          },
        ),
      ),
    );
  }
}
