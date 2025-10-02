import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode; // ガードに使用
import '../utils/csv_loader.dart';
//import '../services/ai_comment_service.dart';


class DeveloperToolsScreen extends StatelessWidget {
  const DeveloperToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 本番ビルドでは画面自体を無効化（メニューからも後述のガードで出さない想定）
    if (!kDebugMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('🛠 開発者ツール')),
        body: const Center(child: Text('本番ビルドでは表示されません')),
      );
    }

    return Scaffold(

      appBar: AppBar(title: const Text('🛠 開発者ツール')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // CSV を .bak から復元
          ElevatedButton(
            onPressed: () async {
              final bool success =
              await CsvLoader.restoreCsvFromBackup('HappinessLevelDB1_v2.csv');
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'CSVデータをバックアップから復元しました'
                        : '復元に失敗しました（バックアップが無い可能性）',
                  ),
                ),
              );
            },
            child: const Text('📥 CSVデータを復元する（.bak から）'),
          ),

          const SizedBox(height: 16),
// 8/5 関連ツールは役目を終えたため削除しました（2025-09-22）。

        /*
          // 8/5 の日次コメントを修理（フォールバック→削除→再生成）
          ListTile(
            title: const Text('8/5 の日次コメントを修理（フォールバック→削除→再生成）'),
            subtitle: const Text('一度だけ実行してください'),
            trailing: const Icon(Icons.build),
            onTap: () async {
              // 確認ダイアログ（bool? → bool）
              final bool ok = (await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('確認'),
                  content: const Text('2025/08/05 の日次を修理します。実行しますか？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('キャンセル'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('実行'),
                    ),
                  ],
                ),
              )) ??
                  false;
              if (!ok) return;

              // ← ここを修正：戻り値を dynamic で受け、bool/int どちらでも解釈
              final dynamic repairedRaw =
              await AiCommentService.repairDailyIfFallback(DateTime(2025, 8, 5));
              final bool wasRepaired = repairedRaw is bool
                  ? repairedRaw
                  : (repairedRaw is int ? repairedRaw > 0 : false);

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '修理結果: ${wasRepaired ? '修理しました' : '修理不要（フォールバックではありません）'}',
                  ),
                ),
              );
            },
          ),


          const Divider(),

          // 日次フォールバックを一括スキャンして安全に修理
          ListTile(
            title: const Text('日次フォールバックの一括スキャン修理'),
            subtitle: const Text('フォールバック保存が残っていれば当日だけ再生成'),
            trailing: const Icon(Icons.search),
            onTap: () async {
              final int n = await AiCommentService.scanAndRepairFallbackDaily();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('修理件数: $n')),
              );
            },
          ),

          ListTile(
            title: const Text('2025/08/05 の raw 件数を確認'),
            subtitle: const Text('デバッグ用：date=daily の生レコード件数をスナック表示'),
            trailing: const Icon(Icons.search),
            onTap: () async {
              final rows = await AiCommentService.debugRawFor('2025/08/05', 'daily');
              // 画面下に件数を表示＆ログ出力
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('raw件数: ${rows.length}')),
              );
              // 中身もログに出す（必要なら）
              // ignore: avoid_print
              print('[DEV] raw(2025/08/05,daily) = $rows');
            },
          ),

          ListTile(
            title: const Text('2025/08/05 を強制再生成（削除→厳密生成）'),
            subtitle: const Text('repairDailyIfFallback を経由せず日次を作り直します'),
            trailing: const Icon(Icons.build),
            onTap: () async {
              final bool? ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('確認'),
                  content: const Text('2025/08/05 の日次コメントを削除して作り直します。よろしいですか？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('キャンセル'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('実行'),
                    ),
                  ],
                ),
              );
              if (ok != true) return; // ← null/false をまとめて弾く

              // 削除前の件数
              final before = await AiCommentService.debugRawFor('2025/08/05', 'daily');

              // (A) 当日の履歴を date+type でハード削除
              await AiCommentService.hardDeleteByDateType('2025/08/05', 'daily');

              // (B) 厳密に再生成（CSVの実データから）
              await AiCommentService.ensureDailySavedForDate(DateTime(2025, 8, 5));

              // 削除・再生成後の件数
              final after = await AiCommentService.debugRawFor('2025/08/05', 'daily');

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('削除前: ${before.length}件 → 再生成後: ${after.length}件')),
              );
            },
          ),
*/
        ],
      ),
    );

  }

}
