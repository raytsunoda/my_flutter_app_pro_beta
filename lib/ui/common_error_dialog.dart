// lib/ui/common_error_dialog.dart
import 'package:flutter/material.dart';

Future<void> showCommonErrorDialog(
    BuildContext context, {
      String? title,
      String? message,
      String okLabel = 'OK',
    }) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title ?? '通信エラー'),
      content: Text(message ?? '通信に失敗しました。しばらくしてから再度お試しください。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(okLabel),
        ),
      ],
    ),
  );
}
