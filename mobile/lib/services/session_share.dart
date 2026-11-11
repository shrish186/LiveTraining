import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'session_store.dart';

/// File names people can sort and recognise, e.g. `2026-12-07_0930_cricket_ankle_3f2a1c.csv`.
String shareBaseName(LocalSession s) {
  final t = s.startedAt;
  String two(int n) => n.toString().padLeft(2, '0');
  final when = t == null ? 'session' : '${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}${two(t.minute)}';
  final placement = s.metadata['placement'] as String?;
  final player = s.player?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return [
    when,
    s.sport,
    if (placement != null && placement.isNotEmpty) placement,
    if (player != null && player.isNotEmpty) player,
    s.id.length >= 6 ? s.id.substring(0, 6) : s.id,
  ].join('_');
}

/// Opens the share sheet with the session's CSV and metadata (AirDrop, Files, email, WhatsApp...).
/// [origin] anchors the sheet on iPad.
Future<void> shareSession(LocalSession s, {Rect? origin}) async {
  final base = shareBaseName(s);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(s.csv.path, mimeType: 'text/csv'),
        XFile(s.metadataFile.path, mimeType: 'application/json'),
      ],
      fileNameOverrides: ['$base.csv', '$base.json'],
      subject: 'Live Training session $base',
      sharePositionOrigin: origin,
    ),
  );
}
