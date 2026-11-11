import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/services/session_store.dart';

void main() {
  test('delete removes the CSV and the metadata, and tolerates missing files', () async {
    final dir = await Directory.systemTemp.createTemp('lt_store');
    addTearDown(() => dir.delete(recursive: true));
    final csv = File('${dir.path}/s.csv')..writeAsStringSync('t_ms,source,kind,x,y,z,value\n');
    final json = File('${dir.path}/s.json')..writeAsStringSync('{"session_id":"s"}');
    final s = LocalSession('s', csv, json, const {'session_id': 's'});
    await SessionStore.delete(s);
    expect(csv.existsSync() || json.existsSync(), isFalse);
    await SessionStore.delete(s); // already gone: no error
  });
}
