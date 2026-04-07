import 'dart:math';
import 'package:flutter/material.dart';
import 'package:my_flutter_app_pro/utils/csv_loader.dart';
import 'package:my_flutter_app_pro/gen_l10n/app_localizations.dart';

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

    final radar = await CsvLoader.loadTodayRadarScores();
    final csvMatrix = await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv');

    final isRestart = _isRestartUser(csvMatrix);
    final isLowSleep = _isLowSleep(radar);
    final isLowMood = _isLowMood(csvMatrix);

    debugPrint('🟣 isRestart=$isRestart, isLowSleep=$isLowSleep, isLowMood=$isLowMood');

    setState(() {
      _allTips = data;
      _pickTipsByCondition(
        isRestart: isRestart,
        isLowSleep: isLowSleep,
        isLowMood: isLowMood,
      );
    });
  }
  bool _isRestartUser(List<List<String>> csvMatrix) {
    if (csvMatrix.length <= 2) return false;

    try {
      final rows = csvMatrix.skip(1).toList();
      if (rows.length < 2) return false;

      final lastDate = DateTime.parse(
        rows.last[0].replaceAll('/', '-'),
      );
      final prevDate = DateTime.parse(
        rows[rows.length - 2][0].replaceAll('/', '-'),
      );

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


  void _shuffleAndPick() {
    _allTips.shuffle(_random);
    _currentTips = _allTips.take(3).toList();
    _steps = List<int>.filled(_currentTips.length, 0);
  }


  void _pickTipsByCondition({
    required bool isRestart,
    required bool isLowSleep,
    required bool isLowMood,
  }) {
    List<Map<String, String>> primary = [];
    List<Map<String, String>> fallbackAny = [];

    if (isRestart) {
      primary = _allTips
          .where((tip) => (tip['restart_state'] ?? 'any') == 'yes')
          .toList();

      fallbackAny = _allTips.where((tip) {
        return (tip['restart_state'] ?? 'any') == 'any';
      }).toList();
    } else if (isLowSleep) {
      primary = _allTips
          .where((tip) => (tip['sleep_state'] ?? 'any') == 'low')
          .toList();

      fallbackAny = _allTips.where((tip) {
        return (tip['sleep_state'] ?? 'any') == 'any';
      }).toList();
    } else if (isLowMood) {
      primary = _allTips
          .where((tip) => (tip['mood_state'] ?? 'any') == 'low')
          .toList();

      fallbackAny = _allTips.where((tip) {
        return (tip['mood_state'] ?? 'any') == 'any';
      }).toList();
    } else {
      primary = _allTips.where((tip) {
        final mood = tip['mood_state'] ?? 'any';
        final sleep = tip['sleep_state'] ?? 'any';
        final restart = tip['restart_state'] ?? 'any';

        return mood == 'any' && sleep == 'any' && restart == 'any';
      }).toList();
    }

    primary.shuffle(_random);
    fallbackAny.shuffle(_random);

    final selected = <Map<String, String>>[];
    selected.addAll(primary);

    for (final tip in fallbackAny) {
      if (selected.length >= 3) break;
      if (!selected.contains(tip)) {
        selected.add(tip);
      }
    }

    if (selected.length < 3) {
      final extra = _allTips.where((tip) => !selected.contains(tip)).toList();
      extra.shuffle(_random);
      selected.addAll(extra.take(3 - selected.length));
    }

    _currentTips = selected.take(3).toList();
    _steps = List<int>.filled(_currentTips.length, 0);

    debugPrint('🟣 isRestart=$isRestart, isLowSleep=$isLowSleep, isLowMood=$isLowMood');
    debugPrint('🟢 selected tip ids = ${_currentTips.map((e) => e['id']).toList()}');
    debugPrint('🟢 selected categories = ${_currentTips.map((e) => e['category']).toList()}');
    debugPrint('🟢 selected restart_state = ${_currentTips.map((e) => e['restart_state']).toList()}');
    debugPrint('🟢 selected sleep_state = ${_currentTips.map((e) => e['sleep_state']).toList()}');
    debugPrint('🟢 selected mood_state = ${_currentTips.map((e) => e['mood_state']).toList()}');
  }



  void _nextStep(int idx) {
    setState(() => _steps[idx] = (_steps[idx] + 1) % 3);
  }

  String _textForStep(Map<String, String> tip, int step) {
    final lang = Localizations.localeOf(context).languageCode;
    final isEn = lang == 'en';

    switch (step) {
      case 0:
        return isEn
            ? (tip['negative_en'] ??
            tip['negative'] ??
            tip['ネガ'] ??
            tip['ネガティブ表現'] ??
            AppLocalizations.of(context)!.tipsMissingNegative)
            : (tip['negative_ja'] ??
            tip['negative'] ??
            tip['ネガ'] ??
            tip['ネガティブ表現'] ??
            AppLocalizations.of(context)!.tipsMissingNegative);

      case 1:
        return isEn
            ? (tip['positive_en'] ??
            tip['positive'] ??
            tip['ポジ'] ??
            tip['ポジティブ表現'] ??
            AppLocalizations.of(context)!.tipsMissingPositive)
            : (tip['positive_ja'] ??
            tip['positive'] ??
            tip['ポジ'] ??
            tip['ポジティブ表現'] ??
            AppLocalizations.of(context)!.tipsMissingPositive);

      case 2:
        return isEn
            ? (tip['episode_en'] ??
            tip['episode'] ??
            tip['エピソード'] ??
            AppLocalizations.of(context)!.tipsMissingEpisode)
            : (tip['episode_ja'] ??
            tip['episode'] ??
            tip['エピソード'] ??
            AppLocalizations.of(context)!.tipsMissingEpisode);

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
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.lightBlue.shade50,
      appBar: AppBar(
        //title: const Text('気持ちが少し楽になるヒント'),
        title: Text(t.tipsTitle),
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
                //  Text('No.${tip['No.'] ?? '-'}',
                //  Text('${t.tipsNoPrefix}${tip['No.'] ?? '-'}',
                  Text('${t.tipsNoPrefix}${tip['id'] ?? tip['No.'] ?? '-'}',
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
                        // 0 => 'タップしてポジ表現へ ▶️',
                        // 1 => 'タップしてエピソードへ ▶️',
                        // 2 => 'タップしてネガ表現に戻る 🔄',
                        0 => t.tipsTapToPositive,
                        1 => t.tipsTapToEpisode,
                        2 => t.tipsTapToNegative,
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
          //label: const Text('次の3件を見る'),
          label: Text(t.tipsNext3),
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
