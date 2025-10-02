// lib/services/ai_comment_exporter.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'ai_comment_service.dart';
import 'package:my_flutter_app_pro/utils/csv_loader.dart';


/// AIコメント履歴（今日のひとこと／週次／月次）をCSVに書き出す（Excel向けUTF-16LE）
class AiCommentExporter {
  /// 設定画面の「AIコメント履歴を書き出す（CSV）」から呼び出してください。
  static Future<void> exportCsv(BuildContext context) async {
    try {
      final rows = await _loadAllHistory();
      if (rows.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AIコメント履歴はありません')),
        );
        return;
      }

      final csv = _toCsv(rows); // 文字列（CRLF）
      final bytes = _encodeUtf16LeWithBom(csv);

      // 保存先: Documents
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'ai_comments_$stamp.csv'; // 拡張子はCSVのままでOK（中身はUTF-16LE）
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);

      // 共有シート表示
      await Share.shareXFiles([XFile(file.path)], text: 'AIコメント履歴のバックアップ');

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('書き出し完了: $filename')),
      );
    } catch (e) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('書き出しエラー'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// 既存サービスの Strict ローダを利用して集約
  static Future<List<_LogRow>> _loadAllHistory() async {
    // 既存履歴の読み込み
    var rows = <_LogRow>[
      ...await AiCommentService.loadDailyHistoryStrict()
          .then((l) => l.map((m) => _LogRow.fromMap(m, 'daily'))),
      ...await AiCommentService.loadWeeklyHistoryStrict()
          .then((l) => l.map((m) => _LogRow.fromMap(m, 'weekly'))),
      ...await AiCommentService.loadMonthlyHistoryStrict()
          .then((l) => l.map((m) => _LogRow.fromMap(m, 'monthly'))),
    ].toList();

    // 日次メトリクスを CSV から合流
    final all = await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv');
    if (all.length > 1) {
      final header = all.first.map((e) => e.toString()).toList();
      int col(String name) => header.indexOf(name);

      final idx = (
      date: col('日付'),
      score: col('幸せ感レベル'),
      walk: col('ウォーキング時間'),
      sleep: col('睡眠の質'),
      g1: col('感謝1'),
      g2: col('感謝2'),
      g3: col('感謝3'),
      memo: col('memo'),
      );

      final metrics = <String, Map<String, String>>{};
      for (final r in all.skip(1)) {
        final d = (idx.date >= 0 ? r[idx.date] : '').toString().trim();
        if (d.isEmpty) continue;
        metrics[d] = {
          'score': idx.score >= 0 ? r[idx.score].toString() : '',
          'walk':  idx.walk  >= 0 ? r[idx.walk ].toString() : '',
          'sleep': idx.sleep >= 0 ? r[idx.sleep].toString() : '',
          'g1':    idx.g1    >= 0 ? r[idx.g1   ].toString() : '',
          'g2':    idx.g2    >= 0 ? r[idx.g2   ].toString() : '',
          'g3':    idx.g3    >= 0 ? r[idx.g3   ].toString() : '',
          'memo':  idx.memo  >= 0 ? r[idx.memo ].toString() : '',
        };
      }

      final df = DateFormat('yyyy/MM/dd');
      rows = rows.map((orig) {
        if (orig.type != 'daily') return orig;
        final m = metrics[df.format(orig.date)];
        if (m == null) return orig;
        // 空の項目だけ CSV 値で埋めた新インスタンスを返す
        num? _n(String? s) => s == null ? null : num.tryParse(s);
        return _LogRow(
          date: orig.date,
          type: orig.type,
          comment: orig.comment,
          score: orig.score ?? _n(m['score']),
          sleep: orig.sleep ?? _n(m['sleep']),
          walk:  orig.walk  ?? _n(m['walk']),
          gratitude1: orig.gratitude1 ?? m['g1'],
          gratitude2: orig.gratitude2 ?? m['g2'],
          gratitude3: orig.gratitude3 ?? m['g3'],
          memo: orig.memo ?? m['memo'],
        );
      }).toList();
    }

    // 日付昇順に整列
    rows.sort((a, b) => a.date.compareTo(b.date));
    return rows;
  }


  /// CSV（ヘッダ＋各行）— Excel互換のため改行は CRLF 固定
  static String _toCsv(List<_LogRow> rows) {
    const header = [
      'date', 'type', 'comment',
      'score', 'sleep', 'walk',
      'gratitude1', 'gratitude2', 'gratitude3', 'memo',
    ];
    final buf = StringBuffer()..writeAll(header, ',')..write('\r\n');

    String q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    final df = DateFormat('yyyy/MM/dd');

    for (final r in rows) {
      buf
        ..writeAll([
          q(df.format(r.date)),
          q(r.type),
          q(r.comment),
          r.score?.toString() ?? '',
          r.sleep?.toString() ?? '',
          r.walk?.toString() ?? '',
          q(r.gratitude1),
          q(r.gratitude2),
          q(r.gratitude3),
          q(r.memo),
        ], ',')
        ..write('\r\n');
    }
    return buf.toString();
  }

  /// UTF-16LE + BOM にエンコード
  static Uint8List _encodeUtf16LeWithBom(String s) {
    final builder = BytesBuilder();
    // BOM
    builder.add([0xFF, 0xFE]);
    // UTF-16 の codeUnit を LE で 2byte に分解
    for (final cu in s.codeUnits) {
      builder.add([cu & 0xFF, (cu >> 8) & 0xFF]);
    }
    return builder.toBytes();
  }
}

