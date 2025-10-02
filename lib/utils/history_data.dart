import 'package:intl/intl.dart';

class HistoryData {
  final Map<String, Map<String, String>> _byYmd; // 'yyyy/MM/dd' → 行

  HistoryData._(this._byYmd);

  factory HistoryData.fromCsv(List<Map<String, String>> rows) {
    final map = <String, Map<String, String>>{};
    for (final r in rows) {
      final d = _normYmdStr(r['日付'] ?? r['date'] ?? '');
      if (d.isNotEmpty) map[d] = Map<String, String>.from(r);
    }
    return HistoryData._(map);
  }

  static String _normYmdStr(String s) {
    s = s.trim();
    final p = s.split('/');
    if (p.length != 3) return '';
    return '${p[0].padLeft(4, '0')}/${p[1].padLeft(2, '0')}/${p[2].padLeft(2, '0')}';
  }

  String memoAt(DateTime date) {
    final ymd = DateFormat('yyyy/MM/dd').format(date);
    final row = _byYmd[ymd];
    if (row == null) return '';
    final m = (row['memo'] ?? '').trim();
    return m;
  }

  /// 任意期間 [start..end] の連続日リストと対応する行を返す（週次/4週/1年向け）
  List<Map<String, String>?> rowsBetween(DateTime start, DateTime end) {
    final res = <Map<String, String>?>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final ymd = DateFormat('yyyy/MM/dd').format(d);
      res.add(_byYmd[ymd]);
    }
    return res;
  }
}
