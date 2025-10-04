// lib/services/legacy_import_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:my_flutter_app_pro/utils/csv_loader.dart'; // ★ 追加


class LegacyImportService {

  // 数値（整数/小数）だけで構成されるか
  static bool _isNumericStr(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    return RegExp(r'^[+-]?\d+(\.\d+)?$').hasMatch(t);
  }

// 末尾から「非数値のセル」を3つ拾って、感謝1/2/3に割り当てる
  static void _fallbackPickGratitudesFromTail({
    required List<dynamic> srcRow,  // 読み込み元の1行（rows[r]）
    required List<dynamic> rowOut,  // 出力行（out[r]）
    required List<String> headerOut // 正規化後ヘッダー（out[0]）
  }) {
    final g1i = headerOut.indexOf('感謝1'); // #15
    final g2i = headerOut.indexOf('感謝2'); // #16
    final g3i = headerOut.indexOf('感謝3'); // #17
    final cti = headerOut.indexOf('感謝数'); // #14
    if (g1i < 0 || g2i < 0 || g3i < 0) return;

    // メモは最後にある想定なので、末尾から「非数値テキスト」を拾う
    final picks = <String>[];
    for (int i = srcRow.length - 1; i >= 0 && picks.length < 3; i--) {
      final v = (srcRow[i] ?? '').toString().trim();
      if (v.isEmpty) continue;
      if (!_isNumericStr(v)) picks.add(v);
    }
    if (picks.length == 3) {
      // 末尾から拾っているので逆順にして G1,G2,G3 へ
      // 末尾から拾っているので逆順にして G1,G2,G3 へ
      final ordered = picks.reversed.toList();
      rowOut[g1i] = ordered[0];
      rowOut[g2i] = ordered[1];
      rowOut[g3i] = ordered[2];

      // 感謝数は再計算（非空の数）
      final cnt = [picks[0], picks[1], picks[2]].where((e) => e.trim().isNotEmpty).length;
      if (cti >= 0) rowOut[cti] = cnt.toString();
    }
  }

// 原本ヘッダーに感謝1/2/3があるなら、それで上書き（あれば優先）
  static void _applyGratitudesFromSourceHeader({
    required List<String> headerSrc, // rows[0]
    required List<dynamic> srcRow,   // rows[r]
    required List<dynamic> rowOut,   // out[r]
    required List<String> headerOut, // out[0]
  }) {
    int _idxOf(List<String> hdr, String key) => hdr.indexOf(key);
    String _cell(dynamic v) => (v ?? '').toString().replaceAll('\r',' ').replaceAll('\n',' ').trim();

    final g1d = headerOut.indexOf('感謝1');
    final g2d = headerOut.indexOf('感謝2');
    final g3d = headerOut.indexOf('感謝3');
    final ctd = headerOut.indexOf('感謝数');
    if (g1d < 0 || g2d < 0 || g3d < 0) return;

    final g1s = _idxOf(headerSrc, '感謝1');
    final g2s = _idxOf(headerSrc, '感謝2');
    final g3s = _idxOf(headerSrc, '感謝3');
    final cts = _idxOf(headerSrc, '感謝数');

    String _get(int i) => (i >= 0 && i < srcRow.length) ? _cell(srcRow[i]) : '';

    final g1 = _get(g1s);
    final g2 = _get(g2s);
    final g3 = _get(g3s);

    // 値が取れたものだけ上書き（空なら触らない）
    if (g1.isNotEmpty) rowOut[g1d] = g1;
    if (g2.isNotEmpty) rowOut[g2d] = g2;
    if (g3.isNotEmpty) rowOut[g3d] = g3;

    // 感謝数は原本にあればそれ、無ければ非空で再計算
    final hasCnt = cts >= 0 && cts < srcRow.length && _cell(srcRow[cts]).isNotEmpty;
    if (ctd >= 0) {
      if (hasCnt) {
        rowOut[ctd] = _cell(srcRow[cts]);
      } else {
        final cnt = [rowOut[g1d], rowOut[g2d], rowOut[g3d]]
            .map((e) => (e ?? '').toString().trim())
            .where((e) => e.isNotEmpty).length;
        rowOut[ctd] = cnt.toString();
      }
    }
  }


