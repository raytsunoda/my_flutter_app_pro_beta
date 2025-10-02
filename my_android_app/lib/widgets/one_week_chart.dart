import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class OneWeekChart extends StatelessWidget {
  final List<List<dynamic>> csvData;

  OneWeekChart({required this.csvData});

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateTime.now();

    final Map<String, List<dynamic>> dataMap = {
      for (var row in csvData.skip(1))
        if (row.isNotEmpty && row[0] != null)
          row[0].toString().trim(): row,
    };

    Widget buildChartSection(String title, DateTime startDate, int columnIndex, Color color, double maxY) {
      List<BarChartGroupData> groups = [];

      for (int i = 0; i < 7; i++) {
        final currentDate = startDate.add(Duration(days: i));
        final dateKey = DateFormat('yyyy/MM/dd').format(currentDate);
        final row = dataMap[dateKey];

        if (row != null) {
          final value = double.tryParse(row[columnIndex].toString()) ?? 0;
          groups.add(BarChartGroupData(
            x: i,
            barRods: [BarChartRodData(toY: value, width: 10.0, color: color)],
          ));
        } else {
          groups.add(BarChartGroupData(x: i, barRods: []));
        }
      }

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
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        final date = startDate.add(Duration(days: value.toInt()));
                        final label = DateFormat('M/d').format(date);
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Transform.rotate(
                            angle: -0.785398,
                            child: Text(label, style: const TextStyle(fontSize: 8)),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  verticalInterval: 1,
                  getDrawingVerticalLine: (value) {
                    return FlLine(
                      color: Colors.grey.withAlpha((0.2 * 255).toInt()),
                      strokeWidth: 0.5,
                    );
                  },
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.withAlpha((0.2 * 255).toInt()),
                      strokeWidth: 0.5,
                    );
                  },
                ),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    bottom: BorderSide(color: Colors.black, width: 1.0),
                    left: BorderSide.none,
                    top: BorderSide.none,
                    right: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("\uD83D\uDCCA1週間グラフ")),
      body: PageView.builder(
        reverse: true,
        itemBuilder: (context, pageIndex) {
          final DateTime endDate = today.subtract(Duration(days: 7 * pageIndex));
          final DateTime startDate = endDate.subtract(const Duration(days: 6));

          final rangeText = "期間: ${DateFormat('yyyy/M/d').format(startDate)} ~ ${DateFormat('yyyy/M/d').format(endDate)}";

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text("\u2190 スワイプで前後の1週間を表示できます \u2192", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                const SizedBox(height: 10),
                Text(rangeText, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 20),
                buildChartSection("幸せ感レベル", startDate, 1, Colors.green, 100),
                buildChartSection("睡眠の質", startDate, 4, Colors.blue, 100),
                buildChartSection("ウォーキング時間（分）", startDate, 3, Colors.blue, 100),
                buildChartSection("感謝（件）", startDate, 13, Colors.blue, 3),
                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }
}
