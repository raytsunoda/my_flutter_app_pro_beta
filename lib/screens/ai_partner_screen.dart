import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

import '../services/ai_comment_service.dart';
//import '../utils/csv_loader.dart';
import '../utils/date_utils.dart';
import 'ai_comment_history_screen.dart';
//import 'package:my_flutter_app_pro/l10n/strings_ja.dart';
import 'package:my_flutter_app_pro/widgets/safety_notice.dart';
import 'dart:async';
import 'package:my_flutter_app_pro/utils/csv_loader.dart';
import 'package:my_flutter_app_pro/l10n/strings.dart';


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
    // ローカライズ文字列をどこからでも取れるようにする
//    S get s => S.of(context);
  // ---- State ----
  final DateFormat _f = DateFormat('yyyy/MM/dd');
 // String _todayStr = DateFormat('yyyy/MM/dd').format(DateTime.now());

  Map<String, String>? _todayRow; // 今日のCSV行（厳密一致）
  // 画面上部の「今日のひとことメモ」専用の表示用テキスト
  //String _memoText = s.memoNone;
  String _memoText = '';
  bool _memoLoaded = false; // ← 追加していない場合は必ず追加

  bool _memoLoadRequested = false; // ★追加：buildからの多重予約防止

  //late final String _todayStr;            // 'yyyy/MM/dd' 固定文字列
  //String aiResponse = s.thinking;
  String aiResponse = '';
  String? _weeklyMessage;
  String? _monthlyMessage;
  String _selectedRowDate = '';

  bool? _hasTodayDaily; // null=判定中 / true=保存済み / false=未保存
  bool _hasFetchedWeekly = false;
  bool _hasFetchedMonthly = false;

  bool _showWeekly = false;
  bool _showMonthly = false;

  bool _stringsInitialized = false;

  // 週次プレビュー（“月曜0:00解禁の直前日曜”のみ）
  Map<String, dynamic>? _weeklyPreview;
      // l10n（context依存）を安全に扱う
      late S _s;
      bool _sReady = false;
      S get s => _sReady ? _s : S(const Locale('en'));

      @override
      void didChangeDependencies() {
          super.didChangeDependencies();
          _s = S.of(context);
          _sReady = true;
          // 初期文言が空ならローカライズを適用
          if (_memoText.isEmpty) _memoText = s.memoNone;
          if (aiResponse.isEmpty) aiResponse = s.thinking;
        }




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
  // ❹ 表示直前の最終サニタイズ（BOM/ゼロ幅/連続句読点/「追伸：」など整形）
  String _sanitizeForDisplay(String? s) {
    var t = (s ?? '');

    // 制御文字・BOM・ゼロ幅
    t = t.replaceAll('\uFEFF', '').replaceAll('\u200B', '');

    // 連続した句読点を絞る（、、、、 → 、 / 。。。。 → 。 / …… → …）
    t = t.replaceAll(RegExp(r'、{2,}'), '、');
    t = t.replaceAll(RegExp(r'。{2,}'), '。');
    t = t.replaceAll(RegExp(r'…{2,}'), '…');

    // 「追伸：」の前後の余分な読点や空白を整理
    t = t.replaceAll(RegExp(r'追伸\s*[:：]\s*[、\s]*'), '追伸：');

    // 最後に全体の前後空白を除去
    return t.trim();
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


  // 今日のメモだけを**最優先**で State に反映
  // ※既存の _loadTodayMemoFirst() をこの実装で「丸ごと置換」してください。
  Future<void> _loadTodayMemoFirst() async {
    // // 重複呼び出しガード（ログで3回呼ばれていたため）
    // if (_memoLoaded) return;
    // 重複呼び出しガード：予約済み/実行済みなら何もしない
      if (_memoLoaded) return;
    try {
      final ymd = DateFormat('yyyy/MM/dd').format(DateTime.now());
      final row = await _findRowStrict(ymd);

      setState(() {
        _todayRow = row;
        final memo = row == null ? '' : _pickMemo(row);
        _memoText = memo.isNotEmpty ? memo : s.memoNone;
        _memoLoaded = true;
        _memoLoadRequested = false; // ★追加：成功後は解除（次回画面再生成でも安定）
      });

      debugPrint('[AI] _loadTodayMemoFirst: date=$ymd memo="${_memoText}"');
    } catch (e, st) {
      debugPrint('[AI] _loadTodayMemoFirst error: $e\n$st');
      setState(() {
        _memoText = s.memoNone;
        _memoLoaded = true;
        _memoLoadRequested = false; // ★追加：失敗時も解除
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

    // @override
    // void didChangeDependencies() {
    //     super.didChangeDependencies();
    //     if (_stringsInitialized) return;
    //     _stringsInitialized = true;
    //
    //     // フィールド初期化では context が使えないのでここで入れる
    //     if (_memoText.trim().isEmpty) _memoText = s.memoNone;
    //     if (aiResponse.trim().isEmpty) aiResponse = s.thinking;
    //   }


  Future<void> _fetchAiComment() async {
    final langCode = S.of(context).locale.languageCode; // ←追加
    // まずは「考え中です…」表示にする
    setState(() {
      aiResponse = s.thinking;
    });

    try {
      // 1) 今日の行を確実にロード
      if (_todayRow == null) {
        await _loadTodayMemoFirst();
      }
      setState(() {
        _selectedRowDate = _todayStr;
      });

      final row = _todayRow;
      // 2) その日になにも入力が無ければ AI コメントは出さない
      if (row == null || !_hasAnyInput(row)) {
        if (!mounted) return;
        setState(() {
          aiResponse = s.aiNone;
          _hasTodayDaily = false;
          _weeklyPreview = null;
        });
        return;
      }

      final now = DateTime.now();

      // 3) 日次・週次コメントをそれぞれ try/catch で安全に呼ぶ
      Map<String, dynamic>? daily;
      Map<String, dynamic>? weekly;

      try {
        daily = await AiCommentService.ensureDailySaved(now);
      } catch (e, st) {
        debugPrint('[AI] ensureDailySaved error: $e\n$st');
      }

      try {
        final visibleSunday = _visibleSunday(now);
        weekly = await AiCommentService.ensureWeeklySaved(visibleSunday);
      } catch (e, st) {
        debugPrint('[AI] ensureWeeklySaved error: $e\n$st');
      }

      if (!mounted) return;

      final dailyText = (daily?['comment'] as String?)?.trim() ?? '';

      // 4) コメントがあればそれを表示、なければタイムアウト/エラー用のメッセージ
      setState(() {
        aiResponse = dailyText.isNotEmpty
            ? dailyText
         //   : '⚠️ コメントの取得に時間がかかったか、うまく作れなかったようです。\n時間をおいてもう一度お試しください。';
      : '⚠️ ${s.isJa ? "コメントの取得に時間がかかったか、うまく作れなかったようです。\\n時間をおいてもう一度お試しください。" : "It took too long or couldn’t generate a comment. Please try again later."}';


        _weeklyPreview = weekly;
        _hasTodayDaily = dailyText.isNotEmpty;
      });
    } catch (e, st) {
      // どこかで予期せぬ例外が出ても必ず「考え中」を解除
      debugPrint('[AI] _fetchAiComment fatal: $e\n$st');
      if (!mounted) return;
      setState(() {
        aiResponse =
     //   '⚠️ コメントの取得中にエラーが発生しました。\n時間をおいてもう一度お試しください。';
      '⚠️ ${s.isJa ? "コメントの取得中にエラーが発生しました。\\n時間をおいてもう一度お試しください。" : "An error occurred while fetching the comment. Please try again later."}';


        _weeklyPreview = null;
      });
    }
  }


  // 週次のふりかえり（ボタン押下時）
  Future<void> _fetchWeeklyComment() async {
    final now = DateTime.now();

    // 対象週の最終日（日曜日）を求める
    final lastSunday = asYMD(now).subtract(
      Duration(days: (now.weekday % 7 == 0) ? 0 : now.weekday),
    );

    // コメント生成 or 既存コメント取得
    final r = await AiCommentService.ensureWeeklySaved(lastSunday);

    setState(() {
      final dateLabel = r['date'] ?? _fmt(lastSunday);
      final comment = (r['comment'] ?? '').toString().trim();

      _weeklyMessage = comment.isEmpty
          // ? '（対象週末日: $dateLabel）\n※この週のコメントは保存されていません。\n'
          // '週次コメントは必要なデータが保存されていれば「毎週日曜」に生成されます。'
          // : '（対象週末日: $dateLabel）\n$comment';
          ? '${s.weeklyTarget(dateLabel)}\n${s.isJa ? '※この週のコメントは保存されていません。\n週次コメントは必要なデータが保存されていれば「毎週日曜」に生成されます。' : 'No saved comment for this week.'}'
          : '${s.weeklyTarget(dateLabel)}\n$comment';

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
 //   final s = S.of(context);
    final s = this.s;
    // // 👇 初回だけ、描画直後に今日のメモを必ず読み込む
    // if (!_memoLoaded) {
    //   _memoLoaded = true;
    //   WidgetsBinding.instance.addPostFrameCallback((_) => _loadTodayMemoFirst());
    // }
// 👇 初回だけ、描画直後に今日のメモを必ず読み込む（フラグを先にtrueにしない）
    if (!_memoLoaded && !_memoLoadRequested) {
      _memoLoadRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadTodayMemoFirst());
    }

    final now = DateTime.now();
    final canGenerateWeekly = isWeeklyActionAllowed(now);   // 注記表示用
    final canGenerateMonthly = isMonthlyActionAllowed(now); // 注記表示用

    // 👇 画面表示用（空/未設定なら J.memoNone を出す）
    final String displayMemo = _memoText.trim().isEmpty ? s.memoNone : _memoText.trim();

    return Scaffold(
  //    appBar: AppBar(title: const Text('💛AIパートナー')),
      appBar: AppBar(title: Text(s.aiPartnerTitle)),

      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const SafetyNotice(),                   // ★ 注意喚起（先頭に1回だけ）
          const SizedBox(height: 12),
          // ✅ 今日のひとことメモ：_memoText だけを見る（CSV は一切触らない）
        //  _buildCommentBox('📝 今日のひとことメモ:\n$displayMemo'),
          _buildCommentBox('${s.todayMemoTitle}\n$displayMemo'),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: InkWell(
              onTap: () => _showFavoriteWordDialog(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F0FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_border, color: Colors.deepPurple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.saveFavoriteWord,
                        style: const TextStyle(
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          // ✅ AI パートナーのひとこと（表示時サニタイズを最終適用）
          //_buildCommentBox('💛 AIパートナーからのひとこと\n\n${_sanitizeForDisplay(aiResponse)}'),
          aiCard(
            s.aiPartnerCommentTitle,
            _sanitizeForDisplay(aiResponse),
          ),
          // ✅ タイムアウト時は、その場で再試行できるようにする（Releaseでも表示）
                  if (aiResponse.trim().startsWith('⚠️'))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                 child: TextButton.icon(
                   onPressed: () async {
                     debugPrint('[AI daily] retry tapped (force delete & retry)');

                     // ① 画面表示を「考え中」に戻す
                     if (!mounted) return;
                     setState(() {
                       aiResponse = s.thinking;
                     });

                     // ② 「その日付のdailyコメント」を強制削除（⚠️が保存済み扱いになってる事故を解除）
                     final now = DateTime.now();
                     await AiCommentService.forceDeleteDaily(now);

                     // ③ 取り直し
                     await _fetchAiComment();
                   },
                   icon: const Icon(Icons.refresh),
                //   label: const Text('もう一度試す'),
                   label: Text(s.retry),
                 ),
                ),




          // --- 週次プレビュー（公開済みの最新日曜のみ） ---
          if (_weeklyPreview != null) ...[
         //   _sectionDivider('AIコメント（週次プレビュー）'),
            _sectionDivider(s.weeklyPreviewSection),

            _buildCommentBox(
           //   '（対象週末日: ${_weeklyPreview!['date']}）\n'
              '${s.weeklyTarget((_weeklyPreview!['date'] ?? '').toString())}\n'

                  '${(_weeklyPreview!['comment'] ?? '').toString()}',
            ),
          ],

          const SizedBox(height: 4),
          _buildDailyActionRowForToday(),

          const SizedBox(height: 8),

          // --- 下部アクションエリア（週次／月次／履歴） ---
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune, size: 18),
                    const SizedBox(width: 6),
                    Text(
                  //    '操作メニュー',
                      s.menuTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 週次（毎週月曜のみ生成可）
                OutlinedButton.icon(
                  onPressed: isWeeklyActionAllowed(DateTime.now())
                      ? () async {
                    setState(() => _showWeekly = true);
                    await _fetchWeeklyComment();
                    if (!mounted) return;
                    setState(() {});
                  }
                      : null,
                  icon: const Icon(Icons.calendar_view_week),
               //   label: const Text('週次のふりかえり'),
                  label: Text(s.weeklyButton),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                if (!canGenerateWeekly)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                   //   '※ 週次：生成は毎週月曜10:00。今日は保存済みの内容のみ表示します。',
                      s.weeklyNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),

                const SizedBox(height: 10),

                // 月次（注記付きで常時閲覧可）
                OutlinedButton.icon(
                  onPressed: () async {
                    setState(() => _showMonthly = true);
                    await _loadMonthlyPreview();
                    if (!mounted) return;
                    setState(() {});
                  },
                  icon: const Icon(Icons.calendar_month),
                  //label: const Text('月次のふりかえり'),
                  label: Text(s.monthlyButton),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                if (!canGenerateMonthly)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                   //   '※ 月次：生成は毎月1日10:00。今日は保存済みの内容のみ表示します。',
                      s.monthlyNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),

                const SizedBox(height: 14),

                // 履歴（強調）
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AiCommentHistoryScreen()),
                    );
                  },
                  icon: const Icon(Icons.history),
                 // label: const Text('🗂 コメント履歴を見る'),
                  label: Text(s.historyButton),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // --- 既存の表示（週次／月次コメント） ---
          if (_showWeekly && _hasFetchedWeekly && _weeklyMessage != null) ...[
           // _sectionDivider('AIコメント（週次のふりかえり）'),
            _sectionDivider(s.weeklySection),
            aiCard(
              s.weeklySection,
              _weeklyMessage!,
            ),
          ],
          if (_showMonthly && _hasFetchedMonthly && _monthlyMessage != null) ...[
          //  _sectionDivider('AIコメント（月次のふりかえり）'),
            _sectionDivider(s.monthlySection),
            aiCard(
              s.monthlySection,
              _monthlyMessage!,
            ),
          ],

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
        //  'この日のAIコメントは保存済みです。再生成はできません。',
          s.dailyAlreadySaved,
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
       //   const SnackBar(content: Text('AIコメントを保存しました')),
          SnackBar(content: Text(s.savedSnack)),
        );
      },
      icon: const Icon(Icons.smart_toy),
     // label: const Text('AIコメントを生成して保存'),
      label: Text(s.debugGenerateAndSave),
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

  Future<void> _showFavoriteWordDialog(BuildContext context) async {
    final controller = TextEditingController();

    // 画面側の「表示対象日」を優先（_todayStr は既存変数）
    DateTime date = DateTime.now();
    try {
      final s = _todayStr; // yyyy/MM/dd 想定
      final parts = s.split('/');
      if (parts.length == 3) {
        date = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
    } catch (_) {}

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
        //  title: const Text('お気に入りのあなたの言葉'),
          title: Text(s.favoriteDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            //  const Text('（40文字以内）'),
              Text(s.favoriteLimit),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLength: 100,
                maxLines: 2,
               //  decoration: const InputDecoration(
               // //   hintText: '例：私は私のペースで大丈夫',
               //    hintText: null,
               //  ),
                decoration: InputDecoration(
                  hintText: s.favoriteHint,
                ),

              ),
              const SizedBox(height: 6),
              // const Text(
              //   '※ 今日のメモの中から、\n　残しておきたいあなたの言葉があれば書いてください',
              //   style: TextStyle(fontSize: 12),
              // ),
              Text(s.favoriteHelp, style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            // ✅ キャンセルは「×で閉じるだけ」
            IconButton(
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.close),
             // tooltip: '閉じる',
              tooltip: s.close,
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
            //  child: const Text('保存'),
              child: Text(s.save),
            ),
          ],
        );
      },
    );

    if (saved != true) return;

    final text = controller.text.trim();
    if (text.isEmpty) return;




    try {
      await CsvLoader.appendFavoriteWord(date: date, text: text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
      //  SnackBar(content: Text('⚠️ 保存に失敗しました: $e')),
        SnackBar(content: Text(s.favoriteSaveFailed('$e'))),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
    //  const SnackBar(content: Text('⭐ お気に入りに保存しました')),
      SnackBar(content: Text(s.favoriteSaved)),
    );
  }
}

Widget aiCard(String title, String text) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F7FB),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE0E0E0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}
