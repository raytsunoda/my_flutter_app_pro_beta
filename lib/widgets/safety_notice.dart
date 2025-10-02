import 'package:flutter/material.dart';

class SafetyNotice extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const SafetyNotice({super.key, this.padding = const EdgeInsets.all(12)});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest, // surfaceVariant → 推奨へ
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AIの回答は必ずしも正確とは限りません。健康・医療・法律など重要な判断は、'
                  '必ず専門家や公的情報でご確認ください。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
