import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:my_flutter_app_pro/utils/date_utils.dart';
import 'package:path/path.dart' as p;


//import '../models/record_entry.dart';
// デバッグ出力の全体トグル
const bool kCsvVerbose = false; // ← ここを true にすれば従来通り詳細ログ

String _norm(String s) => s.replaceAll('\uFEFF', '').trim().toLowerCase();

int _idx(List<String> hdrs, String name, int fallbackIfMissing) {
  final i = hdrs.indexOf(name);
  return (i >= 0) ? i : fallbackIfMissing;
}

// 空判定：null / '' / '-' を空とみなす
bool _isEmptyCell(String? s) {
  if (s == null) return true;
  final t = s.trim();
  return t.isEmpty || t == '-';
}

// 取り込み側が空なら既存を優先、取り込み側に値があれば採用
String _preferNonEmpty(String current, String incoming) {
  return _isEmptyCell(incoming) ? current : incoming;
}


class CsvLoader {
  static Future<File> getCsvFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/HappinessLevelDB1_v2.csv');
  }

  static bool _isWritingAiCommentLog = false;


  static Future<List<List<String>>> loadCsvDataBetween(DateTime start, DateTime end) async {
    final rows = await loadCsvRows();
    final dateFormat = DateFormat('yyyy/MM/dd');
    return rows.where((row) {
      if (row.isEmpty) return false;
      try {
        final date = dateFormat.parse(row[0]);
        return date.isAfter(start.subtract(const Duration(days: 1))) && date.isBefore(end.add(const Duration(days: 1)));
      } catch (_) {
        return false;
      }
    }).toList();
  }


  static Future<String> loadTodayMemo() async {
    final data = await loadLatestCsvData('HappinessLevelDB1_v2.csv');
    if (data.length <= 1) return "";
    final last = data.last;
    return last.length > 17 ? last[17] : "";
  }

  static Future<List<String>> loadTodayGratitude() async {
    final data = await loadLatestCsvData('HappinessLevelDB1_v2.csv');
    if (data.length <= 1) return [];
    final last = data.last;
    return [
      if (last.length > 14) last[14] else
        "",
      if (last.length > 15) last[15] else
        "",
      if (last.length > 16) last[16] else
        "",
    ];
  }

  static Future<List<double>> loadTodayRadarScores() async {
    final data = await loadLatestCsvData('HappinessLevelDB1_v2.csv');
    if (data.length <= 1) return List.filled(7, 0.0);
    final last = data.last;
    return List.generate(7, (i) {
      final idx = i + 7; // 7〜13列がスコア想定
      if (last.length > idx) {
        final val = double.tryParse(last[idx]) ?? 0.0;
        return val;
      }
      return 0.0;
    });
  }

  /// 指定日数分の最新データ（ヘッダー除く）
  static Future<List<List<String>>> loadLastNDays(int days) async {
    final matrix = await loadLatestCsvData('HappinessLevelDB1_v2.csv');
    final now = DateTime.now();

    // ヘッダーを除外して日付でフィルタ
    return matrix.skip(1).where((row) {
      try {
        final date = DateFormat('yyyy/MM/dd').parse(row[0]); // 0列目が日付列
        return date.isAfter(now.subtract(Duration(days: days)));
      } catch (e) {
        return false;
      }
    }).toList();
  }

  static Future<List<Map<String, String>>> _readCsv() async {
    final data = await loadLatestCsvData('HappinessLevelDB1_v2.csv');
    return toMapList(data);
  }


  // ===== csv_loader.dart: 置換版 loadCsv(String filename) 開始 =====
  static final DateFormat _df = DateFormat('yyyy/MM/dd');

  static String _normalizeYmd(String raw) {
    final s = raw.trim().replaceAll('-', '/');
    final p = s.split('/');
    if (p.length != 3) return raw.trim();
    final y = p[0].padLeft(4, '0');
    final m = p[1].padLeft(2, '0');
    final d = p[2].padLeft(2, '0');
    return '$y/$m/$d';
  }

  static Future<List<Map<String, String>>> loadCsv(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$filename';
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('CSV file not found at $path');
    }

    // 既存のロバストパーサを活用して確実に行列化
    final raw = await file.readAsString();
    final matrix = _robustCsvParse(raw);
    if (matrix.isEmpty) return [];

    // ヘッダー行（String化＆trim）
    final headers = matrix.first.map((e) => e.toString().trim()).toList();

    // データ行を Map 化（列数ズレはパディング/切り捨て）
    final out = <Map<String, String>>[];
    for (final row in matrix.skip(1)) {
      final values = row.map((e) => e.toString()).toList();
      final padded = values.length < headers.length
          ? [...values, ...List.filled(headers.length - values.length, '')]
          : values.sublist(0, headers.length);

      final m = <String, String>{};
      for (var i = 0; i < headers.length; i++) {
        m[headers[i]] = padded[i];
      }

      // 日付ゆれをここで吸収（日本語ヘッダ/英語ヘッダどちらでも）
      if (m.containsKey('日付') && m['日付']!.trim().isNotEmpty) {
        final n = _normalizeYmd(m['日付']!);
        m['日付'] = n;
        if (m.containsKey('date')) m['date'] = n;
      } else if (m.containsKey('date') && m['date']!.trim().isNotEmpty) {
        final n = _normalizeYmd(m['date']!);
        m['date'] = n;
        if (m.containsKey('日付')) m['日付'] = n;
      }

      out.add(m);
    }
    return out;
  }
// ===== csv_loader.dart: 置換版 loadCsv(String filename) 終了 =====


  // 補助：指定日付の行を取得
  static Future<List<String>?> getRowForDate(DateTime date) async {
    final csvData = await CsvLoader.loadLatestCsvData(
        'HappinessLevelDB1_v2.csv'); //8/3 ✅
    final targetDate = DateFormat('yyyy/MM/dd').format(date);
    for (var row in csvData) {
      if (row.isNotEmpty && row[0] == targetDate) {
        return row;
      }
    }
    return null;
  }

// 最新（過去）の日付のメモを取得する
  /// 当日データがなければ最新過去データを返す
  static Map<String, String>? getLatestAvailableRow(
      List<Map<String, String>> data, DateTime referenceDate) {
    for (var i = data.length - 1; i >= 0; i--) {
      final row = data[i];
      if (row.containsKey('日付') && row['日付']!.isNotEmpty) {
        print("🔍 Found row: ${row['日付']}");
        return row;
      }
    }
    return null;
  }


  static Future<String> loadMemoForDate(DateTime date) async {
    final row = await getRowForDate(date);
    return row != null && row.length > 17 ? row[17] : '';
  }


  /// ───────────────────────────────────────────────
  /// 共通ヘルパ – 空行を除外しつつ String 化
  /// ───────────────────────────────────────────────
  static List<List<String>> _sanitizeRows(List<List<dynamic>> rows) =>
      rows
          .where((r) =>
      r.isNotEmpty &&
          r.any((c) =>
          c
              .toString()
              .trim()
              .isNotEmpty)) // ← 空行フィルタ
          .map((r) => r.map((e) => e.toString()).toList())
          .toList();

  /// --------------------------------------------------
  /// ⑤ アプリ初回起動時：assets → DocumentDirectory
  /// --------------------------------------------------
  /// /// assets から初期 CSV をコピー（まだ無い場合だけ）
  Future<void> copyAssetCsvIfNotExists() async {
    print('🧪 初期CSVコピー処理を強制実行');

    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/HappinessLevelDB1_v2.csv';
      final file = File(filePath);

      if (await file.exists()) {
        print('📄 CSVファイルは既に存在しています: $filePath');
        return;
      }

      print('📄 CSVファイルが存在しません。assets からコピーします');
      final csvAsset = await rootBundle.loadString(
          'assets/HappinessLevelDB1_v2.csv');
      await file.writeAsString(csvAsset);
      print('✅ 初期CSVコピー完了: $filePath');
    } catch (e) {
      print('❌ 初期CSVコピー中にエラーが発生: $e');
    }
  }

  static List<List<String>> _robustCsvParse(String raw) {
    List<List<dynamic>> tmp = const CsvToListConverter(eol: '\n').convert(raw);

    List<List<String>> sanitize(List<List<dynamic>> rows) =>
        rows
            .where((r) =>
        r.isNotEmpty && r.any((c) =>
        c
            .toString()
            .trim()
            .isNotEmpty))
            .map((r) =>
            r
                .map((e) =>
                e
                    .toString()
                    .replaceAll('"', '') // ← ★ 追加
                    .trim())
                .toList())
            .toList();

    if (tmp.length > 1) return sanitize(tmp);

    // フォールバック
    return sanitize(LineSplitter.split(raw)
        .where((l) =>
    l
        .trim()
        .isNotEmpty)
        .map((l) => l.split(','))
        .toList());
  }

  /// アプリ内で共通で使う正しいヘッダー