  // === 感謝1/2/3を原本から抽出して rowOut(#15〜#17) に強制セットするユーティリティ ===
  static void _applyGratitudesFix({
    required List<String> normalizedHeader,
    required List<String> originalHeader,
    required List<dynamic> srcRow,
    required List<dynamic> rowOut,
  }) {

    int _idxOf(List<String> hdr, List<String> keys) {
      for (final k in keys) {
        final i = hdr.indexOf(k);
        if (i >= 0) return i;
      }
      return -1;
    }

    String _cell(dynamic v) =>
        (v ?? '').toString().replaceAll('\r', ' ').replaceAll('\n', ' ').trim();

    String _cleanQuote(String s) {
      var t = s.trim();
      while (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
        t = t.substring(1, t.length - 1).trim();
      }
      while (t.length >= 6 && t.startsWith('"""') && t.endsWith('"""')) {
        t = t.substring(3, t.length - 3).trim();
      }
      return t;
    }

    // 出力側（正規化後ヘッダー）の目的位置
    final idxG1Dest = normalizedHeader.indexOf('感謝1');   // 15
    final idxG2Dest = normalizedHeader.indexOf('感謝2');   // 16
    final idxG3Dest = normalizedHeader.indexOf('感謝3');   // 17
    final idxCntDest = normalizedHeader.indexOf('感謝数'); // 14

    // 原本ヘッダー上のソース位置（別名が出てきたらここに追記）
    final idxG1Src = _idxOf(originalHeader, const ['感謝1']);
    final idxG2Src = _idxOf(originalHeader, const ['感謝2']);
    final idxG3Src = _idxOf(originalHeader, const ['感謝3']);
    final idxCntSrc = _idxOf(originalHeader, const ['感謝数']);

    String _get(int i) => (i >= 0 && i < srcRow.length) ? _cell(srcRow[i]) : '';

    final g1 = _cleanQuote(_get(idxG1Src));
    final g2 = _cleanQuote(_get(idxG2Src));
    final g3 = _cleanQuote(_get(idxG3Src));
    final cntSrc = int.tryParse(_get(idxCntSrc)) ?? 0;

    // ★ 強制上書き（ここがキモ）
    if (idxG1Dest >= 0 && idxG1Dest < rowOut.length) rowOut[idxG1Dest] = g1;
    if (idxG2Dest >= 0 && idxG2Dest < rowOut.length) rowOut[idxG2Dest] = g2;
    if (idxG3Dest >= 0 && idxG3Dest < rowOut.length) rowOut[idxG3Dest] = g3;

    // 感謝数は原本優先。無ければ非空数から計算
    final nonEmpty = [g1, g2, g3].where((e) => e.isNotEmpty).length;
    final finalCnt = (cntSrc > 0) ? cntSrc : nonEmpty;
    if (idxCntDest >= 0 && idxCntDest < rowOut.length) {
      rowOut[idxCntDest] = finalCnt.toString();
    }
  }

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
// PATCH A: begin
    for (int i = 1; i < rows.length; i++) {
      // 1行分のソース
      final src = rows[i].map((e) => e?.toString() ?? '').toList();

      // 既存ユーティリティで 18列の正規形に一次整形
      final normalized = _normalizeRow(src, normalizedHeader, hdr);

      // --- 10〜13列（寝付き/深い睡眠/目覚め/モチベ）を“列名候補”から安全取得して確定上書き ---
      String _pick(List<String> names) => _cellAny(row: src, header: hdr, candidates: names);

      // #10〜#13 を候補名で吸い上げ（表記ゆれ対応）
      final vSleepEase = _pick(['寝付きの満足度', '寝付き満足度']); // #10
      final vDeepSleep = _pick(['深い睡眠感']);               // #11
      final vWakeFeel  = _pick(['目覚め感']);                 // #12
      final vMoti      = _pick(['モチベーション']);            // #13

      normalized[9]  = vSleepEase;  // #10
      normalized[10] = vDeepSleep;  // #11
      normalized[11] = vWakeFeel;   // #12
      normalized[12] = vMoti;       // #13

      // メモ列が途中で分割されていても救済して復元
      final memoStr = _extractMemo(src, normalizedHeader);
      if (memoStr.isNotEmpty) {
        normalized[_targetHeader().indexOf('memo')] = memoStr;
      }

      // 感謝1〜3を原本ヘッダーから強制補正（数値混入や取り違え対策）
      _applyGratitudesFix(
        normalizedHeader: normalizedHeader,
        originalHeader: hdr,
        srcRow: src,
        rowOut: normalized,
      );

      // 感謝数は最終的に非空 3件のカウントで再計算
      final g1 = normalized[14].toString().trim();
      final g2 = normalized[15].toString().trim();
      final g3 = normalized[16].toString().trim();
      normalized[13] = [g1, g2, g3].where((s) => s.isNotEmpty).length.toString();

      // デバッグログ
      final dateStr = normalized[0].toString();
      debugPrint('[MAP] $dateStr sleepEase="$vSleepEase" deep="$vDeepSleep" '
          'wake="$vWakeFeel" moti="$vMoti"');

      // 以降：上書き/追加の判定〜 mapByDate へ反映
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
          continue;
        }
      } else {
        inserted++;
        mapByDate[date] = normalized;
      }

      final memo = normalized[17].toString();
      debugPrint('🔎 $date memo="${memo.length > 40 ? memo.substring(0, 40) + '…' : memo}" '
          'g=[$g1,$g2,$g3]');
    }
