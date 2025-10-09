import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:my_flutter_app_pro/config/purchase_config.dart';
import 'package:my_flutter_app_pro/services/purchase_service.dart';
import 'package:my_flutter_app_pro/widgets/safety_notice.dart';

enum PaywallMode { enable, manage }

Future<void> openPaywall(BuildContext context, {required PaywallMode mode}) async {
  debugPrint('[paywall] openPaywall mode=$mode ENABLED=${PurchaseConfig.ENABLED}');
  if (!PurchaseConfig.ENABLED) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('課金は現在準備中です')),
    );
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => PaywallSheet(mode: mode),
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
              '・料金：月額プランは¥500/月、買い切りプランは¥5,100です。\n'
              '・購入を復元：機種変更や再インストール時に、過去の購入を端末に戻します（重複課金なし）。\n'
              '・購読管理：iOS/Androidのサブスクリプション管理画面を開きます。',
        ),
      ),
    );
  }

  // 復元の実処理（成功/未該当どちらでも必ずダイアログ表示）
  Future<void> _onRestore() async {
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

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final title = mode == PaywallMode.enable ? 'Proを有効化' : 'アプリ内課金の管理';
    final desc = mode == PaywallMode.enable
        ? 'Proを有効化すると「AIパートナーのひとこと」が使えるようになります。\n'
        '料金：月額プランは¥500/月、買い切りプランは¥5,100です。'
        : '機種変更・再インストール時は「購入を復元」をご利用ください（重複課金は発生しません）。'
        '購読の解約・切替は「購読管理」から行えます。';

    // ストアから必要な ProductDetails をまとめて取得
    final ids = <String>{ PurchaseIds.monthly, PurchaseIds.lifetime };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: FutureBuilder<ProductDetailsResponse>(
          future: InAppPurchase.instance.queryProductDetails(ids),
          builder: (context, snap) {
            final byId = {
              for (final d in (snap.data?.productDetails ?? <ProductDetails>[])) d.id: d
            };
            final monthly = byId[PurchaseIds.monthly];
            final lifetime = byId[PurchaseIds.lifetime];

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
                const SizedBox(height: 16),

                // 有効化モードのときだけ購入ボタンを表示
                if (mode == PaywallMode.enable) ...[
                  // 月額ボタン
                  ElevatedButton(
                    onPressed: monthly == null
                        ? null
                        : () {
                      PLog.info('tap: monthly');
                      PurchaseService.I.buy(monthly);
                    },
                    child: Text(
                      monthly == null ? '¥500 / 月（準備中）' : '${monthly.price} / 月で有効化',
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 買い切りボタン
                  ElevatedButton(
                    onPressed: lifetime == null
                        ? null
                        : () {
                      PLog.info('tap: lifetime');
                      PurchaseService.I.buy(lifetime);
                    },
                    child: Text(
                      lifetime == null ? '¥5,100（買い切り・準備中）' : '${lifetime.price} で買い切り有効化',
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
                      onPressed: _restoring
                          ? null
                          : () async {
                        PLog.info('tap: restore');
                        await _onRestore();
                      },
                      child: const Text('購入を復元'),
                    ),
                    // 「購読管理」
                    TextButton(
                      onPressed: () async {
                        PLog.info('tap: manage');
                        HapticFeedback.selectionClick();
                        await PurchaseService.I.openManage();
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
