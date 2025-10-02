import 'dart:math';
import 'package:flutter/material.dart';
import 'package:my_flutter_app_pro/utils/csv_loader.dart';

class TipsScreen extends StatefulWidget {
  const TipsScreen({super.key});

  @override
  State<TipsScreen> createState() => _TipsScreenState();
}

class _TipsScreenState extends State<TipsScreen> {
  late List<Map<String, String>> _allTips = [];
  late List<Map<String, String>> _currentTips = [];
  late List<int> _steps = [0, 0, 0];

  final _random = Random();

  @override
  void initState() {
    super.initState();
    _loadCsv();
  }

  Future<void> _loadCsv() async {
    final data = await CsvLoader.loadCsvAsMapList('daily_insights.csv');
    if (data.isEmpty) return;

    setState(() {
      _allTips = data;
      _shuffleAndPick();
    });
  }

  void _shuffleAndPick() {
    _allTips.shuffle(_random);
    _currentTips = _allTips.take(3).toList();
    _steps = List<int>.filled(_currentTips.length, 0);
  }

  void _nextStep(int idx) {
    setState(() => _steps[idx] = (_steps[idx] + 1) % 3);
  }

  String _textForStep(Map<String, String> tip, int step) {
    switch (step) {
      case 0:
        return tip['negative'] ?? tip['ネガ'] ?? tip['ネガティブ表現'] ?? '（ネガティブ表現なし）';
      case 1:
        return tip['positive'] ?? tip['ポジ'] ?? tip['ポジティブ表現'] ?? '（ポジティブ表現なし）';
      case 2:
        return tip['episode'] ?? tip['エピソード'] ?? '（エピソードなし）';
      default:
        return '';
    }
  }

  Color _colorForStep(int step) {
    return switch (step) {
      0 => Colors.red.shade100,
      1 => Colors.blue.shade100,
      2 => Colors.green.shade100,
      _ => Colors.grey.shade200,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue.shade50,
      appBar: AppBar(
        title: const Text('気持ちが少し楽になるヒント'),
        backgroundColor: Colors.teal.shade400,
      ),
      body: _currentTips.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _currentTips.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, idx) {
          final tip = _currentTips[idx];
          final step = _steps[idx];

          return InkWell(
            onTap: () => _nextStep(idx),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _colorForStep(step),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(2, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No.${tip['No.'] ?? '-'}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(
                    _textForStep(tip, step),
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      switch (step) {
                        0 => 'タップしてポジ表現へ ▶️',
                        1 => 'タップしてエピソードへ ▶️',
                        2 => 'タップしてネガ表現に戻る 🔄',
                        _ => ''
                      },
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.teal.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('次の3件を見る'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: Colors.teal.shade400,
            foregroundColor: Colors.white,
          ),
          onPressed: () => setState(_shuffleAndPick),
        ),
      ),
    );
  }
}
