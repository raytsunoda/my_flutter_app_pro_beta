// lib/services/legacy_import_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class LegacyImportService {
  /// 設定 > データ移行（ファイルピッカー）
  static Future<ImportSummary?> importFromFilePicker(BuildContext context) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('取り込みがキャンセルされました')),
        );
        return null;
      }

      // ▼ 既存日付の扱いを選択
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('同じ日付がある場合の扱い'),
          content: const Text('既存データがある日は上書きしますか？（「いいえ」はスキップ）'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('スキップ')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('上書き')),
          ],
        ),
      ) ?? true; // 既定は上書き

      final bytes = picked.files.first.bytes ?? await File(picked.files.first.path!).readAsBytes();
      final summary = await importFromBytes(bytes, overwrite: overwrite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取り込み完了: 追加 ${summary.inserted} / 上書き ${summary.overwritten}')),
      );
      return summary;
    } catch (e, st) {
      debugPrint('❌ LegacyImportService.importFromFilePicker error: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('取り込みに失敗しました: $e')));
      }
      return null;
    }
  }


  /// 端末内の CSV / .bak を指定して取り込む（開発用）
  static Future<ImportSummary> importLegacyCsv({
    required File source,
    bool overwrite = false,
  }) async {
    final bytes = await source.readAsBytes();
    return importFromBytes(bytes, overwrite: overwrite);
  }

  /// バイト列から取り込み（BOM/改行正規化 → CsvToListConverter で一発パース）
  static Future<ImportSummary> importFromBytes(
      Uint8List bytes, {
        bool overwrite = true,
      }) async {
    // 1) UTF-8 として復号（BOM 除去）
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    // 2) 改行は LF に統一
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 3) CSV パース（ダブルクォート内の改行/カンマ対応）
    final rows = const CsvToListConverter(eol: '\n').convert(text);
    debugPrint('📥 LegacyImport: rows=${rows.length}');
    if (rows.isEmpty) return ImportSummary.zero();

    // 4) ヘッダー整形
    final hdr = rows.first.map((e) => e.toString().trim()).toList();
    final normalizedHeader = _normalizeHeader(hdr);
    debugPrint('🧭 header(normalized) = $normalizedHeader');

    // 5) 既存 CSV を読み込んで日付キーでマージ
    final file = await _targetFile();
    final existing = await _loadExisting(file);

    final mapByDate = <String, List<dynamic>>{};
    for (var r in existing.skip(1)) {
      if (r.isEmpty) continue;
      final d = r[0].toString().trim();
      mapByDate[d] = r;
    }

    int inserted = 0, overwritten = 0;

