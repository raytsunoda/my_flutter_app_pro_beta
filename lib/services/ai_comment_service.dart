// lib/services/ai_comment_service.dart
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../utils/csv_loader.dart';
import 'package:flutter/foundation.dart';
import 'package:my_flutter_app_pro/utils/date_utils.dart';
import 'dart:math';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/user_prefs.dart';




// ---------- Weekly history with empty Sundays ----------
// CSV の最小日付〜最大日付の範囲で、毎週日曜キーを必ず1行ずつ作る。
// 既に保存済み（weekly）の本文があれば差し込み、無ければ空文字のまま返す。


// ====== 以降はこのファイル内だけで使う小さなヘルパ ======


// === class の外（importsの直後）に置く小ヘルパ ===
DateTime _asYMD(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _eom(DateTime d)   => DateTime(d.year, d.month + 1, 0);
bool _isEom(DateTime d)     => d.day == _eom(d).day;






// 正規化ユーティリティ
String _norm(String s) => s.replaceAll('\uFEFF', '').trim().toLowerCase();
String _cleanDate(String s) => s.replaceAll('\uFEFF', '').trim();

// 期間 [start, end] にCSV実データが1件でもあるか？
// 判定は「日付があり、かつ '幸せ感レベル' などの数値列が数値として読める
// もしくは 'memo' が非空」のいずれか。
//
Future<bool> _hasActualRowsInRange(DateTime start, DateTime end) async {
final s = DateTime(start.year, start.month, start.day);
final e = DateTime(end.year, end.month, end.day);

final csv = await CsvLoader.loadCsv('HappinessLevelDB1_v2.csv');
for (final row in csv) {
final dateStr = row['日付']?.trim() ?? '';
if (dateStr.isEmpty) continue;

DateTime? d;
try {
d = DateFormat('yyyy/MM/dd').parseStrict(dateStr);
} catch (_) {
continue;
}
if (d.isBefore(s) || d.isAfter(e)) continue;

final memo = (row['memo'] ?? '').trim();

double? asDouble(String? v) {
if (v == null) return null;
final t = v.trim();
if (t.isEmpty) return null;
return double.tryParse(t);
}

final hasAnyNumber = [
asDouble(row['幸せ感レベル']),
asDouble(row['睡眠の質']),
asDouble(row['ストレッチ時間']),
asDouble(row['ウォーキング時間']),
].any((v) => v != null);

if (hasAnyNumber || memo.isNotEmpty) {
return true; // 実データあり
}
}
return false; // 実データなし
}


// 月末を求める
//DateTime _eom(DateTime d) => DateTime(d.year, d.month + 1, 0);

// 年月日だけ比較
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// 指定日の入力内容があるか（memo/感謝/睡眠の質/ストレッチ/ウォーキングのいずれか）
bool _rowHasAnyInput(Map<String, String> row) {
  final memo = (row['memo'] ?? '').trim();
  final g1 = (row['感謝1'] ?? row['gratitude1'] ?? '').trim();
  final g2 = (row['感謝2'] ?? row['gratitude2'] ?? '').trim();
  final g3 = (row['感謝3'] ?? row['gratitude3'] ?? '').trim();
  final sleepQ = double.tryParse((row['睡眠の質'] ?? '').toString()) ?? 0;
  final stretch = double.tryParse((row['ストレッチ時間'] ?? '').toString()) ?? 0;
  final walk = double.tryParse((row['ウォーキング時間'] ?? '').toString()) ?? 0;
  return memo.isNotEmpty || g1.isNotEmpty || g2.isNotEmpty || g3.isNotEmpty
      || sleepQ > 0 || stretch > 0 || walk > 0;
}






// 月次の表示解禁カットオフ（翌月1日の 00:00）
DateTime _monthlyVisibleCutoff(DateTime now) =>
    DateTime(now.year, now.month + 1, 1);






class AiCommentService {

  // アプリは鍵を持たず、サーバのプロキシにPOSTする
  // App Store ビルドでも確実に動くように本番URLをデフォルト埋め込み
    static const _aiEndpoint = String.fromEnvironment(
      'AI_PROXY_URL',
      defaultValue: 'https://happiness-h3.com/_functions/ai_comment',
    );

// --- 呼びかけ名ヘルパ（常に「さん」付きに正規化） ---
  // --- 呼びかけ名ヘルパ（常に「さん」付きに正規化） ---
  static Future<String> _callName() async {
    final raw = (await _resolveDisplayName()).trim();
    if (raw.isEmpty) return 'ユーザーさん'; // 未設定時の既定

    // 末尾が「さん」以外なら付与（「様」「くん」「ちゃん」などが既に付いているなら、そのままでも良いが
    // 今回は統一のため原則「さん」に正規化）
    final normalized = raw.endsWith('さん') ? raw : '$rawさん';

    return normalized;
  }


  // --- 念のため出力をサニタイズ（「あなた」を呼び名に置換・重複敬称を整形） ---
  static String _enforceCallName(String text, String callName) {
    var s = text;

    // 「あなた」「あなたさん」「貴方」など代表的な呼称を網羅置換（「あなた方」は除外）
    final patterns = <RegExp>[
      RegExp(r'(?m)^\s*あなたさん', multiLine: true),
      RegExp(r'(?m)^\s*あなた(?!方)', multiLine: true),
      RegExp(r'あなたさん'),
      RegExp(r'あなた(?!方)'),
      RegExp(r'貴方さん'),
      RegExp(r'貴方(?!方)'),
      RegExp(r'貴女さん'),
      RegExp(r'貴女(?!方)'),
      RegExp(r'\b[Yy]ou\b'), // 英語混入対策
      RegExp(r'君'), RegExp(r'きみ'),
    ];

    for (final p in patterns) {
      s = s.replaceAll(p, callName);
    }

    // 二重敬称「さんさん」を1つに
    s = s.replaceAll(RegExp(r'さんさん'), 'さん');

    // 句読点や空白の連続を軽く整える（任意）
    s = s.replaceAll(RegExp(r'[\u3000 ]{2,}'), ' ');

    return s;
  }
// --- 出力に「感謝」の言及が無ければ1つだけ追記する（保険） ---
  static String _ensureGratitudeMention(String text, List<String> candidates) {
    // candidates: pickedMemos など（感謝1〜3を含む候補）
    final first = candidates.firstWhere(
          (e) => e.trim().isNotEmpty,
      orElse: () => '',
    );
    if (first.isEmpty) return text;

    final alreadyMentions =
        text.contains('感謝') || text.contains(first) || RegExp(r'ありがとう').hasMatch(text);

    return alreadyMentions ? text : '$text\n\n追伸：今日は「$first」に感謝ですね。';
  }




  // 指定 EOM（例：2025/08/31）の月次レコードを 1 件返す（あれば）
  static Future<Map<String, dynamic>?> findMonthlyByDate(DateTime dt) async {
    final ymd = _fmtYmd(dt); // 'YYYY/MM/DD'
    final raw = await _loadHistoryRaw();
    final rows = raw.where((e) =>
    (e['type'] ?? '') == 'monthly' &&
        (e['date'] ?? '') == ymd).toList();

    if (rows.isEmpty) return null;

    // createdAt があれば新しいもの優先
    rows.sort((a, b) =>
        ('${b['createdAt'] ?? b['date']}').compareTo('${a['createdAt'] ?? a['date']}'));
    return rows.first;
  }

// 便利：先月末（now の前月の月末）の月次レコードを取る
  static Future<Map<String, dynamic>?> findLastMonthEomRecord({DateTime? now}) async {
    now ??= DateTime.now();
    final eom = DateTime(now.year, now.month, 0); // ← 前月末
    return findMonthlyByDate(eom);
  }


  // 週次ヘルパ：その週の日曜日（同日が日曜ならその日）
  static DateTime _sundayOf(DateTime d) {
    final d0 = DateTime(d.year, d.month, d.day);
    final w = d.weekday; // 1=Mon ... 7=Sun
    return d0.subtract(Duration(days: w == DateTime.sunday ? 0 : w));
  }

// 現在時刻 now に対し、週次を表示してよい「ゲートとなる日曜」
// - 日曜のうちは前週（日付は 7 日前）まで
// - 月曜以降は直近の日曜まで
  static DateTime _weeklyGateSunday(DateTime now) {
    final todayIsSunday = now.weekday == DateTime.sunday;
    final s = _sundayOf(now);
    return todayIsSunday ? s.subtract(const Duration(days: 7)) : s;
  }


  // yyy/MM/dd 文字列が「その月の末日」かどうか
  bool _isEomYmd(String ymd) {
    // 既存のパーサを使う想定（なければ DateTime.parse のラッパを使ってOK）
    final d = _svcParseYmd(ymd); // 例: 2025/08/31 -> DateTime(2025,8,31)
    if (d == null) return false;
    final last = DateTime(d.year, d.month + 1, 0);
    return d.day == last.day;
  }

// 表記ゆれ対策（必要なら追加）
 // static DateTime? _svcParseYMD(String ymd) => _svcParseYmd(ymd);
//  static String _asYMD(DateTime d) => '${d.year.toString().padLeft(4,'0')}/${d.month.toString().padLeft(2,'0')}/${d.day.toString().padLeft(2,'0')}';


// ---- 日付ユーティリティ（クラス内 static）----
static DateTime _asYMD(DateTime d) => DateTime(d.year, d.month, d.day);
static String _fmtYmd(DateTime d) =>
'${d.year.toString().padLeft(4, '0')}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';


static DateTime? _svcParseYmd(String ymd) {
  final p = ymd.split('/');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

static String _svcYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

static DateTime _svcSundayOf(DateTime d) {
// 週の基準を日曜(=0)にそろえる
  final weekday = d.weekday % 7; // Mon=1,...,Sun=7→0にそろえる
  return DateTime(d.year, d.month, d.day).subtract(Duration(days: weekday));
}





static DateTime _eom(DateTime d) {
final firstNext = DateTime(d.year, d.month + 1, 1);
return firstNext.subtract(const Duration(days: 1));
}
static bool _isEom(DateTime d) {
final e = _eom(d);
return d.year == e.year && d.month == e.month && d.day == e.day;
}
static DateTime _prevSunday(DateTime d) {
final x = _asYMD(d);
final delta = x.weekday % 7; // Sun=7 -> 0, Mon=1 -> 1 ...
return x.subtract(Duration(days: delta));
}

// === EOM ガード: 未来のEOMは生成/表示しない、今月は当日が月末のみ ===
  static bool _canCreateMonthlyFor(DateTime targetEom, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    DateTime eom(DateTime d) => DateTime(d.year, d.month + 1, 0);

    final currentEom = eom(today);
    // 未来EOMは生成禁止
    if (targetEom.isAfter(currentEom)) return false;
    // 今月分は「当日が月末」のときだけ生成可
    final isTodayEom = today.day == currentEom.day;
    if (targetEom.isAtSameMomentAs(currentEom) && !isTodayEom) return false;
    return true;
  }



static const _csvName = 'HappinessLevelDB1_v2.csv';








// 置換: loadWeeklyHistoryWithEmptySundays()
  static Future<List<Map<String, String>>> loadWeeklyHistoryWithEmptySundays() async {
    // 1) 保存済み weekly を辞書化（date -> comment）
    final saved = await AiCommentService.loadWeeklyHistoryStrict();
    final byDate = <String, String>{};
    for (final r in saved) {
      final d = (r['date'] ?? '').toString().trim();
      if (d.isNotEmpty) byDate[d] = (r['comment'] ?? '').toString();
    }

    // 2) メインCSVから日付範囲を集める
    final csv = await CsvLoader.loadCsv('HappinessLevelDB1_v2.csv');
    final days = <DateTime>[];
    final seen = <String>{};
    for (final row in csv) {
      final ds = (row['日付'] ?? '').toString().trim();
      if (ds.isEmpty || seen.contains(ds)) continue;
      try {
        days.add(DateFormat('yyyy/MM/dd').parseStrict(ds));
        seen.add(ds);
      } catch (_) {}
    }
    if (days.isEmpty) return [];

    days.sort();
    DateTime _prevSunday(DateTime d) {
      final wd = d.weekday % 7;
      return DateTime(d.year, d.month, d.day).subtract(Duration(days: wd));
    }

    final firstSun   = _prevSunday(days.first);
    final lastSunCsv = _prevSunday(days.last);
    final cutoffSun  = _latestVisibleSunday(DateTime.now());
    // 表示上の上限 = CSV最終日曜 と カットオフ の“早い方”
    final lastSun    = lastSunCsv.isBefore(cutoffSun) ? lastSunCsv : cutoffSun;

    // 3) スロット生成（カットオフを超えない）
    final out = <Map<String, String>>[];
    for (DateTime cur = firstSun; !cur.isAfter(lastSun); cur = cur.add(const Duration(days: 7))) {
      final ymd =
          '${cur.year.toString().padLeft(4, '0')}/${cur.month.toString().padLeft(2, '0')}/${cur.day.toString().padLeft(2, '0')}';
      out.add({'type': 'weekly', 'date': ymd, 'comment': byDate[ymd] ?? ''});
    }

    out.sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));
    return out;
  }





  // 未来の月次エントリを掃除（例: 8/25 時点の 2025/08/31 を削除）
  static Future<int> purgeFutureMonthly({DateTime? now}) async {
    final _now = now ?? DateTime.now();
    final currentEom = _eom(_asYMD(_now));

    final rows = await CsvLoader.loadAiCommentLog();
    final before = rows.length;

    bool _isFutureMonthly(Map<String, dynamic> r) {
      final type = (r['type'] ?? '').toString().toLowerCase().trim();
      if (type != 'monthly') return false;
      final d = (r['date'] ?? '').toString().trim();
      if (d.isEmpty) return false;
      final p = d.split('/');
      if (p.length != 3) return false;
      final dt = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      return dt.isAfter(currentEom);
    }

    final filtered = rows.where((r) => !_isFutureMonthly(r)).toList();
    if (filtered.length != rows.length) {
      await CsvLoader.writeAiCommentLog(filtered);
    }
    return before - filtered.length; // 削除件数
  }





// 週次：将来の日曜は生成禁止。過去/直近に過ぎた日曜は生成OK。
  static bool _canCreateWeeklyFor(DateTime lastSunday, DateTime now) {
    DateTime _toLastSunday(DateTime d) {
      final wd = d.weekday % 7; // Sun=0, Mon=1..Sat=6
      return DateTime(d.year, d.month, d.day).subtract(Duration(days: wd));
    }

    // 表示と同じゲート：日曜は“前週の日曜”、月〜土は“直近の日曜”
    final today = DateTime(now.year, now.month, now.day);
    final thisSunOrPrev = _toLastSunday(today);
    final latestVisibleSunday =
    (today.weekday == DateTime.sunday) ? thisSunOrPrev.subtract(const Duration(days: 7))
        : thisSunOrPrev;

    // 生成可否：lastSunday <= latestVisibleSunday のときのみ
    return !lastSunday.isAfter(latestVisibleSunday);
  }


  // 週次（end=日曜）
  static Future<Map<String, String>> ensureWeeklySaved(DateTime lastSunday) async {
    final end   = DateTime(lastSunday.year, lastSunday.month, lastSunday.day);
    final start = end.subtract(const Duration(days: 6));
    final key   = DateFormat('yyyy/MM/dd').format(end);

    // ① 先に「保存済み」を再利用（←ここを先頭へ）
    final saved = await getSavedComment(date: key, type: 'weekly');
    if (saved != null && saved.trim().isNotEmpty) {
      return {'date': key, 'type': 'weekly', 'comment': saved};
    }

    // ② 生成許可の判定（許可外なら“生成しない”が、保存済みがあれば上で返っている）
    if (!_canCreateWeeklyFor(end, DateTime.now())) {
      return {'date': key, 'type': 'weekly', 'comment': ''};
    }

    // ③ 週内に実データが無ければ生成せず空
    final hasData = await _hasActualRowsInRange(start, end);
    if (!hasData) {
      return {'date': key, 'type': 'weekly', 'comment': ''};
    }

    // ④ 新規生成
    final text = await getPeriodComment(
      startDate: start,
      endDate: end,
      type: 'weekly',
    );
    return {'date': key, 'type': 'weekly', 'comment': text.trim()};
  }




// ==== ここから: AiCommentService に追加 ====

// yyyy/MM/dd 文字列
  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4,'0')}/${d.month.toString().padLeft(2,'0')}/${d.day.toString().padLeft(2,'0')}';

  /// 指定日の「日次AIコメント」を、
  /// 1) 既に ai_comment_log.csv にあればそれを返す（生成しない）
  /// 2) 無ければメインCSVからその日の行を exact に取り、AIで生成して保存してから返す
  /// 3) メインCSVに当日の行が無い場合は何もしない（生成もしない／保存もしない）
  // AiCommentService 内
  // DAILY（1日だけ厳密生成）※既存の ensureDailySavedForDate があればそれを使う
  static Future<Map<String, String>?> ensureDailySavedForDate(DateTime date) async {
    String _fmt(DateTime d) =>
        '${d.year.toString().padLeft(4,'0')}/${d.month.toString().padLeft(2,'0')}/${d.day.toString().padLeft(2,'0')}';

    final target = _fmt(date);

    final log = await CsvLoader.loadAiCommentLog();
    final already = log.firstWhere(
          (r) => (r['type'] ?? '').toLowerCase() == 'daily' && (r['date'] ?? '') == target,
      orElse: () => {},
    );
    if (already.isNotEmpty) return Map<String, String>.from(already);

    final matrix = await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv');
    final mainRow = CsvLoader.getRowByExactDate(matrix, date);
    if (mainRow == null) return null;

    // 入力が全く無い日はAIコメントを生成しない//9/6
    if (!_rowHasAnyInput(mainRow)) {
      return null;
    }

    final comment = await _buildDailyCommentFromMainRow(mainRow);
    final newRow = <String, String>{'date': target, 'type': 'daily', 'comment': comment};
    log.add(newRow);
    log.sort((a,b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));
    await CsvLoader.writeAiCommentLog(log);
    return newRow;
  }


  /// メインCSVの行（列名は日本語ヘッダ）から日次AIコメント本文を作る
  /// ※ ここは「一度だけAI生成」の入口に置き換えてOK。
  ///   既に OpenAI 呼び出し等の関数があるなら、その関数を呼ぶだけにして構いません。
  static Future<String> _buildDailyCommentFromMainRow(Map<String,String> row) async {
    // すでにある日次生成ロジックがあるなら ↓ をそれに置換してください。
    // ひとまず手元生成のダミー（低コスト・オフライン）で埋めています。
    final happy = row['幸せ感レベル'] ?? '';
    final sleepQ = row['睡眠の質'] ?? '';
    final walkMin = row['ウォーキング時間'] ?? row['ウォーキング'] ?? '';
    final memo   = row['memo'] ?? row['メモ'] ?? row['メモ:'] ?? '';

    final b = StringBuffer();
    b.writeln('今日の振り返りです。幸せ感レベルは${happy}、睡眠の質は${sleepQ}でした。');
    if (walkMin.isNotEmpty) b.writeln('ウォーキングや運動の時間は${walkMin}分でした。');
    if (memo.isNotEmpty)   b.writeln('メモ：$memo');
    b.writeln('無理なく続けられるリズムで、明日も一歩ずついきましょう。');

    return b.toString();
  }
