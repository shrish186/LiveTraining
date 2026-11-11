import 'package:flutter/material.dart';

import '../services/backend_api.dart';
import '../ui/theme.dart';

/// Ask the AI coach about your training. The question and a compact summary of your sessions go to the
/// Live Training server, which asks Claude; the API key never leaves the server.
class CoachChatScreen extends StatefulWidget {
  const CoachChatScreen({
    super.key,
    required this.ask,
    required this.context,
    this.title = 'Coach',
    this.suggestions = const [
      'How did my last session go?',
      'Am I doing too much this week?',
      'What should I focus on next session?',
    ],
    this.notSetUp,
  });

  /// Sends one question (with the data and the conversation so far) and returns the answer.
  final Future<String> Function(String question, Map<String, dynamic> context, List<Map<String, String>> history) ask;

  /// The athlete's data, built when the screen opens.
  final Map<String, dynamic> Function() context;
  final String title;
  final List<String> suggestions;

  /// Shown instead of the chat when the coach can't be reached at all (e.g. no server set up).
  final String? notSetUp;

  @override
  State<CoachChatScreen> createState() => _CoachChatScreenState();
}

class _Turn {
  _Turn(this.role, this.text, {this.error = false});
  final String role; // user | assistant
  final String text;
  final bool error;
}

class _CoachChatScreenState extends State<CoachChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Turn> _turns = [];
  late final Map<String, dynamic> _data = widget.context();
  bool _busy = false;

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _input.text).trim();
    if (q.isEmpty || _busy) return;
    final history = [
      for (final t in _turns.where((t) => !t.error)) {'role': t.role, 'content': t.text},
    ];
    setState(() {
      _turns.add(_Turn('user', q));
      _busy = true;
      _input.clear();
    });
    _toEnd();
    try {
      final answer = await widget.ask(q, _data, history);
      if (!mounted) return;
      setState(() => _turns.add(_Turn('assistant', answer)));
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _turns.add(_Turn('assistant', e.message, error: true)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _toEnd();
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notSetUp = widget.notSetUp;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: notSetUp != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.forum_outlined, size: 40, color: AppColors.textFaint),
                    const SizedBox(height: 12),
                    const Text('The AI coach needs your Live Training server', style: AppText.body),
                    const SizedBox(height: 6),
                    Text(notSetUp, style: AppText.dim),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        if (_turns.isEmpty) ...[
                          const Text(
                            'Ask about your sessions, your week, or what to do next. The coach answers from your '
                            'own data.',
                            style: AppText.dim,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in widget.suggestions) ActionChip(label: Text(s), onPressed: () => _send(s)),
                            ],
                          ),
                        ],
                        for (final t in _turns) _Bubble(turn: t),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                                ),
                                SizedBox(width: 10),
                                Text('Looking at your data…', style: AppText.dim),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Training-load advice, not medical advice. For pain or an injury, see a physio or doctor.',
                      style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            textCapitalization: TextCapitalization.sentences,
                            style: AppText.body,
                            decoration: const InputDecoration(hintText: 'Ask the coach…', counterText: ''),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _busy ? null : _send,
                          icon: const Icon(Icons.arrow_upward_rounded),
                          tooltip: 'Send',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn});

  final _Turn turn;

  @override
  Widget build(BuildContext context) {
    final mine = turn.role == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        decoration: BoxDecoration(
          color: turn.error
              ? AppColors.danger.withValues(alpha: 0.12)
              : mine
              ? AppColors.accent.withValues(alpha: 0.18)
              : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          turn.text,
          style: turn.error ? AppText.body.copyWith(color: AppColors.danger) : AppText.body,
        ),
      ),
    );
  }
}
