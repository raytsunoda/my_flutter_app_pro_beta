import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:my_flutter_app_pro/services/legacy_import_service.dart';

class DataMigrationScreen extends StatefulWidget {
  const DataMigrationScreen({super.key});
  @override
  State<DataMigrationScreen> createState() => _DataMigrationScreenState();
}

class _DataMigrationScreenState extends State<DataMigrationScreen> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('データ移行')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('旧アプリのCSVを選択して取り込みます。', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.file_upload),
              label: const Text('CSVを選択して取り込み'),
              onPressed: () async {
                // 1) ファイル選択
                final picked = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['csv', 'bak'],
                  withReadStream: true, // iCloud経由でも安全
                );
                if (picked == null) return;

                final file = await _materializePickedFile(picked.files.single);
                if (file == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ファイルを読み出せませんでした')),
                  );
                  return;
                }

                // 2) 上書き or スキップ
                final overwrite = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('上書きモードで取り込みますか？'),
                    content: const Text('同じ日付が既にある場合の挙動を選べます。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('スキップ'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('上書き'),
                      ),
                    ],
                  ),
                ) ??
                    false;

                setState(() => _status = '取り込み中…');

                // 3) 取り込み（堅牢版）
                final report = await LegacyImportService.importLegacyCsv(
                  source: file,
                  overwrite: overwrite,
                );

                if (!mounted) return;


                // サービス側の toString() をそのまま表示（型差異でも安全）
                final msg = report.toString();
                setState(() => _status = '');
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('取り込み結果'),
                    content: Text(msg),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  /// FilePicker の結果を必ずローカルの一時ファイルにするヘルパ
  Future<File?> _materializePickedFile(PlatformFile pf) async {
    // 端末ローカルならそのまま
    if (pf.path != null) return File(pf.path!);

    // bytes / readStream のどちらでも一時ファイルに落とす
    final tmpDir = await getTemporaryDirectory();
    final file = File(p.join(tmpDir.path, pf.name.isNotEmpty ? pf.name : 'import.csv'));

    if (pf.bytes != null) {
      await file.writeAsBytes(pf.bytes!, flush: true);
      return file;
    }
    if (pf.readStream != null) {
      final sink = file.openWrite();
      await pf.readStream!.pipe(sink);
      await sink.close();
      return file;
    }
    return null;
  }
}
