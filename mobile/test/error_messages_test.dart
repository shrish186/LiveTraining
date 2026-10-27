import 'dart:async';
import 'dart:io';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_training/services/backend_api.dart';
import 'package:live_training/sources/ble_status_message.dart';
import 'package:live_training/util/error_messages.dart';

const url = 'http://192.168.1.23:8000';

SocketException socketError(int errno, String msg) =>
    SocketException('Connection failed', osError: OSError(msg, errno));

void main() {
  group('validateBackendUrl', () {
    test('accepts a LAN http URL', () => expect(validateBackendUrl(url), isNull));
    test('rejects garbage, https, localhost', () {
      expect(validateBackendUrl('192.168.1.23:8000'), contains('not valid'));
      expect(validateBackendUrl(''), contains('not valid'));
      expect(validateBackendUrl('https://192.168.1.23:8000'), contains('http://'));
      expect(validateBackendUrl('http://localhost:8000'), contains('phone itself'));
    });
  });

  group('describeConnectionError', () {
    test('connection refused points at run_dev.sh', () {
      final m = describeConnectionError(socketError(61, 'Connection refused'), url);
      expect(m, contains('nothing is listening'));
      expect(m, contains('run_dev.sh'));
      expect(m, contains('Details: SocketException'));
      expect(m, contains('Connection refused'));
    });
    test('no route mentions same Wi-Fi and Local Network', () {
      final m = describeConnectionError(socketError(65, 'No route to host'), url);
      expect(m, contains('same Wi-Fi'));
      expect(m, contains('Local Network'));
    });
    test('timeout', () {
      expect(describeConnectionError(TimeoutException('x'), url), contains('No answer'));
    });
    test('anything else still gives the checklist and the exact error', () {
      final m = describeConnectionError(http.ClientException('boom'), url);
      expect(m, contains('run_dev.sh'));
      expect(m, endsWith('Details: ClientException: boom'));
    });
  });

  group('describeHttpStatus', () {
    test('unknown athlete', () {
      expect(describeHttpStatus(404, '/athletes/9/whoop/recovery/latest', athleteId: 9), contains('Athlete ID 9'));
    });
    test('WHOOP not connected', () {
      expect(describeHttpStatus(401, '/athletes/1/whoop/recovery/latest', athleteId: 1), contains('Connect WHOOP'));
    });
    test('health answered by something else', () {
      expect(describeHttpStatus(404, '/health'), contains('Live Training backend'));
    });
  });

  group('BackendApi', () {
    test('health ok', () async {
      final api = BackendApi(url, client: MockClient((r) async {
        expect(r.url.toString(), '$url/health');
        return http.Response('{"status":"ok"}', 200);
      }));
      await api.health();
    });
    test('health refused -> clear message', () async {
      final api = BackendApi(url, client: MockClient((_) => throw socketError(61, 'Connection refused')));
      expect(api.health, throwsA(isA<BackendException>().having((e) => e.message, 'message', contains('run_dev.sh'))));
    });
    test('invalid URL never makes a request', () async {
      var calls = 0;
      final api = BackendApi('192.168.1.23', client: MockClient((_) async {
        calls++;
        return http.Response('', 200);
      }));
      await expectLater(api.health(), throwsA(isA<BackendException>()));
      expect(calls, 0);
    });
    test('recovery 401 -> reconnect WHOOP', () async {
      final api = BackendApi(url, client: MockClient((_) async => http.Response('{"detail":"WHOOP not connected"}', 401)));
      expect(() => api.latestRecovery(1),
          throwsA(isA<BackendException>().having((e) => e.message, 'message', contains('Connect WHOOP'))));
    });
  });

  group('bleStatusMessage', () {
    test('ready and unknown are not errors', () {
      expect(bleStatusMessage(BleStatus.ready, isIOS: true), isNull);
      expect(bleStatusMessage(BleStatus.unknown, isIOS: true), isNull);
    });
    test('off and unauthorized explain the fix', () {
      expect(bleStatusMessage(BleStatus.poweredOff, isIOS: true), contains('Bluetooth is off'));
      expect(bleStatusMessage(BleStatus.unauthorized, isIOS: true), contains('Privacy & Security › Bluetooth'));
      expect(bleStatusMessage(BleStatus.unauthorized, isIOS: false), contains('Nearby devices'));
      expect(bleStatusNeedsSettings(BleStatus.unauthorized), isTrue);
      expect(bleStatusNeedsSettings(BleStatus.poweredOff), isFalse);
    });
    test('HR not found reminds about Heart Rate Broadcast', () {
      expect(hrNotFoundMessage, contains('Heart Rate Broadcast'));
    });
  });
}
