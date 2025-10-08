import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart'; // iOS 管理画面用
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/purchase_config.dart';
// Fallback / Android

// ==== 追加：プロダクトID定義 ====
class PurchaseIds {
  static const monthly  = 'pro_monthly_500';
  static const lifetime = 'pro_lifetime_5100';
  static const ids = {monthly, lifetime};
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



  Future<void> init() async {

      // --- 開発用：Proを強制付与（.env or --dart-define）---
      if (PurchaseConfig.DEV_FORCE_PRO || _kForceProFromBuild) {
        debugPrint('[Purchase] FORCE_PRO enabled (env/build). gating OFF.');
        hasPro.value = true; // ← 既存の ValueNotifier<bool> を想定
        return; // 以降の課金初期化はスキップ
      }


// 起動時に呼ぶ（init() の「FORCE_PROのreturn」より後でOK）
    Future<void> loadProducts() async {
      try {
        final resp = await InAppPurchase.instance.queryProductDetails(PurchaseIds.ids);
        _products
          ..clear()
          ..addEntries(resp.productDetails.map((p) => MapEntry(p.id, p)));
      } catch (e) {
        // 失敗してもアプリは継続。ボタン側で未取得時の案内を出す
      }
    }

    /// 共通購入ヘルパー（購買UIはOS側が表示）
    Future<void> buy(BuildContext context, String productId) async {
      final details = _products[productId];
      if (details == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('購入情報を取得できませんでした。少し待って再度お試しください')),
        );
        return;
      }
      final param = PurchaseParam(productDetails: details);
      // サブスク/非消費型は buyNonConsumable を使う（in_app_purchase の流儀）
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
      // 成否は purchaseStream 側で反映。hasPro が切り替わればUIが更新されます。
    }






      // （ここから先は既存の課金初期化ロジックのまま）



      // ストア利用可否
    available = await _iap.isAvailable();

    // 商品問い合わせ（販売開始前でも errors にはならないのでOK）
    final resp = await _iap.queryProductDetails(PurchaseIds.ids);
    products = resp.productDetails;

    // 購入/復元のストリーム
    _sub = _iap.purchaseStream.listen(_onPurchaseUpdated, onError: (e) {});

    // ローカルの状態（復元相当）を読む
    final sp = await SharedPreferences.getInstance();
    hasPro.value = sp.getBool('hasPro') ?? false;
  }

  Future<void> dispose() async => _sub?.cancel();

  Future<bool> isPro() async => hasPro.value;

  Future<void> buy(ProductDetails p) async {
    final param = PurchaseParam(productDetails: p);
    await _iap.buyNonConsumable(purchaseParam: param); // サブスク/買切りの両方で可
  }

  Future<bool> restore() async {
    try {
      // iOS/Android 共通：復元リクエスト
      await InAppPurchase.instance.restorePurchases();

      // 購入ストリームの反映を少し待って hasPro を見る
      final ok = await _waitForProFlag();
      debugPrint('[restore] result hasPro=$ok');
      return ok;
    } on PlatformException catch (e) {
      debugPrint('[restore] PlatformException ${e.code}: ${e.message}');
      return false;
    } catch (e, st) {
      debugPrint('[restore] error: $e\n$st');
      return false;
    }
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


  Future<void> _onPurchaseUpdated(List<PurchaseDetails> list) async {
    for (final pd in list) {
      switch (pd.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _setPro(true);
          break;
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }
      if (pd.pendingCompletePurchase) {
        await _iap.completePurchase(pd);
      }
    }
  }

  Future<void> _setPro(bool v) async {
    hasPro.value = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('hasPro', v);
  }
  /// OSの購読管理画面を開く
  Future<void> openManage() async {
    try {
      if (Platform.isIOS) {
        final add = InAppPurchase.instance
            .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
        try {
          // 新しめの iOS だけにある API を試す（未対応なら例外）
          await (add as dynamic).showManageSubscriptionsSheet();
          return;
        } catch (e) {
          debugPrint('[manage] showManageSubscriptionsSheet failed: $e');
          // フォールバックURL
          final uri = Uri.parse('https://apps.apple.com/account/subscriptions');
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } else {
        final uri = Uri.parse('https://play.google.com/store/account/subscriptions');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e, st) {
      debugPrint('[manage] fatal: $e\n$st');
      final fallback = Platform.isIOS
          ? Uri.parse('https://apps.apple.com/account/subscriptions')
          : Uri.parse('https://play.google.com/store/account/subscriptions');
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  /// モーダルで進捗を出しつつ、必ず結果ダイアログを出す復元
  Future<void> restoreWithUI(BuildContext context) async {
    if (_restoring) return;
    _restoring = true;

    // 進捗ダイアログ（キャンセル不可）
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
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
