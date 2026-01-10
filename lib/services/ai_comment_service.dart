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
import 'package:path/path.dart' as p;
import 'dart:async';

// === DEBUG: AIプロンプト/応答ログ制御（--dart-define=LOG_AI=true で有効） ===
const bool LOG_AI = bool.fromEnvironment('LOG_AI', defaultValue: false);

// 長いテキストを先頭だけ安全に切り出す小ヘルパ
String _clipForLog(String s, {int max = 400}) {
  if (s.length <= max) return s;
  return s.substring(0, max) + ' ...<clipped>';
}


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

// === ADD: 正規化ユーティリティ ===
String _normType(String s) => (s.trim().toLowerCase());
bool _isWeekly(String s) => _normType(s) == 'weekly';
bool _isMonthly(String s) => _normType(s) == 'monthly';
bool _isDaily(String s) => _normType(s) == 'daily';

// CSV 1行 -> {date, type, comment} へ（安全に）
Map<String, String>? _toRow(Map<String, dynamic> m) {
  final date = (m['date'] ?? '').toString().trim();
  final type = _normType((m['type'] ?? '').toString());
  final comment = (m['comment'] ?? '').toString();
  if (date.isEmpty || type.isEmpty) return null;
  return {'date': date, 'type': type, 'comment': comment};
}