// CSVヘッダーを外部で使えるように公開
  static const List<String> _header = [

    '日付',
    '幸せ感レベル',
    'ストレッチ時間',
    'ウォーキング時間',
    '睡眠の質',
    '睡眠時間（時間換算）',
    '睡眠時間（分換算）',
    '睡眠時間（時間）',
    '睡眠時間（分）',
    '寝付き満足度',
    '深い睡眠感',
    '目覚め感',
    'モチベーション',
    '感謝数',
    '感謝1',
    '感謝2',
    '感謝3',
    'memo', // ← 追加
  ];

// 外部に公開する getter
  static List<String> get header => _header;

  static const _expectedLen = 18; // ← 変更

/*───────────────────────────────────────────────
  assets ➜ DocumentDirectory へ初期 CSV を撒く
───────────────────────────────────────────────*/
  Future<void> ensureCsvSeeded(String filename) async {
    print('🟢 ensureCsvSeeded: called for $filename'); // <- リリースでも出力される
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');

    if (!await file.exists()) {
      print('📦 assets から $filename をコピー開始');
      try {
        final data = await rootBundle.loadString('assets/$filename');
        await file.writeAsString(data);
        print('✅ コピー成功: ${file.path}');
      } catch (e) {
        print('❌ assets からのコピー失敗: $e');
      }
    } else {
      if (kCsvVerbose) debugPrint('ℹ️ 既にファイル存在: ${file.path}');
    }
  }


/*───────────────────────────────────────────────
/// ① DocumentDirectory の最新 CSV を取得（壊れていても復旧）
───────────────────────────────────────────────*/
  // ★ force を追加（既存呼び出しはそのまま動きます）
  static Future<List<List<String>>> loadLatestCsvData(
      String filename, { bool force = false }
      ) async {

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');

      if (!await file.exists()) {
        debugPrint('📄 ファイルが存在しません: ${file.path}');
        // ✅ リリースモードでも assets からコピー
        debugPrint('📦 assets から $filename をコピー開始（モード問わず）');
        final assetData = await rootBundle.loadString('assets/$filename');
        await file.writeAsString(assetData);
        debugPrint('✅ assets から $filename をコピー完了: ${file.path}');
      } else {
        if (kCsvVerbose) debugPrint('ℹ️ 既にファイル存在: ${file.path}');
        // ✅ バックアップを取る（同じ内容でもOK）
        final backupFile = File('${file.path}.bak');
        await backupFile.writeAsString(await file.readAsString());
        if (kCsvVerbose) debugPrint('🗂️ バックアップ作成: ${backupFile.path}');
      }

      // ① 読み込み + パース（空行除外付き）
      final raw = await file.readAsString();
      final data = _robustCsvParse(raw);
      if (data.isEmpty) {
        // 空ならヘッダーのみ返す
        final fixedRows = <List<String>>[List<String>.from(_header)];
        debugPrint("📄 読み込んだCSV内容(空扱い): $fixedRows");
        debugPrint('✅ loadLatestCsvData rows = ${fixedRows.length}');
        return fixedRows;
      }

      // ② データ行が無ければヘッダーのみ返す
      if (data.length <= 1) {
        debugPrint('⚠️ データ行が無いため、再コピーせず空データとして扱います');
        final fixedRows = <List<String>>[List<String>.from(_header)];
        debugPrint("📄 読み込んだCSV内容(ヘッダーのみ): $fixedRows");
        debugPrint('✅ loadLatestCsvData rows = ${fixedRows.length}');
        return fixedRows;
      }

      // ==== ここから “固定ヘッダーに名前で合わせて再マッピング” ====

      // 固定ヘッダー（出力の列順）
      final targetHeader = List<String>.from(_header);

      // 元CSVの実ヘッダー（読み取ったまま）
      final srcHeader = data.first.map((e) => e.toString().trim()).toList();

      // 別名（表記ゆれ）対応マップ：左が固定ヘッダー、右が元CSVであり得る別名たち
      final Map<String, List<String>> aliases = {
        '日付': ['日付', 'date', 'Date'],
        '幸せ感レベル': ['幸せ感レベル', 'score', 'スコア'],
        'ストレッチ時間': ['ストレッチ時間', 'ストレッチ', 'stretch', 'ストレッチ(分)'],
        'ウォーキング時間': ['ウォーキング時間', 'ウォーキング', 'walk', 'ウォーキング(分)'],
        '睡眠の質': ['睡眠の質', 'sleep_score', '睡眠スコア'],
        '睡眠時間（時間換算）': ['睡眠時間（時間換算）', '睡眠時間(時間換算)', '睡眠(時間)'],
        '睡眠時間（分換算）': ['睡眠時間（分換算）', '睡眠時間(分換算)', '睡眠(分)'],
        '睡眠時間（時間）': ['睡眠時間（時間）', '睡眠時間(時間)'],
        '睡眠時間（分）': ['睡眠時間（分）', '睡眠時間(分)'],
        '寝付き満足度': ['寝付き満足度', '寝つき満足度', '寝付きの満足度'],
        '深い睡眠感': ['深い睡眠感', '深い睡眠'],
        '目覚め感': ['目覚め感', '目ざめ感'],
        'モチベーション': ['モチベーション', 'motivation'],
        '感謝数': ['感謝数', 'gratitude_count'],
        '感謝1': ['感謝1', 'gratitude1'],
        '感謝2': ['感謝2', 'gratitude2'],
        '感謝3': ['感謝3', 'gratitude3'],
        'memo': ['memo', 'メモ', 'ひとことメモ', '今日のひとことメモ'],
      };

      // ヘルパ：固定名→srcHeader上のインデックス
      int findSrcIndex(String canonical) {
        final candidates = aliases[canonical] ?? [canonical];
        for (final name in candidates) {
          final idx = srcHeader.indexOf(name);
          if (idx >= 0) return idx;
        }
        return -1; // 見つからない
      }

      // ヘルパ：yyyy/MM/dd へ正規化
      String normalizeYmd(String raw) {
        final s = raw.trim().replaceAll('-', '/');
        final p = s.split('/');
        if (p.length != 3) return raw.trim();
        final y = p[0].padLeft(4, '0');
        final m = p[1].padLeft(2, '0');
        final d = p[2].padLeft(2, '0');
        return '$y/$m/$d';
      }

      // ③ 固定ヘッダー + 再マッピングした行を構築
      final fixedRows = <List<String>>[];
      fixedRows.add(targetHeader);

      for (var i = 1; i < data.length; i++) {
        final row = data[i].map((e) => e.toString()).toList();
        final outRow = <String>[];

        for (final colName in targetHeader) {
          final srcIdx = findSrcIndex(colName);
          final val = (srcIdx >= 0 && srcIdx < row.length) ? row[srcIdx] : '';
          outRow.add(val);
        }

        // 日付（列0）をゼロ詰め・区切り統一
        if (outRow.isNotEmpty && outRow[0].trim().isNotEmpty) {
          outRow[0] = normalizeYmd(outRow[0]);
        }

        fixedRows.add(outRow);
      }

      // （古い挙動との互換が必要なら）長さを合わせるが、通常は targetHeader 長に揃っている
      if (_expectedLen != null && _expectedLen > 0) {
        for (var i = 0; i < fixedRows.length; i++) {
          final row = fixedRows[i];
          if (row.length < _expectedLen) {
            row.addAll(List.filled(_expectedLen - row.length, ''));
          } else if (row.length > _expectedLen) {
            fixedRows[i] = row.sublist(0, _expectedLen);
          }
        }
      }

      // debugPrint("📄 読み込んだCSV内容: $fixedRows");
      // debugPrint('✅ loadLatestCsvData rows = ${fixedRows.length}');
      return fixedRows;
    } catch (e, st) {
      debugPrint('❌ CSV 読み込み失敗: $e');
      debugPrintStack(stackTrace: st);
      return [];
    }
  }



  /// --------------------------------------------------
  /// ② assets 直読み（旧 loadCsvAsStringMatrix 互換）
  /// --------------------------------------------------
  Future<List<List<String>>> loadCsvAsStringMatrix(String assetPath) async =>
      loadCsvFromAssets(assetPath);

  static Future<List<List<String>>> loadCsvFromAssets(String assetPath) async {
    final raw = await rootBundle.loadString('assets/$assetPath');
    return _robustCsvParse(raw);
  }


