# 幸せ感ナビPro（Flutter）

iOS / Android 両対応の Flutter 版アプリです。  
開発フローは **`dev` で作業 → `main` に fast-forward 取り込み**。

## クイックスタート

```bash
flutter clean && flutter pub get
flutter run -d <device>
```
次に読む: README_handoff.md（通知仕様・週次/月次ロジック・Git運用・データ移行など）

> 画像追加ダイアログが出ても **Cancel** でOK（READMEはテキストのみで十分）。

---

## 保存 → コミット → プッシュ（ターミナル手順）

1. Android StudioでREADME.mdを**保存**（⌘S）
2. ターミナルでプロジェクト直下から:

```bash
git status                       # README.md が modified になっていることを確認
git add README.md
git commit -m "docs: READMEを簡潔に整備（クイックスタート追記）"
git push origin dev
```