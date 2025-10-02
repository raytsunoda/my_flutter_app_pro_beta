import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class OneYearChart extends StatelessWidget {
  final List<List<dynamic>> csvData;

  OneYearChart({required this.csvData});

  @override
  Widget build(BuildContext context) {
    final DateTime today = DateTime.now();
    final DateTime startDate = today.subtract(const Duration(days: 364));

    final Map<String, List<dynamic>> dataMap = {
      for (var row in csvData.skip(1))
        if (row.isNotEmpty && row[0] != null)
          row[0].toString().trim(): row,
    };

    List<BarChartGroupData> buildBarGroups(int columnIndex, double Function(String) parser, Color color) {
      List<BarChartGroupData> groups = [];
      for (int i = 0; i < 365; i++) {
        final DateTime currentDate = startDate.add(Duration(days: i));
        final String dateKey = DateFormat('yyyy/MM/dd').format(currentDate);
        final row = dataMap[dateKey];

        if (row != null) {
          final value = parser(row[columnIndex].toString());
          groups.add(BarChartGroupData(
            x: i,
            barRods: [BarChartRodData(toY: value, width: 0.2, color: color)],
          ));
        } else {
          groups.add(BarChartGroupData(x: i, barRods: []));
        }
      }
      return groups;
    }

    final happinessBarGroups = buildBarGroups(1, (s) => double.tryParse(s) ?? 0, Colors.green);
    final sleepBarGroups = buildBarGroups(4, (s) => double.tryParse(s) ?? 0, Colors.blue);
    final walkingBarGroups = buildBarGroups(3, (s) => double.tryParse(s) ?? 0, Colors.blue);
    final appreciationBarGroups = buildBarGroups(13, (s) => double.tryParse(s) ?? 0, Colors.blue);

    Widget buildSection(String title, List<BarChartGroupData> data, double maxY) {
      return Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                barGroups: data,
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
                        if (value % 28 == 0) {
                          final DateTime labelDate = startDate.add(Duration(days: value.toInt()));
                          final label = DateFormat('M/d').format(labelDate);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Transform.rotate(
                              angle: -0.785398, // -45度
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 8),
                              ),
                            ),
                          );
                        } else {
                          return const SizedBox.shrink();
                        }
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawHorizontalLine: true,
                  drawVerticalLine: true,
                  verticalInterval: 28,
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
                    bottom: BorderSide(
                      color: Colors.black,
                      width: 1.0,
                    ),
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
    final formatter = DateFormat('yyyy/M/d');
    final String rangeText = "期間: ${formatter.format(startDate)} ~ ${formatter.format(today)}";

    return Scaffold(
      appBar: AppBar(title: const Text("📊1年グラフ")),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Text(rangeText, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 20),
            buildSection("幸せ感レベル", happinessBarGroups, 100),
            buildSection("睡眠の質", sleepBarGroups, 100),
            buildSection("ウォーキング時間（分）", walkingBarGroups, 100),
            buildSection("感謝（件）", appreciationBarGroups, 3),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