/*───────────────────────────────────────────────
  FileSystem 読み込み（行列 → String 化・空行除外）
───────────────────────────────────────────────*/
  Future<List<List<String>>> loadCsvFromFileSystem(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');

    if (!await file.exists()) return [];

    final raw = await file.readAsString();
    return _robustCsvParse(raw);
  }

  /// --------------------------------------------------
  /// ④ Map 形式で欲しい場合（TipsScreen 等の互換性）
  /// --------------------------------------------------
  static Future<List<Map<String, String>>> loadCsvAsMapList(
      String assetPath) async {
    final matrix = await CsvLoader.loadCsvFromAssets(assetPath);
    return toMapList(matrix);
  }

  static List<Map<String, String>> toMapList(List<List<String>> matrix) {
    if (matrix.isEmpty) return [];

    final header = matrix.first.map((h) => h.trim()).toList();
    return matrix.skip(1).map((row) {
      final padded = row.length < header.length
          ? [...row, ...List.filled(header.length - row.length, '')]
          : row.sublist(0, header.length);
      return Map<String, String>.fromIterables(header, padded);
    }).toList();
  }


  static Future<bool> restoreCsvFromBackup(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      final backupFile = File('${dir.path}/$filename.bak');

      if (!await backupFile.exists()) return false;

      await backupFile.copy(file.path);
      return true;
    } catch (e) {
      print('Failed to restore CSV from backup: $e');
      return false;
    }
  }

  // ===============================
  // AIコメント履歴バックアップ関連
  // ===============================

  static const List<String> _aiCommentLogHeader = <String>[
    'date',
    'type',
    'comment',
    'score',
    'sleep',
    'walk',
    'gratitude1',
    'gratitude2',
    'gratitude3',
    'memo',
  ];

  static String _aiCommentHeaderLine() {
    return _aiCommentLogHeader.join(',');
  }

  static Future<File> getAiCommentBackupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/ai_comment_log_backup.csv');

    if (!(await file.exists())) {
      await file.create(recursive: true);
      await file.writeAsString('${_aiCommentHeaderLine()}\n', flush: true);
    } else {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        await file.writeAsString('${_aiCommentHeaderLine()}\n', flush: true);
      }
    }

    return file;
  }

  static bool _looksBrokenAiLogText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return true;

    try {
      final rows = const CsvToListConverter().convert(raw, eol: '\n');
      if (rows.isEmpty) return true;

      final headers = rows.first
          .map((e) => e.toString().replaceAll('\uFEFF', '').trim().toLowerCase())
          .toList();

      final hasDate = headers.contains('date');
      final hasType = headers.contains('type');
      final hasComment = headers.contains('comment');

      if (!hasDate || !hasType || !hasComment) {
        return true;
      }

      return false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> backupAiCommentLogBeforeWrite() async {
    try {
      final src = await getAiCommentLogFile();
      final dst = await getAiCommentBackupFile();

      if (!await src.exists()) return;

      final raw = await src.readAsString();
      if (_looksBrokenAiLogText(raw)) {
        debugPrint('⚠️ backupAiCommentLogBeforeWrite skipped: source looks broken');
        return;
      }

      await dst.writeAsString(raw, flush: true);
      debugPrint('✅ AI comment log pre-write backup saved: ${dst.path}');
    } catch (e, st) {
      debugPrint('❌ backupAiCommentLogBeforeWrite failed: $e');
      debugPrint('$st');
    }
  }

  static Future<void> backupAiCommentLogAfterWrite() async {
    try {
      final src = await getAiCommentLogFile();
      final dst = await getAiCommentBackupFile();

      if (!await src.exists()) return;

      final raw = await src.readAsString();
      if (_looksBrokenAiLogText(raw)) {
        debugPrint('⚠️ backupAiCommentLogAfterWrite skipped: source looks broken');
        return;
      }

      await dst.writeAsString(raw, flush: true);
      debugPrint('✅ AI comment log backup updated: ${dst.path}');
    } catch (e, st) {
      debugPrint('❌ backupAiCommentLogAfterWrite failed: $e');
      debugPrint('$st');
    }
  }

  static Future<bool> restoreAiCommentLogFromBackup() async {
    try {
      final logFile = await getAiCommentLogFile();
      final backupFile = await getAiCommentBackupFile();

      if (!await backupFile.exists()) return false;

      final raw = await backupFile.readAsString();
      if (_looksBrokenAiLogText(raw)) {
        debugPrint('⚠️ restoreAiCommentLogFromBackup: backup also looks broken');
        return false;
      }

      await logFile.writeAsString(raw, flush: true);
      debugPrint('✅ AI comment log restored from backup');
      return true;
    } catch (e, st) {
      debugPrint('❌ restoreAiCommentLogFromBackup failed: $e');
      debugPrint('$st');
      return false;
    }
  }

  static Future<String> _readAiCommentLogRawWithFallback() async {
    final logFile = await getAiCommentLogFile();

    if (await logFile.exists()) {
      final raw = await logFile.readAsString();
      if (!_looksBrokenAiLogText(raw)) {
        return raw;
      }
      debugPrint('⚠️ ai_comment_log.csv looks broken. Trying backup...');
    }

    final backupFile = await getAiCommentBackupFile();
    if (await backupFile.exists()) {
      final backupRaw = await backupFile.readAsString();
      if (!_looksBrokenAiLogText(backupRaw)) {
        debugPrint('✅ backup ai_comment_log loaded successfully');
        return backupRaw;
      }
    }

    return '${_aiCommentHeaderLine()}\n';
  }



  static String _normalizeAiLogDate(String s) {
    final t = s.replaceAll('\uFEFF', '').trim();
    final m = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$').firstMatch(t);
    if (m == null) return '';
    final y = m.group(1)!;
    final mo = m.group(2)!.padLeft(2, '0');
    final d = m.group(3)!.padLeft(2, '0');
    return '$y/$mo/$d';
  }

  static bool _isValidAiLogType(String s) {
    final t = s.trim().toLowerCase();
    return t == 'daily' || t == 'weekly' || t == 'monthly';
  }

  static List<Map<String, String>> _normalizeAiCommentRows(
      List<Map<String, String>> rows,
      ) {
    final out = <Map<String, String>>[];

    for (final r in rows) {
      final date = _normalizeAiLogDate(r['date'] ?? '');
      final type = (r['type'] ?? '').trim().toLowerCase();

      if (date.isEmpty) continue;
      if (!_isValidAiLogType(type)) continue;

      out.add(<String, String>{
        'date': date,
        'type': type,
        'comment': (r['comment'] ?? '').toString(),
        'score': (r['score'] ?? '').toString(),
        'sleep': (r['sleep'] ?? '').toString(),
        'walk': (r['walk'] ?? '').toString(),
        'gratitude1': (r['gratitude1'] ?? '').toString(),
        'gratitude2': (r['gratitude2'] ?? '').toString(),
        'gratitude3': (r['gratitude3'] ?? '').toString(),
        'memo': (r['memo'] ?? '').toString(),
      });
    }

    out.sort((a, b) {
      final da = a['date']!;
      final db = b['date']!;
      final c = da.compareTo(db);
      if (c != 0) return c;

      const order = <String, int>{
        'daily': 0,
        'weekly': 1,
        'monthly': 2,
      };
      return (order[a['type']] ?? 99).compareTo(order[b['type']] ?? 99);
    });

    return out;
  }

  static Future<int> repairAiCommentLog() async {
    final rows = await loadAiCommentLog();
    final normalized = _normalizeAiCommentRows(rows);
    await writeAiCommentLog(normalized);
    return normalized.length;
  }




  static Future<File> getAiCommentLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/ai_comment_log.csv');

    if (!(await file.exists())) {
      await file.create(recursive: true);
      await file.writeAsString('${_aiCommentHeaderLine()}\n', flush: true);
    } else {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        await file.writeAsString('${_aiCommentHeaderLine()}\n', flush: true);
      }
    }

    return file;
  }





  // ✅ 追加: 指定日付・種別のAIコメントを読み込む
  static Future<Map<String, String>?> loadSavedComment(DateTime date, String type) async {
    final file = await getAiCommentLogFile();
    if (!await file.exists()) return null;

    final rows = const CsvToListConverter().convert(await file.readAsString(), eol: '\n');
    if (rows.length < 2) return null;

    // 正規化したヘッダーを作る
    final rawHeaders = rows[0].map((e) => e.toString()).toList();
    final headers = rawHeaders.map(_norm).toList();

    // 列位置（見つからなければ 0=日付,1=type,2=comment をフォールバック）
    final dateIndex    = _idx(headers, 'date', 0);
    final typeIndex    = _idx(headers, 'type', 1);
    final commentIndex = _idx(headers, 'comment', 2);

    final targetDate = DateFormat('yyyy/MM/dd').format(date);
    final targetType = type.trim().toLowerCase();

    for (int i = rows.length - 1; i >= 1; i--) {
      final row = rows[i];
      if (row.length <= commentIndex) continue;
      final savedDate = row[dateIndex].toString().trim();
      final savedType = row[typeIndex].toString().trim().toLowerCase();
      if (savedDate == targetDate && savedType == targetType) {
        return {
          'date': savedDate,
          'comment': row[commentIndex].toString(),
        };
      }
    }
    return null;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }





  // CSV → List<Map> 変換（オプション）
  static Future<List<Map<String, String>>> loadAiCommentLog() async {
    String raw = await _readAiCommentLogRawWithFallback();

    List<List<dynamic>> rows =
    const CsvToListConverter().convert(raw, eol: '\n');

    // CSV破損チェック → backupから自動復旧
    if (rows.length <= 1) {
      final file = await getAiCommentLogFile();
      final backup = await getAiCommentBackupFile();

      if (await backup.exists()) {
        final backupText = await backup.readAsString();

        if (backupText.trim().isNotEmpty) {
          final backupRows =
          const CsvToListConverter().convert(backupText, eol: '\n');

          if (backupRows.length > 1) {
            await file.writeAsString(backupText, flush: true);
            debugPrint('⚠️ AI comment log restored from backup');

            raw = backupText;
            rows = backupRows;
          }
        }
      }
    }

    if (rows.length <= 1) {
      return <Map<String, String>>[];
    }

    final headers = rows.first
        .map((e) => e.toString().replaceAll('\uFEFF', '').trim().toLowerCase())
        .toList();

    final parsed = rows.skip(1).map((row) {
      final values = row.map((e) => e.toString()).toList();

      final List<String> padded = <String>[];
      if (values.length < headers.length) {
        padded.addAll(values);
        padded.addAll(List<String>.filled(headers.length - values.length, ''));
      } else {
        padded.addAll(values.sublist(0, headers.length));
      }

      final m = Map<String, String>.fromIterables(headers, padded);

      if (m.containsKey('comment')) {
        m['comment'] = CsvLoader.sanitizeCommentForDisplay(m['comment'] ?? '');
      }

      return m;
    }).toList();

    return _normalizeAiCommentRows(parsed);
  }


  /// AIコメントをCSVに1行ずつ追記する
  /// AIコメントをCSVに1行ずつ追記する
  static Future<void> appendAiCommentLog({
    required String date,
    required String type,
    required String comment,
    required String score,
    required String sleep,
    required String walk,
    required String gratitude1,
    required String gratitude2,
    required String gratitude3,
    required String memo,
  }) async {
    final normalizedDate = _normalizeAiLogDate(date);
    final normalizedType = type.trim().toLowerCase();

    if (normalizedDate.isEmpty) {
      debugPrint('⚠️ appendAiCommentLog skipped: invalid date="$date"');
      return;
    }
    if (!_isValidAiLogType(normalizedType)) {
      debugPrint('⚠️ appendAiCommentLog skipped: invalid type="$type"');
      return;
    }

    final rows = await loadAiCommentLog();

    rows.add(<String, String>{
      'date': normalizedDate,
      'type': normalizedType,
      'comment': comment,
      'score': score,
      'sleep': sleep,
      'walk': walk,
      'gratitude1': gratitude1,
      'gratitude2': gratitude2,
      'gratitude3': gratitude3,
      'memo': memo,
    });

    await writeAiCommentLog(_normalizeAiCommentRows(rows));
  }

  // ===============================
  // ⭐ Favorite Words（お気に入りのあなたの言葉）
  // 保存先: Documents/favorite_words.csv
  // 形式: createdAt,date,text
  // ===============================

  static Future<File> getFavoriteWordsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'favorite_words.csv'));

    if (!await file.exists()) {
      await file.writeAsString('createdAt,date,text\n');
    } else {
      // ✅ 既存ファイルが壊れている可能性に備え、ヘッダーだけの時はそのままにする（何もしない）
    }

    return file;
  }

  static Future<void> appendFavoriteWord({
    required DateTime date,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final file = await getFavoriteWordsFile();
    final createdAt = DateTime.now().toIso8601String();
    final dateStr = DateFormat('yyyy/MM/dd').format(date);

    final safeText = trimmed.replaceAll('\n', ' ').replaceAll('\r', ' ');

    final csvLineRaw = const ListToCsvConverter(eol: '\n').convert([
      [createdAt, dateStr, safeText]
    ]);

// ✅ 末尾改行を必ず付与
    final csvLine = csvLineRaw.endsWith('\n') ? csvLineRaw : '$csvLineRaw\n';

    try {
      // ✅ もし末尾が改行で終わっていないファイルなら、先に改行を足してから append
      // （過去に "...\n2026-..." の行連結が起きると、CsvToListConverter が死にます）
      if (await file.exists()) {
        final len0 = await file.length();
        if (len0 > 0) {
          final raf = await file.open(mode: FileMode.read);
          try {
            // 最後の1バイトを見る
            await raf.setPosition(len0 - 1);
            final lastByte = await raf.readByte();
            if (lastByte != 10 /* \n */) {
              await file.writeAsString('\n', mode: FileMode.append);
            }
          } finally {
            await raf.close();
          }
        }
      }

      // ✅ 本体追記
      await file.writeAsString(csvLine, mode: FileMode.append, flush: true);

      // ✅ 念のため：書けたかチェック（長さが増えているか）
      final len = await file.length();
      if (len <= 'createdAt,date,text\n'.length) {
        throw Exception('favorite_words.csv length not increased');
      }
    } catch (_) {
      rethrow;
    }


    if (kDebugMode) {
      debugPrint('[fav] saved: $dateStr text="$safeText"');
      debugPrint('[fav] file: ${file.path}');
    }
  }


  // ✅ favorite_words.csv を安全に読み込む（カンマ/改行混入でも壊れにくい）
// 戻り値の型は、あなたの _items に入れている型に合わせてください。
// ここでは Map<String, String> で返します（createdAt/date/text）。
  static Future<List<Map<String, String>>> loadFavoriteWords() async {
    final file = await getFavoriteWordsFile();
    if (!await file.exists()) return [];

    final raw = await file.readAsString();
    final lines = raw.split('\n');

    final items = <Map<String, String>>[];

    for (final line in lines) {
      final s = line.trim();
      if (s.isEmpty) continue;
      if (s.startsWith('createdAt,')) continue;

      // ★ 先頭2カンマだけで分割
      final i1 = s.indexOf(',');
      if (i1 < 0) continue;
      final i2 = s.indexOf(',', i1 + 1);
      if (i2 < 0) continue;

      final createdAt = s.substring(0, i1).trim();
      final date = s.substring(i1 + 1, i2).trim();
      final text = s.substring(i2 + 1).trim();

      if (!createdAt.contains('T')) continue;

      items.add({
        'createdAt': createdAt,
        'date': date,
        'text': text,
      });
    }

    // 新しい順
    items.sort((a, b) => b['createdAt']!.compareTo(a['createdAt']!));
    return items;
  }


  static Future<void> deleteFavoriteWord({
    required String createdAt,
  }) async {
    final file = await getFavoriteWordsFile();
    if (!await file.exists()) return;

    final original = await file.readAsString();
    final rawLines = original.replaceAll('\r\n', '\n').split('\n');

    // ヘッダー維持（なければ付ける）
    const header = 'createdAt,date,text';
    final hasHeader = rawLines.isNotEmpty && rawLines.first.trim() == header;

    final out = <String>[header];
    bool removed = false;

    Iterable<String> dataLines = rawLines;
    if (hasHeader) dataLines = rawLines.skip(1);

    for (final line in dataLines) {
      final l = line.trimRight();
      if (l.isEmpty) continue;

      final firstComma = l.indexOf(',');
      if (firstComma <= 0) {
        // 壊れた行でも捨てない（そのまま残す）
        out.add(l);
        continue;
      }

      final id = l.substring(0, firstComma);
      if (id == createdAt) {
        removed = true;
        continue;
      }
      out.add(l);
    }

    if (!removed) return;

    final newText = out.join('\n') + '\n';

    // 念のためバックアップ（初回だけ）
    try {
      final bak = File(file.path + '.bak');
      if (!await bak.exists()) {
        await bak.writeAsString(original);
      }
    } catch (_) {
      // backup失敗は無視（削除本体を優先）
    }

    await file.writeAsString(newText, mode: FileMode.write);

    if (kDebugMode) {
      debugPrint('[fav] deleted: createdAt=$createdAt');
    }
  }

  static Future<void> repairFavoriteWordsCsvIfNeeded() async {
    final file = await getFavoriteWordsFile();
    const header = 'createdAt,date,text';

    if (!await file.exists()) {
      await file.writeAsString('$header\n', mode: FileMode.write);
      return;
    }

    final original = await file.readAsString();
    final normalized = original.replaceAll('\r\n', '\n');
    final rawLines = normalized.split('\n');

    // 空ファイルならヘッダーだけ
    if (rawLines.isEmpty || rawLines.every((l) => l.trim().isEmpty)) {
      await file.writeAsString('$header\n', mode: FileMode.write);
      return;
    }

    final hasHeader = rawLines.first.trim() == header;

    // 出力は必ずヘッダー付き
    final out = <String>[header];

    // 1行=1レコード前提。ただし途中改行で壊れていて
    // 「カンマが2つ未満の行」が出たら前行に結合して救済（捨てない）
    Iterable<String> dataLines = rawLines;
    if (hasHeader) dataLines = rawLines.skip(1);

    for (final line in dataLines) {
      final l = line.trimRight();
      if (l.isEmpty) continue;

      final commaCount = ','.allMatches(l).length;
      if (commaCount >= 2) {
        out.add(l);
      } else {
        // 壊れた行は前行に結合（前行が無ければそのまま追加）
        if (out.length >= 2) {
          out[out.length - 1] = out.last + ' ' + l;
        } else {
          out.add(l);
        }
      }
    }

    final newText = out.join('\n') + '\n';

    // 変更なしなら何もしない
    final current = (hasHeader ? normalized : '$header\n$normalized').replaceAll('\r\n', '\n');
    if (newText == current || newText == normalized) {
      return;
    }

    // 念のためバックアップ（初回だけ）
    try {
      final bak = File(file.path + '.bak');
      if (!await bak.exists()) {
        await bak.writeAsString(original);
      }
    } catch (_) {}

    await file.writeAsString(newText, mode: FileMode.write);

    if (kDebugMode) {
      debugPrint('[fav] repairFavoriteWordsCsvIfNeeded done');
    }
  }



// コメントの表示用サニタイズ
//  - 「追伸：メモの『（未入力）』、大切にできると良さそうです。」のような
//    ワンパターン文章を削る
  // AIコメント表示前のサニタイズ（履歴も含めてすべてここを通す）
  // 追伸の「（未入力）」行や古いテンプレの末尾を整理する
  static String sanitizeCommentForDisplay(String raw) {
    if (raw.isEmpty) return raw;

    var s = raw;

    // ▼パターン1: 「追伸：……（未入力）……」の行を丸ごと削除
    final pattern1 = RegExp(
      r'^\s*追伸：.*?（未入力）.*$',
      multiLine: true,
    );
    s = s.replaceAll(pattern1, '').trim();

    // ▼パターン2:
    // 「追伸：◯◯◯大切にできると良さそうです。」系を
    // 「追伸：◯◯◯。」に整形
    final pattern2 = RegExp(
      r'追伸：([^。]*?)大切にできると良さそうです。?',
      multiLine: true,
    );

    s = s.replaceAllMapped(pattern2, (match) {
      var before = match.group(1)?.trim() ?? '';

      // 末尾が「、」「。」で終わっていたら一度削る
      before = before.replaceAll(RegExp(r'[、。]+$'), '');

      if (before.isEmpty) {
        // 何も残らなければ追伸行ごと消す
        return '';
      }

      // 「追伸：◯◯。」という形に統一
      return '追伸：$before。';
    }).trim();

    // ▼パターン3: 古い「追伸：メモの「◯◯◯」。」形式を自然な文にする
    final pattern3 = RegExp(
      r'追伸：メモの「([^」]+)」。?',
      multiLine: true,
    );
    s = s.replaceAllMapped(pattern3, (m) {
      final cue = (m.group(1) ?? '').trim();
      if (cue.isEmpty) {
        // メモが空っぽの場合は追伸まるごと削除
        return '';
      }
      return '追伸：メモの「$cue」、大事な視点ですね。';
    }).trim();

    return s;
  }






  static Future<bool> isCommentAlreadySaved({
    required String date, // 'YYYY/MM/DD'
    required String type, // 'daily' | 'weekly' | 'monthly'
  }) async {
    final file = await getAiCommentLogFile();
    if (!await file.exists()) return false;

    final rows = const CsvToListConverter().convert(
      await file.readAsString(),
      eol: '\n',
    );

    bool isTransient(String text) {
      final t = text.trim();
      if (t.isEmpty) return true;
      return t.startsWith('⚠') || t.contains('タイムアウト') || t.contains('通信');
    }

    // 末尾（新しい方）から探す：同日重複時も安全
    for (int i = rows.length - 1; i >= 1; i--) {
      final row = rows[i];
      if (row.length < 3) continue;

      final d = row[0].toString().trim();
      final ty = row[1].toString().trim().toLowerCase();
      final comment = row[2].toString();

      if (d == date && ty == type.toLowerCase()) {
        // ★ ⚠️系は「保存済み」にしない（再生成できるようにする）
        if (isTransient(comment)) return false;
        return true;
      }
    }
    return false;
  }







  static Future<String?> getSavedCommentLatest({
    required String date,
    required String type,
  }) async {
    final file = await getAiCommentLogFile();
    if (!await file.exists()) return null;

    // 末尾(=新しい)から探すことで同日重複時に“最後勝ち”
    final rows = const CsvToListConverter().convert(await file.readAsString(), eol: '\n');
    for (int i = rows.length - 1; i >= 1; i--) {
      final row = rows[i];
      if (row.length >= 3 &&
          row[0].toString().trim() == date &&
          row[1].toString().trim() == type) {
        return row[2].toString();
      }
    }
    return null;
  }
// CSVをList<Map<String, String>>形式で読み込む（ヘッダーあり）
  //CSVの全行（ヘッダー以外）を「列名 → 値」のマップ形式で扱えるようにする
  static Future<List<Map<String, String>>> loadCsvAsMaps(File file) async {
    final content = await file.readAsLines();
    if (content.length < 2) return [];

    final headers = content.first.split(',');
    return content.skip(1).map((line) {
      final values = line.split(',');
      return Map.fromIterables(headers, values);
    }).toList();
  }

  static Future<DateTime?> getLatestDate(File file) async {
    if (!await file.exists()) return null;
    final rows = await file.readAsLines();
    final dateFormat = DateFormat('yyyy/MM/dd');
    List<DateTime> dates = [];

    for (final line in rows.skip(1)) {
      final values = line.split(',');
      try {
        final date = dateFormat.parse(values[0]);
        dates.add(date);
      } catch (_) {}
    }

    dates.sort((a, b) => b.compareTo(a));
    return dates.isNotEmpty ? dates.first : null;
  }

  static Future<bool> hasDataForDate(DateTime date) async {
    final rows = await loadCsvRows();
    final targetDateStr = DateFormat('yyyy/MM/dd').format(date);
    return rows.any((row) => row.isNotEmpty && row[0] == targetDateStr);
  }


  // CSV全行取得
  static Future<List<List<String>>> loadCsvRows() async {
    // ❷ これなら存在しなくても自動配置→読み込み
    return await loadLatestCsvData('HappinessLevelDB1_v2.csv');
  }

// 指定日付のデータのみ取得（DateTime引数対応）
  static Future<List<List<String>>> loadCsvDataForDate(DateTime date) async {
    final rows = await loadCsvRows();
    final dateStr = DateFormat('yyyy/MM/dd').format(date);
    return rows.where((row) => row.isNotEmpty && row[0] == dateStr).toList();
  }

  static Future<List<String>> loadGratitudeForDate(DateTime date) async {
    final rows = await loadCsvRows();
    final targetDateStr = DateFormat('yyyy/MM/dd').format(date);
    for (final row in rows) {
      if (row.isNotEmpty && row[0] == targetDateStr) {
        return [row[14], row[15], row[16]];
      }
    }
    return [];
  }
  static Future<String> loadHappinessScoreForDate(DateTime date) async {
    final rows = await loadCsvRows();
    final targetDateStr = DateFormat('yyyy/MM/dd').format(date);
    for (final row in rows) {
      if (row.isNotEmpty && row[0] == targetDateStr) {
        return row[1];
      }
    }
    return '';
  }
  // レーダーは「睡眠の質 / ウォーキング時間 / ストレッチ時間 / 感謝数」
  static Future<List<double>> loadRadarScoresForDate(DateTime date) async {
    final rows = await loadCsvRows();
    final targetDateStr = DateFormat('yyyy/MM/dd').format(date);
    for (final row in rows) {
      if (row.isNotEmpty && row[0] == targetDateStr) {
        return [
          double.tryParse(row[4]) ?? 0.0, // 睡眠の質
          double.tryParse(row[3]) ?? 0.0, // ウォーキング
          double.tryParse(row[2]) ?? 0.0, // ストレッチ
        //  double.tryParse(row[13]) ?? 0.0, // 感謝件数
        ];
      }
    }
    return [];
  }

  /// {date, type, comment, ...} をキー(date+type)でUPSERTする
  /// {date, type, comment, ...} をキー(date+type)でUPSERTする
  static Future<void> upsertAiCommentLog(Map<String, String> row) async {
    final all = await loadAiCommentLog();

    final String keyDate = _normalizeAiLogDate(row['date'] ?? '');
    final String keyType = (row['type'] ?? '').trim().toLowerCase();

    if (keyDate.isEmpty) {
      debugPrint('⚠️ upsertAiCommentLog skipped: invalid date="${row['date']}"');
      return;
    }
    if (!_isValidAiLogType(keyType)) {
      debugPrint('⚠️ upsertAiCommentLog skipped: invalid type="${row['type']}"');
      return;
    }

    final List<Map<String, String>> filtered = all.where((r) {
      final existingDate = _normalizeAiLogDate(r['date'] ?? '');
      final existingType = (r['type'] ?? '').trim().toLowerCase();
      return existingDate != keyDate || existingType != keyType;
    }).toList();

    final Map<String, String> normalizedRow = <String, String>{
      'date': keyDate,
      'type': keyType,
      'comment': (row['comment'] ?? '').toString(),
      'score': (row['score'] ?? '').toString(),
      'sleep': (row['sleep'] ?? '').toString(),
      'walk': (row['walk'] ?? '').toString(),
      'gratitude1': (row['gratitude1'] ?? '').toString(),
      'gratitude2': (row['gratitude2'] ?? '').toString(),
      'gratitude3': (row['gratitude3'] ?? '').toString(),
      'memo': (row['memo'] ?? '').toString(),
    };

    filtered.add(normalizedRow);

    await writeAiCommentLog(_normalizeAiCommentRows(filtered));
  }

  
  // 小文字ヘッダのAIコメントログ（date,type,comment,score,sleep,walk,gratitude1,gratitude2,gratitude3,memo）
  // 小文字ヘッダのAIコメントログ（date,type,comment,score,sleep,walk,gratitude1,gratitude2,gratitude3,memo）
  static Future<void> saveAiCommentLog(List<Map<String, String>> rows) async {
    final file = await getAiCommentLogFile();
    await file.parent.create(recursive: true);

    await backupAiCommentLogBeforeWrite();

    final normalizedRows = _normalizeAiCommentRows(rows);

    final List<List<dynamic>> data = <List<dynamic>>[
      _aiCommentLogHeader,
      ...normalizedRows.map((r) {
        return _aiCommentLogHeader.map((h) {
          return (r[h] ?? '').toString();
        }).toList();
      }),
    ];

    final String csvText = const ListToCsvConverter().convert(data);
    await file.writeAsString(csvText, flush: true);

    await backupAiCommentLogAfterWrite();
  }

// 完全一致でその日を返す。無ければ null
  static Map<String, String>? findRowByDateExact(
      List<Map<String, String>> rows,
      DateTime date,
      ) {
    final target = DateFormat('yyyy/MM/dd').format(date);
    try {
      return rows.firstWhere(
            (r) => (r['日付'] ?? '').trim() == target,
      );
    } catch (_) {
      return null;
    }
  }
  /// メインCSV: 「日付に完全一致する1行」を返す（無ければ null）
  /// rows: List<List<dynamic>> 形式（先頭行にヘッダー想定）
  static Map<String, String>? getRowByExactDate(List<List<dynamic>> rows, DateTime d) {
    final target = DateFormat('yyyy/MM/dd').format(d);
    if (rows.isEmpty) return null;

    final header = rows.first.map((e) => e.toString()).toList();
    final idxDate = header.indexOf('日付');
    if (idxDate < 0) return null;

    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (idxDate < r.length && r[idxDate].toString().trim() == target) {
        // Map<String, String> に揃える
        final m = <String, String>{};
        for (int c = 0; c < header.length && c < r.length; c++) {
          m[header[c]] = r[c].toString();
        }
        return m;
      }
    }
    return null;
  }
