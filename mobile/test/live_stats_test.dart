import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/util/live_stats.dart';

void main() {
  group('RollingSeries', () {
    test('keeps only the last N values', () {
      final s = RollingSeries(3);
      for (final v in [1.0, 2.0, 3.0, 4.0]) {
        s.add(v);
      }
      expect(s.values, [2.0, 3.0, 4.0]);
    });

    test('range ignores gaps', () {
      final s = RollingSeries(5)
        ..add(null)
        ..add(70)
        ..add(null)
        ..add(150)
        ..add(90);
      expect(s.range, (70.0, 150.0));
      expect((RollingSeries(2)..add(null)).range, isNull);
    });
  });

  group('SessionStats', () {
    test('average and max HR', () {
      final st = SessionStats();
      expect(st.hrAvg, isNull);
      for (final bpm in [100.0, 150.0, 170.0]) {
        st.addHr(bpm);
      }
      expect(st.hrAvg, closeTo(140, 1e-9));
      expect(st.hrMax, 170);
    });

    test('load integrates magnitude over minutes', () {
      final st = SessionStats();
      for (var i = 0; i < 300; i++) {
        st.addMotion(2.0, 0.2); // 2 m/s² for 60 s
      }
      expect(st.load, closeTo(2.0, 1e-9));
    });
  });
}
