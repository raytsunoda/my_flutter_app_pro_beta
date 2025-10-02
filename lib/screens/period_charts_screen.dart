// lib/screens/period_charts_screen.dart
// ASCII only / safe version

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for HapticFeedback



enum PeriodKind { week, fourWeeks, year }

class PeriodChartsScreen extends StatefulWidget {
  const PeriodChartsScreen({
    super.key,
    required this.csvData,
    required this.period,
    this.title,
  });

  // CSV: List<Map<String,String>> header-applied
  final List<Map<String, String>> csvData;
  final PeriodKind period;
  final String? title;

  @override
  State<PeriodChartsScreen> createState() => _PeriodChartsScreenState();
}

class _PeriodChartsScreenState extends State<PeriodChartsScreen> with SingleTickerProviderStateMixin {

  int _animDir = 0; // -1: past(from left), +1: future(from right), 0: none
// 追加フィールド
  late final AnimationController _chevCtrl;
  late final Animation<double> _chevAnim;



  String _yyyyMMdd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, "0")}/${d.day.toString().padLeft(2, "0")}';

  late DateTime _end;         // inclusive right edge
  double _dragX = 0;          // accumulated horizontal drag
  late final DateTime _today; // today 00:00

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _end = _today; // latest page
    // initState内の末尾あたりに追加
    _chevCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _chevAnim = CurvedAnimation(parent: _chevCtrl, curve: Curves.easeInOut);

  }
