/// CSV row formatting for the session format (docs/session-format.md). Pure Dart.
library;

import '../sources/motion_source.dart';

const csvHeader = 't_ms,source,kind,x,y,z,value';

/// Up to 5 decimals, trailing zeros trimmed, `.` decimal separator, no `-0`.
String formatFloat(double v) {
  if (v.isNaN || v.isInfinite) return '';
  var text = v.toStringAsFixed(5);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return text == '-0' ? '0' : text;
}

/// Event labels may not contain commas, quotes or newlines.
String sanitizeLabel(String label) {
  final cleaned = label.replaceAll(RegExp(r'[,"\r\n]'), ' ').trim();
  return cleaned.isEmpty ? 'mark' : cleaned;
}

String csvRow(int tMs, Sample s) {
  String f(double? v) => v == null ? '' : formatFloat(v);
  final value = s.kind == 'event' ? sanitizeLabel(s.label ?? '') : f(s.value);
  return '$tMs,${s.source},${s.kind},${f(s.x)},${f(s.y)},${f(s.z)},$value';
}
