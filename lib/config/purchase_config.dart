// lib/config/purchase_config.dart
// 課金の有効/無効を --dart-define で切り替える（デフォルトは false）
class PurchaseConfig {
  /// 本番・テストを問わず、アプリ内課金機能をUIに出すか
  /// // App Store アーカイブで --dart-define を渡せないため、既定値を true に
  static const ENABLED = bool.fromEnvironment('ENABLE_PURCHASES', defaultValue: true);

  /// テスト用: Pro判定を強制的に真とみなす（UI解放のため）
    // 本番は強制開放しない既定（必要時のみ dart-define で true に）
  static const DEV_FORCE_PRO = bool.fromEnvironment('DEV_FORCE_PRO', defaultValue: false);
}
