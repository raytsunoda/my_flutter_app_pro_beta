// lib/widgets/migration_guide_modal.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../gen_l10n/app_localizations.dart';

class MigrationGuideModal extends StatefulWidget {
  const MigrationGuideModal({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        final media = MediaQuery.of(context);

        return Dialog(
          // ↘ ほぼ全画面に近づける（上下の余白を小さく）
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              // 画面高さの 90% まで使う
              maxHeight: media.size.height * 0.9,
              // 横幅はタブレットなどで広がりすぎないように
              maxWidth: 540,
            ),
            child: const MigrationGuideModal(),
          ),
        );
      },
    );
  }




  // 起動時など自動表示（「次回から表示しない」を尊重）
  static Future<void> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final off = prefs.getBool('migrationGuide_suppress') ?? false;
    if (!off) {
      await show(context);
    }
  }

  @override
  State<MigrationGuideModal> createState() => _MigrationGuideModalState();
}

class _MigrationGuideModalState extends State<MigrationGuideModal> {
  bool _suppress = false;

    @override
    void initState() {
        super.initState();
        // 「次回から表示しない」の状態をUIに反映（←これが無いと常にfalse表示になる）
        SharedPreferences.getInstance().then((prefs) {
            if (!mounted) return;
            setState(() {
              _suppress = prefs.getBool('migrationGuide_suppress') ?? false;
            });
          });
      }


  Future<void> _toggleSuppress(bool v) async {
    setState(() => _suppress = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('migrationGuide_suppress', v);
  }

  Future<void> _openWeb() async {
    // final uri = Uri.parse('https://www.happiness-h3.com/');
    // if (await canLaunchUrl(uri)) {
    //   await launchUrl(uri, mode: LaunchMode.externalApplication);
    // }

        final t = AppLocalizations.of(context)!;
        final uri = Uri.parse('https://www.happiness-h3.com/support');
        final ok = await canLaunchUrl(uri);
        if (!ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.commonLinkOpenFailed)),
          );
          return;
        }
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.commonLinkOpenFailed)),
          );
        }
  }

  Widget _step({
    required int no,
    required String title,
    required String body,
    String? asset, // 画像を入れたいときは assets/***.png を。
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.black,
            child: Text('$no', style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    )),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
                if (asset != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(asset, fit: BoxFit.cover, height: 140),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isRelease = kReleaseMode;

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 540, // 横幅だけ制限
      ),
      // はみ出したらスクロールできるようにする
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ヘッダ
              Row(
                children: [
                  const Expanded(
                    child: Text(
                     // 'データ移行ガイド（旧アプリ → Pro）',
                      '', // ← ここは下で Text(t.xxx) を使うので const を外す
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
                // ↑のconstを外したいので、タイトルはここで改めて描画
                Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t.migrationGuideTitle,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              const SizedBox(height: 4),
              const SizedBox(height: 4),
              // const Text(
              //   '旧アプリのデータは「バックアップファイル（CSV形式）」として保存し、Pro版に読み込むだけで引き継げます。',
              //   style: TextStyle(fontSize: 14, color: Colors.black87),
              // ),
            Text(
                t.migrationGuideIntro,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              const SizedBox(height: 16),

              // ステップ
              _step(
                no: 1,
                // title: '旧アプリでバックアップを作成',
                // body:
                // '旧アプリを最新にアップデート後、メニューから「データを書き出す」を選択。'
                //     '“バックアップファイル（CSV形式）”として保存します。',
                title: t.migrationGuideStep1Title,
                body: t.migrationGuideStep1Body,
              ),
              const SizedBox(height: 10),
              _step(
                no: 2,
                // title: 'Pro版で読み込む',
                // body:
                // '「幸せ感ナビPro」をインストールし、設定 → データ移行 から、'
                //     'さきほどのバックアップファイルを選択して読み込みます。',
                title: t.migrationGuideStep2Title,
                body: t.migrationGuideStep2Body,
              ),
              const SizedBox(height: 10),
              _step(
                no: 3,
                // title: 'AIパートナーを使いはじめる',
                // body:
                // '日次のひとこと／週次・月次のふりかえりを確認。必要に応じて「再生成」も可能です。',
                title: t.migrationGuideStep3Title,
                body: t.migrationGuideStep3Body,
              ),
              const SizedBox(height: 14),

              // 補助リンク
              // 補助リンク
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 上段：公式サイトへのリンク（左寄せ）
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _openWeb,
                      icon: const Icon(Icons.open_in_new),
                     // label: const Text('詳しい手順（公式サイト）'),
                      label: Text(t.migrationGuideMoreDetails),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 下段：チェックボックス（右寄せ）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Checkbox(
                        value: _suppress,
                        onChanged: (v) => _toggleSuppress(v ?? false),
                      ),
                      // const Text(
                      //   '次回から表示しない',
                      //   style: TextStyle(fontSize: 13),
                  Text(
                        t.migrationGuideDontShowAgain,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),


              const SizedBox(height: 6),

              // フッタボタン
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                   // child: const Text('今はしない'),
                    child: Text(t.commonNotNow),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // 必要ならここで「データ移行」画面に遷移
                    },
                    icon: const Icon(Icons.file_upload),
                    //label: const Text('移行をはじめる'),
                    label: Text(t.migrationGuideStart),
                  ),
                ],
              ),

              // デバッグ専用セクション
              if (!isRelease) ...[
                const Divider(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                   // '[DEBUG] 表示制御',
                    '[DEBUG] 表示制御',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        final prefs =
                        await SharedPreferences.getInstance();
                        await prefs.remove('migrationGuide_suppress');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            // const SnackBar(
                            //   content: Text('抑止フラグを削除しました'),
                            // ),
                            SnackBar(content: Text(t.migrationGuideDebugCleared)),
                          );
                        }
                      },
                     // child: const Text('抑止フラグをクリア'),
                      child: Text(t.migrationGuideDebugClearButton),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

}
