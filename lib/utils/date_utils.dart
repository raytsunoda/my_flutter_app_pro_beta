// lib/utils/date_utils.dart
import 'dart:async';
import '../utils/csv_loader.dart'; // あなたの CsvLoader の相対パスに合わせて調整

/// 時刻を切り落として Y-M-D のみを保持（00:00:00）
DateTime asYMD(DateTime d) => DateTime(d.year, d.month, d.day);

/// "YYYY/MM/DD" or "YYYY-MM-DD" を厳密にパース
DateTime parseYMD(String s) {
  final t = s.contains('/') ? s.split('/') : s.split('-');
  if (t.length != 3) {
    throw FormatException('Invalid date string: $s');
  }
  final y = int.parse(t[0]);
  final m = int.parse(t[1]);
  final d = int.parse(t[2]);
  return DateTime(y, m, d);
}

/// 表示用 "YYYY/MM/DD"
String fmtYMD(DateTime d) =>
    "${d.year.toString().padLeft(4,'0')}/${d.month.toString().padLeft(2,'0')}/${d.day.toString().padLeft(2,'0')}";

/// HappinessデータCSV（Documents側）に実在する「日付」セット
Future<Set<DateTime>> loadExistingDataDates() async {
  // ❶ 無ければ assets→Documents に自動コピーされる安全版
  final rows = await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv');


  final set = <DateTime>{};
  for (int i = 1; i < rows.length; i++) { // 0行目はヘッダ
    final raw = (rows[i].isNotEmpty ? rows[i][0] : '').toString().trim();
    if (raw.isEmpty) continue;
    try { set.add(asYMD(parseYMD(raw))); } catch (_) {}
  }
  return set;
}
/// 週・月判定（週次/月次実装でも使い回します）
bool isSunday(DateTime d) => asYMD(d).weekday == DateTime.sunday;

DateTime monthEnd(DateTime d) =>
    DateTime(d.year, d.month + 1, 1).subtract(const Duration(days: 1));

bool isMonthEnd(DateTime d) => asYMD(d) == monthEnd(d);


// 追加 ----------------------------

/// ref当日を含めた「直近日曜」（refが日曜ならref自身）
DateTime lastSundayOnOrBefore(DateTime ref) {
  final r = asYMD(ref);
  final wd0 = r.weekday % 7; // Sun=0, Mon=1, ... Sat=6
  return r.subtract(Duration(days: wd0));
}

/// 「日曜終わり」の週の月曜（開始日）
DateTime mondayOfWeekEndingOnSunday(DateTime sunday) =>
    asYMD(sunday).subtract(const Duration(days: 6));

/// 当月1日
DateTime firstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

/// 来月1日
DateTime firstDayOfNextMonth(DateTime d) => DateTime(d.year, d.month + 1, 1);

/// 前月末（例：ref=2025/09/01 → 2025/08/31）
DateTime lastDayOfPreviousMonth(DateTime d) =>
    firstDayOfMonth(d).subtract(const Duration(days: 1));

/// 週次生成の許可：
/// ・「今日が月曜」で、かつ「指定endが今日時点の直近日曜」と一致する
bool canCreateWeeklyForEnd(DateTime weekEnd, DateTime now) {
  final today = asYMD(now);
  if (today.weekday != DateTime.monday) return false;
  final lastSun = lastSundayOnOrBefore(today);
  return asYMD(weekEnd) == lastSun;
}

/// 月次生成の許可：
/// ・指定endが「今日時点の前月末」と一致
/// ・かつ「今日が当月1日以降」（= 前月分の解禁済み）
bool canCreateMonthlyForEnd(DateTime monthEndDay, DateTime now) {
  final today = asYMD(now);
  final prevEom = lastDayOfPreviousMonth(today);
  if (asYMD(monthEndDay) != prevEom) return false;
  return !today.isBefore(firstDayOfMonth(today)); // 当月1日以降
}

/// 次回の週次有効日（月曜）
DateTime nextWeeklyAllowedDate(DateTime now) {
  final today = asYMD(now);
  final delta = (DateTime.monday - today.weekday) % 7;
  final days = (delta == 0) ? 7 : delta;
  return today.add(Duration(days: days));
}

/// 次回の月次有効日（来月1日）
DateTime nextMonthlyAllowedDate(DateTime now) => firstDayOfNextMonth(now);