Future<http.Response> _postWithTimeout(
    String url, {
      required Map<String, String> headers,
      required Object body,
    }) {
  return http
      .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
      .timeout(const Duration(seconds: 30));
}






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
// 例：既存の実装名が違うならエイリアスでも可
  static Future<void> deleteCommentsForDates(List<String> ymdList) async {
    // ← あなたが作った削除実装をここで呼ぶ or 本体をここに置く
    await _deleteHistoryForDatesInternal(ymdList);
  }
  /// ai_comment_log.csv から、指定 yyyy/MM/dd の全タイプ(daily/weekly/monthly)を削除
    static Future<void> _deleteHistoryForDatesInternal(List<String> ymdList) async {
        final targets = ymdList.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        if (targets.isEmpty) return;

        final rows = await CsvLoader.loadAiCommentLog();
        final filtered = rows.where((r) {
          final d = (r['date'] ?? '').toString().trim();
          return !targets.contains(d);
        }).toList();

        if (filtered.length != rows.length) {
          await CsvLoader.writeAiCommentLog(filtered);
          debugPrint('[AI LOG] delete ${rows.length - filtered.length} rows for ${targets.join(", ")}');
        }
      }




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
      RegExp(r'^\s*あなたさん', multiLine: true),
      RegExp(r'^\s*あなた(?!方)', multiLine: true),
      RegExp(r'あなたさん'),
      RegExp(r'あなた(?!方)'),
      RegExp(r'貴方さん'),
      RegExp(r'貴方(?!方)'),
      RegExp(r'貴女さん'),
      RegExp(r'貴女(?!方)'),
      RegExp(r'\b[Yy]ou\b'),
      RegExp(r'君'),
      RegExp(r'きみ'),
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
      if (d.isNotEmpty) {
        byDate[d] = (r['comment'] ?? '').toString();
      }
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
      } catch (_) {
        // パースできない日付は無視
      }
    }
    if (days.isEmpty) return [];

    days.sort();

    // 「その日の属する日曜」に丸めるヘルパ
    DateTime _prevSunday(DateTime d) {
      final wd = d.weekday % 7;
      return DateTime(d.year, d.month, d.day).subtract(Duration(days: wd));
    }

    // 先頭側：メインCSVの最初の日付から見た「最初の日曜」
    final firstSun = _prevSunday(days.first);

    // メインCSV側の最終日曜
    final lastSunCsv = _prevSunday(days.last);

    // ログ(ai_comment_log.csv)側の最終日曜（weeklyのみ）
    DateTime? lastSunLog;
    if (byDate.isNotEmpty) {
      final weeklyDates = <DateTime>[];
      for (final ds in byDate.keys) {
        try {
          // ここも yyyy/MM/dd 固定のまま（形式は今まで通り）
          weeklyDates.add(DateFormat('yyyy/MM/dd').parseStrict(ds));
        } catch (_) {
          // パースできないものは無視
        }
      }
      if (weeklyDates.isNotEmpty) {
        weeklyDates.sort();
        lastSunLog = _prevSunday(weeklyDates.last);
      }
    }

    // 表示カットオフ（日曜基準）
    final cutoffSun = _latestVisibleSunday(DateTime.now());

    // データとして存在する範囲の最終日曜 = CSV と ログのうち「遅い方」
    final lastDataSun = (lastSunLog == null || lastSunCsv.isAfter(lastSunLog))
        ? lastSunCsv
        : lastSunLog;

    // 最終的な表示上限 = lastDataSun と cutoffSun の「早い方」
    final lastSun = lastDataSun.isBefore(cutoffSun) ? lastDataSun : cutoffSun;

    // 3) スロット生成（firstSun 〜 lastSun の各日曜）
    final out = <Map<String, String>>[];
    for (DateTime cur = firstSun;
    !cur.isAfter(lastSun);
    cur = cur.add(const Duration(days: 7))) {
      final ymd =
          '${cur.year.toString().padLeft(4, '0')}/${cur.month.toString().padLeft(2, '0')}/${cur.day.toString().padLeft(2, '0')}';
      out.add({
        'type': 'weekly',
        'date': ymd,
        'comment': byDate[ymd] ?? '',
      });
    }

    // 日付の新しい順（降順）にソート
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
  // 週次（end=日曜）
  static Future<Map<String, String>> ensureWeeklySaved(DateTime lastSunday) async {
    final end   = DateTime(lastSunday.year, lastSunday.month, lastSunday.day);
    final start = end.subtract(const Duration(days: 6));
    final key   = DateFormat('yyyy/MM/dd').format(end);

    // ① 先に「保存済み」を再利用
    final saved = await getSavedComment(date: key, type: 'weekly');
    if (saved != null && saved.trim().isNotEmpty) {
      return {'date': key, 'type': 'weekly', 'comment': saved};
    }

    // ② 生成許可の判定（許可外なら“生成しない”）
    if (!_canCreateWeeklyFor(end, DateTime.now())) {
      return {'date': key, 'type': 'weekly', 'comment': ''};
    }

    // ③ 週内に実データが無ければ生成せず空
    final hasData = await _hasActualRowsInRange(start, end);
    if (!hasData) {
      return {'date': key, 'type': 'weekly', 'comment': ''};
    }

    // ④ 新規生成 → 生成できたら必ず保存（上書き）
    final text = (await getPeriodComment(
      startDate: start,
      endDate: end,
      type: 'weekly',
    ))
        .trim();

    if (text.isNotEmpty) {
      // ★ここで永続化（関数名はプロジェクトの実体に合わせてください）
      await saveComment(date: key, type: 'weekly', text: text);

    }

    return {'date': key, 'type': 'weekly', 'comment': text};
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

    // ① 保存済みがあれば最優先で返す
    final saved = await getSavedComment(date: key, type: 'monthly');
    if (saved != null && saved.trim().isNotEmpty) {
      return {'date': key, 'type': 'monthly', 'comment': saved};
    }

    // ② 生成許可を満たさなければ生成しない
    if (!_canCreateMonthlyFor(end, DateTime.now())) {
      return {'date': key, 'type': 'monthly', 'comment': ''};
    }

    // ③ その月に材料が無ければ空
    final hasData = await _hasActualRowsInRange(start, end);
    if (!hasData) {
      return {'date': key, 'type': 'monthly', 'comment': ''};
    }

    // ④ 新規生成 → 生成できたら必ず保存（上書き）
    final text = (await getPeriodComment(
      startDate: start,
      endDate: end,
      type: 'monthly',
    ))
        .trim();

    if (text.isNotEmpty) {
      // ★ここで永続化（関数名はプロジェクトの実体に合わせてください）
      await saveComment(date: key, type: 'monthly', text: text);

    }

    return {'date': key, 'type': 'monthly', 'comment': text};
  }


    static bool _isTransientAiErrorMessage(String text) {
        final t = text.trim();
        if (t.isEmpty) return true;
        return t.startsWith('⚠') || t.contains('タイムアウト') || t.contains('通信');
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

  // === ADD: メモ使用可視化用のプレビュー関数（ログ用） ==================
  static String _preview(String s, [int n = 40]) {
    final one = s.replaceAll('\n', ' ').trim();
    if (one.isEmpty) return '(empty)';
    return (one.length <= n) ? one : (one.substring(0, n) + '…');
  }
  // /// PATCH 1/3: メモ由来のキーフレーズ抽出＆検出ヘルパ
  // static String _memoCue(String memo) {
  //   final t = memo.replaceAll(RegExp(r'\s+'), ' ').trim();
  //   if (t.isEmpty) return '';
  //   // 句読点や助詞でざっくり切って短い名詞句っぽい先頭を拾う
  //   final cut = t.split(RegExp(r'[、。]|は|が|を|に|で|と')).first.trim();
  //   final short = cut.length > 14 ? '${cut.substring(0, 14)}…' : cut;
  //   return short;
  // }

  static bool _textMentionsCue(String text, String cue) {
    if (text.trim().isEmpty || cue.trim().isEmpty) return false;
    // cue の一部（3文字以上の連続部分）が本文に含まれていればOKという緩い判定
    final c = cue.replaceAll(RegExp(r'\s+'), '');
    if (c.length < 3) return false;
    for (int len = c.length; len >= 3; len--) {
      final sub = c.substring(0, len);
      if (text.contains(sub)) return true;
    }
    return false;
  }

  // 追伸：メモ未反映なら短い一文を“決定論ランダム”で追加（同じ日＋同じメモなら同じ文）
  static String _appendMemoLineIfMissing(String text, String memoCue, bool hasMemo) {
    if (!hasMemo) return text;
    final cue = memoCue.trim();
    if (cue.isEmpty) return text;

    final s = text.trim();
    // すでに本文がメモに触れているなら追記しない
    final already = s.contains(cue) || s.contains('メモ');
    if (already) return s;

    // 以前の固定句が混ざっていたら安全に除去/置換
    var cleaned = s.replaceAll('大切にできると良さそうです。', '次の一歩に活かせそうです。');

    // 同じ入力で毎回同じ文になるように（ぶれない“ランダム”）
    final variants = <String>[
      '追伸：メモの「$cue」、良い視点ですね。',
      '追伸：今日のメモ「$cue」を次の一歩に活かせそうです。',
      '追伸：メモ「$cue」、気づきを言葉にできていて素敵です。',
      '追伸：メモ「$cue」、無理のない形で一歩だけ試しましょう。',
      '追伸：メモ「$cue」、その気づきが明日に繋がります。',
      '追伸：メモ「$cue」、一歩一歩の積み重ね大切ですね。',
      '追伸：メモ「$cue」、大事な視点ですね。',
    ];
    final seed = cue.hashCode; // cue 由来で決定
    final idx = (seed.abs()) % variants.length;
    final follow = variants[idx];

    // 末尾に句点が無ければ付けてから追記
    final withPeriod = RegExp(r'[。.!?]$').hasMatch(cleaned) ? cleaned : '$cleaned。';
    return '$withPeriod $follow';
  }


  static String _memoCue(String memo) {
    final m = memo.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (m.isEmpty) return '';
    final head = m.split(RegExp(r'[、。]')).first.trim();
    return head.length > 12 ? '${head.substring(0, 12)}…' : head;
  }









// === 日次のAIコメント生成（OpenAI使用）—ボリューム1.5倍 & 伴走トーン強化 ===
  static Future<String> getTodayComment({
    required DateTime displayDate,
    required String memo,
  }) async {
    // 材料をCSVから取得（既存CsvLoaderユーティリティを最大活用）
    final ymdLabel = DateFormat('yyyy/MM/dd').format(displayDate);
    final scoreStr = await CsvLoader.loadHappinessScoreForDate(displayDate); // 幸せ感(0-100)
    final radar    = await CsvLoader.loadRadarScoresForDate(displayDate);    // [睡眠の質, ウォーキング分, ストレッチ分]
    final thanks   = await CsvLoader.loadGratitudeForDate(displayDate);      // 文字列リスト（最大3想定）


    // 表示用の見栄えは別で扱い、プロンプトには空なら渡さない
    final thanksStr = thanks.where((t) => t.trim().isNotEmpty).join(' / ');
    final memoStr   = memo.trim();              // ← 空なら空のまま
    final hasMemo   = memoStr.isNotEmpty;       // ← 以降の判定で使用



    // レーダー値の安全取り出し
    final sleepQ   = radar.isNotEmpty ? radar[0] : 0.0; // 0-100%
    final walkMin  = radar.length > 1 ? radar[1] : 0.0; // 分
    final stretch  = radar.length > 2 ? radar[2] : 0.0; // 分

    final callName = await _callName();
    // デバッグ追跡用の軽いプレビュー
    try {
      debugPrint('[AI daily] $ymdLabel memoPreview="${_preview(memoStr, 40)}"');
    } catch (_) {}

    // メモ由来のキーフレーズ（後段の検証/追記に利用）
    final memoCue = _memoCue(memoStr);


    final memoRule = hasMemo
        ? '・メモがある場合：本文の前半2文のうち最低1文で「${callName}」のメモの要点を具体語で要約し（コピペ不可・短く言い換える）、その内容に直結する次の一歩を1つだけ提示する。'
        : '・メモが無い場合：メモには一切触れない（「未入力」等にも触れない）。';
    // プロンプト強化：メモに必ず触れる・一般論回避・伴走トーンひと言
    final prompt = '''
      
      ${callName} へ。あなたはユーザーの心に寄り添い、前向きな気持ちを支える、共感的かつ実践的なAIパートナーです。
      **当日のスコア、3つの感謝、今日のひとことメモ**（※メモが空なら無理に触れない）を参照し、薄味な一般論ではなく ${callName} 個人の今日に寄り添う短文コメントを作成してください。
      
      【必須要件】
      - 全体は**日本語・300文字以内、かつ「3〜4文構成」**
      - 構成：「寄り添いの導入 → 今日の特徴（**メモがある場合のみ要点に1度触れる**） → 感謝の**短い言及**1つ（原文コピペ不可・短く言い換える） → **次の一歩**1つ（約20文字／具体的で無理のない提案） → 安心感のある締め」
      - 呼びかけは常に「${callName}」。**「あなた」「あなたさん」は使わない**
      - 今日のひとことメモを参照して、短く言い換えて必ず１点は反映
      - 感謝1〜3のうち**最低1つ**を短く言い換えて引用（例:「◯◯に感謝」）（原文コピペ不可）
      - **次の一歩**は**20文字程度**で1つだけ（過度に難しくしない）
      - 「素晴らしい」は**幸せ感レベル80以上**のみ使用可（数値だけの賛辞は禁止）
      - 幸せ感の表現は自然語（例：「50台」「落ち着いている」）。小数は直接言及しない
      - 絵文字・顔文字・過度な敬語・説教調・数値だけの賛辞は使わない。
      - ネガティブや説教的な言葉は避ける。押しつけず、伴走トーン。
      - 優しい安心感を感じさせるトーンでまとめる（全体300文字以内）
      - ユーザーの継続を応援する伴走者として語りかける
      - メモがある日は**本文の30〜40%をメモの要点に割く**（一般論で埋めない、具体語で短く）

      
      【書き方のヒント（出力に含めない）】
      - メモは最低1点から２点だけ短く言い換えて触れる（例：要約キーフレーズ）
      - 感謝1〜3のうち最低1つを、短い再表現で一言添える（例：「◯◯に感謝」）
      - 次の一歩は実行可能な小ささで1つだけ（例：「寝る前に深呼吸を3回」）

　　　【出力例の構成（あくまで構成の例・文言は生成すること）】
      - 寄り添いの導入：${callName} への短いねぎらい
      - 本文：今日の特徴（例：睡眠/運動/メモの要点）に1〜2点触れる
      - 感謝の短い引用：例「◯◯に感謝」
      - 次の一歩：1つだけ。20文字程度で具体的に
      - しめ：明日への伴走ひと言
      - しめのポイント: 短く、わかりやすく、地に足のついた言葉で。事実を尊重しつつ、無理のない実践提案を1つ入れてください。
    $memoRule
      - 呼びかけは常に「${callName}」。
      
      【当日のスコア】
      📅 日付: $ymdLabel
      😊 幸せ感レベル: $scoreStr
      😴 睡眠の質: ${sleepQ.toStringAsFixed(0)}（%）
      🚶 ウォーキング: ${walkMin.toStringAsFixed(0)}分
      🧘 ストレッチ: ${stretch.toStringAsFixed(0)}分
      
      【3つの感謝】（要約引用に使う / 原文コピペ禁止）
      🙏 ${thanksStr.isEmpty ? '（未入力）' : thanksStr}
      
      【今日のひとことメモ】（必ず1度は触れる／短く言い換える）
      📝 ${hasMemo ? memoStr : '(なし)'}
      
''';

// === 送信直前ログ（プロンプト/メモ/感謝が入っているか可視化） ===
    if (LOG_AI) {
      debugPrint('[AI PROMPT][daily $ymdLabel]');
      debugPrint('  memoStr   = ${_clipForLog(memoStr, max: 200)}');
      debugPrint('  thanksStr = ${_clipForLog(thanksStr, max: 200)}');
      debugPrint('  prompt    =\n${_clipForLog(prompt, max: 600)}');
    }


    try {
      final payload = {
        'kind': 'daily',
        'date': ymdLabel,
        'callName': callName,
        'prompt': prompt,
        'metrics': {
          'happiness': scoreStr,
          'sleepQ': sleepQ,
          'walkMin': walkMin,
          'stretchMin': stretch,
        },
        'gratitudes': thanks.where((t) => t.trim().isNotEmpty).toList(),
        'memo': memoStr,
      };

      http.Response res;
      try {
        res = await _postWithTimeout(
          _aiEndpoint,
          headers: {'Content-Type': 'application/json'},
          body: payload,
        );
      } on TimeoutException {
        debugPrint('[AI] Timeout (daily $ymdLabel)');
        // ここでは「空文字を返してフォールバックに任せる」か、
        // 直接メッセージを返すか、どちらでもOKです。
        return '⚠️ 通信がタイムアウトしました。しばらくしてから、もう一度お試しください。';
      } catch (e, st) {
        debugPrint('[AI] post error (daily $ymdLabel): $e\n$st');
        return '⚠️ 通信に問題が発生しました。少し時間をおいて再試行してください。';
      }


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        var text = (data['comment'] ?? data['text'] ?? '').toString().trim();

        if (LOG_AI) {
          debugPrint('[AI RESP][daily $ymdLabel] ${_clipForLog(text, max: 400)}');
        }


        if (text.isNotEmpty) {
          try {
            text = _enforceCallName(text, callName);
          } catch (_) {}
          // 感謝が皆無の場合の保険（既存実装）
          final cues = thanks
              .where((t) => t.trim().isNotEmpty)
              .map((s) {
            final cut = s.replaceAll(RegExp(r'\s+'), ' ').trim();
            final head = cut.split(RegExp(r'[、。]|は|が|を|に|で|と')).first.trim();
            return head.isEmpty
                ? ''
                : (head.length > 12 ? '${head.substring(0, 12)}…' : head) + 'に感謝';
          })
              .where((t) => t.isNotEmpty)
              .toList();
          text = _ensureGratitudeMention(text, cues);

          // ★メモ反映の最終チェック：触れていなければ短い一文を自動追記
          text = _appendMemoLineIfMissing(text, _memoCue(memoStr), hasMemo);

          text = text.replaceAll('大切にできると良さそうです。', '次の一歩に活かせそうです。');
          return text;
        }
      }
    } catch (_) {
      // 失敗時は下のフォールバックへ
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
        // ①-2) タイムアウト等の一時エラー文言は「保存しない」
        // → 保存してしまうと「保存済み扱い」になり、以後タップしても再生成されない原因になる
        if (generated != null && _isTransientAiErrorMessage(generated)) {
          debugPrint('[ensureDailySaved] transient error -> skip save: $key');
          return {'date': key, 'type': 'daily', 'comment': generated};
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
    String type = 'weekly', // 'weekly' or 'monthly'
  }) async {
    final endDateStr = DateFormat('yyyy/MM/dd').format(endDate);

    // 既存保存があれば再利用（終了日キー）
    if (await CsvLoader.isCommentAlreadySaved(date: endDateStr, type: type)) {
      final saved = await getSavedComment(date: endDateStr, type: type);
      if (saved != null && saved.isNotEmpty) return saved;
      return 'この${type == "weekly" ? "週" : "月"}のコメントは既に保存されています。';
    }

    // 期間データの読み出し（従来ロジックを活用）
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

    // 期間サマリ（軽量）
    String _avg(List<String> xs) {
      final vs = xs.map((e) => double.tryParse(e) ?? double.nan).where((v) => v == v).toList();
      if (vs.isEmpty) return '';
      final avg = vs.reduce((a,b)=>a+b) / vs.length;
      // 幸せ感は自然語を促すため、ここでは数値を晒しすぎない（表示はプロンプト上だけ）
      return avg.toStringAsFixed(0);
    }
    final happyAvg = _avg(happinessList);
    final sleepAvg = _avg(sleepList);
    final walkAvg  = _avg(walkList);

    // 感謝の原文を短いキューへ（原文コピペ防止）
    String _toGratitudeCue(String s) {
      final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isEmpty) return '';
      final cut = t.split(RegExp(r'[、。]|は|が|を|に|で|と')).first.trim();
      final short = cut.length > 12 ? '${cut.substring(0,12)}…' : cut;
      return '$shortに感謝';
    }
    final gratitudeCues = pickedGratitudes.map(_toGratitudeCue).where((t) => t.isNotEmpty).toList();

    final callName = await _callName();
    final titleJa = (type == 'weekly') ? '週次' : '月次';
    final periodLabel =
        '${DateFormat('yyyy/MM/dd').format(startDate)} ～ ${DateFormat('yyyy/MM/dd').format(endDate)}';

    // ❶ “伴走トーン＆約1.5倍” のプロンプト（あなた禁止／構成＆最大300文字）
    final prompt = '''
${callName} へ。共感的で実践的なAIパートナーとして、以下の期間データを踏まえた${titleJa}コメントを作成します。一般論ではなく ${callName} 個人に寄り添う言葉でまとめてください。

【出力仕様（厳守）】
- 冒頭の呼びかけは必ず「${callName}」
- 文量は優しいトーンで日本語で最大300文字（現状より約1.5倍）
- 構成：「共感の導入 → 期間の特徴に1〜2点触れる（軽く根拠） → 感謝の短い引用1つ → 次の一歩（1つ／20文字程度） → やさしい締め」
- 「あなた」「あなたさん」は使わない。絵文字/顔文字/説教調/過度な賛辞は禁止
- 幸せ感レベルの表現は自然語（例：「50台」「落ち着いている」等）。小数の直接言及は避ける
- ネガティブや説教的な言葉は避ける。伴走者として語りかける
- 次の一歩は実行可能な小ささで1つだけ（例：「寝る前に3回深呼吸」）

【期間】$periodLabel
【傾向（平均目安）】幸せ感:$happyAvg / 睡眠:$sleepAvg / ウォーキング:$walkAvg
【感謝の候補（要約用）】${gratitudeCues.isEmpty ? '（未入力）' : gratitudeCues.join(' / ')}
【メモ要点（必要に応じて1〜2つ言及）】
$memosForPrompt
''';

    try {
      final res = await _postJsonWithRetry(_aiEndpoint, {
        'kind': type, // 'weekly'|'monthly'
        'date': endDateStr,
        'callName': callName,
        'prompt': prompt,
        'metrics': {
          'avg_happiness': happyAvg,
          'avg_sleepQ': sleepAvg,
          'avg_walk': walkAvg,
        },
        'gratitude_cues': gratitudeCues,
        'memos': pickedMemos,
      });


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        var text = (data['comment'] ?? data['text'] ?? '').toString().trim();
        if (text.isNotEmpty) {
          try {
            text = _enforceCallName(text, callName);
          } catch (e, st) {
            debugPrint('[enforceCallName] ignore: $e\n$st');
          }
          text = _ensureGratitudeMention(text, gratitudeCues);
          return text;
        }
      }
    } catch (e, st) {
      debugPrint('[getPeriodComment:$type] error: $e');
      debugPrintStack(stackTrace: st);
    }

    // 失敗時は空を返す（呼び出し元が保存をスキップ or フォールバックを適用）
    return '';
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
  static Future<String?> getSavedComment({required String date, required String type}) async {
    final wantType = _normType(type);
    final rows = (await CsvLoader.loadAiCommentLog())
        .map(_toRow)
        .whereType<Map<String, String>>()
        .toList();


    final hit = rows.firstWhere(
          (r) => r['date']!.trim() == date.trim() && _normType(r['type']!) == wantType,
      orElse: () => const {'date': '', 'type': '', 'comment': ''},
    );
    return (hit['date']!.isEmpty) ? null : hit['comment'];
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

  /// 保存データ（日付）に対応するAIコメントの履歴/キャッシュを削除する。
  /// ymd は 'YYYY/MM/DD' 形式を想定。
  static Future<void> deleteCommentsByDates(Iterable<String> ymds) async {
    final set = ymds.where((e) => e.trim().isNotEmpty).toSet();
    if (set.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final base = dir.path;
    // 本アプリで使っているAIコメント保存ファイル（両系統を対象）
    const kinds = ['daily', 'weekly', 'monthly'];
    const bases = ['ai_comment_history_', 'ai_comments_']; // 既存実装に合わせて両方

    for (final k in kinds) {
      for (final b in bases) {
        final f = File('$base/$b$k.json');
        if (!await f.exists()) continue;

        try {
          final raw = await f.readAsString();
          if (raw.trim().isEmpty) continue;
          final List<dynamic> list = jsonDecode(raw) as List<dynamic>;

          bool changed = false;
          final filtered = <dynamic>[];
          for (final e in list) {
            // 既存のキー表記に幅を持たせる
            final d = (e is Map)
                ? (e['displayDate'] ??
                e['date'] ??
                e['ymd'] ??
                e['day'] ??
                '')
                : '';
            if (set.contains(d)) {
              changed = true; // この行は捨てる（=削除）
            } else {
              filtered.add(e);
            }
          }

          if (changed) {
            await f.writeAsString(const JsonEncoder.withIndent('  ').convert(filtered));
            // ログ（任意）
            // debugPrint('[AI-HISTORY] purged $k for ${set.join(", ")} in $b$k.json');
          }
        } catch (_) {
          // 壊れたJSONは握りつぶす（安全側）
        }
      }
    }
  }
  static Future<void> deleteHistoryForDates(List<String> ymds) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dailyPath   = p.join(dir.path, 'ai_comment_history_daily.json');
      final weeklyPath  = p.join(dir.path, 'ai_comment_history_weekly.json');
      final monthlyPath = p.join(dir.path, 'ai_comment_history_monthly.json');

      Future<void> _prune(String path) async {
        final f = File(path);
        if (!await f.exists()) return;
        final txt = await f.readAsString();
        if (txt.trim().isEmpty) return;
        final map = (jsonDecode(txt) as Map).map((k, v) => MapEntry(k.toString(), v));
        var changed = false;
        for (final d in ymds) {
          if (map.remove(d) != null) changed = true;
        }
        if (changed) {
          await f.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
          debugPrint('[AI] history pruned: $path -> removed ${ymds.length} day(s)');
        }
      }

      await _prune(dailyPath);
      await _prune(weeklyPath);
      await _prune(monthlyPath);
    } catch (e) {
      debugPrint('[AI] deleteHistoryForDates error: $e');
    }
  }
