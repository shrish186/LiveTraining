import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../report/session_report.dart';
import '../services/session_store.dart';
import 'coach_chat_screen.dart';

/// Opens the AI coach with the athlete's data; about one session when [report] is given.
void openCoach(BuildContext context, AppController c, {SessionReport? report, LocalSession? session}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CoachChatScreen(
        title: report == null ? 'Coach' : 'Coach · this session',
        ask: c.askCoach,
        context: () => c.coachData(report: report, startedAt: session?.startedAt),
        notSetUp: c.coachNotSetUp,
        suggestions: report == null
            ? const [
                'How did my last session go?',
                'Am I doing too much this week?',
                'What should I focus on next session?',
              ]
            : [
                'What went well, and what should I change?',
                if (report.actions != null) 'When did I start to tire in this spell?',
                'How does this compare with my other sessions?',
              ],
      ),
    ),
  );
}
