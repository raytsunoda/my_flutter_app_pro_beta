import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Future<void> debugPrintLocalCsvContent() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/HappinessLevelDB1_v2.csv');

    if (!await file.exists()) {
      debugPrint('⚠️ CSVファイルが存在しません: ${file.path}');
      return;
    }

    final lines = await file.readAsLines();
    final previewLines = lines.take(50).toList();

    debugPrint('📄 CSV内容（最初の ${previewLines.length} 行）:');
    for (var i = 0; i < previewLines.length; i++) {
      debugPrint('${i + 1}: ${previewLines[i]}');
    }

  } catch (e) {
    debugPrint('❌ CSV読み込み中にエラー: $e');
  }
}