// 小文字ヘッダのAIコメントログを上書き保存するユーティリティ
// 受け取り: rows = List<Map<String,String>>  （キーは 'date','type','comment',...）
  static Future<void> writeAiCommentLog(List<Map<String, String>> rows) async {
    if (_isWritingAiCommentLog) {
      debugPrint('⚠️ writeAiCommentLog skipped: already writing');
      return;
    }

    _isWritingAiCommentLog = true;

    try {
      final file = await getAiCommentLogFile();
      await file.parent.create(recursive: true);

      await backupAiCommentLogBeforeWrite();

      final normalizedRows = _normalizeAiCommentRows(rows);

      final List<List<dynamic>> data = <List<dynamic>>[
        _aiCommentLogHeader,
        ...normalizedRows.map((r) {
          return _aiCommentLogHeader.map((h) {
            return (r[h] ?? '').toString();
          }).toList();
        }),
      ];

      final String csvText = const ListToCsvConverter().convert(data);
      await file.writeAsString(csvText, flush: true);

      await backupAiCommentLogAfterWrite();
    } finally {
      _isWritingAiCommentLog = false;
    }
  }

  Future<List<Map<String, dynamic>>> loadDailyRecordsInRange(
      DateTime start, DateTime end,
      ) async {
    final file = await CsvLoader.getAiCommentLogFile();
    final rows = await CsvLoader.loadCsvAsMaps(file);


 //   final file = await getCsvFile();
// final rows = await loadCsv(file);
    final s = fmtYMD(asYMD(start));
    final e = fmtYMD(asYMD(end));
    return rows.where((r) {
      final raw = (r['date'] ?? '').toString().trim();
      if (raw.isEmpty) return false;
      final d = asYMD(parseYMD(raw));
      final ds = fmtYMD(d);
      return (ds.compareTo(s) >= 0) && (ds.compareTo(e) <= 0);
    }).toList();
  }


  /// Map<String,String> 行（通常の loadCsv の戻り）から感謝数を数える
  static int gratitudeCountFromMap(Map<String, String> m) {
    int c = 0;
    for (final k in const ['感謝1', '感謝2', '感謝3']) {
      if ((m[k] ?? '').trim().isNotEmpty) c++;
    }
    return c;
  }