// ==== ここまで: AiCommentService に追加 ====








// 月次（end=月末）
// 月次：monthEndDay は「保存したい月の月末日」（例: 先月末）を渡す
// 期間内に実データなし → comment=""（＝UI側で「表示なし」）
  static Future<Map<String, String>> ensureMonthlySaved(DateTime monthEndDay) async {
    final end   = DateTime(monthEndDay.year, monthEndDay.month, monthEndDay.day);
    final start = DateTime(end.year, end.month, 1);
    final key   = DateFormat('yyyy/MM/dd').format(end);

    // ① 保存済みがあれば最優先で返す（←先頭へ）
    final saved = await getSavedComment(date: key, type: 'monthly');
    if (saved != null && saved.trim().isNotEmpty) {
      return {'date': key, 'type': 'monthly', 'comment': saved};
    }

    // ② 生成許可（当月1日以降 & endが前月末）を満たさなければ生成しない
    if (!_canCreateMonthlyFor(end, DateTime.now())) {
      return {'date': key, 'type': 'monthly', 'comment': ''};
    }

    // ③ その月に材料が無ければ空
    final hasData = await _hasActualRowsInRange(start, end);
    if (!hasData) {
      return {'date': key, 'type': 'monthly', 'comment': ''};
    }

    // ④ 新規生成
    final text = await getPeriodComment(
      startDate: start,
      endDate: end,
      type: 'monthly',
    );
    return {'date': key, 'type': 'monthly', 'comment': text.trim()};
  }