// === 追加：JSON POST（タイムアウト＋リトライ） ===
  static Future<http.Response> _postJsonWithRetry(
      String url,
      Map<String, dynamic> body, {
        int retries = 2,
        Duration timeout = const Duration(seconds: 12),
      }) async {
    http.Client? client;
    Object? lastError;
    StackTrace? lastStack;

    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        client = http.Client();
        final res = await client
            .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
            .timeout(timeout);
        return res;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        debugPrint('[AI] POST retry #$attempt failed: $e');
        if (attempt < retries) {
          // backoff: 400ms, 800ms...
          final backoff = Duration(milliseconds: 400 * (attempt + 1));
          await Future.delayed(backoff);
        }
      } finally {
        client?.close();
      }
    }
    // すべて失敗
    if (lastError != null) {
      debugPrint('[AI] POST failed after retries: $lastError');
      if (lastStack != null) debugPrintStack(stackTrace: lastStack);
    }
    // 疑似的に 599 を返す
    return http.Response('', 599);
  }
  /// ai_comment_log.csv に (date,type) で upsert 保存する軽量ヘルパ
  /// - 既存の同一 (date,type) 行があれば置き換え
  /// - なければ追加
  // === saveComment: 週次/月次キーを正規化してから保存（この定義を1つだけ残す） ===
  static Future<void> saveComment({
    required String date,   // 'yyyy/MM/dd'
    required String type,   // 'daily' | 'weekly' | 'monthly'
    required String text,
  }) async {
    // 型を小文字に正規化
    final t = _normType(type);

    // 'yyyy/MM/dd' を DateTime へ（スラッシュ・ハイフン両対応）
    DateTime _parseYmd(String s) {
      final ss = s.replaceAll('/', '-'); // 例: 2025/09/07 → 2025-09-07
      return DateTime.parse(ss);
    }

    // 週=その週の日曜キー、月=その月の月末キーに防御的に揃える
    String key = date.trim();
    try {
      final d = _parseYmd(date);
      if (t == 'weekly') {
        final sun = DateTime(d.year, d.month, d.day)
            .subtract(Duration(days: d.weekday % 7)); // Sun=0
        key =
        '${sun.year.toString().padLeft(4, '0')}/${sun.month.toString().padLeft(2, '0')}/${sun.day.toString().padLeft(2, '0')}';
      } else if (t == 'monthly') {
        final eom = DateTime(d.year, d.month + 1, 0);
        key =
        '${eom.year.toString().padLeft(4, '0')}/${eom.month.toString().padLeft(2, '0')}/${eom.day.toString().padLeft(2, '0')}';
      }
    } catch (_) {
      // パースできない場合は渡された date をそのまま使う
    }

    // 実際の保存（CsvLoader の仕様に合わせて comment キーへ書く）
    await CsvLoader.appendAiCommentLog(
      date: key,
      type: t,
      comment: text.trim(),
      // 追加カラムは空でOK（将来の分析列に合わせやすい）
      score: '',
      sleep: '',
      walk: '',
      gratitude1: '',
      gratitude2: '',
      gratitude3: '',
      memo: '',
    );

    debugPrint('[AI LOG] saved ($type) $date (${text.trim().length} chars)');

    // 保存直後にキャッシュ無効化（存在すれば呼ぶ／無ければ無害）
    try {
      _invalidateCaches();
    } catch (_) {}
  }

// === キャッシュ無効化フック（空実装でも可・プロジェクトに合わせて中身を追加） ===
  static void _invalidateCaches() {
    try {
      // 例) CsvLoader 側にキャッシュがある場合:
      // CsvLoader.invalidateAiCommentCaches();
    } catch (_) {
      // 何もしない
    }
  }




}