// PATCH A: end





// 7) 日付昇順で保存（ヘッダー先頭）
    final out = <List<dynamic>>[];
    out.add(_targetHeader());
    final keys = mapByDate.keys.toList()
      ..sort((a, b) => _parseYmd(a).compareTo(_parseYmd(b)));
    for (final k in keys) {
      out.add(mapByDate[k]!);
    }



    // ★ ここで “保存する直前” に #15〜#17（感謝1/2/3）を原本から強制上書き
    for (int r = 1; r < out.length; r++) { // r=0 はヘッダー
      final rowOut = out[r];
      final srcRow = (r < rows.length) ? rows[r] : const <dynamic>[];
      _applyGratitudesFix(
        normalizedHeader: normalizedHeader,
        originalHeader: hdr,
        srcRow: srcRow,
        rowOut: rowOut,
      );
    }

// --- 追加：保存直前の最終矯正（#15〜#17） ---
    final headerOut = out.first.map((e) => e.toString()).toList();
    final headerSrc = rows.first.map((e) => e.toString()).toList();

    for (int r = 1; r < out.length; r++) {
      final rowOut = out[r];
      final srcRow = (r < rows.length) ? rows[r] : const <dynamic>[];

      final g1i = headerOut.indexOf('感謝1');
      final g2i = headerOut.indexOf('感謝2');
      final g3i = headerOut.indexOf('感謝3');
      if (g1i < 0 || g2i < 0 || g3i < 0) continue;

      final g1v = (rowOut[g1i] ?? '').toString().trim();
      final g2v = (rowOut[g2i] ?? '').toString().trim();
      final g3v = (rowOut[g3i] ?? '').toString().trim();

      bool _isNumericStr(String s) =>
          RegExp(r'^[+-]?\d+(\.\d+)?$').hasMatch(s.trim());
      final looksBad = _isNumericStr(g1v) || _isNumericStr(g2v) || _isNumericStr(g3v);

      if (looksBad) {
        // 1) 原本ヘッダーから復元（取れた分だけ上書き）
        _applyGratitudesFromSourceHeader(
          headerSrc: headerSrc,
          srcRow: srcRow,
          rowOut: rowOut,
          headerOut: headerOut,
        );

        // 2) まだ数値なら、末尾から非数値テキスト3つを拾って上書き
        final ng1 = (rowOut[g1i] ?? '').toString().trim();
        final ng2 = (rowOut[g2i] ?? '').toString().trim();
        final ng3 = (rowOut[g3i] ?? '').toString().trim();
        if (_isNumericStr(ng1) || _isNumericStr(ng2) || _isNumericStr(ng3)) {
          _fallbackPickGratitudesFromTail(
            srcRow: srcRow,
            rowOut: rowOut,
            headerOut: headerOut,
          );
        }
      }
    }