// フォールバック検知（1つだけ定義を残す）
  static bool _looksFallback(String text) {
    final t = text.replaceAll(RegExp(r'\s+'), '');
    const patterns = <String>[
      '今日も一日お疲れさまでした',
      'AIパートナー構想実現',
      '独学でこれが実現できたらうれしい',
      // 追加
      '無理なく続けられるリズムで明日も一歩ずついきましょう', // 既定のオフライン生成文
    ];
    return patterns.any((p) => t.contains(p));
  }

// yyyy/MM/dd → DateTime（1つだけ定義を残す）
  static DateTime _parseYmd(String ymd) {
    final p = ymd.split('/');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

// 8/5 など一日だけ安全修理
  static Future<bool> repairDailyIfFallback(DateTime date) async {
    final ymd = _fmtYmd(date); // 例: 2025/08/05
    final raw = await _loadHistoryRaw();

    final hasFallback = raw.any((e) =>
    e['type'] == 'daily' &&
        e['date'] == ymd &&
        _looksFallback((e['comment'] ?? '').toString()));

    if (!hasFallback) return false;

    // いったん対象日の daily を全削除
    await hardDeleteByDateType(ymd, 'daily');

    // CSV 実データから「厳密に」作り直し
    await ensureDailySavedForDate(date);

    return true;
  }



// 一括修理
  static Future<int> scanAndRepairFallbackDaily() async {
    final rows = await CsvLoader.loadAiCommentLog();
    if (rows.isEmpty) return 0;

    final targets = <String>{};
    for (final r in rows) {
      if ((r['type'] ?? '').toLowerCase() != 'daily') continue;
      final c = (r['comment'] ?? '').trim();
      if (c.isNotEmpty && _looksFallback(c)) {
        final d = (r['date'] ?? '').trim();
        if (d.isNotEmpty) targets.add(d);
      }
    }
    if (targets.isEmpty) return 0;

    // まとめて削除→再生成
    final remain = rows.where((r) {
      final isDaily = (r['type'] ?? '').toLowerCase() == 'daily';
      final d = (r['date'] ?? '').trim();
      return !(isDaily && targets.contains(d));
    }).toList();
    await CsvLoader.writeAiCommentLog(remain);

    for (final ds in targets) {
      await ensureDailySavedForDate(_parseYmd(ds));
    }
    return targets.length;
  }

// === 追加: 日次のAIコメント生成（OpenAI使用） ===
  static Future<String> getTodayComment({
    required DateTime displayDate,
    required String memo,
  }) async {
    // 材料をCSVから取得（既存CsvLoaderユーティリティを最大活用）
    final ymdLabel = DateFormat('yyyy/MM/dd').format(displayDate);
    final scoreStr = await CsvLoader.loadHappinessScoreForDate(displayDate); // 幸せ感(0-100)
    final radar    = await CsvLoader.loadRadarScoresForDate(displayDate);    // [睡眠の質, ウォーキング分, ストレッチ分]
    final thanks   = await CsvLoader.loadGratitudeForDate(displayDate);      // 文字列リスト（最大3想定）

    // 追加: 表示用に文字列へ
    final thanksStr = thanks.where((t) => t.trim().isNotEmpty).join(' / ');
    final memoStr   = memo.trim().isNotEmpty ? memo.trim() : '（未入力）';



    // レーダー値の安全取り出し
    final sleepQ   = radar.isNotEmpty ? radar[0] : 0.0; // 0-100%
    final walkMin  = radar.length > 1 ? radar[1] : 0.0; // 分
    final stretch  = radar.length > 2 ? radar[2] : 0.0; // 分

    final callName = await _callName();
    final prompt = '''
${callName} へ。

あなたは共感的なAIカウンセラーです。以下の**当日情報**を根拠に、薄味な一般論を避け、
${callName} 個人に刺さる短いコメントを**200文字以内**で日本語で作成してください。

【必須ルール】
- 必ず「感謝1〜3」のうち**最低1つ**を引用し、本文中に「◯◯に感謝」の形で言及する
- 具体的な**次の一歩**を**1つだけ**、20文字程度で提示する（箇条書きでも可）
- 「素晴らしい」は**幸せ感レベルが80以上のときのみ**使用可（数値だけの賛辞は禁止）
- 呼びかけは常に「${callName}」。**「あなた」「あなたさん」は使わない**
- 絵文字・顔文字・過度な敬語・説教調は使わない

【当日情報】
📅 日付: $ymdLabel
😊 幸せ感レベル: $scoreStr
😴 睡眠の質: ${sleepQ.toStringAsFixed(0)}（%）
🚶 ウォーキング: ${walkMin.toStringAsFixed(0)}分
🧘 ストレッチ: ${stretch.toStringAsFixed(0)}分
🙏 感謝: ${thanksStr.isEmpty ? '（未入力）' : thanksStr}
📝 メモ: $memoStr
{memosForPrompt}

出力フォーマット例：
- 導入1文（${callName} を呼びかけ）
- 感謝の引用を1つ（◯◯に感謝）
- 次の一歩（20文字程度、1つだけ）

ポイント: 短く、地に足のついた言葉で。事実を尊重しつつ、無理のない実践提案を1つ入れてください。
''';

    try {
      final res = await http.post(
        Uri.parse(_aiEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'kind': 'daily',
          'date': ymdLabel,
          'callName': callName,
          'prompt': prompt,
          // 参考: サーバ側で使えるように最低限の材料も添える（任意）
          'metrics': {
            'happiness': scoreStr,
            'sleepQ': sleepQ,
            'walkMin': walkMin,
            'stretchMin': stretch,
          },
          'gratitudes': thanks.where((t) => t.trim().isNotEmpty).toList(),
          'memo': memoStr,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // プロキシの返却仕様に合わせて柔軟に取得
        final text =
        (data['comment'] ?? data['text'] ?? '').toString().trim();
        if (text.isNotEmpty) {
          final withName = _enforceCallName(text, callName);
          // thanks（= 感謝1〜3）から最低1つは本文で触れるよう保険をかける
          final withGratitude = _ensureGratitudeMention(
            withName,
            thanks.where((t) => t.trim().isNotEmpty).toList(),
          );
          return withGratitude;
        }

      }
    } catch (_) {
      // 握りつぶし → 下のフォールバックに任せる
    }
    return '';




  }





  /// ───────────────────────────────────────────────
  /// 日次コメント（表示日付キー）。保存済み優先、なければ生成→保存
  /// 戻り値: {'date','type','comment'}
  /// ───────────────────────────────────────────────
  static Future<Map<String,String>> ensureDailySaved(DateTime date) async {
    final key = DateFormat('yyyy/MM/dd').format(date);

    try {
      final saved = await CsvLoader.loadSavedComment(date, 'daily');
      final savedComment = saved?['comment']?.trim() ?? '';
      if (savedComment.isNotEmpty) {
        // ★フォールバックぽいなら削除→再生成
        if (_looksFallback(savedComment)) {
          await repairDailyIfFallback(date);
          final fixed = await CsvLoader.loadSavedComment(date, 'daily');
          final txt = fixed?['comment']?.trim() ?? '';
          if (txt.isNotEmpty) {
            return {'date': key, 'type': 'daily', 'comment': txt};
          }
          // ここで空なら以降の新規生成へフォールスルー
        } else {
          // 正常保存はそのまま返す
          return {'date': key, 'type': 'daily', 'comment': savedComment};
        }
      }
    } catch (e, st) {
      debugPrint('[ensureDailySaved] ignore saved read error: $e');
      debugPrintStack(stackTrace: st);
    }

    // 材料
    final memo = await CsvLoader.loadMemoForDate(date);

    // ① OpenAI を使って生成（メモ・スコア等を反映）
    String? generated;
    try {
      generated = await AiCommentService.getTodayComment(
        memo: memo,
        displayDate: date,
      );
      if (generated.trim().isEmpty) generated = null;
    } catch (_) {
      generated = null;
    }

    // ② API失敗時はルールベースにフォールバック
    generated ??= await _generateDailyAiTextFromCsv(date);

    await CsvLoader.appendAiCommentLog(
      date: key,
      type: 'daily',
      comment: generated,
      score: await CsvLoader.loadHappinessScoreForDate(date),
      sleep: '',
      walk: '',
      gratitude1: '',
      gratitude2: '',
      gratitude3: '',
      memo: memo,
    );
    debugPrint('[ensureDailySaved] appended daily $key');

    return {'date': key, 'type': 'daily', 'comment': generated};
  }

  /// OpenAI使用：今日のコメント（displayDate をキーとして保存）
  static Future<String> getPeriodComment({
    required DateTime startDate,
    required DateTime endDate,
    String type = 'weekly',
  }) async {
    final endDateStr = DateFormat('yyyy/MM/dd').format(endDate);

    // 既存保存があれば再利用（終了日キー）
    if (await CsvLoader.isCommentAlreadySaved(date: endDateStr, type: type)) {
      final saved = await getSavedComment(date: endDateStr, type: type);
      if (saved != null && saved.isNotEmpty) return saved;
      return 'この${type == "weekly" ? "週" : "月"}のコメントは既に保存されています。';
    }

    final rows = await CsvLoader.loadCsvDataBetween(startDate, endDate);

    // 定量（そのままの値を平均化）
    final happinessList = rows
        .map((row) => row.length > 1 ? row[1].toString().trim() : '')
        .where((h) => h.isNotEmpty).toList();
    final sleepList = rows
        .map((row) => row.length > 4 ? row[4].toString().trim() : '')
        .where((s) => s.isNotEmpty).toList();
    final walkList = rows
        .map((row) => row.length > 3 ? row[3].toString().trim() : '')
        .where((w) => w.isNotEmpty).toList();

    // 定性：感謝（重複・空白除去 → 決定論的ランダム抽出）
    final allGratitudes = _dedupNonEmpty(rows.expand((row) => [
      if (row.length > 14) row[14].toString(),
      if (row.length > 15) row[15].toString(),
      if (row.length > 16) row[16].toString(),
    ]));
    final int maxG = (type == 'weekly') ? 10 : 40;
    final pickedGratitudes = _pickDeterministicRandom(allGratitudes, maxG, endDate);

    // 定性：メモ（重複・空白除去 → 1件あたり文字上限 → 件数上限）
    final allMemos = _dedupNonEmpty(rows.map((row) => row.length > 17 ? row[17].toString() : ''));
    final int maxMemoCount = (type == 'weekly') ? 10 : 40;
    final int maxMemoChars = (type == 'weekly') ? 300 : 250;
    final pickedMemos = allMemos
        .map((m) => _trimMemo(m, maxMemoChars))
        .take(maxMemoCount)
        .toList();
    final memosForPrompt = pickedMemos.map((m) => '・$m').join('\n');

    // 期間サマリ（従来通り）
    final graphSummary = '''
📅 期間: ${DateFormat('yyyy/MM/dd').format(startDate)} ～ ${DateFormat('yyyy/MM/dd').format(endDate)}
幸せ感レベル: ${happinessList.join(', ')}
睡眠の質: ${sleepList.join(', ')}
ウォーキング: ${walkList.join(', ')}
''';

    final callName = await _callName();

// 感謝は2〜3件、メモは2件ほどに絞って“厚み”を担保
    final pickedForPrompt = pickedGratitudes.take(3).toList();
    final gratitudeLine = pickedForPrompt.isNotEmpty
        ? pickedForPrompt.map((g) => '・' + g).join('\n')
        : '（未入力）';

    final memosForPromptTop = pickedMemos.take(2).map((m) => '・' + m).join('\n');
    final memosLine = memosForPromptTop.isNotEmpty ? memosForPromptTop : '（未入力）';

    final label = (type == 'weekly') ? 'この1週間' : 'この1か月';

    final prompt = '''
${callName}、${label}をふり返って短い応援メッセージを日本語で作成してください。**200文字以内**。
口調はやさしく、根拠（実データ・感謝・メモ）に1回は触れてください。

【概要（自動要約）】
$graphSummary

【感謝（引用候補）】
$gratitudeLine

【メモ（要点）】
$memosLine

【出力要件】
- 冒頭の呼びかけは「${callName}」。以後も「あなた」は使わない
- 幸せ感レベルは**自然な言い方**を優先（例：「50台」「60台」など。小数は避ける）
- 次に取れる一歩を**1つだけ**、20文字程度で具体的に
- 事実に根ざし、過度な賛辞や断定は避ける
''';


    final response = await http.post(
      Uri.parse(_aiEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'kind': type, // 'weekly' or 'monthly'
        'start': DateFormat('yyyy/MM/dd').format(startDate),
        'end'  : DateFormat('yyyy/MM/dd').format(endDate),
        'callName': callName,
        'prompt': prompt,
        // サーバ側が使える参考情報（任意）
        'summary': graphSummary,
        'gratitudes': pickedGratitudes,
        'memos': pickedMemos,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final generatedCommentRaw =
      (data['comment'] ?? data['text'] ?? '').toString().trim();


      // 生成テキスト（空ならエラーメッセージ）
      final base = generatedCommentRaw.isNotEmpty
          ? generatedCommentRaw
          : 'コメント取得に失敗しました。';

// callName は _callName() 側で「さん」付与済み想定（呼び捨て防止）
// 「あなた」等を呼び名に置換し、二重「さんさん」を整形
      final withName = _enforceCallName(base, callName);

// 感謝1〜3のいずれかが本文で触れられていない場合は、追伸で1つだけ補う（保険）
      final withGratitude = _ensureGratitudeMention(withName, pickedMemos);
      final generatedComment = withGratitude;


      await CsvLoader.appendAiCommentLog(
        date: endDateStr,
        type: type,
        comment: generatedComment,
        // 小数の不自然な見えを避けるため 0桁丸め
        score: _averageScore(happinessList).round().toString(),
        sleep: _averageScore(sleepList).round().toString(),
        walk: _averageScore(walkList).round().toString(),
        gratitude1: pickedGratitudes.isNotEmpty ? pickedGratitudes[0] : '',
        gratitude2: pickedGratitudes.length > 1 ? pickedGratitudes[1] : '',
        gratitude3: pickedGratitudes.length > 2 ? pickedGratitudes[2] : '',
        memo: pickedMemos.isNotEmpty ? pickedMemos.first : '',
      );

      return generatedComment;
    } else {
      return 'コメントの取得に失敗しました。';
    }

  }


  static double _averageScore(List<String> list) {
        final nums = list
            .map((e) => double.tryParse(e.trim()))
            .whereType<double>()  // ← null を除外しつつ non-null 型に
            .toList();
    if (nums.isEmpty) return 0.0;
    final sum = nums.reduce((a, b) => a + b);
    return sum / nums.length;
  }

  /// CSVログから安全に取得
  static Future<String?> getSavedComment({
    required String date,
    required String type,
  }) async {
    final file = await CsvLoader.getAiCommentLogFile();
    if (!await file.exists()) return null;

    final rows = const CsvToListConverter().convert(await file.readAsString(), eol: '\n');
    for (final row in rows.skip(1)) {
      if (row.length >= 3 && row[0].toString() == date && row[1].toString() == type) {
        return row[2].toString();
      }
    }
    return null;
  }

  /// API不要の軽量生成（フォールバック／欠落補完に使用）
  static Future<String> _generateDailyAiTextFromCsv(DateTime date) async {
    final d = asYMD(date);

    final memo   = await CsvLoader.loadMemoForDate(d);
    final scoreS = await CsvLoader.loadHappinessScoreForDate(d);
    final radar  = await CsvLoader.loadRadarScoresForDate(d);
    final thanks = await CsvLoader.loadGratitudeForDate(d);

    final score  = double.tryParse(scoreS) ?? 0.0;
    final sleepQ = radar.isNotEmpty ? radar[0] : 0.0;
    final walk   = radar.length > 1 ? radar[1] : 0.0;
    final stretch= radar.length > 2 ? radar[2] : 0.0;

    final hints = <String>[];
    if (sleepQ   < 70) hints.add('今夜は就寝前のスマホ時間を短めにしてみましょう');
    if (walk     < 60) hints.add('短い散歩でもOK、今日の歩数を少しだけ積み増し');
    if (stretch  < 60) hints.add('寝る前の軽いストレッチで体と気持ちを緩めよう');

    final opening = (score >= 80)
        ? '今日の調子はとても良さそう。自分を信じていきましょう。'
        : '無理せずペース配分を。小さな一歩からで大丈夫です。';

    final memoLine   = memo.trim().isNotEmpty ? '📝 メモの想いが背中を押してくれます。' : '';
    final thanksLine = thanks.any((t) => t.trim().isNotEmpty)
        ? '感謝の気持ちを続けると、穏やかさが積み重なります。'
        : '';

    final tip = hints.isNotEmpty ? hints.first : 'その調子で小さな積み重ねを続けましょう。';
    final text = '$opening $tip $thanksLine $memoLine'.trim();

    return text.isNotEmpty
        ? text
        : '今日は小さく整える日にしましょう。深呼吸して、無理のない範囲で一歩だけ進めば十分です。';
  }

  // REPLACE: loadDailyHistoryStrict()
  static Future<List<Map<String, dynamic>>> loadDailyHistoryStrict() async {
    final raw  = await _loadHistoryRaw();
    final only = raw.where((e) => e['type'] == 'daily').toList();

    final deduped = _dedupPreferReal(only);

    // 日付降順（YYYY/MM/DD 文字列なら単純比較でOK）→ 時刻降順
    deduped.sort((a, b) {
      final d = (b['date'] as String).compareTo((a['date'] as String));
      if (d != 0) return d;
      final tb = (b['ts'] as int?) ?? 0;
      final ta = (a['ts'] as int?) ?? 0;
      return tb.compareTo(ta);
    });
    return deduped;
  }




// 置換: loadWeeklyHistoryStrict()
  static Future<List<Map<String, dynamic>>> loadWeeklyHistoryStrict() async {
    final raw = await _loadHistoryRaw();
    final cutoff = _latestVisibleSunday(DateTime.now());

    // weekly のみ
    List<Map<String, dynamic>> weekly = raw
        .where((e) => (e['type'] ?? '').toString().toLowerCase() == 'weekly')
        .toList();

    // カットオフより未来（= 当日の日曜を含む）は非表示
    weekly = weekly.where((w) {
      final ymd = (w['date'] ?? '').toString();
      final dt = _svcParseYmd(ymd);
      return dt != null && !dt.isAfter(cutoff);
    }).toList();

    // 新しいものが上に来るよう降順
    weekly.sort((a, b) =>
        ('${b['createdAt'] ?? b['date']}').compareTo('${a['createdAt'] ?? a['date']}'));

    // （必要なら）重複統合
    // return _dedupPreferReal(weekly);
    return weekly;
  }



// === Weekly gate helpers ===
// その日を含む直近の日曜（同日が日曜ならその日）
  static DateTime _prevOrSameSunday(DateTime d) {
    final wd = d.weekday % 7; // Sun=0, Mon=1..Sat=6
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: wd));
  }

// 「表示してよい最新の日曜」
// - 日曜の間は “前週の日曜” まで
// - 月〜土は “直近の日曜” まで
  static DateTime _latestVisibleSunday(DateTime now) {
    final s = _prevOrSameSunday(now);
    return (now.weekday == DateTime.sunday)
        ? s.subtract(const Duration(days: 7))
        : s;
  }

  static DateTime? _parseYmdSafe(String ymd) {
    if (ymd.isEmpty) return null;
    final p = ymd.split('/');
    if (p.length != 3) return null;
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }




  // REPLACE 全体: loadMonthlyHistoryStrict()
  // REPLACE 全体: loadMonthlyHistoryStrict()
  static Future<List<Map<String, dynamic>>> loadMonthlyHistoryStrict() async {
    final raw = await _loadHistoryRaw();
    final now = DateTime.now();

    // 月次のみ
    List<Map<String, dynamic>> monthly =
    raw.where((e) => (e['type'] ?? '') == 'monthly').toList();

    // 各「月末」のレコードだけに丸める（既存ユーティリティを利用）
    monthly = _onlyEndOfMonth(monthly);

    // === 表示ガード ===
    // ・未来のEOMは非表示
    // ・当月EOMは「翌月1日 00:00」までは非表示（= 0:00 で解禁）
    final today = DateTime(now.year, now.month, now.day);
    final currentEom = _eom(today);
    final cutoff = _monthlyVisibleCutoff(now); // 翌月1日 00:00


    final filtered = <Map<String, dynamic>>[];
    for (final m in monthly) {
      final ymd = (m['date'] ?? '').toString();
      if (ymd.isEmpty) continue;
      final p = ymd.split('/');
      if (p.length != 3) continue;

      final dt = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])); // ←EOM
      // 未来のEOMは見せない
      if (dt.isAfter(currentEom)) continue;

      // 当月EOMは「翌月1日 00:00」までは見せない
      if (_sameDay(dt, currentEom) && now.isBefore(cutoff)) continue;

      filtered.add(m);
    }



    // 表示順（降順）
    filtered.sort((a, b) =>
        ('${b['createdAt'] ?? b['date']}').compareTo('${a['createdAt'] ?? a['date']}'));

    return _dedupPreferReal(filtered);
  }


  // 欠損/壊れ行の一括補完・修理
  static Future<int> backfillOrRepairDailyFromHappiness() async {
    final existingDates = await loadExistingDataDates();
    final logs = await CsvLoader.loadAiCommentLog();

    final latestDailyByDate = <String, Map<String, String>>{};
    for (final r in logs) {
      if ((r['type'] ?? '') == 'daily') {
        final d = (r['date'] ?? '').trim();
        if (d.isNotEmpty) latestDailyByDate[d] = r;
      }
    }

    int changed = 0;
    for (final d in existingDates) {
      final key = fmtYMD(d);
      final saved = latestDailyByDate[key];

      final isMissing = (saved == null);
      final isBroken = saved != null &&
          (((saved['comment'] ?? '').trim().isEmpty) ||
              ((saved['comment'] ?? '').trim() == (saved['memo'] ?? '').trim()));

      if (isMissing || isBroken) {
        final memo  = await CsvLoader.loadMemoForDate(d);
        final ai    = await _generateDailyAiTextFromCsv(d);
        final score = await CsvLoader.loadHappinessScoreForDate(d);

        await CsvLoader.appendAiCommentLog(
          date: key,
          type: 'daily',
          comment: ai,
          score: score,
          sleep: '',
          walk: '',
          gratitude1: '',
          gratitude2: '',
          gratitude3: '',
          memo: memo,
        );
        changed++;
      }
    }
    debugPrint('[BACKFILL] daily addedOrRepaired = $changed');
    return changed;
  }
  /// 月次の「当月末(例: 2025/08/31)」で保存されてしまったレコードを
  /// 「前月末(例: 2025/07/31)」へ矯正する。
  /// 既に前月末のレコードがある場合は、当月末の重複分を削除します。
  static Future<int> migrateMonthlyToPrevMonthEndIfNeeded(DateTime latestDate) async {
    // Aiコメントログ（小文字ヘッダ: date, type, comment, ...）を読み込み
    final rows = await CsvLoader.loadAiCommentLog(); // List<Map<String, String>>
    if (rows.isEmpty) return 0;

    // 日付フォーマッタ
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/'
            '${d.day.toString().padLeft(2, '0')}';

    // 当月末(誤) と 前月末(正)
    final wrongMonthEnd = DateTime(latestDate.year, latestDate.month + 1, 0);
    final prevMonth = (latestDate.month == 1)
        ? DateTime(latestDate.year - 1, 12, 1)
        : DateTime(latestDate.year, latestDate.month - 1, 1);
    final correctMonthEnd = DateTime(prevMonth.year, prevMonth.month + 1, 0);

    final wrong = fmt(wrongMonthEnd);     // 例: 2025/08/31
    final correct = fmt(correctMonthEnd); // 例: 2025/07/31

    // 既に正しい前月末が存在するか
    final hasCorrect = rows.any((r) =>
    (r['type'] ?? '').toLowerCase() == 'monthly' &&
        (r['date'] ?? '') == correct);

    int moved = 0;
    bool removedWrong = false;

    // 1) 当月末(誤) → 前月末(正) に置換 or 削除マーク
    for (final r in rows) {
      final type = (r['type'] ?? '').toLowerCase();
      final date = (r['date'] ?? '');
      if (type == 'monthly' && date == wrong) {
        if (hasCorrect) {
          // 正が既にあるなら誤データは削除対象
          r['__drop__'] = '1';
          removedWrong = true;
        } else {
          // 正しい日付へ移動
          r['date'] = correct;
          moved++;
        }
      }
    }

    // 2) 削除マークを除去
    final newRows = rows.where((r) => r['__drop__'] != '1').toList();

    // 3) 日付降順で並べ替え
    newRows.sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));

    // 4) CSVに上書き保存（共通ヘルパーで書く）
    if (moved > 0 || removedWrong) {
      await CsvLoader.writeAiCommentLog(newRows);  // ← ここだけでOK
    }


    // 置換件数（削除のみの場合は 0）
    return moved;
  }

  // ← 既存 import 群のままでOK（intl を使っている場合は import 'package:intl/intl.dart'; が既にあるはず）