// 末尾に追加
  /// 感謝数を「感謝1〜3の非空数」で再計算して返す（列の揺れにも強い）
  static int gratitudeCountFromRow(Map<String, String> row) {
    final g1 = (row['感謝1'] ?? row['gratitude1'] ?? '').trim();
    final g2 = (row['感謝2'] ?? row['gratitude2'] ?? '').trim();
    final g3 = (row['感謝3'] ?? row['gratitude3'] ?? '').trim();
    return [g1, g2, g3].where((s) => s.isNotEmpty).length;
  }

  /// 指定日の行を読み、gratitudeCountFromRow で再計算して返す
  static Future<int> loadGratitudeCountForDate(DateTime date) async {
    final f = DateFormat('yyyy/MM/dd');
    final rows = await loadCsv('HappinessLevelDB1_v2.csv');
    final target = rows.firstWhere(
          (r) => (r['日付'] ?? '').trim() == f.format(date),
      orElse: () => <String, String>{},
    );
    if (target.isEmpty) return 0;
    return gratitudeCountFromRow(target);
  }
// utils/csv_loader.dart のクラス内に追加
  static List<dynamic>? pickBestRowForDate(
      List<List<dynamic>> rows,
      String ymd, // 'YYYY/MM/DD'
      ) {
    if (rows.isEmpty) return null;
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final memoIdx = header.indexOf('memo');

    List<dynamic>? candidate;
    for (final raw in rows.skip(1)) {
      final r = raw.map((e) => e?.toString() ?? '').toList();
      if (r.isEmpty) continue;
      if (r[0].toString().trim() != ymd) continue;
      if (candidate == null) {
        candidate = r;
      } else if (memoIdx >= 0) {
        final curHasMemo = candidate.length > memoIdx && candidate[memoIdx].toString().trim().isNotEmpty;
        final newHasMemo = r.length > memoIdx && r[memoIdx].toString().trim().isNotEmpty;
        if (!curHasMemo && newHasMemo) candidate = r;
      }
    }
    return candidate;
  }
