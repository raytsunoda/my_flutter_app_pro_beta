// lib/widgets/one_week_chart.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class OneWeekChart extends StatelessWidget {
  final List<List<dynamic>> csvData;
  const OneWeekChart({Key? key, required this.csvData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateTime.now();

    // "yyyy/MM/dd" -> その行 のマップを作る
    final Map<String, List<dynamic>> dataMap = {
      for (final row in csvData.skip(1))
        if (row.isNotEmpty && row[0] != null)
          row[0].toString().trim(): row,
    };

    // 1週間分の棒グループを作る
    List<BarChartGroupData> _buildWeekGroups(
        DateTime startDate,
        int columnIndex,
        double Function(String) parser,
        Color color,
        ) {
      final groups = <BarChartGroupData>[];
      for (int i = 0; i < 7; i++) {
        final d = startDate.add(Duration(days: i));
        final key = DateFormat('yyyy/MM/dd').format(d);
        final row = dataMap[key];
        if (row != null) {
          final v = parser(row[columnIndex].toString());
          groups.add(BarChartGroupData(
            x: i,
            barRods: [BarChartRodData(toY: v, width: 10, color: color)],
          ));
        } else {
          groups.add(BarChartGroupData(x: i, barRods: []));
        }
      }
      return groups;
    }

    Widget _section({
      required String title,
      required List<BarChartGroupData> groups,
      required double maxY,
      required DateTime startDate,
    }) {
      return Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                barGroups: groups,
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final date = startDate.add(Duration(days: v.toInt()));
                        final label = DateFormat('M/d').format(date);
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(label, style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    bottom: BorderSide(color: Colors.black, width: 1),
                    left: BorderSide.none,
                    top: BorderSide.none,
                    right: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('📊1週間グラフ')),
      body: PageView.builder(
        reverse: true, // 右スワイプで過去へ
        itemBuilder: (context, pageIndex) {
          final DateTime end = today.subtract(Duration(days: 7 * pageIndex));
          final DateTime start = end.subtract(const Duration(days: 6));
          final rangeText =
              "期間: ${DateFormat('yyyy/M/d').format(start)} ~ ${DateFormat('yyyy/M/d').format(end)}";

          final happiness = _buildWeekGroups(start, 1, (s) => double.tryParse(s) ?? 0, Colors.green);
          final sleep     = _buildWeekGroups(start, 4, (s) => double.tryParse(s) ?? 0, Colors.blue);
          final walk      = _buildWeekGroups(start, 3, (s) => double.tryParse(s) ?? 0, Colors.blue);
          final thanks    = _buildWeekGroups(start, 13, (s) => double.tryParse(s) ?? 0, Colors.blue);

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text("← スワイプで前後の1週間を表示できます →",
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                const SizedBox(height: 8),
                Text(rangeText, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 16),
                _section(title: "幸せ感レベル", groups: happiness, maxY: 100, startDate: start),
                _section(title: "睡眠の質",     groups: sleep,     maxY: 100, startDate: start),
                _section(title: "ウォーキング時間（分）", groups: walk, maxY: 100, startDate: start),
                _section(title: "感謝（件）",   groups: thanks,    maxY: 3,   startDate: start),
                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }
}