// 週次：開始日で保存されているレコードを、同じ週の「日曜」に移す
  static Future<int> migrateWeeklyToSundayIfNeeded() async {
    final rows = await CsvLoader.loadAiCommentLog();
    if (rows.isEmpty) return 0;

    // 日曜変換ヘルパ
    DateTime toSunday(DateTime d) {
      final wd = d.weekday % 7;       // 月=1..土=6, 日=0
      return asYMD(d).add(Duration(days: (7 - wd) % 7)); // 次の日曜(同日が日曜ならその日)
    }

    // 既に日曜キーの存在チェック用
    final hasSunday = <String, bool>{};
    for (final r in rows) {
      if ((r['type'] ?? '').toLowerCase() != 'weekly') continue;
      final raw = (r['date'] ?? '').trim();
      if (raw.isEmpty) continue;
      DateTime d; try { d = parseYMD(raw); } catch (_) { continue; }
      hasSunday[fmtYMD(toSunday(d))] = true;
    }

    int moved = 0;
    for (final r in rows) {
      if ((r['type'] ?? '').toLowerCase() != 'weekly') continue;
      final raw = (r['date'] ?? '').trim();
      if (raw.isEmpty) continue;

      DateTime d; try { d = parseYMD(raw); } catch (_) { continue; }
      if (isSunday(d)) continue; // 既に正しい

      final sun = toSunday(d);
      final sunKey = fmtYMD(sun);
      if (hasSunday[sunKey] == true) {
        // 既に日曜キーがあるなら、こちらは捨てる（重複回避）
        r['type'] = '__delete__';
      } else {
        r['date'] = sunKey;  // 日曜キーへ移す
        hasSunday[sunKey] = true;
        moved++;
      }
    }

    final remain = rows.where((r) => (r['type'] ?? '') != '__delete__').toList();
    await CsvLoader.writeAiCommentLog(remain);
    return moved;
  }

