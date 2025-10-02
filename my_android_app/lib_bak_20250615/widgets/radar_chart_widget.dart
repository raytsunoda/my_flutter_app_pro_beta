import 'package:flutter/material.dart';
import 'dart:math';

class RadarChartWidget extends StatelessWidget {
  final List<String> labels;
  final List<double> scores;

  const RadarChartWidget({
    Key? key,
    required this.labels,
    required this.scores,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(320, 320),
      painter: _RadarChartPainter(labels: labels, scores: scores),
    );
  }
}

class _RadarChartPainter extends CustomPainter {
  final List<String> labels;
  final List<double> scores;

  _RadarChartPainter({required this.labels, required this.scores});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 * 0.8;
    final angleStep = 2 * pi / labels.length;

    final Paint gridPaint = Paint()
      ..color = Colors.black.withOpacity(0.15)
      ..style = PaintingStyle.stroke;

    final Paint fillPaint = Paint()
      ..color = Colors.blue.withAlpha(80)
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // グリッド（25%, 50%, 75%, 100%）
    for (int i = 1; i <= 4; i++) {
      final r = radius * i / 4;
      final path = Path();
      for (int j = 0; j < labels.length; j++) {
        final angle = j * angleStep - pi / 2;
        final x = center.dx + cos(angle) * r;
        final y = center.dy + sin(angle) * r;
        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // ラベル描画
    for (int i = 0; i < labels.length; i++) {
      final angle = i * angleStep - pi / 2;
      final labelX = center.dx + cos(angle) * (radius + 16);
      final labelY = center.dy + sin(angle) * (radius + 16);
      final score = scores[i].isNaN || scores[i].isInfinite ? 0 : scores[i];
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${labels[i]}\n${score.toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 12, color: Colors.black),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      canvas.save();
      canvas.translate(labelX - textPainter.width / 2, labelY - textPainter.height / 2);
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // スコアポリゴン描画
    final path = Path();
    for (int i = 0; i < scores.length; i++) {
      final angle = i * angleStep - pi / 2;
      final score = scores[i].isNaN || scores[i].isInfinite ? 0.0 : scores[i].clamp(0, 100);
      final x = center.dx + cos(angle) * radius * (score / 100.0);
      final y = center.dy + sin(angle) * radius * (score / 100);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