// 例: CsvLoader クラス内に追記
  static String _normDateStr(String s) {
    final t = s.trim().replaceAll('-', '/');
    final p = t.split('/');
    if (p.length != 3) return s.trim();
    return '${p[0].padLeft(4,'0')}/${p[1].padLeft(2,'0')}/${p[2].padLeft(2,'0')}';
  }

  /// 入力: 任意の列名Map（ja/en混在OK）
  /// 出力: 仕様で固定した“正規化キー”のMap
  ///   date, score, stretch, walk, sleep_quality, sleep_h, sleep_m,
  ///   fall_asleep, deep_sleep, wake_feel, motivation,
  ///   gratitude_count, gratitude1, gratitude2, gratitude3, memo
  static Map<String, String> normalizeRow(Map<String, String> row) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = row[k];
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    final m = <String, String>{
      'date'            : pick(['日付','date']),
      'score'           : pick(['幸せ感レベル','score']),
      'stretch'         : pick(['ストレッチ時間','stretch']),
      'walk'            : pick(['ウォーキング時間','walk']),
      'sleep_quality'   : pick(['睡眠の質','sleep_quality']),
      'sleep_h'         : pick(['睡眠時間（時間）','睡眠時間(時間)','睡眠時間（時）','sleep_h']),
      'sleep_m'         : pick(['睡眠時間（分）','睡眠時間(分)','sleep_m']),
      'fall_asleep'     : pick(['寝付き満足度','寝つき満足度','寝付きの満足度','fall_asleep']),
      'deep_sleep'      : pick(['深い睡眠感','deep_sleep']),
      'wake_feel'       : pick(['目覚め感','wake_feel']),
      'motivation'      : pick(['モチベーション','motivation']),
      'gratitude_count' : pick(['感謝数','gratitude_count']),
      'gratitude1'      : pick(['感謝1','gratitude1']),
      'gratitude2'      : pick(['感謝2','gratitude2']),
      'gratitude3'      : pick(['感謝3','gratitude3']),
      'memo'            : pick(['memo','メモ','今日のひとことメモ','one_line_memo']),
    };

    // 日付は yyyy/MM/dd に統一
    m['date'] = _normDateStr(m['date'] ?? '');

    // 感謝数は“空でない感謝の数”に再計算（0/1/2/3）
    final g1 = m['gratitude1']?.trim() ?? '';
    final g2 = m['gratitude2']?.trim() ?? '';
    final g3 = m['gratitude3']?.trim() ?? '';
    final cnt = [g1,g2,g3].where((e) => e.isNotEmpty).length;
    m['gratitude_count'] = cnt.toString();

    return m;
  }
