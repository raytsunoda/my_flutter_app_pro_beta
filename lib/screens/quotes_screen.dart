
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

  String? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCSV();
  }

  Future<void> _loadCSV() async {
    try {
      final rawData = await rootBundle.loadString('assets/quotes.csv');
      final rows = const CsvToListConverter().convert(rawData, eol: '\n');

      if (rows.isEmpty) {
        throw Exception('quotes.csv is empty');
      }

      final headers = rows.first.map((e) => e.toString()).toList();

      final data = rows.skip(1).map((row) {
        final values = row.map((e) => e.toString()).toList();

        final padded = values.length < headers.length
            ? [...values, ...List.filled(headers.length - values.length, '')]
            : values.sublist(0, headers.length);

        return Map<String, String>.fromIterables(headers, padded);
      }).toList();

      setState(() {
        _quotes = data;
        _tapState = List.filled(_quotes.length, 0);
        _shuffleQuotes();
        _updateDisplayQuotes();
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
      debugPrint('❌ quotes.csv load failed: $e');
    }
  }

  void _shuffleQuotes() {
    _quotes.shuffle(Random());
  }

  void _updateDisplayQuotes() {
    if (_quotes.isEmpty) return;

    if (_currentIndex >= _quotes.length) {
      _shuffleQuotes();
      _currentIndex = 0;
    }

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Failed to load quotes:\n$_loadError',
            textAlign: TextAlign.center,
          ),
        ),
      )
          : _displayQuotes.isEmpty
          ? const Center(child: Text('No messages found'))
          : Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _displayQuotes.length,
              itemBuilder: (context, index) {
                final quote = _displayQuotes[index];
                final globalIndex = _quotes.indexOf(quote);
                final state = _tapState[globalIndex];

                final lang = Localizations.localeOf(context).languageCode;
                final isEn = lang == 'en';

                final quoteText = isEn
                    ? (quote['text_en'] ?? '')
                    : (quote['text_ja'] ?? '');

                final commentary = isEn
                    ? (quote['detail_en'] ?? '')
                    : (quote['detail_ja'] ?? '');

                final id = quote['id'] ?? quote['番号'] ?? '';
               // Text('・$quoteText');  // ← これが抜けていた可能性が高い

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
                            Text('・$quoteText')
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
