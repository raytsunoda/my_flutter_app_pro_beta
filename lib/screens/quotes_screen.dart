
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'dart:math';
import 'package:my_flutter_app_pro/widgets/load_more_button.dart';
import '../gen_l10n/app_localizations.dart';
import 'package:my_flutter_app_pro/utils/csv_loader.dart';

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

  bool _isRestartUser(List<List<String>> csvMatrix) {
    if (csvMatrix.length <= 2) return false;

    try {
      final rows = csvMatrix.skip(1).toList();
      if (rows.length < 2) return false;

      final lastDate = DateTime.parse(rows.last[0].replaceAll('/', '-'));
      final prevDate = DateTime.parse(rows[rows.length - 2][0].replaceAll('/', '-'));

      return lastDate.difference(prevDate).inDays >= 3;
    } catch (_) {
      return false;
    }
  }

  bool _isLowSleep(List<double> radar) {
    if (radar.isEmpty) return false;
    return radar[0] <= 2.0;
  }

  bool _isLowMood(List<List<String>> csvMatrix) {
    if (csvMatrix.length <= 1) return false;

    try {
      final lastRow = csvMatrix.last;
      if (lastRow.length < 2) return false;

      final mood = double.tryParse(lastRow[1]) ?? 0;
      return mood <= 2.0;
    } catch (_) {
      return false;
    }
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

      final radar = await CsvLoader.loadTodayRadarScores();
      final csvMatrix = await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv');

      final isRestart = _isRestartUser(csvMatrix);
      final isLowSleep = _isLowSleep(radar);
      final isLowMood = _isLowMood(csvMatrix);

      final filtered = _filterQuotesByCondition(
        data,
        isRestart: isRestart,
        isLowSleep: isLowSleep,
        isLowMood: isLowMood,
      );

      setState(() {
        _quotes = filtered;
        _tapState = List.filled(_quotes.length, 0);
        _shuffleQuotes();
        _updateDisplayQuotes();
        _loadError = null;
        _isLoading = false;
      });

      print('🟣 quotes isRestart=$isRestart, isLowSleep=$isLowSleep, isLowMood=$isLowMood');
      print('🟢 quotes selected use_when pool = ${_quotes.map((e) => e['use_when']).toList()}');
      print('🟢 quotes selected ids pool = ${_quotes.map((e) => e['id']).toList()}');
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
      debugPrint('❌ quotes.csv load failed: $e');
    }
  }

  List<Map<String, String>> _filterQuotesByCondition(
      List<Map<String, String>> allQuotes, {
        required bool isRestart,
        required bool isLowSleep,
        required bool isLowMood,
      }) {
    List<Map<String, String>> primary = [];
    List<Map<String, String>> fallbackAny = [];

    if (isRestart) {
      primary = allQuotes.where((q) => (q['use_when'] ?? 'any') == 'restart').toList();
    } else if (isLowSleep) {
      primary = allQuotes.where((q) => (q['use_when'] ?? 'any') == 'poor_sleep').toList();
    } else if (isLowMood) {
      primary = allQuotes.where((q) => (q['use_when'] ?? 'any') == 'low_mood').toList();
    }

    fallbackAny = allQuotes.where((q) => (q['use_when'] ?? 'any') == 'any').toList();

    final selected = <Map<String, String>>[];
    selected.addAll(primary);

    for (final q in fallbackAny) {
      if (!selected.contains(q)) {
        selected.add(q);
      }
    }

    if (selected.isEmpty) {
      return allQuotes;
    }

    return selected;
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

           //     final quoteText = isEn
                final messageText = isEn
                    ? (quote['text_en'] ?? '')
                    : (quote['text_ja'] ?? '');

           //     final commentary = isEn
                final detailText = isEn
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
                            Text('・$messageText')
                          else
                            Text(detailText),
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