// ============================
// file: lib/services/ai_comment_service.dart (追加: 手動補完 & Strictローダ強化)
// 既存のクラス AiCommentService に下記メソッドを追記してください。
// ============================


static Future<int> backfillDailyMissing() async {
// メインCSVから全ての入力日を取得し、保存が無い日だけ daily を生成
final csv = await CsvLoader.loadCsv('HappinessLevelDB1_v2.csv');
final seen = <String>{};
final dates = <DateTime>[];
for (final r in csv) {
final ds = (r['日付'] ?? '').trim();
if (ds.isEmpty || seen.contains(ds)) continue;
try {
dates.add(DateFormat('yyyy/MM/dd').parseStrict(ds));
seen.add(ds);
} catch (_) {}
}
dates.sort();

var added = 0;
for (final d in dates) {
final key = DateFormat('yyyy/MM/dd').format(d);
final saved = await getSavedComment(date: key, type: 'daily');
if (saved == null || saved.trim().isEmpty) {
final res = await ensureDailySaved(d);
if ((res['comment'] ?? '').trim().isNotEmpty) added++;
}
}
return added;
}

static Future<int> backfillWeeklyMissing() async {
// メインCSVの期間に存在する「直近で過ぎた日曜」ごとに weekly を生成
final csv = await CsvLoader.loadCsv('HappinessLevelDB1_v2.csv');
DateTime? minD, maxD;
for (final r in csv) {
final ds = (r['日付'] ?? '').trim();
if (ds.isEmpty) continue;
try {
final d = DateFormat('yyyy/MM/dd').parseStrict(ds);
minD = (minD == null || d.isBefore(minD!)) ? d : minD;
maxD = (maxD == null || d.isAfter(maxD!)) ? d : maxD;
} catch (_) {}
}
   if (minD == null || maxD == null) return 0;
   final min = minD!;
   final max = maxD!;
   // max 時点での直近の日曜…
   DateTime lastSunday(DateTime x) {
final wd = x.weekday % 7; // 日=0
final back = (wd == 0) ? 7 : wd;
return DateTime(x.year, x.month, x.day).subtract(Duration(days: back));
}

final endSun = lastSunday(max);
final sundays = <DateTime>[];
for (var d = lastSunday(min.add(const Duration(days: 6)));
!d.isAfter(endSun);
d = d.add(const Duration(days: 7))) {

sundays.add(d);
}

var added = 0;
for (final s in sundays) {
final key = DateFormat('yyyy/MM/dd').format(s);
final saved = await getSavedComment(date: key, type: 'weekly');
if (saved == null || saved.trim().isNotEmpty == false) {
final res = await ensureWeeklySaved(s);
if ((res['comment'] ?? '').trim().isNotEmpty) added++;
}
}
return added;
}
static Future<int> backfillMonthlyMissing() async {
// メインCSVの期間に存在する各「月末」について monthly を生成
final csv = await CsvLoader.loadCsv('HappinessLevelDB1_v2.csv');
DateTime? minD, maxD;
for (final r in csv) {
final ds = (r['日付'] ?? '').trim();
if (ds.isEmpty) continue;
try {
final d = DateFormat('yyyy/MM/dd').parseStrict(ds);
minD = (minD == null || d.isBefore(minD!)) ? d : minD;
maxD = (maxD == null || d.isAfter(maxD!)) ? d : maxD;
} catch (_) {}
}
   if (minD == null || maxD == null) return 0;
   final min = minD!;
   final max = maxD!;
   DateTime eom(DateTime x) => DateTime(x.year, x.month + 1, 0);

   var cursor = DateTime(min.year, min.month, 1);
   final limit = DateTime(max.year, max.month, 1);
var added = 0;
while (!cursor.isAfter(limit)) {
final monthEnd = eom(cursor);
final key = DateFormat('yyyy/MM/dd').format(monthEnd);

final saved = await getSavedComment(date: key, type: 'monthly');
if (saved == null || saved.trim().isEmpty) {
final res = await ensureMonthlySaved(monthEnd);
if ((res['comment'] ?? '').trim().isNotEmpty) added++;
}

cursor = DateTime(cursor.year, cursor.month + 1, 1);
}
return added;
}

  static Future<List<Map<String, dynamic>>> _loadHistoryRaw() async {
    final rows = await CsvLoader.loadAiCommentLog(); // List<Map<String,String>>
    return rows.map((r) => {
      'date'      : r['date'] ?? '',
      'type'      : (r['type'] ?? '').toLowerCase(),
      'comment'   : r['comment'] ?? '',
      // createdAt が無い場合は date を使って降順安定化
      'createdAt' : r['createdAt'] ?? '${r['date'] ?? ''}T00:00:00',
    }).toList();
  }

