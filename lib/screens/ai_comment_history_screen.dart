import 'package:flutter/material.dart';
import '../services/ai_comment_service.dart';

class AiCommentHistoryScreen extends StatefulWidget {
  final int initialTab;
  const AiCommentHistoryScreen({Key? key, this.initialTab = 0}) : super(key: key);

  @override
  State<AiCommentHistoryScreen> createState() => _AiCommentHistoryScreenState();
}

class _AiCommentHistoryScreenState extends State<AiCommentHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // サービス層の出力差異に耐えるため dynamic で統一
  List<Map<String, dynamic>> _daily = [];
  List<Map<String, dynamic>> _weekly = [];
  List<Map<String, dynamic>> _monthly = [];

  bool _isLoading = false;
  bool _routeApplied = false; // pushNamed の arguments を一度だけ適用

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _reloadAllFromLog(); // ← 初期表示時に必ず最新を取得
  }

  /// pushNamed の arguments（int / String / Map）からタブIndexを解釈
  int _parseIndexFromArgs(Object? args) {
    if (args == null) return -1;
    if (args is int) return (args >= 0 && args <= 2) ? args : -1;

    if (args is String) {
      final s = args.toLowerCase();
      if (s.startsWith('week')) return 1;
      if (s.startsWith('month')) return 2;
      if (s == '0' || s.startsWith('day') || s == 'daily' || s.contains('日次')) return 0;
      final n = int.tryParse(s);
      if (n != null && n >= 0 && n <= 2) return n;
      return -1;
    }

    if (args is Map) {
      final v = args['tab'] ?? args['initialTab'] ?? args['index'];
      return _parseIndexFromArgs(v);
    }
    return -1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // pushNamed の arguments を一度だけ適用
    final args = ModalRoute.of(context)?.settings.arguments;
    final idx = _parseIndexFromArgs(args);
    if (!_routeApplied && idx != -1 && _tab.index != idx) {
      _routeApplied = true;
      _tab.animateTo(idx);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _reloadAllFromLog() async {
    setState(() => _isLoading = true);

    // 日次・月次は従来通りの厳密ローダ
    final daily   = await AiCommentService.loadDailyHistoryStrict();
    final monthly = await AiCommentService.loadMonthlyHistoryStrict();

    // 週次は「空の週も含めて」取得
    final wkAll = await AiCommentService.loadWeeklyHistoryWithEmptySundays();

    // カットオフ: 直近（当日を含む）の日曜日までだけ表示
    DateTime _prevOrSameSunday(DateTime d) {
      final back = d.weekday % 7; // Sun=0, Mon=1...
      final localMidnight = DateTime(d.year, d.month, d.day);
      return localMidnight.subtract(Duration(days: back));
    }
    final cutoff = _prevOrSameSunday(DateTime.now());

    DateTime? _parseYmd(String ymd) {
      final p = ymd.split('/');
      if (p.length != 3) return null;
      final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
      if (y == null || m == null || d == null) return null;
      return DateTime(y, m, d);
    }

    // 未来は除外して、日付降順に整列
    final weekly = wkAll.where((r) {
      final dt = _parseYmd((r['date'] ?? '').toString());
      return dt != null && !dt.isAfter(cutoff);
    }).toList()
      ..sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));

    if (!mounted) return;
    setState(() {
      _daily   = daily;
      _weekly  = weekly.map((e) => Map<String, dynamic>.from(e)).toList();
      _monthly = monthly;
      _isLoading = false;
    });

    // デバッグ概要
    debugPrint('[history] daily=${_daily.length}, weekly=${_weekly.length}, monthly=${_monthly.length}');
  }


  Future<void> _backfillCurrentTab() async {
    final labels = ['日次', '週次', '月次'];
    final idx = _tab.index;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${labels[idx]}の欠け分を補完'),
        content: const Text('不足しているAIコメントを一括生成します（APIコストあり）。続行しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('実行する')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _isLoading = true);
    int added = 0;
    if (idx == 0) {
      added = await AiCommentService.backfillDailyMissing();
    } else if (idx == 1) {
      added = await AiCommentService.backfillWeeklyMissing();
    } else {
      added = await AiCommentService.backfillMonthlyMissing();
    }

    await _reloadAllFromLog();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${labels[idx]}コメントを $added 件補完しました')),
    );
  }

  Widget _card({
    required String kind,
    required dynamic date,
    required dynamic body,
    String emptyMessage = 'コメントが保存されていません',
  }) {
    final subtitle = (date ?? '').toString().trim();
    final text = (body ?? '').toString().trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(blurRadius: 6, spreadRadius: 2, color: Color(0x11000000))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kind, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(text.isNotEmpty ? text : emptyMessage, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _tabHeaderButtons() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Row(
      children: [
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _reloadAllFromLog,
          icon: const Icon(Icons.refresh),
          label: const Text('最新データを再読込'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _backfillCurrentTab,
          icon: const Icon(Icons.construction),
          label: const Text('欠け分を補完'),
        ),
      ],
    ),
  );

  Widget _dailyTab() => Column(
    children: [
      _tabHeaderButtons(),
      Expanded(
        child: _daily.isEmpty
            ? const Center(child: Text('コメントが保存されていません'))
            : ListView.builder(
          itemCount: _daily.length,
          itemBuilder: (_, i) {
            final r = _daily[i];
            return _card(kind: '日次', date: r['date'], body: r['comment']);
          },
        ),
      ),
    ],
  );

  Widget _weeklyTab() => Column(
    children: [
      _tabHeaderButtons(),
      Expanded(
        child: _weekly.isEmpty
            ? const Center(child: Text('この週のコメントは保存されていません'))
            : ListView.builder(
          itemCount: _weekly.length,
          itemBuilder: (_, i) {
            final r = _weekly[i];
            return _card(kind: '週次', date: r['date'], body: r['comment'],
                emptyMessage: 'この週のコメントは保存されていません');
          },
        ),
      ),
    ],
  );

  Widget _monthlyTab() => Column(
    children: [
      _tabHeaderButtons(),
      Expanded(
        child: _monthly.isEmpty
            ? const Center(child: Text('この月のコメントは保存されていません'))
            : ListView.builder(
          itemCount: _monthly.length,
          itemBuilder: (_, i) {
            final r = _monthly[i];
            return _card(kind: '月次', date: r['date'], body: r['comment'],
                emptyMessage: 'この月のコメントは保存されていません');
          },
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AIコメント履歴'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: '日次'), Tab(text: '週次'), Tab(text: '月次')],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tab,
        children: [
          _dailyTab(),
          _weeklyTab(),
          _monthlyTab(),
        ],
      ),
    );
  }
}
