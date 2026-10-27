import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../util/error_messages.dart';

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
  static const _timeout = Duration(seconds: 10);

  Uri _uri(String path) {
    final problem = validateBackendUrl(baseUrl);
    if (problem != null) throw BackendException(problem);
    return Uri.parse('$baseUrl$path');
  }

  /// Runs [request]; network failures become a BackendException with a clear message.
  Future<http.Response> _call(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on BackendException {
      rethrow;
    } catch (e) {
      throw BackendException(describeConnectionError(e, baseUrl));
    }
  }

  Never _fail(http.Response r, String path, {int? athleteId}) =>
      throw BackendException(describeHttpStatus(r.statusCode, path, athleteId: athleteId, detail: _detail(r)));

  Future<void> health() async {
    final uri = _uri('/health');
    final r = await _call(() => _client.get(uri).timeout(const Duration(seconds: 5)));
    if (r.statusCode != 200) _fail(r, '/health');
  }

  Future<Recovery> latestRecovery(int athleteId) async {
    final path = '/athletes/$athleteId/whoop/recovery/latest';
    final uri = _uri(path);
    final r = await _call(() => _client.get(uri).timeout(_timeout));
    if (r.statusCode == 200) return Recovery.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    if (r.statusCode == 404 && _detail(r) == 'no recovery yet') {
      throw BackendException('WHOOP has no recovery for you yet. It appears after your first scored sleep.');
    }
    _fail(r, path, athleteId: athleteId);
  }

  Future<UploadResult> uploadSession(File csv, File metadata) async {
    final uri = _uri('/sessions');
    final request = http.MultipartRequest('POST', uri)
      ..fields['metadata'] = await metadata.readAsString()
      ..files.add(await http.MultipartFile.fromPath('file', csv.path, filename: csv.uri.pathSegments.last));
    final r = await _call(
        () async => http.Response.fromStream(await _client.send(request).timeout(const Duration(minutes: 5))));
    if (r.statusCode == 201) return UploadResult.uploaded;
    if (r.statusCode == 409) return UploadResult.alreadyUploaded;
    _fail(r, '/sessions');
  }

  static String? _detail(http.Response r) {
    try {
      final detail = (jsonDecode(r.body) as Map<String, dynamic>)['detail'];
      if (detail is Map && detail['errors'] is List) return (detail['errors'] as List).take(3).join('\n');
      if (detail != null) return '$detail';
    } on FormatException {
      // not JSON
    } on TypeError {
      // JSON but not an object
    }
    return null;
  }
}
