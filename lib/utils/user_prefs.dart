import 'package:shared_preferences/shared_preferences.dart';

class UserPrefs {
  static const _kDisplayName = 'display_name';

  static Future<String?> getDisplayName() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kDisplayName);
    // 空文字は未設定扱い
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  static Future<void> setDisplayName(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDisplayName, name.trim());
  }
  // 末尾に「さん」を付けた表示名を返す（未設定は null）
  static Future<String?> getDisplayNameWithSan() async {
    final v = await getDisplayName();
    if (v == null || v.trim().isEmpty) return null;
    final t = v.trim();
    return t.endsWith('さん') ? t : '$tさん';
  }

}
