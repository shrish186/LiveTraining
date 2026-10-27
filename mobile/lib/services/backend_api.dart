import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class Recovery {
  Recovery.fromJson(Map<String, dynamic> j)
      : scoreState = j['score_state'] as String?,
        recoveryScore = (j['recovery_score'] as num?)?.toDouble(),
        restingHr = (j['resting_heart_rate'] as num?)?.toDouble(),
        hrvMs = (j['hrv_rmssd_milli'] as num?)?.toDouble(),
        calibrating = j['user_calibrating'] as bool? ?? false,
        createdAt = DateTime.tryParse(j['created_at'] as String? ?? '');

  final String? scoreState;
  final double? recoveryScore;
  final double? restingHr;
  final double? hrvMs;
  final bool calibrating;
  final DateTime? createdAt;
}

class BackendException implements Exception {
  BackendException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum UploadResult { uploaded, alreadyUploaded }

class BackendApi {
  BackendApi(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<void> health() async {
    try {
      final r = await _client.get(_uri('/health')).timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) throw BackendException('HTTP ${r.statusCode}');
    } on BackendException {
      rethrow;
    } on Exception catch (e) {
      throw BackendException('Backend not reachable at $baseUrl ($e)');
    }
  }

  Future<Recovery> latestRecovery(int athleteId) async {
    final http.Response r;
    try {
      r = await _client.get(_uri('/athletes/$athleteId/whoop/recovery/latest')).timeout(_timeout);
    } on Exception catch (e) {
      throw BackendException('Backend not reachable at $baseUrl ($e)');
    }
    if (r.statusCode == 200) return Recovery.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw BackendException(_detail(r));
  }

  Future<UploadResult> uploadSession(File csv, File metadata) async {
    final request = http.MultipartRequest('POST', _uri('/sessions'))
      ..fields['metadata'] = await metadata.readAsString()
      ..files.add(await http.MultipartFile.fromPath('file', csv.path, filename: csv.uri.pathSegments.last));
    final http.Response r;
    try {
      r = await http.Response.fromStream(await _client.send(request).timeout(const Duration(minutes: 5)));
    } on Exception catch (e) {
      throw BackendException('Backend not reachable at $baseUrl ($e)');
    }
    if (r.statusCode == 201) return UploadResult.uploaded;
    if (r.statusCode == 409) return UploadResult.alreadyUploaded;
    throw BackendException(_detail(r));
  }

  static String _detail(http.Response r) {
    try {
      final detail = (jsonDecode(r.body) as Map<String, dynamic>)['detail'];
      if (detail is Map && detail['errors'] is List) return (detail['errors'] as List).take(3).join('\n');
      if (detail != null) return '$detail';
    } on FormatException {
      // not JSON
    }
    return 'HTTP ${r.statusCode}';
  }
}
