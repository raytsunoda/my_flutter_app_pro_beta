import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import 'package:my_flutter_app_pro/screens/navigation_screen.dart';
import '../screens/ai_partner_screen.dart';
import 'package:my_flutter_app_pro/screens/navigation_screen.dart';
import '../screens/ai_comment_history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
                  print('[notif-test] Weekly button pressed');
                  await NotificationService.debugFireWeeklyNow(localeCode: localeCode);

                  print('[notif-test] Weekly button pressed');

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Weekly test notification scheduled (15s).')),
                  );
                },
                child: const Text('Fire Weekly (15s)'),
              ),
            ),


            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  print('[notif-test] Schedule weekly 60s pressed');

                  await NotificationService.debugScheduleWeeklyIn60s(
                    localeCode: localeCode,
                  );

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Weekly test notification scheduled in 60s.'),
                    ),
                  );
                },
                child: const Text('Fire Weekly in 60s'),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  print('[notif-test] Schedule monthly 60s pressed');

                  await NotificationService.debugScheduleMonthlyIn60s(
                    localeCode: localeCode,
                  );

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Monthly test notification scheduled in 60s.'),
                    ),
                  );
                },
                child: const Text('Fire Monthly in 60s'),
              ),
            ),


            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  print('[notif-test] Direct open weekly history');

                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AiCommentHistoryScreen(initialTab: 1),
                    ),
                  );
                },
                child: const Text('DEV: Open Weekly History Direct'),
              ),
            ),





            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  print('[notif-test] Direct open monthly history');

                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AiCommentHistoryScreen(initialTab: 2),
                    ),
                  );
                },
                child: const Text('DEV: Open Monthly History Direct'),
              ),
            ),


            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();

                  final payload = prefs.getString('last_notification_payload') ?? '(none)';
                  final route = prefs.getString('last_notification_route') ?? '(none)';
                  final tab = prefs.getString('last_notification_tab') ?? '(none)';
                  final tappedAt = prefs.getString('last_notification_tapped_at') ?? '(none)';

                  final initialPayload =
                      prefs.getString('last_initial_action_payload') ?? '(none)';
                  final initialRoute =
                      prefs.getString('last_initial_action_route') ?? '(none)';
                  final initialTab =
                      prefs.getString('last_initial_action_tab') ?? '(none)';
                  final initialCheckedAt =
                      prefs.getString('last_initial_action_checked_at') ?? '(none)';
                  final pendingPayload =
                      prefs.getString('last_pending_action_payload') ?? '(none)';


                  if (!context.mounted) return;

                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Last notification tap'),
                      content: SingleChildScrollView(
                        child: Text(
                          'payload: $payload\n'
                              'route: $route\n'
                              'tab: $tab\n'
                              'tappedAt: $tappedAt\n\n'
                              'initialPayload: $initialPayload\n'
                              'initialRoute: $initialRoute\n'
                              'initialTab: $initialTab\n'
                              'initialCheckedAt: $initialCheckedAt\n'
                              'pendingPayload: $pendingPayload',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('DEV: Show Last Notification Tap'),
              ),
            ),







            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  print('[notif-test] Simulate weekly payload');
                  NotificationService.debugGoByPayloadForTest(tab: 'weekly');
                },
                child: const Text('DEV: Simulate Weekly Payload'),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  print('[notif-test] Simulate monthly payload');
                  NotificationService.debugGoByPayloadForTest(tab: 'monthly');
                },
                child: const Text('DEV: Simulate Monthly Payload'),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  print('[notif-test] Test date fallback weekly');

                  await NotificationService.debugConsumeWeeklyDateFallbackForTest();
                },
                child: const Text('DEV: Test Date Fallback Weekly'),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  print('[notif-test] Test date fallback monthly');

                  await NotificationService.debugConsumeMonthlyDateFallbackForTest();
                },
                child: const Text('DEV: Test Date Fallback Monthly'),
              ),
            ),



            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  print('[notif-test] Clear all notifications pressed');

                  await NotificationService.debugClearAllNotificationsOnly();

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notifications cleared.')),
                  );
                },
                child: const Text('DEV: Clear All Notifications Only'),
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
                    const SnackBar(content: Text('Monthly test notification scheduled (15s).')),
                  );
                },
                child: const Text('Fire Monthly (15s)'),
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
                    const SnackBar(content: Text('Morning & Evening test notifications scheduled (15s).')),
                  );
                },
                child: const Text('Fire Morning + Evening (15s)'),
              ),
            ),

            const SizedBox(height: 18),


            const Text(
              'Tip: Tap each notification to verify routing/payload.\n'
                  'This does NOT affect weekly/monthly schedules.',
              textAlign: TextAlign.center,
            ),

            ElevatedButton(
              child: const Text('DEV: Open AI screen (no gate)'),
              // onPressed: () async {
              //   try {
              //     await Navigator.push(
              //       context,
              //       MaterialPageRoute(builder: (_) => const AiPartnerScreen()),
              //     );
              //   } catch (e, st) {
                onPressed: () async {
                try {
                   await Navigator.push(
                     context,
                     MaterialPageRoute(
                       builder: (_) => const NavigationScreen(
                         csvData: [],
                         initialIndex: 2, // ← AIタブに直行（あなたのタブ順に合わせて調整）
                       ),
                     ),
                  );
                } catch (e, st) {

    debugPrint('DEV open AI failed: $e\n$st');
                  if (!context.mounted) return;
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('AI open failed'),
                      content: SingleChildScrollView(child: Text('$e\n\n$st')),
                    ),
                  );
                }
              },
            )






          ],
        ),
      ),
    );
  }
}