// ★ 1) 実際に使っているCSVの状況をログ出力（デバッグ用）
  static Future<void> debugDumpActiveCsv() async {
    try {
      final file = await CsvLoader.getCsvFile(); // 既存の本番CSVファイル取得関数
      final exists = await file.exists();
      print('[CSV DEBUG] path=${file.path} exists=$exists');
      if (!exists) return;

      final stat = await file.stat();
      print('[CSV DEBUG] size=${stat.size} bytes modified=${stat.modified}');

      final raf = await file.open();
      final bytes = await raf.read(4096); // 先頭4KB
      await raf.close();
      final head = utf8.decode(bytes, allowMalformed: true);
      final lines = head.split(RegExp(r'\r?\n')).take(2).toList();
      print('[CSV DEBUG] first line: ${lines.isNotEmpty ? lines[0] : "(none)"}');
      print('[CSV DEBUG] second line: ${lines.length > 1 ? lines[1] : "(none)"}');
    } catch (e, st) {
      print('[CSV DEBUG] error: $e\n$st');
    }
  }

  /// 既存CSVに対して、取り込みCSVを「空で上書きしない」方針で安全マージします。
  /// - 既存に無い日付は新規追加
  /// - 既存にある日付はフィールド毎に非空優先（空文字は上書きしない）
  /// - 感謝数は 感謝1〜3 の非空件数から再計算
  /// - 最終的に公式ヘッダ順＆日付昇順で保存
  static Future<void> importCsvSafely(File pickedFile) async {
    // ★ 関数の先頭ログ（リクエストされた “開始ログ”）
    debugPrint('[IMPORT] importCsvSafely: begin file=${pickedFile.path}');

    // 1) 取り込むCSVを Map<List> に（列名ゆれに強い）
    final importedMaps = await loadCsvAsMaps(pickedFile);
    if (importedMaps.isEmpty) {
      debugPrint('[IMPORT] no rows in picked file');
      return;
    }

    // 2) 既存CSVを読み出して Map に（公式ヘッダ順に近づける）
    final existingMatrix = await loadLatestCsvData('HappinessLevelDB1_v2.csv');
    final existingHeader = existingMatrix.isNotEmpty
        ? existingMatrix.first.map((e) => e.toString()).toList()
        : header;
    final existingRows = <Map<String, String>>[];

    for (final row in existingMatrix.skip(1)) {
      final m = <String, String>{};
      for (int i = 0; i < existingHeader.length && i < row.length; i++) {
        m[existingHeader[i]] = row[i].toString();
      }
      final ymd = (m['日付'] ?? '').trim();
      if (ymd.isNotEmpty) {
        existingRows.add(m);
      }
    }

    // 3) 日付正規化ヘルパ（yyyy/MM/dd）
    String _normYmd(String s) {
      final t = s.trim();
      if (t.isEmpty) return '';
      final only = t.replaceAll(RegExp(r'[^0-9]'), '');
      if (only.length < 8) return t; // どうしても無理なら原文
      final y = only.substring(0, 4);
      final m = only.substring(4, 6);
      final d = only.substring(6, 8);
      return '$y/$m/$d';
    }

    // 4) 既存を日付キーで索引化
    final byDate = <String, Map<String, String>>{};
    for (final r in existingRows) {
      final key = _normYmd(r['日付'] ?? '');
      if (key.isEmpty) continue;
      byDate[key] = {
        for (final h in header) h: (r[h] ?? '').toString(),
        '日付': key,
      };
    }

    // 5) 取り込み側：正規化（あなたの normalizeRow を再利用）
    Map<String, String> _toCanon(Map<String, String> raw) {
      final n = normalizeRow(raw); // date, score, stretch, walk, sleep_quality, memo, gratitude1..3 など
      return <String, String>{
        '日付'                 : (n['date'] ?? '').toString(),
        '幸せ感レベル'         : (n['score'] ?? '').toString(),
        'ストレッチ時間'       : (n['stretch'] ?? '').toString(),
        'ウォーキング時間'     : (n['walk'] ?? '').toString(),
        '睡眠の質'             : (n['sleep_quality'] ?? '').toString(),
        '睡眠時間（時間換算）' : (n['sleep_h'] ?? '').toString(),
        '睡眠時間（分換算）'   : (n['sleep_m'] ?? '').toString(),
        '睡眠時間（時間）'     : (n['sleep_h'] ?? '').toString(),  // 旧列互換（残してOK）
        '睡眠時間（分）'       : (n['sleep_m'] ?? '').toString(),
        '寝付き満足度'         : (n['fall_asleep'] ?? '').toString(),
        '深い睡眠感'           : (n['deep_sleep'] ?? '').toString(),
        '目覚め感'             : (n['wake_feel'] ?? '').toString(),
        'モチベーション'       : (n['motivation'] ?? '').toString(),
        '感謝数'               : (n['gratitude_count'] ?? '').toString(),
        '感謝1'                : (n['gratitude1'] ?? '').toString(),
        '感謝2'                : (n['gratitude2'] ?? '').toString(),
        '感謝3'                : (n['gratitude3'] ?? '').toString(),
        'memo'                 : (n['memo'] ?? '').toString(),
      };
    }

    // 6) マージ規則（空文字で既存を潰さない／memo/感謝は情報量多い方）
    Map<String, String> _mergeRow(Map<String, String> base, Map<String, String> inc) {
      final out = Map<String, String>.from(base);
      for (final k in header) {
        final cur = (out[k] ?? '').trim();
        final add = (inc[k] ?? '').trim();
        if (add.isEmpty) {
          // 空は上書き禁止
          continue;
        }
        if (k == 'memo') {
          if (add.length > cur.length) out[k] = add;
        } else if (k == '感謝1' || k == '感謝2' || k == '感謝3') {
          if (cur.isEmpty || add.length > cur.length) out[k] = add;
        } else {
          if (cur.isEmpty) out[k] = add;
        }
      }
      // 感謝数を再計算
      out['感謝数'] = gratitudeCountFromRow(out).toString();
      return out;
    }

    // 7) 取り込みCSVを既存へ反映（空で上書きしない・未指定は触らない）
        for (final raw in importedMaps) {
          // 列名ゆれ→正規化（ja/en混在OK）
          final incCanon = _toCanon(raw);
          // 取り込み側の値で「null/''/'-'」はすべて空文字に統一しておく
          incCanon.updateAll((k, v) => _isEmptyCell(v) ? '' : v.trim());

          final ymd = _normYmd(incCanon['日付'] ?? '');
          if (ymd.isEmpty) continue;

          final exists = byDate.containsKey(ymd);
          if (!exists) {
            // 新規追加：公式ヘッダ順だけを埋め、空は ''（'-' は使わない）
            final added = <String, String>{ for (final h in header) h: (incCanon[h] ?? '') };
            added['日付'] = ymd;
            // 感謝数は感謝1〜3の非空件数から再計算
            added['感謝数'] = gratitudeCountFromRow(added).toString();
            byDate[ymd] = added;
            debugPrint('[IMPORT] add new $ymd');
            continue;
          }

          // 既存あり → フィールド単位で「空で上書きしない」マージ
          final dst = byDate[ymd]!;
          for (final key in header) {
            final incoming = (incCanon[key] ?? '');
            final current  = (dst[key] ?? '');
            dst[key] = _preferNonEmpty(current, incoming);
          }
          // 感謝数は感謝1〜3の内容から再計算（全て空のときだけ 0）
          dst['感謝数'] = gratitudeCountFromRow(dst).toString();
          debugPrint('[IMPORT] merge existing $ymd');
        }

    // 8) 日付昇順で整形→保存
    final dates = byDate.keys.toList()..sort();
    final rows = <List<String>>[List<String>.from(header)];
    for (final d in dates) {
      final m = byDate[d]!;
      rows.add(header.map((h) => (m[h] ?? '').toString()).toList());
    }

    final file = await getCsvFile();
    final csvText = const ListToCsvConverter().convert(rows);
    await file.writeAsString(csvText, flush: true);

    debugPrint('[IMPORT] importCsvSafely: done; rows=${rows.length - 1}');
  }
  /// 既存 ai_comment_log.csv を読み込み、comment をサニタイズして書き戻す（破壊的）
  /// 戻り値：実際に修正した件数
  static Future<int> fixAiLogTailPhrases() async {
    final file = await getAiCommentLogFile();
    if (!await file.exists()) return 0;

    final lines = await file.readAsLines();
    if (lines.isEmpty) return 0;

    final headers = lines.first.split(',');
    final idxComment = headers.indexOf('comment');

    if (idxComment < 0) {
      // comment列がない場合は何もしない
      return 0;
    }

    int fixed = 0;
    final out = <String>[];
    out.add(lines.first); // header

    for (final line in lines.skip(1)) {
      // 1行だけをCSVとして解析して安全に列を得る
      final values =
      const CsvToListConverter().convert(line).first.map((e) => e.toString()).toList();
      // 列数ずれを吸収
      while (values.length <= idxComment) {
        values.add('');
      }

      final raw = values[idxComment];
      final sanitized = CsvLoader.sanitizeCommentForDisplay(raw);
      if (sanitized != raw) fixed++;

      // 改行を \n にエスケープして書き戻し
      values[idxComment] = sanitized.replaceAll('\n', r'\n');

      // 1行をCSVに戻す
      final rowCsv = const ListToCsvConverter().convert([values], eol: '');
      out.add(rowCsv);
    }

    await file.writeAsString(out.join('\n') + '\n');
    return fixed;
  }
// --- isolate で CSV を読む（UIブロック回避） ---
  List<List<String>> _readCsvIsolate(String path) {
    final f = File(path);
    if (!f.existsSync()) return const [];
    final lines = f.readAsLinesSync();
    if (lines.isEmpty) return const [];
    return lines.map((l) => l.split(',')).toList();
  }


}

