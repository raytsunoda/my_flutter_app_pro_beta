import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart'; // iOS 管理画面用
//import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/purchase_config.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
// ...
/*
/// OSの購読管理画面を開く（URL遷移に一本化）
Future<void> openManage() async {
  PLog.info('manage: open subscriptions screen');
  try {
    final url = Platform.isIOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    if (await canLaunchUrlString(url)) {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } else {
      PLog.error('manage: cannot open $url');
    }
  } catch (e, st) {
    debugPrint('[manage] fatal: $e\n$st');
    final url = Platform.isIOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }
}
*/
// Fallback / Android

// ==== 追加：プロダクトID定義 ====
class PurchaseIds {
  // App Store Connect > サブスクリプションで作った製品ID
  static const monthly  = 'pro_monthly_500_auto';
  static const yearly = 'pro_yearly_4800_auto';
  static const ids = {monthly, yearly};
}


class PurchaseService {




  // 開発用：ビルドフラグでも強制Pro
  static const bool _kForceProFromBuild =
  bool.fromEnvironment('FORCE_PRO', defaultValue: false);

  bool _restoring = false; // 二重タップ防止


  PurchaseService._();
  static final PurchaseService I = PurchaseService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  final Set<String> _productIds = PurchaseIds.ids;

  bool available = false;
  List<ProductDetails> products = [];
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// アプリ全体で参照する Pro 権限（購読状態）
  final ValueNotifier<bool> hasPro = ValueNotifier<bool>(false);

  // 取得した商品をキャッシュ
  final Map<String, ProductDetails> _products = {};

  // ストアから商品を読み込み（起動時に呼ぶ）
  Future<void> loadProducts() async {
    try {
      final resp = await _iap.queryProductDetails(PurchaseIds.ids);
      products = resp.productDetails;
      _products
        ..clear()
        ..addEntries(products.map((p) => MapEntry(p.id, p)));
      for (final p in products) {
        PLog.ok('product loaded: id=${p.id} title=${p.title} price=${p.price} currency=${p.currencyCode} raw=${p.rawPrice}');
      }
      if (_products.isEmpty) {
        PLog.warn('product loaded: 0 item(s). ID不一致/反映待ちの可能性');
      }
    } catch (e) {
      PLog.err('loadProducts failed: $e');
    }
  }