// date(yyyy/MM/dd) と type(daily/weekly/monthly) で重複をまとめ、
// 「非フォールバック > フォールバック」の優先で 1 件に集約。
// 同優先度なら「後勝ち」（読み込み順が新しい方）を採用。
  // 同一 (date + type) が複数ある場合、フォールバックより実文を優先。
// フォールバック同士 or 実文同士なら ts(保存時刻) が新しい方。
  static List<Map<String, dynamic>> _dedupPreferReal(
      List<Map<String, dynamic>> rows) {
    final map = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final key = '${r['date']}_${r['type']}';
      if (!map.containsKey(key)) {
        map[key] = r;
        continue;
      }
      final prev = map[key]!;
      final prevIsFb = _looksFallback((prev['comment'] ?? '').toString());
      final currIsFb = _looksFallback((r['comment'] ?? '').toString());

      if (prevIsFb && !currIsFb) {
        map[key] = r; // 実文が勝ち
        continue;
      }
      if (!prevIsFb && currIsFb) {
        continue;    // 既に実文 → 現行のフォールバックは捨て
      }
      // 同種同士は ts が新しい方
      final pt = (prev['ts'] as int?) ?? 0;
      final ct = (r['ts'] as int?) ?? 0;
      if (ct >= pt) map[key] = r;
    }
    return map.values.toList();
  }




