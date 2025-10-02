// lib/views/daily_insights_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

class DailyInsight {
  final String negative;
  final String positive;
  final String episode;

  DailyInsight(this.negative, this.positive, this.episode);
}

class DailyInsightsView extends StatefulWidget {
  const DailyInsightsView({super.key});

  @override
  State<DailyInsightsView> createState() => _DailyInsightsViewState();
}

class _DailyInsightsViewState extends State<DailyInsightsView> {
  List<DailyInsight> insights = [];
  int index = 0;
  int subIndex = 0;

  @override
  void initState() {
    super.initState();
    loadCSV();
  }

  Future<void> loadCSV() async {
    final raw = await rootBundle.loadString('assets/daily_insights.csv');
    final rows = const LineSplitter().convert(raw);
    final loaded = rows.skip(1).map((line) {
      final values = line.split(',');
      return DailyInsight(values[0], values[1], values[2]);
    }).toList();
    setState(() {
      insights = loaded;
    });
  }

  void nextTriple() {
    setState(() {
      index = (index + 3) % insights.length;
      subIndex = 0;
    });
  }

  void nextCard() {
    setState(() {
      subIndex = (subIndex + 1) % 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = insights.isNotEmpty ? insights[index % insights.length] : null;
    final cardText = () {
      if (current == null) return '';
      return subIndex == 0
          ? current.negative
          : subIndex == 1
          ? current.positive
          : current.episode;
    }();

    return Scaffold(
      appBar: AppBar(title: const Text('気持ちが少し楽になるヒント')),
      body: Center(
        child: insights.isEmpty
            ? const CircularProgressIndicator()
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: nextCard,
              child: Card(
                elevation: 4,
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    cardText,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: nextTriple,
              child: const Text('次の3件を見る'),
            )
          ],
        ),
      ),
    );
  }
}
