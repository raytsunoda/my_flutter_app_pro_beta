// lib/screens/period_selection_screen.dart
// === 完全置換してください ===
import 'package:flutter/material.dart';
import 'package:my_flutter_app_pro/screens/period_charts_screen.dart';
import '../gen_l10n/app_localizations.dart';



enum PeriodPick { day, week, fourWeeks, year }

class PeriodSelectionScreen extends StatefulWidget {
  final List<List<dynamic>> csvData; // 先頭行がヘッダ想定

  const PeriodSelectionScreen({super.key, required this.csvData});

  @override
  State<PeriodSelectionScreen> createState() => _PeriodSelectionScreenState();
}

class _PeriodSelectionScreenState extends State<PeriodSelectionScreen> {
  // String _selected = '1週間';
  // final _options = const ['1日', '1週間', '4週間', '1年'];
  PeriodPick _selected = PeriodPick.week;
    static const List<PeriodPick> _options = <PeriodPick>[
      PeriodPick.day,
      PeriodPick.week,
      PeriodPick.fourWeeks,
      PeriodPick.year,
    ];


  // ヘッダ付きの2次元配列 → 行Mapのリストへ変換（&日付正規化）
  List<Map<String, String>> _toRowMaps(List<List<dynamic>> rows) {
    if (rows.isEmpty) return const [];
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final idxDate = header.indexOf('日付');

    return rows.skip(1).map((r) {
      final m = <String, String>{};
      for (int i = 0; i < header.length && i < r.length; i++) {
        m[header[i]] = r[i]?.toString().trim() ?? '';
      }
      // "2025/9/4" → "2025/09/04" に正規化
      if (idxDate >= 0) {
        final raw = (r[idxDate]?.toString() ?? '').replaceAll('"', '').trim();
        final parts = raw.split('/');
        if (parts.length == 3) {
          final y = parts[0];
          final mo = parts[1].padLeft(2, '0');
          final d = parts[2].padLeft(2, '0');
          m['日付'] = '$y/$mo/$d';
        } else {
          m['日付'] = raw;
        }
      }
      return m;
    }).toList();
  }

  //void _navigate() {
    String _labelFor(PeriodPick p, AppLocalizations t) {
        switch (p) {
          case PeriodPick.day:
           return t.periodOptionDay;
          case PeriodPick.week:
            return t.periodOptionWeek;
          case PeriodPick.fourWeeks:
            return t.periodOptionFourWeeks;
          case PeriodPick.year:
            return t.periodOptionYear;
        }
      }

    void _navigate(AppLocalizations t) {

    final maps = _toRowMaps(widget.csvData);

    switch (_selected) {
  //    case '1週間':
      case PeriodPick.week:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PeriodChartsScreen(
           //   title: '📊1週間グラフ',
              title: t.periodChartTitleWeek,
              period: PeriodKind.week,
              csvData: maps,

            ),
          ),
        );
        break;

   //   case '4週間':
      case PeriodPick.fourWeeks:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PeriodChartsScreen(
          //    title: '📊4週間グラフ',
              title: t.periodChartTitleFourWeeks,
              period: PeriodKind.fourWeeks,
              csvData: maps,
            ),
          ),
        );
        break;

    //  case '1年':
      case PeriodPick.year:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PeriodChartsScreen(
            //  title: '📊1年グラフ',
              title: t.periodChartTitleYear,
              period: PeriodKind.year,
              csvData: maps,
            ),
          ),
        );
        break;

 //     case '1日':
      default:
        ScaffoldMessenger.of(context).showSnackBar(
       //   const SnackBar(content: Text('1日グラフはナビ画面の「1日グラフで見る」からご覧ください')),
          SnackBar(content: Text(t.periodDayGraphHint)),

        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
   //   appBar: AppBar(title: const Text('期間を選択')),
      appBar: AppBar(title: Text(t.periodSelectTitle)),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          //  const Text('表示する期間を選んでください', textAlign: TextAlign.center),
            Text(t.periodSelectMessage, textAlign: TextAlign.center),
            const SizedBox(height: 16),
           // DropdownButton<String>(
            DropdownButton<PeriodPick>(
              value: _selected,
              // items: _options.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              // onChanged: (v) => setState(() => _selected = v!),
              items: _options
                  .map((p) => DropdownMenuItem(
                    value: p,
                   child: Text(_labelFor(p, t)),
              ))
                .toList(),
            onChanged: (v) => setState(() => _selected = v ?? PeriodPick.week),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                // onPressed: _navigate,
                // child: const Text('保存データを読み込み📊を表示'),
                onPressed: () => _navigate(t),
                child: Text(t.periodShowButton),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
