// lib/screens/period_selection_screen.dart
// === 完全置換してください ===
import 'package:flutter/material.dart';
import 'package:my_flutter_app_pro/screens/period_charts_screen.dart';

class PeriodSelectionScreen extends StatefulWidget {
  final List<List<dynamic>> csvData; // 先頭行がヘッダ想定

  const PeriodSelectionScreen({super.key, required this.csvData});

  @override
  State<PeriodSelectionScreen> createState() => _PeriodSelectionScreenState();
}

class _PeriodSelectionScreenState extends State<PeriodSelectionScreen> {
  String _selected = '1週間';
  final _options = const ['1日', '1週間', '4週間', '1年'];

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

  void _navigate() {
    final maps = _toRowMaps(widget.csvData);

    switch (_selected) {
      case '1週間':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PeriodChartsScreen(
              title: '📊1週間グラフ',
              period: PeriodKind.week,
              csvData: maps,

            ),
          ),
        );
        break;

      case '4週間':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PeriodChartsScreen(
              title: '📊4週間グラフ',
              period: PeriodKind.fourWeeks,
              csvData: maps,
            ),
          ),
        );
        break;

      case '1年':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PeriodChartsScreen(
              title: '📊1年グラフ',
              period: PeriodKind.year,
              csvData: maps,
            ),
          ),
        );
        break;

      case '1日':
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('1日グラフはナビ画面の「1日グラフで見る」からご覧ください')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('期間を選択')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('表示する期間を選んでください', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            DropdownButton<String>(
              value: _selected,
              items: _options.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => setState(() => _selected = v!),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _navigate,
                child: const Text('保存データを読み込み📊を表示'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
