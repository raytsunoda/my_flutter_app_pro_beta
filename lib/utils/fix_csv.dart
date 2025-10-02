import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> fixCsvFile(String filename, int expectedColumnCount) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$filename';
    final file = File(path);

    if (!await file.exists()) {
      print('ファイルが見つかりません: $path');
      return;
    }

    final lines = await file.readAsLines();
    final fixedLines = <String>[];

    for (var line in lines) {
      final columns = line.split(',');
      if (columns.length != expectedColumnCount) {
        print('列数不一致: ${columns.length} → 修正');
        if (columns.length < expectedColumnCount) {
          columns.addAll(List.filled(expectedColumnCount - columns.length, ''));
        } else {
          columns.removeRange(expectedColumnCount, columns.length);
        }
      }
      fixedLines.add(columns.join(','));
    }

    await file.writeAsString(fixedLines.join('\n'));
    print('CSV修正完了: $path');
  } catch (e) {
    print('CSV修正中にエラー: $e');
  }
}
