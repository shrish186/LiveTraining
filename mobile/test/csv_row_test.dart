import 'package:flutter_test/flutter_test.dart';
import 'package:live_training/recording/csv_row.dart';
import 'package:live_training/sources/motion_source.dart';

void main() {
  test('header matches docs/session-format.md exactly', () {
    expect(csvHeader, 't_ms,source,kind,x,y,z,value');
  });

  group('formatFloat', () {
    test('trims zeros, max 5 decimals', () {
      expect(formatFloat(9.81), '9.81');
      expect(formatFloat(12.0), '12');
      expect(formatFloat(1.234567), '1.23457');
      expect(formatFloat(-0.5), '-0.5');
    });
    test('no negative zero', () {
      expect(formatFloat(-0.000001), '0');
      expect(formatFloat(0), '0');
    });
    test('non-finite becomes empty', () {
      expect(formatFloat(double.nan), '');
      expect(formatFloat(double.infinity), '');
    });
  });

  group('csvRow', () {
    test('acc and gyro fill x,y,z and leave value empty', () {
      expect(csvRow(4, const Sample.vector('phone', 'acc', 0.1214, 9.7902, 0.3311)),
          '4,phone,acc,0.1214,9.7902,0.3311,');
      expect(csvRow(5, const Sample.vector('phone', 'gyro', 0.0012, -0.0031, 0)),
          '5,phone,gyro,0.0012,-0.0031,0,');
    });
    test('hr and rr use value only', () {
      expect(csvRow(812, const Sample.scalar('whoop_hr', 'hr', 72)), '812,whoop_hr,hr,,,,72');
      expect(csvRow(812, const Sample.scalar('whoop_hr', 'rr', 833.984375)), '812,whoop_hr,rr,,,,833.98438');
    });
    test('event labels are sanitised', () {
      expect(csvRow(15032, const Sample.event('phone', 'sync_jumps')), '15032,phone,event,,,,sync_jumps');
      expect(csvRow(1, const Sample.event('phone', 'set 2, "heavy"\n')), '1,phone,event,,,,set 2   heavy');
      expect(csvRow(1, const Sample.event('phone', ' , ')), '1,phone,event,,,,mark');
    });
    test('every row has 7 columns', () {
      for (final s in const [
        Sample.vector('phone', 'acc', 1, 2, 3),
        Sample.scalar('whoop_hr', 'hr', 60),
        Sample.event('phone', 'x'),
      ]) {
        expect(csvRow(0, s).split(',').length, 7);
      }
    });
  });
}