// 6) 取り込み元を1行ずつ整形して投入
    for (int i = 1; i < rows.length; i++) {
      final src = rows[i].map((e) => e?.toString() ?? '').toList();
      final normalized = _normalizeRow(src, normalizedHeader);

      // ▼ memo の保全：ヘッダー位置以降に分割された列があっても全部まとめて入れる
      final memoStr = _extractMemo(src, normalizedHeader);
      if (memoStr.isNotEmpty) {
        normalized[_targetHeader().indexOf('memo')] = memoStr;
      }

      // 感謝数は感謝1〜3の非空数で再計算
      final g1 = normalized[14].toString().trim();
      final g2 = normalized[15].toString().trim();
      final g3 = normalized[16].toString().trim();
      final gratitudeCount = [g1, g2, g3].where((s) => s.isNotEmpty).length;
      normalized[13] = gratitudeCount.toString();

      final date = normalized[0].toString().trim();
      if (date.isEmpty) {
        debugPrint('⚠️ skip: empty date @row $i');
        continue;
      }

      if (mapByDate.containsKey(date)) {
        if (overwrite) {
          overwritten++;
          mapByDate[date] = normalized;
        } else {
          continue; // スキップ運用
        }
      } else {
        inserted++;
        mapByDate[date] = normalized;
      }

      final memo = normalized[17].toString();
      debugPrint('🔎 $date memo="${memo.length > 40 ? memo.substring(0, 40) + '…' : memo}" g=[$g1,$g2,$g3] cnt=$gratitudeCount');
    }


    // 7) 日付昇順で保存（ヘッダー先頭）
    final out = <List<dynamic>>[];
    out.add(_targetHeader());
    final keys = mapByDate.keys.toList()
      ..sort((a, b) => _parseYmd(a).compareTo(_parseYmd(b)));
    for (final k in keys) {
      out.add(mapByDate[k]!);
    }

    final csv = const ListToCsvConverter(eol: '\n').convert(out);
    await file.writeAsString(csv);
    debugPrint('✅ LegacyImport: saved -> ${file.path} (rows=${out.length})');

    return ImportSummary(inserted: inserted, overwritten: overwritten);
  }

  // ===== helper =====

  static Future<File> _targetFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/HappinessLevelDB1_v2.csv');
  }

  static Future<List<List<dynamic>>> _loadExisting(File file) async {
    if (!await file.exists()) {
      final init = const ListToCsvConverter(eol: '\n').convert([_targetHeader()]);
      await file.writeAsString(init);
      return [_targetHeader()];
    }
    final text = await file.readAsString();
    final rows = const CsvToListConverter(eol: '\n').convert(
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
    );
    if (rows.isEmpty) return [_targetHeader()];
    // ヘッダー不足は強制補正
    if (rows.first.length != _targetHeader().length) {
      rows.removeAt(0);
      rows.insert(0, _targetHeader());
    }
    // データ行も列数を合わせる
    for (int i = 1; i < rows.length; i++) {
      rows[i] = _fitToLength(rows[i], _targetHeader().length);
    }
    return rows;
  }

  static List<String> _targetHeader() => const [
        '日付', '幸せ感レベル', 'ストレッチ時間', 'ウォーキング時間', '睡眠の質',
        '睡眠時間（時間換算）', '睡眠時間（分換算）', '睡眠時間（時間）', '睡眠時間（分）',
        '寝付きの満足度', '深い睡眠感', '目覚め感', 'モチベーション',
        '感謝数', '感謝1', '感謝2', '感謝3', 'memo'
  ];

  static List<String> _normalizeHeader(List<String> hdr) {
    // 旧 Swift 版は memo なし (17列) を想定。最終形 18列に揃える。
    // さらに「寝付き満足度」→「寝付きの満足度」へ表記統一（入力互換）。
    final canon = _targetHeader();

    // 入力ヘッダーをコピーして最小補正（列順は尊重）
    final fixed = <String>[];
    for (final h in hdr) {
      final t = h.trim();
      if (t == '寝付き満足度') {
        fixed.add('寝付きの満足度'); // 表記統一
      } else {
        fixed.add(t);
      }
    }

    // 列数が 17（memo 無し）なら末尾に memo を足す
    if (fixed.length == 17 && fixed.contains('感謝3')) {
      fixed.add('memo');
    }

    // 列の総称・順序は最終形に合わせる（欠落は強制補完）
    if (fixed.length != canon.length) {
      return canon;
    }

    // 期待セットと同数ならそのまま採用（中身は上で表記統一済み）
    return fixed;
  }


  static List<dynamic> _normalizeRow(List<dynamic> src, List<String> normalizedHeader) {
    final n = _fitToLength(src, normalizedHeader.length).map((e) {
    final s = e?.toString() ?? '';
      // セル内改行はスペースへ
      return s.replaceAll('\r', ' ').replaceAll('\n', ' ');
    }).toList();
    // --- 最小変換ルール ---
    // #7（睡眠時間（分換算））だけを必要に応じて補完する。#6（時間換算）は触らない。
    // インデックス： #6=5, #7=6, #8=7, #9=8
    try {
      // 既に値がきちんと入っていれば触らない（空/0/空白なら補完対象）
      final currentMinStr = (n[6] ?? '').toString().trim();
      final needFill = currentMinStr.isEmpty || currentMinStr == '0';
      if (needFill) {
       final hh = double.tryParse((n[7] ?? '').toString().trim()) ?? 0.0; // 睡眠時間（時間）
        final mm = double.tryParse((n[8] ?? '').toString().trim()) ?? 0.0; // 睡眠時間（分）
        final totalMinutes = (hh * 60.0 + mm).round();
        n[6] = totalMinutes.toString();
      }
    } catch (_) {
      // 失敗してもスルー（他列はそのまま）
    }
    return n;
  }

  static List<dynamic> _fitToLength(List<dynamic> row, int len) {
    if (row.length == len) return row;
    if (row.length > len) return row.sublist(0, len);
    return [...row, ...List.filled(len - row.length, '')];
  }

  static DateTime _parseYmd(String ymd) {
    final s = ymd.replaceAll('"', '').trim();
    try {
      return DateFormat('yyyy/MM/dd').parseStrict(s);
    } catch (_) {
      return DateTime(1970);
    }
  }

  /// Documents 直下の .csv / .bak 候補を返す（開発者向け）
  static Future<List<File>> findBakFilesInDocuments() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(dir.path);
    if (!await d.exists()) return [];
    final entries = await d.list().toList();
    final files = entries.whereType<File>().where((f) {
      final name = f.path.toLowerCase();
      return name.endsWith('.csv') || name.endsWith('.bak');
    }).toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  // LegacyImportService クラスの中に追加（他の private helper と同じ位置でOK）
  static String _extractMemo(List<dynamic> row, List<String> headerNorm) {
    final idx = headerNorm.indexOf('memo');
    if (idx < 0) return '';
    // 行の長さが memo の位置に満たない場合は空（境界安全）
    if (row.length <= idx) return '';

    // memo 以降を結合して1つの文字列に（カンマを復元）
    final tail = row.sublist(idx).map((e) => (e ?? '').toString());
    final joined = tail.join(',').trim();

    // Excel 由来の囲みや全角空白、改行を軽く除去
    return joined
        .replaceAll(RegExp(r'^\s*"+'), '')
        .replaceAll(RegExp(r'"+\s*$'), '')
        .replaceAll('\u3000', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .trim();
  }


}

class ImportSummary {
  final int inserted;
  final int overwritten;
  ImportSummary({required this.inserted, required this.overwritten});
  factory ImportSummary.zero() => ImportSummary(inserted: 0, overwritten: 0);

  @override
  String toString() => '追加: $inserted / 上書き: $overwritten';
}