// 生の rows（date,type,comment,createdAt）を ai_comment_log に保存
  static Future<void> _saveHistoryRaw(List<Map<String, dynamic>> rows) async {
    // 文字列化して Map<String,String> に揃える
    final out = rows.map((e) => <String, String>{
      'date'      : '${e['date'] ?? ''}',
      'type'      : '${e['type'] ?? ''}',
      'comment'   : '${e['comment'] ?? ''}',
      'createdAt' : '${e['createdAt'] ?? ''}',
    }).toList();
    await CsvLoader.writeAiCommentLog(out);
  }
// 強制再生成：対象日の daily を全削除してから厳密生成
  static Future<void> forceRecreateDaily(DateTime date) async {
    final ymd = _fmtYmd(date); // 例: 2025/08/05
    final rows = await CsvLoader.loadAiCommentLog();
    final kept = rows.where((r) =>
    (r['type']?.toLowerCase() != 'daily') || (r['date']?.trim() != ymd)
    ).toList();
    await CsvLoader.writeAiCommentLog(kept);
    // 正規の「その日だけ厳密生成」を実行（既存）
    await ensureDailySavedForDate(date);            // ← 既に実装済み（1日分だけ厳密生成）
  }
// 指定の年月日と種別で、履歴ログの該当行を物理削除
  static Future<int> hardDeleteByDateType(String ymd, String type) async {
    final raw = await _loadHistoryRaw();
    final remain = raw.where((r) => !(r['date'] == ymd && r['type'] == type)).toList();
    await _saveHistoryRaw(remain);
    return raw.length - remain.length;
  }
// 1日の raw レコードを date+type で抽出（デバッグ専用）
  static Future<List<Map<String, dynamic>>> debugRawFor(
      String ymd,
      String type,
      ) async {
    final raw = await _loadHistoryRaw();        // 既存の内部ローダを再利用
    return raw.where((e) => e['date'] == ymd && e['type'] == type).toList();
  }

// 既存の _fmt などは流用してください
  static Future<bool> hasDailyForDate(DateTime d) async {
    final ymd = _fmtYmd(d);
    final raw = await _loadHistoryRaw();       // 既存の生読み出し
    // フォールバックは除外＝実データがあるか
    return raw.any((e) =>
    e['date'] == ymd &&
        e['type'] == 'daily' &&
        !_looksFallback((e['comment'] ?? '').toString()));
  }

// 月次レコードを「その月の末日だけ」に絞り込み
  static List<Map<String, dynamic>> _onlyEndOfMonth(List<Map<String, dynamic>> rows) {
    final out = <Map<String, dynamic>>[];
    for (final e in rows) {
      final ymd = (e['date'] ?? '').toString();
      if (ymd.length != 10) continue;
      final y = int.tryParse(ymd.substring(0, 4)) ?? 0;
      final m = int.tryParse(ymd.substring(5, 7)) ?? 1;
      final d = int.tryParse(ymd.substring(8, 10)) ?? 1;
      if (y == 0) continue;

      final dt  = DateTime(y, m, d);
      final eom = DateTime(y, m + 1, 0); // 月+1 の 0日目 = 月末
      final eomYmd =
          '${eom.year.toString().padLeft(4, '0')}/${eom.month.toString().padLeft(2, '0')}/${eom.day.toString().padLeft(2, '0')}';

      if (ymd == eomYmd) out.add(e);
    }
    return out;
  }
