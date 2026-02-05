// lib/l10n/strings.dart
import 'package:flutter/widgets.dart';
import 'dart:ui';
import 'strings_ja.dart';
import 'strings_en.dart';

class S {
  final Locale locale;
  S(this.locale);

  static S of(BuildContext context) => S(Localizations.localeOf(context));

  bool get isJa => locale.languageCode == 'ja';

  // 既存 J のキー + 追加キーをここで吸収
  String get memoNone => isJa ? J.memoNone : E.memoNone;
  String get thinking => isJa ? J.thinking : E.thinking;
  String get aiNone => isJa ? J.aiNone : E.aiNone;

  String get aiPartnerTitle => isJa ? '💛AIパートナー' : E.aiPartnerTitle;
  String get todayMemoTitle => isJa ? '📝 今日のひとことメモ:' : E.todayMemoTitle;
  String get saveFavoriteWord => isJa ? '⭐ お気に入りに"あなたの言葉"を残す' : E.saveFavoriteWord;
  String get aiPartnerCommentTitle => isJa ? '💛 AIパートナーからのひとこと' : E.aiPartnerCommentTitle;
  String get retry => isJa ? 'もう一度試す' : E.retry;

  // Sections
  String get weeklyPreviewSection => isJa ? 'AIコメント（週次プレビュー）' : E.weeklyPreviewSection;
  String get weeklySection => isJa ? 'AIコメント（週次のふりかえり）' : E.weeklySection;
  String get monthlySection => isJa ? 'AIコメント（月次のふりかえり）' : E.monthlySection;


  String weeklyTarget(String date) =>
      (isJa ? '（対象週末日: $date）' : E.targetWeekEnd.replaceAll('{date}', date));
  String monthlyTarget(String date) =>
      (isJa ? '（対象月末日: $date）' : E.targetMonthEnd.replaceAll('{date}', date));

  String get menuTitle => isJa ? '操作メニュー' : E.menuTitle;
  String get weeklyButton => isJa ? '週次のふりかえり' : E.weeklyButton;
  String get weeklyNote => isJa ? '※ 週次：生成は毎週月曜10:00。今日は保存済みの内容のみ表示します。' : E.weeklyNote;
  String get monthlyButton => isJa ? '月次のふりかえり' : E.monthlyButton;
  String get monthlyNote => isJa ? '※ 月次：生成は毎月1日10:00。今日は保存済みの内容のみ表示します。' : E.monthlyNote;
  String get historyButton => isJa ? '🗂 コメント履歴を見る' : E.historyButton;

  // Daily status / debug
  String get dailyAlreadySaved => isJa ? 'この日のAIコメントは保存済みです。再生成はできません。' : E.dailyAlreadySaved;
  String get debugGenerateAndSave => isJa ? 'AIコメントを生成して保存' : E.debugGenerateAndSave;
  String get savedSnack => isJa ? 'AIコメントを保存しました' : E.savedSnack;





  // Dialog / common
  String get close => isJa ? '閉じる' : E.close;
  String get save => isJa ? '保存' : E.save;
  String favoriteSaveFailed(String error) =>
      isJa ? '⚠️ 保存に失敗しました: $error' : E.favoriteSaveFailed.replaceAll('{error}', error);

    String get favoriteSaved => isJa ? '⭐ お気に入りに保存しました' : E.favoriteSaved;

    // Favorite dialog (AIPartner)
    String get favoriteDialogTitle => isJa ? 'お気に入りのあなたの言葉' : E.favoriteDialogTitle;
    String get favoriteLimit => isJa ? '（40文字以内）' : E.favoriteLimit;
    String get favoriteHint => isJa ? '例：私は私のペースで大丈夫' : E.favoriteHint;
    String get favoriteHelp => isJa ? '※ 今日のメモの中から、\n　残しておきたいあなたの言葉があれば書いてください' : E.favoriteHelp;

    // History empty texts / backfill dialog
    String get emptyDaily => isJa ? 'コメントが保存されていません' : E.emptyDaily;
    String get emptyWeekly => isJa ? 'この週のコメントは保存されていません' : E.emptyWeekly;
    String get emptyMonthly => isJa ? 'この月のコメントは保存されていません' : E.emptyMonthly;
    String get emptyGeneric => isJa ? 'コメントが保存されていません' : E.emptyGeneric;

    String get backfillBody => isJa ? '不足しているAIコメントを一括生成します（APIコストあり）。続行しますか？' : E.backfillBody;
    String get backfillTitleDaily => isJa ? '日次の欠け分を補完' : E.backfillTitleDaily;
    String get backfillTitleWeekly => isJa ? '週次の欠け分を補完' : E.backfillTitleWeekly;
    String get backfillTitleMonthly => isJa ? '月次の欠け分を補完' : E.backfillTitleMonthly;







  // History
  String get historyTitle => isJa ? 'AIコメント履歴' : E.historyTitle;
  String get tabDaily => isJa ? '日次' : E.tabDaily;
  String get tabWeekly => isJa ? '週次' : E.tabWeekly;
  String get tabMonthly => isJa ? '月次' : E.tabMonthly;
  String get reload => isJa ? '最新データを再読込' : E.reload;
  String get backfill => isJa ? '欠け分を補完' : E.backfill;
  String get cancel => isJa ? 'キャンセル' : E.cancel;
  String get run => isJa ? '実行する' : E.run;
}