/// 1行分のモデル（存在しないキーはnull許容）
class _LogRow {
  final DateTime date; // YYYY/MM/DD
  final String type;   // daily / weekly / monthly
  final String? comment;
  final num? score;
  final num? sleep;
  final num? walk;
  final String? gratitude1;
  final String? gratitude2;
  final String? gratitude3;
  final String? memo;

  _LogRow({
    required this.date,
    required this.type,
    this.comment,
    this.score,
    this.sleep,
    this.walk,
    this.gratitude1,
    this.gratitude2,
    this.gratitude3,
    this.memo,
  });

  factory _LogRow.fromMap(Map<String, dynamic> m, String fallbackType) {
    String? _str(dynamic v) => v?.toString();
    num? _num(dynamic v) {
      if (v == null) return null;
      if (v is num) return v;
      return num.tryParse(v.toString());
    }

    // 'YYYY/MM/DD' 以外に 'YYYY/M/D' も許容
    DateTime _parseDate(String s) {
      try {
        return DateFormat('yyyy/MM/dd').parse(s, true).toLocal();
      } catch (_) {
        return DateFormat('y/M/d').parse(s, true).toLocal();
      }
    }

    final dateStr =
        _str(m['date']) ?? _str(m['日付']) ?? _str(m['createdAt']) ?? '';
    final date = _parseDate(dateStr);

    return _LogRow(
      date: date,
      type: _str(m['type']) ?? fallbackType,
      comment: _str(m['comment']) ?? _str(m['aiComment']) ?? _str(m['text']),
      score: _num(m['score']) ?? _num(m['幸せ感レベル']),
      sleep: _num(m['sleep']) ??
          _num(m['睡眠時間（時間換算）']) ??
          _num(m['睡眠時間（分換算)']),
      walk: _num(m['walk']) ?? _num(m['ウォーキング時間']),
      gratitude1: _str(m['gratitude1']) ?? _str(m['感謝1']),
      gratitude2: _str(m['gratitude2']) ?? _str(m['感謝2']),
      gratitude3: _str(m['gratitude3']) ?? _str(m['感謝3']),
      memo: _str(m['memo']) ?? _str(m['メモ']) ?? _str(m['note']),
    );
  }
}