// --- 最終ガード：列数合わせ & 感謝数の再計算 & memo救済 ---
        {
      final gi1 = headerOut.indexOf('感謝1');
      final gi2 = headerOut.indexOf('感謝2');
      final gi3 = headerOut.indexOf('感謝3');
      final mi  = headerOut.indexOf('memo');
      final cti = headerOut.indexOf('感謝数');

      String _t(dynamic v) =>
          (v ?? '').toString().replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
      bool _isNum(String s) => RegExp(r'^[+-]?\d+(\.\d+)?$').hasMatch(s);

      for (int r = 1; r < out.length; r++) {
        final row = out[r];

        if (row.length < headerOut.length) {
          row.addAll(List.filled(headerOut.length - row.length, ''));
        } else {
          while (row.length > headerOut.length) row.removeLast();
        }

        var g1 = _t(row[gi1]);
        var g2 = _t(row[gi2]);
        var g3 = _t(row[gi3]);
        var memo = _t(row[mi]);

        final looksWrong = (_isNum(g1) || _isNum(g2) || _isNum(g3)) && memo.isNotEmpty;
        if (looksWrong) {
          if (g3.isEmpty || _isNum(g3)) { g3 = memo; memo = ''; }
          else if (g2.isEmpty || _isNum(g2)) { g2 = memo; memo = ''; }
          else if (g1.isEmpty || _isNum(g1)) { g1 = memo; memo = ''; }
        }

        row[gi1] = g1;
        row[gi2] = g2;
        row[gi3] = g3;
        row[mi]  = memo;

        final cnt = [g1, g2, g3].where((e) => e.isNotEmpty).length;
        if (cti >= 0) row[cti] = cnt.toString();
      }
    }
// --- 最終ガードここまで ---






    final csv = const ListToCsvConverter(eol: '\n').convert(out);
    await file.writeAsString(csv);
    debugPrint('✅ LegacyImport: saved -> ${file.path} (rows=${out.length})');


// ★ インポート直後に“必ず”最新CSVを読み直してメモリ/UIを更新
    await CsvLoader.loadLatestCsvData('HappinessLevelDB1_v2.csv', force: true);

// ★ どのCSVを読んでいるか＆先頭2行を診断出力（確認しやすく）
    await CsvLoader.debugDumpActiveCsv();

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

// --- 旧フォーマット（#6=時間, #7=分。換算列が無い）を検出して補正 ---
// 旧: ... [睡眠の質, 睡眠時間（時間）, 睡眠時間（分）, 寝付き..., ...]
// 新: ... [睡眠の質, 睡眠時間（時間換算）, 睡眠時間（分換算）, 睡眠時間（時間）, 睡眠時間（分）, 寝付き..., ...]
    final hasHourRaw = fixed.contains('睡眠時間（時間）');
    final hasMinRaw  = fixed.contains('睡眠時間（分）');
    final hasHourConv = fixed.contains('睡眠時間（時間換算）');
    final hasMinConv  = fixed.contains('睡眠時間（分換算）');

    if ((hasHourRaw && hasMinRaw) && (!hasHourConv || !hasMinConv)) {
      // ヘッダー自体は“最終形（canon）”で返す（中身の並びは後段で整える）
      return canon;
    }