  // 任意のIDで買えるヘルパ（UIから使いやすい）
  // 任意のIDで買えるヘルパ（UIから使いやすい）
  Future<void> buyById(BuildContext context, String productId) async {
    final details = _products[productId];
    if (details == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('購入情報の取得中です。数秒後に再度お試しください。')),
        );
      }
      return;
    }

    try {
      PLog.info('buy: start id=$productId price=${details.price}${details.currencyCode}');
      final param = PurchaseParam(productDetails: details);
      await _iap.buyNonConsumable(purchaseParam: param); // サブスクもOK
      PLog.trace('buy: sheet presented');
    } catch (e, st) {
      debugPrint('[buy] fatal: $e\n$st');
      // ここは「サービス層」なので、UIダイアログは呼び出し元(UI)で表示します。
      // （paywall_sheet.dart 側で try/catch + showCommonErrorDialog を実装済みにします）
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('購入に失敗しました。ネットワーク環境をご確認のうえ、もう一度お試しください。')),
        );
      }
    }
  }


  Future<void> init() async {
    if (PurchaseConfig.DEV_FORCE_PRO || _kForceProFromBuild) {
      debugPrint('[Purchase] FORCE_PRO enabled (env/build). gating OFF.');
      hasPro.value = true;
      return;
    }

    available = await _iap.isAvailable();

    // 商品ロード（↑のヘルパを使用）
    await loadProducts();

    // （重複だが安全のため）もう一度直接問い合わせ
    final resp = await _iap.queryProductDetails(PurchaseIds.ids);
    products = resp.productDetails;
    for (final p in products) {
      PLog.ok('product loaded: id=${p.id} title=${p.title} price=${p.price} currency=${p.currencyCode} raw=${p.rawPrice}');
    }
    if (products.isEmpty) {
      PLog.warn('product loaded: 0 item(s). App Store Connect 反映待ち/ID不一致の可能性');
    }

    _sub = _iap.purchaseStream.listen((events) {
      PLog.info('stream: got ${events.length} event(s)');
      _onPurchaseUpdated(events);
    }, onError: (e, st) {
      PLog.err('stream error: $e\n$st');
    });

    final sp = await SharedPreferences.getInstance();
    hasPro.value = sp.getBool('hasPro') ?? false;
  }

  Future<void> dispose() async => _sub?.cancel();

  Future<bool> isPro() async => hasPro.value;

  Future<void> buy(ProductDetails p) async {
    final param = PurchaseParam(productDetails: p);
    await _iap.buyNonConsumable(purchaseParam: param); // サブスク/買切りの両方で可
  }

  /// 進捗UIなしの復元（UI側でスピナーを出す想定）
  Future<bool> restore() async {
    PLog.info('restore: begin');
    final ok = await _restoreInternal();
    PLog.info('restore: end ok=$ok (hasPro=${hasPro.value})');
    return ok;
  }


  /// ValueListenable<bool> の true を待つ補助（timeout は Any 側で管理）
  Future<bool> _waitHasProTrue(Duration maxWait) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < maxWait) {
      if (hasPro.value) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  /// hasPro に切り替わるのを最長3秒待って判定
  Future<bool> _waitForProFlag({Duration timeout = const Duration(seconds: 3)}) async {
    if (hasPro.value) return true;
    final c = Completer<bool>();
    late VoidCallback l;
    final t = Timer(timeout, () {
      try { hasPro.removeListener(l); } catch (_) {}
      if (!c.isCompleted) c.complete(hasPro.value);
    });
    l = () {
      if (hasPro.value && !c.isCompleted) {
        t.cancel();
        hasPro.removeListener(l);
        c.complete(true);
      }
    };
    hasPro.addListener(l);
    return c.future;
  }

  int? _lastTxn; // クラスフィールドに追加
  Future<void> _onPurchaseUpdated(List<PurchaseDetails> list) async {
    for (final pd in list) {
      final ts = int.tryParse(pd.transactionDate ?? '');
      if (ts != null && (_lastTxn == null || ts > _lastTxn!)) {
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        PLog.info('TXN at $dt (epoch=$ts)');
        _lastTxn = ts;
      }
      PLog.trace('update: '
          'status=${pd.status} '
          'product=${pd.productID} '
          'pendingComplete=${pd.pendingCompletePurchase} '
          'transactionDate=${pd.transactionDate} '
          'source=${pd.verificationData.source}');
      // 既存switch…（そのまま）
      switch (pd.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          PLog.info('grant pro: product=${pd.productID} status=${pd.status}');
          await _setPro(true);
          break;

        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }
      if (pd.pendingCompletePurchase) {
        try {
          PLog.info('completePurchase: ${pd.productID} (txn=${pd.transactionDate})');
          await _iap.completePurchase(pd);
          PLog.ok('completePurchase done: ${pd.productID}');
        } catch (e, st) {
          PLog.err('completePurchase failed: $e\n$st');
        }
      }

    }
  }

  Future<void> _setPro(bool v) async {
    hasPro.value = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('hasPro', v);
  }
  /// OSの購読管理画面を開く

  /// OSの購読管理画面を開く（URL遷移に一本化）
  Future<void> openManage() async {
    PLog.info('manage: open subscriptions screen');
    try {
      final url = Platform.isIOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions';
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url, mode: LaunchMode.externalApplication);
      } else {
        PLog.err('manage: cannot open $url');
      }
    } catch (e, st) {
      debugPrint('[manage] fatal: $e\n$st');
      final url = Platform.isIOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions';
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    }
  }

  /// モーダルで進捗を出しつつ、必ず結果ダイアログを出す復元
  Future<void> restoreWithUI(BuildContext context) async {
    if (_restoring) return;
    _restoring = true;
    PLog.info('restore: begin (with UI)');

    // 進捗ダイアログ（キャンセル不可）← await しない
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );


    // 実復元
    final ok = await _restoreInternal();

    // 進捗を閉じる
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    _restoring = false;

    // 結果
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('購入を復元'),
        content: Text(ok ? '購入情報を復元しました' : '復元対象が見つかりませんでした'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
    PLog.ok('restore: ${ok ? "success" : "no purchases found"}');
  }

  /// 実際の復元処理（タイムアウトつき）
  Future<bool> _restoreInternal() async {
    try {
      final completer = Completer<bool>();
      // purchaseStream を1回だけ待ち受ける
      final sub = InAppPurchase.instance.purchaseStream.listen((events) {
        final restored = events.any((e) =>
        e.status == PurchaseStatus.restored ||
            e.status == PurchaseStatus.purchased);
        if (restored) {
          hasPro.value = true;
          if (!completer.isCompleted) completer.complete(true);
        }
      }, onError: (e, st) {
        debugPrint('restore stream error: $e');
        if (!completer.isCompleted) completer.complete(false);
      });

      // 復元をトリガー
      await InAppPurchase.instance.restorePurchases();

      // 何も来ないケースのための保険（iOSは無反応のことがある）
      final ok = await completer.future
          .timeout(const Duration(seconds: 8), onTimeout: () => false);

      await sub.cancel();
      return ok;
    } catch (e, st) {
      debugPrint('restore error: $e\n$st');
      return false;
    }
  }


}





class PLog {
  static const _r = '\x1B[31m'; // red
  static const _g = '\x1B[32m'; // green
  static const _y = '\x1B[33m'; // yellow
  // ignore: unused_field
  static const _b = '\x1B[34m';
// ignore: unused_field
  static const _m = '\x1B[35m';

  static const _c = '\x1B[36m'; // cyan
  static const _k = '\x1B[90m'; // gray
  static const _x = '\x1B[0m';  // reset

  static bool enabled = const bool.fromEnvironment('LOG_IAP', defaultValue: true);

  static void info(String m)  { if (enabled && kDebugMode) print('$_c[iap] INFO $_x$m'); }
  static void ok(String m)    { if (enabled && kDebugMode) print('$_g[iap] OK   $_x$m'); }
  static void warn(String m)  { if (enabled && kDebugMode) print('$_y[iap] WARN $_x$m'); }
  static void err(String m)   { if (enabled && kDebugMode) print('$_r[iap] ERR  $_x$m'); }
  static void trace(String m) { if (enabled && kDebugMode) print('$_k[iap] ...  $_x$m'); }
}