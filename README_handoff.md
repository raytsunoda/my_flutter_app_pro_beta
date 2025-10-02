# README_handoff

この文書は Flutter 版「幸せ感ナビPro」の **引き継ぎメモ** です。  
通知仕様・週次/月次の厳密ロジック・テスト手順・Git 運用・データ移行を要約しています。

---

## 通知仕様（awesome_notifications）
- ライブラリ: `awesome_notifications`
- 週次: **毎週 月曜 10:00** に「先週（日曜締め）」の振り返りを通知  
  → `NotificationService.scheduleWeeklyOnMonday10()`
- 月次: **毎月 1日 10:00** に「前月（月末締め）」の振り返りを通知  
  → `NotificationService.scheduleMonthlyOnFirstDay10()`
- デバッグ通知（開発中確認用）: `payload.route = '/history'`、`payload.tab = weekly | monthly`
- 受信時の遷移: `NotificationService.listenNotificationActions(navigatorKey)`  
  → `payload.route` を `Navigator.pushNamed()` に渡す  
  → `payload.tab` で `AiCommentHistoryScreen(initialTab: …)` を切替

---

## 週次 / 月次ロジック（表示の厳密化）
### 週次
- 週の締めは **日曜**。
- 履歴の上限は **「現在日時が属する日曜」**（`prevOrSameSunday(now)`）。
- 例: 端末日付が 9/1 の場合、**8/31（前日曜）まで**の週が並ぶ。
- 補完後は `AiCommentService.loadWeeklyHistoryStrict()` を使って表示。

### 月次
- **月末のみ**を履歴に載せる（EOMフィルタ）。
- **表示カットオフ**は **翌月 0:00**。通知は **翌月 10:00**。
    - 例: 8/31 の月次は **9/1 0:00 以降**に表示OK、通知は **9/1 10:00**。

---

## テスト手順（抜粋）
1. アプリ起動 → デバッグ通知を発火 → タップ
    - `payload.route='/history'` で履歴画面へ
    - `payload.tab='weekly'|'monthly'` でタブが合っているか確認
2. 週次タブ: 端末日付を 9/1 にして **8/31 の週が並ぶ**ことを確認。
3. 月次タブ: 端末日付を 9/1 00:01 にして **8/31 が表示**され、本文が正しいか確認。

---

## Git 運用（dev/main の基本）
- 作業は `dev`、反映は `main`（**fast-forward** 運用）
- よく使うコマンド
  ```bash
  # 作業前
  git switch dev
  git pull --ff-only

  # 変更を push
  git add -A
  git commit -m "feat/fix: ..."
  git push origin dev

  # リリース取り込み
  git switch main
  git pull --ff-only
  git merge --ff-only dev
  git push origin main