// 列の総称・順序は最終形に合わせる（欠落は強制補完）
    if (fixed.length != canon.length) {
      return canon;
    }
    return fixed;

  }


  static List<dynamic> _normalizeRow(
      List<dynamic> src,
      List<String> normalizedHeader,
      List<String> originalHeader,
      ) {
    // まず出力行の器を作る（正規化後ヘッダーの長さ）
    final out = List<String>.filled(normalizedHeader.length, '');

    // ユーティリティ：安全に文字列化して改行を潰す
    String _cell(dynamic v) =>
        (v ?? '').toString().replaceAll('\r', ' ').replaceAll('\n', ' ');

    // 1) 同名/別名ヘッダーはそのままマッピング（存在するぶんだけ）
    int _findByAlias(List<String> orig, String want) {
      // 完全一致を優先
      final exact = orig.indexOf(want);
      if (exact >= 0) return exact;

      // 旧名→新名のエイリアス
      const Map<String, List<String>> aliases = {
        // 新名 : [旧名候補...]
        '寝付きの満足度': ['寝付き満足度', '寝つきの満足度', '寝付き満足度'],
        // 他にも旧称がありえる場合はここに追加
        // '睡眠の質': ['睡眠の質'], // 例：同名なら不要
      };

      final list = aliases[want];
      if (list != null) {
        for (final a in list) {
          final i = orig.indexOf(a);
          if (i >= 0) return i;
        }
      }
      return -1;
    }

    for (int dest = 0; dest < normalizedHeader.length; dest++) {
      final name = normalizedHeader[dest];
      final srcIdx = _findByAlias(originalHeader, name);
      if (srcIdx >= 0 && srcIdx < src.length) {
        out[dest] = _cell(src[srcIdx]);
      }
    }


    // 2) 旧フォーマット（#6=時間, #7=分。換算列が無い）→ 新フォーマット（#6=時間換算, #7=分換算, #8=時間, #9=分）を再構成
    final idxHourRawSrc = originalHeader.indexOf('睡眠時間（時間）'); // 旧：時間
    final idxMinRawSrc  = originalHeader.indexOf('睡眠時間（分）');   // 旧：分
    final idxHourConvSrc = originalHeader.indexOf('睡眠時間（時間換算）'); // 新：時間換算（もし既にあれば）
    final idxMinConvSrc  = originalHeader.indexOf('睡眠時間（分換算）');   // 新：分換算（もし既にあれば）

    // 出力側の目的インデックス
    final idxHourConvDest = normalizedHeader.indexOf('睡眠時間（時間換算）'); // #6
    final idxMinConvDest  = normalizedHeader.indexOf('睡眠時間（分換算）');   // #7
    final idxHourRawDest  = normalizedHeader.indexOf('睡眠時間（時間）');     // #8
    final idxMinRawDest   = normalizedHeader.indexOf('睡眠時間（分）');       // #9

    // 旧の時間/分（あれば取得）
    final hRaw = (idxHourRawSrc >= 0 && idxHourRawSrc < src.length)
        ? double.tryParse(_cell(src[idxHourRawSrc]).trim()) ?? 0.0
        : 0.0;
    final mRaw = (idxMinRawSrc >= 0 && idxMinRawSrc < src.length)
        ? double.tryParse(_cell(src[idxMinRawSrc]).trim()) ?? 0.0
        : 0.0;

    // 既に換算列がソースにある場合は優先して使い、無ければ旧の時間/分から計算
    final hourConv = (idxHourConvSrc >= 0 && idxHourConvSrc < src.length)
        ? double.tryParse(_cell(src[idxHourConvSrc]).trim()) ?? (hRaw + (mRaw / 60.0))
        : (hRaw + (mRaw / 60.0));
    final minConv = (idxMinConvSrc >= 0 && idxMinConvSrc < src.length)
        ? double.tryParse(_cell(src[idxMinConvSrc]).trim()) ?? (hRaw * 60.0 + mRaw)
        : (hRaw * 60.0 + mRaw);

    // 出力行へ上書き（空欄の場合も確実にセット）
    if (idxHourConvDest >= 0) out[idxHourConvDest] = hourConv.toString();           // #6
    if (idxMinConvDest  >= 0) out[idxMinConvDest]  = minConv.round().toString();    // #7（整数）
    if (idxHourRawDest  >= 0 && hRaw != 0.0) out[idxHourRawDest] = hRaw.toString(); // #8
    if (idxMinRawDest   >= 0 && mRaw != 0.0) out[idxMinRawDest]  = mRaw.toString(); // #9


    // === 10〜14列（寝付き/深い睡眠/目覚め/モチベ/感謝数）を “列名候補” から確定コピーする ===

// 宛先インデックス（新フォーマットの#10〜#14）
    final idxSleepEaseDest   = normalizedHeader.indexOf('寝付きの満足度'); // #10
    final idxDeepSleepDest   = normalizedHeader.indexOf('深い睡眠感');     // #11
    final idxWakeFeelDest    = normalizedHeader.indexOf('目覚め感');       // #12
    final idxMotiDest        = normalizedHeader.indexOf('モチベーション'); // #13
    final idxThanksCntDest   = normalizedHeader.indexOf('感謝数');         // #14

    int _findByNames(List<String> names) {
      for (final n in names) {
        final i = originalHeader.indexOf(n);
        if (i >= 0) return i;
      }
      return -1;
    }

    String _pickByNames(List<String> names) {
      final i = _findByNames(names);
      if (i >= 0 && i < src.length) return _cell(src[i]).trim();
      return '';
    }

// 旧CSVでの表記ゆれ候補
    final sleepEaseVal = _pickByNames(['寝付きの満足度','寝付き満足度','寝付の満足度','寝つきの満足度']);
    final deepSleepVal = _pickByNames(['深い睡眠感','深い眠り感','深い睡眠 の 感']); // 後方互換のため緩め
    final wakeFeelVal  = _pickByNames(['目覚め感','目覚めの感','目覚め満足度']);
    final motiVal      = _pickByNames(['モチベーション','ﾓﾁﾍﾞｰｼｮﾝ','モチベ']);
    final thanksCntVal = _pickByNames(['感謝数','感謝 件数']);

// 宛先に上書き（ブランクはスキップ）
// 数値かどうかはアプリ側で範囲チェックしているのでここではそのまま渡す
    if (idxSleepEaseDest >= 0 && sleepEaseVal.isNotEmpty) {
      out[idxSleepEaseDest] = sleepEaseVal;
    }
    if (idxDeepSleepDest >= 0 && deepSleepVal.isNotEmpty) {
      out[idxDeepSleepDest] = deepSleepVal;
    }
    if (idxWakeFeelDest >= 0 && wakeFeelVal.isNotEmpty) {
      out[idxWakeFeelDest] = wakeFeelVal;
    }
    if (idxMotiDest >= 0 && motiVal.isNotEmpty) {
      out[idxMotiDest] = motiVal;
    }
    if (idxThanksCntDest >= 0 && thanksCntVal.isNotEmpty) {
      out[idxThanksCntDest] = thanksCntVal;
    }

// デバッグ（_normalizeRow 内では out[0] が日付）
    final _dateForLog = (out.isNotEmpty ? out[0] : '').toString();
    debugPrint('[MAP] $_dateForLog sleepEase="$sleepEaseVal" deep="$deepSleepVal" wake="$wakeFeelVal" '
        'moti="$motiVal" thanks="$thanksCntVal"');


    // === ★ ここから追記：感謝1/2/3を原本ヘッダーから強制上書き（数値混入の矯正） ===

    String _cleanQuote(String s) {
      var t = s.trim();
      // 先頭/末尾の " や """ を安全に剥がす（何重でも）
      while (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
        t = t.substring(1, t.length - 1).trim();
      }
      while (t.length >= 6 && t.startsWith('"""') && t.endsWith('"""')) {
        t = t.substring(3, t.length - 3).trim();
      }
      return t;
    }

    int _idxOf(List<String> hdr, List<String> names) {
      for (final n in names) {
        final i = hdr.indexOf(n);
        if (i >= 0) return i;
      }
      return -1;
    }

    // 出力先の位置（正規化後ヘッダー）
    final idxG1Dest = normalizedHeader.indexOf('感謝1');
    final idxG2Dest = normalizedHeader.indexOf('感謝2');
    final idxG3Dest = normalizedHeader.indexOf('感謝3');
    final idxCntDest = normalizedHeader.indexOf('感謝数');

    // 原本ヘッダー上の位置（別名があればここに追加）
    final idxG1Src = _idxOf(originalHeader, const ['感謝1']);
    final idxG2Src = _idxOf(originalHeader, const ['感謝2']);
    final idxG3Src = _idxOf(originalHeader, const ['感謝3']);
    final idxCntSrc = _idxOf(originalHeader, const ['感謝数']);

    // 原本の値をテキスト化＆引用符除去
    String _get(int idx) {
      if (idx < 0 || idx >= src.length) return '';
      return _cell(src[idx]);
    }
    final g1Src = _cleanQuote(_get(idxG1Src));
    final g2Src = _cleanQuote(_get(idxG2Src));
    final g3Src = _cleanQuote(_get(idxG3Src));
    final cntSrc = int.tryParse(_get(idxCntSrc)) ?? 0;

    // 出力先へ「必ず」上書き（ここで 4/3 のような数値混入を矯正）
    if (idxG1Dest >= 0) out[idxG1Dest] = g1Src;
    if (idxG2Dest >= 0) out[idxG2Dest] = g2Src;
    if (idxG3Dest >= 0) out[idxG3Dest] = g3Src;

    // 感謝数は原本が正ならそれを、そうでなければ非空数を採用
    final nonEmptyGratitudes = [g1Src, g2Src, g3Src].where((e) => e.isNotEmpty).length;
    final finalCnt = cntSrc > 0 ? cntSrc : nonEmptyGratitudes;
    if (idxCntDest >= 0) out[idxCntDest] = finalCnt.toString();

    // === ★ 追記ここまで ===

    return out;
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


  /// 複数候補のヘッダー名から最初に見つかった列を返す（見つからなければ ""）
  static String _cellAny({
    required List<dynamic> row,
    required List<dynamic> header,
    required List<String> candidates,
  }) {
    for (final name in candidates) {
      final i = header.indexOf(name);
      if (i >= 0 && i < row.length) {
        final v = row[i];
        return (v == null) ? "" : v.toString();
      }
    }
    return "";
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


