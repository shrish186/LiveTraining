import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_training/coach/coach_context.dart';
import 'package:live_training/coach/profiles.dart';
import 'package:live_training/report/session_report.dart';
import 'package:live_training/screens/coach_chat_screen.dart';
import 'package:live_training/services/backend_api.dart';
import 'package:live_training/ui/theme.dart';
import 'package:live_training/util/day_summary.dart';
import 'package:live_training/util/trends.dart';

SessionReport _spell() => SessionReport.build(
  const LineSplitter().convert(utf8.decode(gzip.decode(File('test/fixtures/spell_session.csv.gz').readAsBytesSync()))),
  {'sport': 'cricket', 'placement': 'ankle'},
  SportProfiles.parse(File('assets/sport_profiles.yaml').readAsStringSync()),
);

void main() {
  test('context: recent sessions, weeks, and the session in detail, small enough to send', () {
    final now = DateTime.now();
    final entries = [
      for (var d = 0; d < 30; d++)
        DayEntry(
          startedAt: DateTime(now.year, now.month, now.day - d, 9),
          duration: const Duration(minutes: 50),
          sport: 'cricket',
          summary: SessionSummary(load: 12.34, efforts: 3, fatigueEfforts: 0, actions: 30, actionsLabel: 'deliveries'),
        ),
    ];
    final ctx = coachContext(
      sport: 'cricket',
      placement: 'ankle',
      entries: entries,
      trends: Trends.of(entries, now),
      session: _spell(),
    );
    final json = jsonEncode(ctx);
    expect(json.length, lessThan(60000), reason: 'the server rejects summaries over 60k characters');
    expect((ctx['recent_sessions'] as List).length, 20);
    expect((ctx['recent_sessions'] as List).first['deliveries'], 30);
    expect((ctx['weeks'] as List), hasLength(4));
    final s = ctx['session_asked_about'] as Map<String, dynamic>;
    expect((s['deliveries'] as List), hasLength(12));
    expect(s['landing_last_vs_first_pct'], -19);
    expect((s['app_advice'] as List).first, startsWith('Fatigue building late in the spell'));
  });

  test('askCoach posts the question, data and history; server messages reach the athlete', () async {
    late Map<String, dynamic> sent;
    final api = BackendApi(
      'http://192.168.1.5:8000',
      client: MockClient((req) async {
        if (req.url.path != '/coach/ask') return http.Response('', 404);
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        if (sent['question'] == 'off?') {
          return http.Response(jsonEncode({'detail': 'The AI coach is not set up on this server.'}), 503);
        }
        return http.Response(jsonEncode({'answer': 'Bowl 5 overs.', 'model': 'claude-opus-5-5'}), 200);
      }),
    );
    final answer = await api.askCoach(
      'How many overs?',
      {'sport': 'cricket'},
      [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
      ],
    );
    expect(answer, 'Bowl 5 overs.');
    expect(sent['context'], {'sport': 'cricket'});
    expect((sent['history'] as List).length, 2);
    expect(
      () => api.askCoach('off?', {}, []),
      throwsA(isA<BackendException>().having((e) => e.message, 'message', contains('not set up'))),
    );
  });

  testWidgets('chat: a suggested question gets an answer; errors show in the chat', (tester) async {
    final asked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: CoachChatScreen(
          context: () => {'sport': 'cricket'},
          ask: (q, ctx, history) async {
            asked.add(q);
            if (asked.length == 2) throw BackendException('The AI coach is busy. Try again in a minute.');
            return 'Your landings held up for 9 deliveries, then dropped 19%. Plan a break after 9 next time.';
          },
        ),
      ),
    );
    await tester.tap(find.text('How did my last session go?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Plan a break after 9'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'And tomorrow?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('busy'), findsOneWidget);
    expect(asked, ['How did my last session go?', 'And tomorrow?']);
  });

  testWidgets('chat: explains what is missing when there is no server', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: CoachChatScreen(
          context: () => {},
          ask: (q, c, h) async => '',
          notSetUp: 'Add your server address in Settings.',
        ),
      ),
    );
    expect(find.text('The AI coach needs your Live Training server'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