// disposeを追加
  @override
  void dispose() {
    _chevCtrl.dispose();
    super.dispose();
  }


  // number of days for current period
  int get _days {
    switch (widget.period) {
      case PeriodKind.week:
        return 7;
      case PeriodKind.fourWeeks:
        return 28;
      case PeriodKind.year:
        return 365;
    }
  }

  // start date of current page (inclusive)
  DateTime get _start => _end.subtract(Duration(days: _days - 1));

  // list of days shown in x axis (left to right)
  List<DateTime> _visibleDays() =>
      List.generate(_days, (i) => _start.add(Duration(days: i)));

  // first date in CSV (for clamping)
  DateTime? _csvFirstDate() {
    DateTime? first;
    for (final r in widget.csvData) {
      final s = (r['日付'] ?? r['date'] ?? '').trim();
      if (s.isEmpty) continue;
      final p = s.split('/');
      if (p.length != 3) continue;
      final y = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      final d = int.tryParse(p[2]);
      if (y == null || m == null || d == null) continue;
      final dt = DateTime(y, m, d);
      final f = first;
      if (f == null || dt.isBefore(f)) {
        first = dt;
      }
    }
    return first;
  }

  // 置換後（1年未満でも2ページ間で動ける版）
  DateTime _clampEnd(DateTime e) {
    final maxEnd = _today;                  // 今日を上限
    final first = _csvFirstDate() ?? maxEnd;
    final minEnd = first;                   // ★ 下限を「最古日」に変更

    if (e.isBefore(minEnd)) return minEnd;  // 最古日より左（過去）へ行かない
    if (e.isAfter(maxEnd)) return maxEnd;   // 未来へ行かない
    return e;
  }






  // shift page by +/- one page
  void _shiftByOnePage(int dir) {
    final next = _clampEnd(_end.add(Duration(days: dir * _days)));
    final changed = next != _end;
    setState(() {
      _animDir = dir;
      _end = next;
    });
    if (changed) HapticFeedback.lightImpact(); // 軽いカチッ
  }


  Map<String, String>? _rowAt(DateTime d) {
    final key = _yyyyMMdd(d);
    return widget.csvData.firstWhere(
          (r) => (r['日付'] ?? r['date'] ?? '').trim() == key,
      orElse: () => <String, String>{},
    );
  }

  double? _v(Map<String, String>? row, List<String> keys) {
    if (row == null || row.isEmpty) return null;
    for (final k in keys) {
      final s = row[k];
      if (s != null && s.trim().isNotEmpty) {
        final n = double.tryParse(s.trim());
        if (n != null) return n;
      }
    }
    return null;
  }

  List<BarChartGroupData> _makeBarGroups({
    required List<DateTime> days,
    required List<List<String>> columnsPerChart,
    required int chartIndex,
  }) {
    final List<BarChartGroupData> groups = [];
    for (int i = 0; i < days.length; i++) {
      final row = _rowAt(days[i]);
      final value = _v(row, columnsPerChart[chartIndex]);
      final isBlank = value == null;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: (value ?? 0).toDouble(),
              width: 5,
              borderRadius: BorderRadius.circular(2),
              color: _barColor(chartIndex, isBlank),
            ),
          ],
        ),
      );
    }
    return groups;
  }

  Color _barColor(int chartIndex, bool blank) {
    if (blank) return Colors.transparent;
    if (chartIndex == 0) return Colors.blue; // main score
    return Colors.teal;
  }

  Widget _chart({required String title, required int chartIndex}) {
    final visibleDays = _visibleDays();

    final groups = _makeBarGroups(
      days: visibleDays,
      columnsPerChart: const [
        ['幸せ感レベル'],                 // 0
        ['睡眠の質'],                   // 1
        ['ウォーキング時間', 'ウォーキング時間（分）'], // 2
        ['感謝数'],                      // 3
      ],
      chartIndex: chartIndex,
    );

    double _yMaxOfLocal(int idx) {
      switch (idx) {
        case 0:
        case 1:
          return 100;
        case 2:
          return 90; // walking limit
        case 3:
          return 3;  // thanks limit
        default:
          return 100;
      }
    }

    String _mmddLocal(DateTime d) => '${d.month}/${d.day}';

    String _labelForIndex(int idx) {
      final days = visibleDays;
      if (idx < 0 || idx >= days.length) return '';
      final d = days[idx];

      if (widget.period == PeriodKind.week) {
        return _mmddLocal(d);
      } else if (widget.period == PeriodKind.fourWeeks) {
        final last = days.length - 1;
        if (idx == 0 || idx == 7 || idx == last || idx == last - 7 || idx == last - 14) {
          return _mmddLocal(d);
        }
        return '';
      } else {
        // year
        return (d.day == 1) ? _mmddLocal(d) : '';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Text(
              title,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
            ),
          ),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: _yMaxOfLocal(chartIndex),
                barGroups: groups,
                barTouchData: BarTouchData(enabled: false),
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: (chartIndex <= 1) ? 25 : (chartIndex == 2 ? 30 : 1),
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          value.toInt().toString(),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        final text = _labelForIndex(idx);
                        if (text.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(text, style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade400, width: 1),
                    left: BorderSide.none,
                    right: BorderSide.none,
                    top: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
// スワイプ案内文
  String _swipeHint() {
    switch (widget.period) {
      case PeriodKind.week:
        return '左右にスワイプで、前後の週を表示';
      case PeriodKind.fourWeeks:
        return '左右にスワイプで、前後の4週を表示';
      case PeriodKind.year:
        return '左右にスワイプで、前後の1年を表示';
    }
  }

  Widget _header() {
    final start = _start;
    final end = _end;
    final periodText = '期間: ${_yyyyMMdd(start)} - ${_yyyyMMdd(end)}';
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 50) return;
        final dir = (v > 0) ? -1 : 1; // 右フリック=過去, 左=未来
        final next = _clampEnd(_end.add(Duration(days: dir * _days)));
        final changed = next != _end;
        setState(() {
          _animDir = dir;
          _end = next;
        });
        if (changed) HapticFeedback.lightImpact();
      },


      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Text(
          periodText,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _hintBar() {
    final text = _swipeHint();
    final iconColor = Colors.grey.shade600;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SlideTransition(
            position: Tween<Offset>(begin: const Offset(-0.12, 0), end: Offset.zero)
                .animate(_chevAnim),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_chevAnim),
              child: Icon(Icons.chevron_left, size: 18, color: iconColor),
            ),
          ),
          const SizedBox(width: 6),
          Text(text, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: iconColor)),
          const SizedBox(width: 6),
          SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero)
                .animate(_chevAnim),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_chevAnim),
              child: Icon(Icons.chevron_right, size: 18, color: iconColor),
            ),
          ),
        ],
      ),
    );
  }




  @override
  Widget build(BuildContext context) {
    final titleText = widget.title ??
        ({
          PeriodKind.week: '1週間グラフ',
          PeriodKind.fourWeeks: '4週間グラフ',
          PeriodKind.year: '1年グラフ',
        }[widget.period] ?? 'グラフ');

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText, style: const TextStyle(fontSize: 16)),
        centerTitle: true,


          actions: const []





      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) {
              final dx = _animDir == 0 ? 0.0 : (_animDir > 0 ? 1.0 : -1.0);
              return SlideTransition(
                position: Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
            child: KeyedSubtree(
              key: ValueKey('${_start.toIso8601String()}_${_end.toIso8601String()}'),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  //
                  _hintBar(),

                  _header(),
                  const SizedBox(height: 4),
                  _chart(title: '幸せ感レベル', chartIndex: 0),
                  _chart(title: '睡眠の質', chartIndex: 1),
                  _chart(title: 'ウォーキング時間(分)', chartIndex: 2),
                  _chart(title: '感謝(件)', chartIndex: 3),
                ],
              ),
            ),
          ),

          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) => _dragX += d.delta.dx,
              onHorizontalDragEnd: (_) {
                const threshold = 96;
                if (_dragX.abs() > threshold) {
                  _shiftByOnePage(_dragX < 0 ? 1 : -1);
                }
                _dragX = 0;
              },
            ),
          ),
        ],
      ),
    );
  }
}
