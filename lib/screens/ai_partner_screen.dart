import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/ai_comment_service.dart';
import '../utils/csv_loader.dart';
import '../utils/date_utils.dart';
import 'ai_comment_history_screen.dart';
import 'package:my_flutter_app_pro/l10n/strings_ja.dart';
import 'package:my_flutter_app_pro/widgets/safety_notice.dart';


DateTime _computePrevMonthEnd(DateTime latestDate) {
  final prevMonth = (latestDate.month == 1)
      ? DateTime(latestDate.year - 1, 12, 1)
      : DateTime(latestDate.year, latestDate.month - 1, 1);
  return DateTime(prevMonth.year, prevMonth.month + 1, 0);
}

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

DateTime _parseYmd(String s) => DateFormat('yyyy/MM/dd').parseStrict(s);

// 余分な空白/全角空白/BOM を除去して小文字化
String _normKey(String s) => s
    .replaceAll('\ufeff', '')                // BOM
    .replaceAll(RegExp(r'[\s\u3000]'), '')   // 半角/全角スペース等
    .toLowerCase();

// 行から候補キーにマッチする値を取得（キーは正規化して比較）
String? _getByKeys(Map<String, String> row, List<String> candidates) {
  for (final k in row.keys) {
    final nk = _normKey(k);
    for (final c in candidates) {
      final nc = _normKey(c);
      if (nk == nc || nk.contains(nc)) {
        final v = (row[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
    }
  }
  return null;
}





class AIPartnerScreen extends StatefulWidget {
  const AIPartnerScreen({super.key});
  @override
  State<AIPartnerScreen> createState() => _AIPartnerScreenState();
}

class _AIPartnerScreenState extends State<AIPartnerScreen> {
  // ---- State ----
  final DateFormat _f = DateFormat('yyyy/MM/dd');
 // String _todayStr = DateFormat('yyyy/MM/dd').format(DateTime.now());

  Map<String, String>? _todayRow; // 今日のCSV行（厳密一致）
  // 画面上部の「今日のひとことメモ」専用の表示用テキスト
  String _memoText = J.memoNone;
  bool _memoLoaded = false; // ← 追加していない場合は必ず追加
  //late final String _todayStr;            // 'yyyy/MM/dd' 固定文字列
  String aiResponse = J.thinking;
  String? _weeklyMessage;
  String? _monthlyMessage;
  String _selectedRowDate = '';

  bool? _hasTodayDaily; // null=判定中 / true=保存済み / false=未保存
  bool _hasFetchedWeekly = false;
  bool _hasFetchedMonthly = false;

  bool _showWeekly = false;
  bool _showMonthly = false;

  // 週次プレビュー（“月曜0:00解禁の直前日曜”のみ）
  Map<String, dynamic>? _weeklyPreview;

  // ---- helpers ----
  String _sanitize(String? v) => (v ?? '').replaceAll('\u3000', ' ').trim();

  // ❶ 文字列の掃除（BOM・全角空白なども除去）
  String _clean(String? s) {
    if (s == null) return '';
    return s
        .replaceAll('\uFEFF', '')     // BOM
        .replaceAll('\u200B', '')     // ゼロ幅
        .replaceAll(RegExp(r'^[\s\u3000]+|[\s\u3000]+$'), '') // 前後の半角/全角空白
        .trim();
  }

// ❷ 当日を yyyy/MM/dd で
  String get _todayStr => DateFormat('yyyy/MM/dd').format(DateTime.now());

  // ❸ 列名ゆらぎ対応で「メモ列」を拾う
  String _pickMemo(Map<String, String> row) {
    final v = _getByKeys(row, [
      'memo', 'メモ', '今日のひとことメモ', '今日のひとこととメモ', 'todayMemo', '今日のメモ'
    ]);
    debugPrint('[AI] _pickMemo -> "${v ?? ''}" (keys=${row.keys.join(', ')})');
    return v ?? '';
  }


// ❹ 日付列ゆらぎも吸収して「その日」を厳密一致で探す
  Map<String, String>? _findRowForDate(List<Map<String, String>> csv, DateTime d) {
    final target = _todayStr; // ここでは当日を探す
    for (final r in csv) {
      final dateStr = _clean(r['日付'] ?? r['date']);
      if (dateStr == target) return r;
    }
    return null;
  }

  // CSVから今日の行を厳密一致で取得（引数は日付だけ）
  // ===== ai_partner_screen.dart: 置換版 _findRowStrict 開始 =====
  Future<Map<String, String>?> _findRowStrict(String ymd) async {
    String norm(String s) {
      final t = s.trim().replaceAll('-', '/');
      final p = t.split('/');
      if (p.length != 3) return s.trim();
      return '${p[0].padLeft(4, '0')}/${p[1].padLeft(2, '0')}/${p[2].padLeft(2, '0')}';
    }

    final key = norm(ymd);
    final rows = await CsvLoader.loadCsv('HappinessLevelDB1_v2.csv');
    for (final r in rows) {
      final raw = (r['日付'] ?? r['date'] ?? '').toString();
      if (norm(raw) == key) {
        debugPrint('[AI] _findRowStrict hit: date=$key keys=${r.keys.toList()}');
        return r;
      }
    }
    debugPrint('[AI] _findRowStrict miss for $key');
    return null;
  }
// ===== ai_partner_screen.dart: 置換版 _findRowStrict 終了 =====

/*
  Future<void> _loadTodayMemo() async {
    try {
      final ymd = DateFormat('yyyy/MM/dd').format(DateTime.now());
      final rows = await CsvLoader.loadCsv('HappinessLevelDB1_v2.csv');

      Map<String, String>? todayRow;
      for (final r in rows) {
        if ((r['日付'] ?? '').trim() == ymd) {
          todayRow = r;
          break;
        }
      }

      // ヘッダの揺れに強く（memo / メモ / 今日のひとことメモ）
      final memo = (todayRow?['memo'] ??
          todayRow?['メモ'] ??
          todayRow?['今日のひとことメモ'] ??
          '')
          .toString()
          .trim();

      setState(() {
        _memoText = memo.isNotEmpty ? memo : J.memoNone;
      });

      debugPrint('[AI] _loadTodayMemo: date=$ymd memo="${_memoText}"');
    } catch (e, st) {
      debugPrint('[AI] _loadTodayMemo error: $e\n$st');
      // 失敗しても画面は出したいので既定文にしておく
      setState(() => _memoText = J.memoNone);
    }
  }
*/





  // 今日のメモだけを**最優先**で State に反映
  // ※既存の _loadTodayMemoFirst() をこの実装で「丸ごと置換」してください。
  Future<void> _loadTodayMemoFirst() async {
    // 重複呼び出しガード（ログで3回呼ばれていたため）
    if (_memoLoaded) return;
    try {
      final ymd = DateFormat('yyyy/MM/dd').format(DateTime.now());
      final row = await _findRowStrict(ymd);

      setState(() {
        _todayRow = row;
        final memo = row == null ? '' : _pickMemo(row);
        _memoText = memo.isNotEmpty ? memo : J.memoNone;
        _memoLoaded = true;
      });

      debugPrint('[AI] _loadTodayMemoFirst: date=$ymd memo="${_memoText}"');
    } catch (e, st) {
      debugPrint('[AI] _loadTodayMemoFirst error: $e\n$st');
      setState(() {
        _memoText = J.memoNone;
        _memoLoaded = true;
      });
    }
  }



  bool _hasAnyInput(Map<String, String> row) {
    String s(String? v) => (v ?? '').trim();
    double n(String? v) => double.tryParse((v ?? '').toString()) ?? 0;

    return s(row['memo']).isNotEmpty ||
        s(row['感謝1']).isNotEmpty ||
        s(row['感謝2']).isNotEmpty ||
        s(row['感謝3']).isNotEmpty ||
        n(row['睡眠の質']) > 0 ||
        n(row['ストレッチ時間']) > 0 ||
        n(row['ウォーキング時間']) > 0;
  }

  bool isWeeklyActionAllowed(DateTime now) {
    // 週次は“毎週月曜”に生成可（UIの有効/無効に使用）
    return now.weekday == DateTime.monday;
  }

  bool isMonthlyActionAllowed(DateTime now) {
    // 月次：1日10:00以降を生成可とみなす（UIの注記用）
    final gate = DateTime(now.year, now.month, 1, 10);
    return (now.year == gate.year && now.month == gate.month && now.day == 1);
  }

  Future<void> _refreshHasDaily() async {
    final v = await AiCommentService.hasDailyForDate(DateTime.now());
    if (!mounted) return;
    setState(() => _hasTodayDaily = v);
  }

  // “週次プレビュー”として見せる基準日（日曜は1週前を返す → 当日(日)は解禁前なので見せない）
  DateTime _visibleSunday(DateTime now) {
    final base = DateTime(now.year, now.month, now.day);
    final wd = base.weekday % 7; // Sun=0
    final delta = (wd == 0) ? 7 : wd; // 日曜=7日戻す / それ以外=直近日曜まで戻す
    return base.subtract(Duration(days: delta));
  }

  double _d(dynamic v) {
    if (v == null) return 0;
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    return double.tryParse(s) ?? 0;
  }

  @override
  void initState() {
    super.initState();

    // 1) まずメモを確定
    _loadTodayMemoFirst();


    // 3) AIコメントの取得（この中で _memoText を絶対に setState しないこと）
    _fetchAiComment(); // ← 既存呼び出しのままでOK（ただし後述の修正を反映）
  }


  Future<void> _fetchAiComment() async {
    setState(() => aiResponse = J.thinking);

    // 1) メモを必ず先に（initState から呼ばれても念のため）
    if (_todayRow == null) {
      await _loadTodayMemoFirst();
    }
    setState(() => _selectedRowDate = _todayStr);

    final row = _todayRow;

    // 2) 当日入力が無ければ AI文は出さない
    if (row == null || !_hasAnyInput(row)) {
      setState(() {
        aiResponse = J.aiNone;
        _hasTodayDaily = false;
      });
      return;
    }

    // 3) デイリー（保存済み優先 → 無ければ生成＆保存）
    final now = DateTime.now();
    final daily = await AiCommentService.ensureDailySaved(now);
    final dailyText = (daily?['comment'] as String?)?.trim() ?? '';

    // 4) 週次プレビュー（“月曜0:00解禁”の直前日曜のみ）
    final visibleSunday = _visibleSunday(now);
    final weekly = await AiCommentService.ensureWeeklySaved(visibleSunday);

    setState(() {
      aiResponse = dailyText.isNotEmpty ? dailyText : '🤖 コメントが保存されていません';
      _weeklyPreview = weekly;
      _hasTodayDaily = true;
    });
  }

  // 週次のふりかえり（ボタン押下時）
  Future<void> _fetchWeeklyComment() async {
    final now = DateTime.now();
    final lastSunday = asYMD(now).subtract(
      Duration(days: (now.weekday % 7 == 0) ? 7 : now.weekday % 7),
    );
    final r = await AiCommentService.ensureWeeklySaved(lastSunday);
    setState(() {
      final dateLabel = r['date'] ?? _fmt(lastSunday);
      final comment = (r['comment'] ?? '').toString().trim();
      _weeklyMessage = comment.isEmpty
          ? '（対象週末日: $dateLabel）\n※この週のコメントは保存されていません。\n'
          '週次コメントは必要なデータが保存されていれば「毎週月曜」に生成されます。'
          : '（対象週末日: $dateLabel）\n$comment';
      _hasFetchedWeekly = true;
    });
  }

  // 月次：保存済みの先月末を読む（無ければ案内）
  Future<void> _loadMonthlyPreview() async {
    setState(() {
      _hasFetchedMonthly = false;
      _monthlyMessage = null;
    });

    final rec = await AiCommentService.findLastMonthEomRecord();
    if (!mounted) return;

    if (rec != null) {
      final ymd = (rec['date'] ?? '').toString();
      final body = (rec['comment'] ?? '').toString();
      setState(() {
        _monthlyMessage = '（対象月末日: $ymd）\n$body';
        _hasFetchedMonthly = true;
      });
    } else {
      setState(() {
        _monthlyMessage = '（対象月末日: 先月末）\n※まだ保存済みの月次コメントがありません。';
        _hasFetchedMonthly = true;
      });
    }
  }
/*
  Future<void> _fetchMonthlyComment() async {
    // ① メインCSVの“最新入力日”を厳密取得
    final mainCsv = await CsvLoader.loadCsv('HappinessLevelDB1_v2.csv');
    DateTime latest = DateTime.now();
    for (final r in mainCsv) {
      final ds = (r['日付'] ?? '').trim();
      if (ds.isEmpty) continue;
      try {
        final d = _parseYmd(ds);
        if (d.isAfter(latest)) latest = d;
      } catch (_) {}
    }

    // ② 前月末で作成/再利用（サービス側で保存済み優先）
    final r = await AiCommentService.ensureMonthlySaved(latest);

    // ③ ラベルは“前月末”固定
    final targetMonthlyDate = _computePrevMonthEnd(latest);
    final targetLabel = _fmt(targetMonthlyDate);

    setState(() {
      final body = (r['comment'] ?? '').toString().trim();
      _monthlyMessage = body.isEmpty
          ? '（対象月末日: $targetLabel）\n※先月の実データが無いか、まだ保存済みの月次コメントがありません。'
          : '（対象月末日: $targetLabel）\n$body';
      _hasFetchedMonthly = true;
    });
  }
*/
  // ---- UI ----
  Widget _buildCommentBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14),
        softWrap: true,
        overflow: TextOverflow.visible,
        maxLines: null,
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    // 👇 初回だけ、描画直後に今日のメモを必ず読み込む
    if (!_memoLoaded) {
      _memoLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadTodayMemoFirst());
    }

    final now = DateTime.now();
    final canGenerateWeekly = isWeeklyActionAllowed(now);   // 注記表示用
    final canGenerateMonthly = isMonthlyActionAllowed(now); // 注記表示用

    // 👇 画面表示用（空/未設定なら J.memoNone を出す）
    final String displayMemo = _memoText.trim().isEmpty ? J.memoNone : _memoText.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('💛AIパートナー')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const SafetyNotice(),                   // ★ 注意喚起（先頭に1回だけ）
          const SizedBox(height: 12),
          // ✅ 今日のひとことメモ：_memoText だけを見る（CSV は一切触らない）
          _buildCommentBox('📝 今日のひとことメモ:\n$displayMemo'),

          // ✅ AI パートナーのひとこと（そのまま）
          _buildCommentBox('💛 AIパートナーからのひとこと\n\n$aiResponse'),

          // --- 週次プレビュー（公開済みの最新日曜のみ） ---
          if (_weeklyPreview != null) ...[
            _sectionDivider('AIコメント（週次プレビュー）'),
            _buildCommentBox(
              '（対象週末日: ${_weeklyPreview!['date']}）\n'
                  '${(_weeklyPreview!['comment'] ?? '').toString()}',
            ),
          ],

          const SizedBox(height: 8),
          _buildDailyActionRowForToday(),

          const SizedBox(height: 12),
          Row(
            children: [
              // 週次（毎週月曜のみ生成可）
              Expanded(
                child: ElevatedButton(
                  onPressed: isWeeklyActionAllowed(DateTime.now())
                      ? () async {
                    setState(() => _showWeekly = true);
                    await _fetchWeeklyComment();
                    if (!mounted) return;
                    setState(() {});
                  }
                      : null,
                  child: const Text('週次のふりかえり'),
                ),
              ),
              const SizedBox(width: 8),
              // 月次（注記付きで常時閲覧可）
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    setState(() => _showMonthly = true);
                    await _loadMonthlyPreview();
                    if (!mounted) return;
                    setState(() {});
                  },
                  child: const Text('月次のふりかえり'),
                ),
              ),
            ],
          ),

          if (!canGenerateWeekly)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '※ 週次：生成は毎週月曜10:00。今日は保存済みの内容のみ表示します。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (!canGenerateMonthly)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '※ 月次：生成は毎月1日10:00。今日は保存済みの内容のみ表示します。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

          if (_showWeekly && _hasFetchedWeekly && _weeklyMessage != null) ...[
            _sectionDivider('AIコメント（週次のふりかえり）'),
            _buildCommentBox(_weeklyMessage!),
          ],
          if (_showMonthly && _hasFetchedMonthly && _monthlyMessage != null) ...[
            _sectionDivider('AIコメント（月次のふりかえり）'),
            _buildCommentBox(_monthlyMessage!),
          ],

          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiCommentHistoryScreen()),
              );
            },
            icon: const Icon(Icons.history),
            label: const Text('🗂 コメント履歴を見る'),
          ),
        ],
      ),
    );
  }




  Widget _buildDailyActionRowForToday() {
    final today = DateTime.now();

    if (_hasTodayDaily == null) {
      return const SizedBox.shrink();
    }

    if (_hasTodayDaily!) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'この日のAIコメントは保存済みです。再生成はできません。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    if (!kDebugMode) return const SizedBox.shrink();
    return FilledButton.icon(
      onPressed: () async {
        await AiCommentService.ensureDailySavedForDate(today);
        await _refreshHasDaily();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AIコメントを保存しました')),
        );
      },
      icon: const Icon(Icons.smart_toy),
      label: const Text('AIコメントを生成して保存'),
    );
  }

  Widget _sectionDivider(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(
        children: [
          const Expanded(child: Divider(thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(text, style: Theme.of(context).textTheme.labelLarge),
          ),
          const Expanded(child: Divider(thickness: 1)),
        ],
      ),
    );
  }
}
