import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// CSVファイルの全内容をデバッグログに出力
Future<void> printAllCsvData() async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/data.csv');

    if (await file.exists()) {
      print('[DEBUG] CSV読み込み成功。行数: ${(await file.readAsLines()).length}');
    } else {
      print('[DEBUG] CSVファイルが存在しません: ${file.path}');
    }


    final content = await file.readAsString();
    debugPrint('[DEBUG] CSV全件内容:\n$content');
  } catch (e) {
    debugPrint('[ERROR] CSV読み込みエラー: $e');
  }
}

/// 指定された日付（yyyy/MM/dd形式）のCSV行を削除
Future<void> deleteCsvEntryByDate(String targetDate) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/HappinessLevelDB1_v2.csv');

    if (!await file.exists()) {
      debugPrint('[DEBUG] CSVファイルが存在しません。');
      return;
    }

    final lines = await file.readAsLines();
    if (lines.isEmpty) return;

    final header = lines.first;
    final filtered = lines.skip(1).where((line) => !line.startsWith(targetDate)).toList();

    final newContent = [header, ...filtered].join('\n');
    await file.writeAsString(newContent);

    debugPrint('[DEBUG] 日付 "$targetDate" の行を削除しました。残り: ${filtered.length} 件');
  } catch (e) {
    debugPrint('[ERROR] 日付削除エラー: $e');
  }
}