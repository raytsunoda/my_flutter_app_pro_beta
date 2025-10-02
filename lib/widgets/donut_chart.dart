import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class DonutChart extends StatelessWidget {
  final double happinessLevel;

  const DonutChart({super.key, required this.happinessLevel});

  @override
  Widget build(BuildContext context) {
    final percentage = happinessLevel.clamp(0, 100);
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 0,
            centerSpaceRadius: 50,
            startDegreeOffset: -90,
            sections: [
              PieChartSectionData(
                value: percentage.toDouble(),

                color: Colors.green,
                radius: 30,
                showTitle: false,
              ),
              PieChartSectionData(
                value: 100 - percentage.toDouble(),
                color: Colors.grey.shade300,
                radius: 30,
                showTitle: false,
              ),
            ],
          ),
        ),
        // 🔧 修正ポイント：mainAxisSize を min に変更
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("幸せ感レベル", style: TextStyle(fontSize: 12)),
            Text("${percentage.floor()}",
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}
