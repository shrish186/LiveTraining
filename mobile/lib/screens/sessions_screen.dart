import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../services/session_store.dart';

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key, required this.controller});

  final AppController controller;

  String _date(DateTime? d) {
    if (d == null) return '?';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sessions = controller.sessions;
        return RefreshIndicator(
          onRefresh: controller.refreshSessions,
          child: sessions.isEmpty
              ? ListView(children: const [
                  Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No sessions recorded yet.'))),
                ])
              : ListView.separated(
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _tile(context, sessions[i]),
                ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, LocalSession s) {
    final c = controller;
    final status = c.uploadStatus[s.id];
    final recordingThis = c.isRecording && c.recorder?.sessionId == s.id;
    final minutes = s.duration.inSeconds / 60;
    final details = [
      _date(s.startedAt),
      if (!recordingThis) '${minutes.toStringAsFixed(1)} min',
      if (recordingThis) 'recording…',
      if (!s.complete && !recordingThis) 'incomplete',
    ].join(' · ');
    final Widget trailing;
    if (c.uploading.contains(s.id)) {
      trailing = const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (c.isUploaded(s.id)) {
      trailing = const Icon(Icons.cloud_done, color: Colors.green);
    } else {
      trailing = IconButton(
        icon: const Icon(Icons.cloud_upload),
        tooltip: 'Upload',
        onPressed: recordingThis ? null : () => c.upload(s),
      );
    }
    final failed = status?.startsWith('Failed') ?? false;
    return ListTile(
      title: Text('${s.sport} · ${s.sessionType}'),
      subtitle: Text(
        status == null ? details : '$details\n${failed ? 'Upload failed (tap for details)' : status}',
        style: failed ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
      ),
      isThreeLine: status != null,
      trailing: trailing,
      onTap: failed
          ? () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Upload failed'),
                  content: SingleChildScrollView(child: SelectableText(status!.replaceFirst('Failed: ', ''))),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                ),
              )
          : null,
    );
  }
}
