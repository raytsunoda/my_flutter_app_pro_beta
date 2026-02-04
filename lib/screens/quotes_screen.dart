
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'dart:math';
import 'package:my_flutter_app_pro/widgets/load_more_button.dart';
import '../gen_l10n/app_localizations.dart';

class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  List<Map<String, String>> _quotes = [];
  List<Map<String, String>> _displayQuotes = [];
  int _currentIndex = 0;
  final int _batchSize = 3;
  List<int> _tapState = [];

  @override
  void initState() {
    super.initState();
    _loadCSV();
  }

  Future<void> _loadCSV() async {
    final rawData = await rootBundle.loadString('assets/quotes.csv');
    final rows = const CsvToListConverter().convert(rawData, eol: '\n');
    final headers = rows.first.cast<String>();
    final data = rows.skip(1).map((row) {
      final values = row.map((e) => e.toString()).toList();
      return Map.fromIterables(headers, values);
    }).toList();

    setState(() {
      _quotes = data;
      _tapState = List.filled(_quotes.length, 0);
      _shuffleQuotes();
      _updateDisplayQuotes();
    });
  }

  void _shuffleQuotes() {
    _quotes.shuffle(Random());
  }

  void _updateDisplayQuotes() {
    final nextIndex = (_currentIndex + _batchSize <= _quotes.length)
        ? _currentIndex + _batchSize
        : _quotes.length;
    setState(() {
      _displayQuotes = _quotes.sublist(_currentIndex, nextIndex);
      _currentIndex = nextIndex;
    });
  }

  void _handleTap(int index) {
    final globalIndex = _quotes.indexOf(_displayQuotes[index]);
    setState(() {
      _tapState[globalIndex] = (_tapState[globalIndex] + 1) % 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        //title: const Text('名言をチェック'),
        title: Text(t.quotesTitle),
      ),
      body: _displayQuotes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _displayQuotes.length,
              itemBuilder: (context, index) {
                final quote = _displayQuotes[index];
                final globalIndex = _quotes.indexOf(quote);
                final state = _tapState[globalIndex];

                final quoteText = quote['名言・格言'] ?? '';
                final author = quote['出典'] ?? '';
                final commentary = quote['解説'] ?? '';

                final id = quote['番号'] ?? '';
                Text('・$quoteText');  // ← これが抜けていた可能性が高い

                return GestureDetector(
                  onTap: () => _handleTap(index),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('No.$id', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 8),
                          if (state == 0)
                            Text('・$quoteText\n・$author')
                          else
                            Text(commentary),
                          const SizedBox(height: 8),
                          Text(
                            //state == 0 ? '🔵 タップして解説を見る' : '🔵 タップして名言に戻る',
                            state == 0 ? t.tipsTapToExplanation : t.tipsBackToQuote,
                            style: const TextStyle(color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          LoadMoreButton(onPressed: _updateDisplayQuotes),
        ],
      ),
    );
  }
}
