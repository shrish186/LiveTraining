import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../services/session_store.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sessions = controller.sessions;
        final uploaded = sessions.where((s) => controller.isUploaded(s.id)).length;
        return RefreshIndicator(
          onRefresh: controller.refreshSessions,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              ScreenHeader(
                overline: sessions.isEmpty ? 'History' : '${sessions.length} recorded · $uploaded uploaded',
                title: 'Sessions',
              ),
              if (sessions.isEmpty)
                const AppCard(
                  child: Column(
                    children: [
                      Icon(Icons.timeline_rounded, size: 40, color: AppColors.textFaint),
                      SizedBox(height: 12),
                      Text('No sessions yet', style: AppText.body),
                      SizedBox(height: 4),
                      Text('Start one from the Live tab.', style: AppText.dim),
                    ],
                  ),
                )
              else
                for (final s in sessions) ...[
                  _SessionTile(controller: controller, session: s),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.controller, required this.session});

  final AppController controller;
  final LocalSession session;

  void _showFailure(BuildContext context, String status) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Upload failed'),
      content: SingleChildScrollView(child: SelectableText(status.replaceFirst('Failed: ', ''), style: AppText.dim)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            controller.upload(session);
          },
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = session;
    final status = c.uploadStatus[s.id];
    final failed = status?.startsWith('Failed') ?? false;
    final recordingThis = c.isRecording && c.recorder?.sessionId == s.id;
    final start = s.startedAt;
    String two(int n) => n.toString().padLeft(2, '0');

    final details = [
      if (start != null) '${two(start.hour)}:${two(start.minute)}',
      if (recordingThis) 'recording…' else '${(s.duration.inSeconds / 60).toStringAsFixed(1)} min',
      prettySlug(s.metadata['placement'] as String? ?? ''),
      if (!s.complete && !recordingThis) 'incomplete',
    ].where((e) => e.isNotEmpty).join(' · ');

    final Widget trailing;
    if (c.uploading.contains(s.id)) {
      trailing = const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent),
      );
    } else if (c.isUploaded(s.id)) {
      trailing = const StatusPill(color: AppColors.good, text: 'Uploaded');
    } else if (failed) {
      trailing = StatusPill(color: AppColors.danger, text: 'Failed', onTap: () => _showFailure(context, status!));
    } else {
      trailing = FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onPressed: recordingThis ? null : () => c.upload(s),
        icon: const Icon(Icons.cloud_upload_rounded, size: 18),
        label: const Text('Upload'),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: failed ? () => _showFailure(context, status!) : null,
      child: Row(
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                Text(start == null ? '--' : '${start.day}', style: AppText.stat),
                Text(start == null ? '' : _months[start.month - 1], style: AppText.label.copyWith(fontSize: 9)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${prettySlug(s.sport)} · ${s.sessionType}',
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(details, style: AppText.dim, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