// 決定論的ランダム用シード（終了日ベース）
  static int _seedFromDate(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static List<T> _pickDeterministicRandom<T>(
      List<T> items, int maxCount, DateTime seedDate,
      ) {
    if (items.length <= maxCount) return List<T>.from(items);
    final rnd = Random(_seedFromDate(seedDate));
    final list = List<T>.from(items);
    list.shuffle(rnd);
    return list.take(maxCount).toList();
  }

  static List<String> _dedupNonEmpty(Iterable<String> src) =>
      src.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();

  static String _trimMemo(String s, int maxChars) {
    final t = s.trim();
    return (t.length <= maxChars) ? t : (t.substring(0, maxChars) + '…');
  }


  // ==== 追加・置換ここから =====================================

  // 呼び出し側の互換用（exporterが daily/weekly/monthly で呼べます）
  static Future<List<dynamic>> loadHistoryDaily()   => loadHistory('daily');
  static Future<List<dynamic>> loadHistoryWeekly()  => loadHistory('weekly');
  static Future<List<dynamic>> loadHistoryMonthly() => loadHistory('monthly');

  /// kind: 'daily' | 'weekly' | 'monthly'
  static Future<List<dynamic>> loadHistory(String kind) async {
    // 1) Documents / Application Support を横断スキャン
    final bases = <Directory>[
      await getApplicationDocumentsDirectory(),
      await getApplicationSupportDirectory(),
    ];
    for (final base in bases) {
      final list = await _scanHistoryFiles(base, kind);
      if (list.isNotEmpty) return list;
    }

    // 2) SharedPreferences の全キーから “history & kind” を探索
    final fromPrefs = await _loadHistoryFromPrefs(kind);
    if (fromPrefs.isNotEmpty) return fromPrefs;

    return <dynamic>[];
  }

  static Future<List<dynamic>> _scanHistoryFiles(
      Directory base, String kind) async {
    // よくある候補名（まず直指定）
    final candidates = <String>[
      'ai_history/$kind.json',
      'ai_comment_history_$kind.json',
      'ai_comments_$kind.json',
      'history_$kind.json',
      '$kind.json',
    ];
    for (final rel in candidates) {
      final f = File('${base.path}/$rel');
      if (await f.exists()) {
        final list = await _readJsonAsList(f);
        if (list != null && list.isNotEmpty) return list;
      }
    }

    // なければ配下をスキャン
    try {
      await for (final e in base.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final p = e.path.toLowerCase();
        if (p.endsWith('.json') &&
            p.contains(kind) &&
            (p.contains('history') || p.contains('comment') || p.contains('ai'))) {
          final list = await _readJsonAsList(e);
          if (list != null && list.isNotEmpty) return list;
        }
      }
    } catch (_) {}
    return <dynamic>[];
  }

  static Future<List<dynamic>> _loadHistoryFromPrefs(String kind) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // 代表的キー名（まず優先）
      final priority = <String>{
        'history_$kind',
        'ai_history_$kind',
        'ai_comment_history_$kind',
        '${kind}History',
        'history${_cap(kind)}',
      };

      // 候補＝全キーから "history" を含み、なおかつ kind（daily/weekly/monthly）を含むもの
      final dynamicKeys = keys.where((k) {
        final s = k.toLowerCase();
        return s.contains('history') && s.contains(kind);
      }).toList()
        ..sort();

      final all = [
        ...priority.where(keys.contains),
        ...dynamicKeys,
      ].toSet().toList();

      for (final k in all) {
        // String or StringList のどちらにも対応
        final str = prefs.getString(k);
        if (str != null && str.isNotEmpty) {
          final list = _decodeHistoryString(str);
          if (list.isNotEmpty) return list;
        }
        final sl = prefs.getStringList(k);
        if (sl != null && sl.isNotEmpty) {
          final list = <dynamic>[];
          for (final s in sl) {
            final d = _decodeHistoryString(s);
            list.addAll(d.isEmpty ? [s] : d);
          }
          if (list.isNotEmpty) return list;
        }
      }
    } catch (_) {}
    return <dynamic>[];
  }

  static List<dynamic> _decodeHistoryString(String s) {
    try {
      var t = s.replaceFirst('\uFEFF', ''); // BOM除去
      final decoded = jsonDecode(t);
      if (decoded is List) return decoded;
      if (decoded is Map<String, dynamic>) {
        // {"2025/09/04": {...}} の辞書形式にも対応
        return decoded.entries.map((e) {
          final m = Map<String, dynamic>.from(e.value as Map);
          m.putIfAbsent('date', () => e.key);
          return m;
        }).toList();
      }
    } catch (_) {}
    return <dynamic>[];
  }

  static Future<List<dynamic>?> _readJsonAsList(File f) async {
    try {
      var text = await f.readAsString();
      if (text.isEmpty) return <dynamic>[];
      text = text.replaceFirst('\uFEFF', '');
      final decoded = jsonDecode(text);
      if (decoded is List) return decoded;
      if (decoded is Map<String, dynamic>) {
        if (decoded['items'] is List) return List.from(decoded['items']);
        if (decoded['data']  is List) return List.from(decoded['data']);
        if (decoded.isNotEmpty && decoded.values.first is Map) {
          return decoded.entries.map((e) {
            final m = Map<String, dynamic>.from(e.value as Map);
            m.putIfAbsent('date', () => e.key);
            return m;
          }).toList();
        }
      }
    } catch (_) {}
    return null;
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
// ==== 追加・置換ここまで =====================================

  /// 当日のユーザー入力があるか判定
  /// ・CSVに当日行が存在し、いずれかの項目に入力がある場合 true
  static Future<bool> hasDailyUserInput(DateTime date) async {
    final f = DateFormat('yyyy/MM/dd');
    final target = f.format(date);
    final csv = await CsvLoader.loadCsv('HappinessLevelDB1_v2.csv');

    final Map<String,String> row = csv.firstWhere(
          (r) => (r['日付'] ?? '').trim() == target,
      orElse: () => <String,String>{},
    );

    if (row.isEmpty) return false;

    String t(String k) => (row[k] ?? '').toString().trim();
    double n(String k) => double.tryParse((row[k] ?? '').toString()) ?? 0;

    final hasText = t('memo').isNotEmpty ||
        t('感謝1').isNotEmpty || t('gratitude1').isNotEmpty ||
        t('感謝2').isNotEmpty || t('gratitude2').isNotEmpty ||
        t('感謝3').isNotEmpty || t('gratitude3').isNotEmpty;

    final hasNum = n('睡眠の質') > 0 || n('ストレッチ時間') > 0 || n('ウォーキング時間') > 0;

    return hasText || hasNum;
  }

  // 当日行を取得（厳密一致）
  static Future<Map<String, String>?> getTodayRow() async {
    final csv = await CsvLoader.loadCsv('HappinessLevelDB1_v2.csv');
    final todayStr = DateFormat('yyyy/MM/dd').format(DateTime.now());
    for (final r in csv) {
      if ((r['日付'] ?? '').trim() == todayStr) return r;
    }
    return null;
  }

// 何かしら入力があるかを判定
  static bool hasAnyInput(Map<String, String> row) {
    String t(String? s) => (s ?? '').trim();
    double n(String? s) => double.tryParse((s ?? '').toString()) ?? 0;

    final memo = t(row['memo']);
    final g1 = t(row['感謝1'] ?? row['gratitude1']);
    final g2 = t(row['感謝2'] ?? row['gratitude2']);
    final g3 = t(row['感謝3'] ?? row['gratitude3']);

    final sleepQ = n(row['睡眠の質']);
    final stretch = n(row['ストレッチ時間']);
    final walk = n(row['ウォーキング時間']);
    final happy = n(row['幸せ感レベル']);

    return memo.isNotEmpty || g1.isNotEmpty || g2.isNotEmpty || g3.isNotEmpty
        || sleepQ > 0 || stretch > 0 || walk > 0 || happy > 0;
  }
  static Future<String> _resolveDisplayName() async {
    final name = await UserPrefs.getDisplayName();
    // 未設定時に「あなた」を返さない（呼びかけ汚染源を断つ）
    return (name == null || name.trim().isEmpty) ? '' : name.trim();
  }




}
