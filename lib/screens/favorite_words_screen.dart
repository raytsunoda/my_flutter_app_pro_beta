import 'package:flutter/material.dart';
//import '../utils/csv_loader.dart';
import 'package:my_flutter_app_pro/utils/csv_loader.dart';

class FavoriteWordsScreen extends StatefulWidget {
  const FavoriteWordsScreen({super.key});

  @override
  State<FavoriteWordsScreen> createState() => _FavoriteWordsScreenState();
}

class _FavoriteWordsScreenState extends State<FavoriteWordsScreen> {
  bool _loading = false;
  List<Map<String, String>> _items = [];

  @override
  void initState() {
    super.initState();
    // 画面表示後に読み込み開始（setStateの安全性が高い）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }


  Future<void> _load() async {
    if (!mounted) return;

    setState(() => _loading = true);

    try {
      // ✅ 壊れた favorite_words.csv を必要なら自動修復
      await CsvLoader.repairFavoriteWordsCsvIfNeeded();

      final list = await CsvLoader.loadFavoriteWords();

      if (!mounted) return;
      setState(() {
        _items = list;
      });
    } catch (e) {
      if (!mounted) return;

      // 例外でも必ず画面を復帰させる
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('読み込みに失敗しました: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _delete(String createdAt) async {
    await CsvLoader.deleteFavoriteWord(createdAt);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('削除しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⭐ お気に入りの言葉（あなたの言葉）')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ここには、あなたが残した言葉が並びます。\n無理に増やさなくて大丈夫です。',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final file = await CsvLoader.getFavoriteWordsFile();
                final content = await file.readAsString();
                if (!context.mounted) return;

                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('favorite_words.csv 確認'),
                    content: SingleChildScrollView(
                      child: Text('path:\n${file.path}\n\ncontent:\n$content'),
                    ),
                  ),
                );
              },
              child: const Text('ファイル内容を見る（デバッグ）'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await _load();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      )
          : ListView.separated(

      padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final item = _items[i];
          final createdAt = (item['createdAt'] ?? '').trim();
          final date = (item['date'] ?? '').trim();
          final text = (item['text'] ?? '').trim();

          return Dismissible(
            key: ValueKey(createdAt),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('削除しますか？'),
                  content: const Text('このお気に入りを削除します。入力データは消えません。'),
                  actions: [
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close),
                      tooltip: '閉じる',
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('削除'),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (_) => _delete(createdAt),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date.isEmpty ? '日付不明' : date,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(text, style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
