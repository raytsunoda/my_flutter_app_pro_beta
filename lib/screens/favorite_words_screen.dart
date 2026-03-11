import 'package:flutter/material.dart';
//import '../utils/csv_loader.dart';
import 'package:my_flutter_app_pro/utils/csv_loader.dart';
import '../gen_l10n/app_localizations.dart';
import 'package:flutter/services.dart';

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

      final t = AppLocalizations.of(context)!;

      // 例外でも必ず画面を復帰させる
      ScaffoldMessenger.of(context).showSnackBar(
      //  SnackBar(content: Text('読み込みに失敗しました: $e')),
        SnackBar(content: Text(t.favoriteWordsLoadFailed(e.toString()))),

      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _delete(String createdAt) async {
    await CsvLoader.deleteFavoriteWord(createdAt: createdAt);
    await _load();
    if (!mounted) return;

    final t = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
  //    const SnackBar(content: Text('削除しました')),
      SnackBar(content: Text(t.favoriteWordsDeleted)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      //appBar: AppBar(title: const Text('⭐ お気に入りのあなたの言葉')),
      appBar: AppBar(title: Text(t.favoriteWordsTitle)),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // const Text(
            //   'ここには、あなたが残した言葉が並びます。\n無理に増やさなくて大丈夫です。',
            //   style: TextStyle(fontSize: 16),
            // ),

            Text(
                t.favoriteWordsEmptyIntro,
                style: const TextStyle(fontSize: 16),
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
                    //title: const Text('favorite_words.csv 確認'),
                    title: Text(t.favoriteWordsCsvCheckTitle),
                    content: SingleChildScrollView(
                    //  child: Text('path:\n${file.path}\n\ncontent:\n$content'),
                    child: Text(
                        t.favoriteWordsCsvCheckBody(file.path, content),
                      ),
                    ),
                  ),
                );
              },
              //child: const Text('ファイル内容を見る（デバッグ）'),
              child: Text(t.favoriteWordsViewFileDebug),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await _load();
              },
           //   child: const Text('再読み込み'),
              child: Text(t.favoriteWordsReload),
            ),
          ],
        ),
      )


          : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

      Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
       // "長押しでコピーできます",
        t.favoriteCopyHint,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black54,
        ),
      ),
    ),

    Expanded(
    child: ListView.separated(

      padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final item = _items[i];
          final createdAt = (item['createdAt'] ?? '').trim();
          final date = (item['date'] ?? '').trim();
          final text = (item['text'] ?? '').trim();

          return Dismissible(
            key: ValueKey(createdAt.isNotEmpty ? createdAt : 'row-$i-${item['date']}-${item['text']}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.redAccent,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              return true;
            },
            onDismissed: (_) async {
              try {
                if (createdAt.isNotEmpty) {
                  await CsvLoader.deleteFavoriteWord(createdAt: createdAt);
                }

                if (!mounted) return;
                setState(() {
                  _items.removeWhere((e) => (e['createdAt'] ?? '') == createdAt);
                });

                // 念のためファイルから再読み込み（永続化の反映）
                await _load();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    //const SnackBar(content: Text('削除しました')),
                    SnackBar(content: Text(t.favoriteWordsDeleted)),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  //SnackBar(content: Text('削除に失敗しました: $e')),
                  SnackBar(content: Text(t.favoriteWordsDeleteFailed('$e'))),
                );
                // 失敗時は画面を復元するため再読み込み
                await _load();
              }
            },
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
              color: const Color(0xFFF7F4FB),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        const Padding(
                          padding: EdgeInsets.only(right: 8, top: 2),
                          child: Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: Color(0xFFF2C94C),
                          ),
                        ),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                date,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onLongPress: () async {
                                  await Clipboard.setData(ClipboardData(text: text));

                                  if (!mounted) return;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      //content: Text("お気に入りの言葉をコピーしました"),
                                        content : Text (t.favoriteCopied),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: Text(
                                  '"$text"',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              ),
            ),
          );

        },
      ),
      ),
      ],
      ),
    );
  }
}
