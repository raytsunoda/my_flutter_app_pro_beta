import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// DocumentDirectoryに保存された最新CSVを読み込む（ファイルがなければ空リスト）
Future<List<List<String>>> loadLatestCsvData(String filename) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$filename';
    final file = File(filePath);

    if (!await file.exists()) {
      print('📄 ファイルが存在しません: $filePath');
      return [];
    }

    final contents = await file.readAsString();
    final rows = const CsvToListConverter(eol: '\n').convert(contents);
    return rows.map((row) => row.map((e) => e.toString()).toList()).toList();
  } catch (e) {
    print('❌ 最新CSVの読み込み失敗: $e');
    return [];
  }
}

/// 1. 全行を List<List<String>> として読み込む（フィールド区切り明示）
Future<List<List<String>>> loadCsvAsStringMatrix(String filename) async {
  try {
    final rawData = await rootBundle.loadString('assets/$filename');

    final dynamicList = const CsvToListConverter(
      eol: '\n',
      fieldDelimiter: ',', // カンマ区切りを明示
    ).convert(rawData);
    return dynamicList.map<List<String>>(
          (row) => row.map((e) => e.toString()).toList(),
    ).toList();
  } catch (e) {
    print("❌ $filename の読み込みエラー: $e");
    return [];
  }
}

/// 2. ヘッダー付きCSVを List<Map<String, String>> として読み込む（quotes.csvなど）
Future<List<Map<String, String>>> loadCsvAsListOfMap(String filename) async {
  try {
    final rawData = await rootBundle.loadString('assets/$filename');
    final rows = const CsvToListConverter(
      eol: '\n',
      fieldDelimiter: ',', // 明示することで誤読を防ぐ
    ).convert(rawData);
    if (rows.isEmpty) return [];

    final headers = rows.first.map((e) => e.toString()).toList();
    return rows.skip(1).map((row) {
      final rowStrings = row.map((e) => e.toString()).toList();
      return Map<String, String>.fromIterables(headers, rowStrings);
    }).toList();
  } catch (e) {
    print("❌ $filename の読み込みエラー: $e");
    return [];
  }
}
/// バンドルCSVを読み込む：List<List<String>>
Future<List<List<String>>> loadCsvFromAssets(String path) async {
  final rawData = await rootBundle.loadString('assets/$path');
  final csv = const CsvToListConverter(eol: '\n').convert(rawData);
  return csv.map((row) => row.map((e) => e.toString()).toList()).toList();
}
/// ファイルシステム上のCSVを読み込む（ユーザー保存分）
Future<List<List<String>>> loadCsvFromFileSystem(String filename) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$filename';
    final file = File(filePath);

    if (!await file.exists()) {
      print('📄 ファイルが存在しません: $filePath');
      return [];
    }

    final contents = await file.readAsString();
    final rows = const CsvToListConverter(eol: '\n').convert(contents);
    return rows.map((row) => row.map((e) => e.toString()).toList()).toList();
  } catch (e) {
    print('❌ ファイル読み込み失敗: $e');
    return [];
  }
}

/// 4. List<Map<String, String>>（ヘッダー付きCSV用。こちらも互換性のため保持）
Future<List<Map<String, String>>> loadCsvAsStringList(String fileName) async {
  try {
    final rawData = await rootBundle.loadString('assets/$fileName');
    final rows = const CsvToListConverter(eol: '\n').convert(rawData);
    final headers = rows.first.map((e) => e.toString()).toList();
    return rows.skip(1).map((row) =>
    Map<String, String>.fromIterables(headers, row.map((e) => e.toString()))).toList();
  } catch (e) {
    print("❌ $fileName の読み込みエラー: $e");
    return [];
  }
}
/// ヘッダー行を持つCSV → List<Map<String, String>> に変換（トリム処理付き）
Future<List<Map<String, String>>> loadCsvAsMapList(String path) async {
  try {
    final rawData = await rootBundle.loadString('assets/$path');
    print('✅ CSV読み込み成功: $path');
    final rows = const CsvToListConverter(eol: '\n').convert(rawData);

    final headers = rows.first.map((e) => e.toString().trim()).toList();

    return rows.skip(1).map((row) {
      final values = row.map((e) => e.toString().trim()).toList();
      return Map<String, String>.fromIterables(headers, values);
    }).toList();
  } catch (e) {
    print('❌ CSV読み込み失敗: $e');
    return [];
  }
}
