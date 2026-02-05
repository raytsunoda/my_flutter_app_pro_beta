// lib/l10n/strings_en.dart
class E {
  // 既存：J.memoNone / J.thinking / J.aiNone はすでにある想定
  static const String memoNone = 'No memo yet.';
  static const String thinking = 'Thinking...';
  static const String aiNone = 'No entry found for today, so no AI comment yet.';

  // AIPartnerScreen
  static const String aiPartnerTitle = '💛 AI Partner';
  static const String todayMemoTitle = '📝 Today\'s quick memo:';
  static const String saveFavoriteWord = '⭐ Save your favorite phrase';
  static const String aiPartnerCommentTitle = '💛 A note from your AI Partner';
  static const String retry = 'Try again';

  static const String weeklyPreviewSection = 'AI (Weekly Preview)';
  static const String weeklySection = 'AI (Weekly Reflection)';
  static const String monthlySection = 'AI (Monthly Reflection)';
  static const String targetWeekEnd = '(Week ending: {date})';
  static const String targetMonthEnd = '(Month ending: {date})';

  static const String dailyAlreadySaved = 'Today\'s AI comment is already saved. You can’t regenerate it.';
  static const String debugGenerateAndSave = 'Generate & save AI comment';
  static const String savedSnack = 'AI comment saved.';

  static const String menuTitle = 'Menu';
  static const String weeklyButton = 'Weekly reflection';
  static const String weeklyNote = 'Note: New weekly comments are generated every Monday at 10:00. Today, only saved content is shown.';
  static const String monthlyButton = 'Monthly reflection';
  static const String monthlyNote = 'Note: New monthly comments are generated on the 1st at 10:00. Today, only saved content is shown.';
  static const String historyButton = '🗂 View comment history';

  // Favorite word dialog
  static const String favoriteDialogTitle = 'Your favorite phrase';
  static const String favoriteLimit = '(Up to 40 characters)';
  static const String favoriteHint = 'e.g., I\'m okay at my own pace.';
  static const String favoriteHelp = 'Tip: If there’s a line from today you want to keep, write it here.';
  static const String close = 'Close';
  static const String save = 'Save';
  static const String favoriteSaved = '⭐ Saved.';
  static const String favoriteSaveFailed = '⚠️ Failed to save: {error}';

  // History screen
  static const String historyTitle = 'AI Comment History';
  static const String tabDaily = 'Daily';
  static const String tabWeekly = 'Weekly';
  static const String tabMonthly = 'Monthly';
  static const String reload = 'Reload';
  static const String backfill = 'Fill missing';

  static const String backfillTitleDaily = 'Fill missing (Daily)';
  static const String backfillTitleWeekly = 'Fill missing (Weekly)';
  static const String backfillTitleMonthly = 'Fill missing (Monthly)';
  static const String backfillBody = 'This will generate missing comments (API cost may apply). Continue?';
  static const String cancel = 'Cancel';
  static const String run = 'Run';

  static const String emptyDaily = 'No saved daily comments.';
  static const String emptyWeekly = 'No saved weekly comments for this week.';
  static const String emptyMonthly = 'No saved monthly comments for this month.';
  static const String emptyGeneric = 'No saved comment.';
}
