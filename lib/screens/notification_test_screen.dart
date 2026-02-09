import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class NotificationTestScreen extends StatelessWidget {
  const NotificationTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;

    // 念のため：Releaseでは表示しない（画面自体はルート登録してもOK）
    if (kReleaseMode) {
      return const Scaffold(
        body: Center(child: Text('Not available in Release.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('app localeCode: $localeCode'),
            const SizedBox(height: 12),

            // ① Weekly
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await NotificationService.debugFireWeeklyNow(localeCode: localeCode);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Weekly test notification scheduled (3s).')),
                  );
                },
                child: const Text('Fire Weekly (3s)'),
              ),
            ),

            const SizedBox(height: 10),

            // ② Monthly
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await NotificationService.debugFireMonthlyNow(localeCode: localeCode);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Monthly test notification scheduled (3s).')),
                  );
                },
                child: const Text('Fire Monthly (3s)'),
              ),
            ),

            const SizedBox(height: 10),

            // ③ Morning + Evening（同時に2本出す）
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await NotificationService.debugFireMorningNow(localeCode: localeCode);
                  await NotificationService.debugFireEveningNow(localeCode: localeCode);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Morning & Evening test notifications scheduled (3s).')),
                  );
                },
                child: const Text('Fire Morning + Evening (3s)'),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'Tip: Tap each notification to verify routing/payload.\n'
                  'This does NOT affect weekly/monthly schedules.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
