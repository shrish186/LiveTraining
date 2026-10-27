/// Turns low-level failures into on-screen messages that say what to check.
/// Pure Dart (no Flutter), so it is unit-testable.
library;

import 'dart:async';
import 'dart:io';

const backendChecklist = 'Check that:\n'
    '• the iPhone and the Mac are on the same Wi-Fi\n'
    '• backend/run_dev.sh is running on the Mac\n'
    '• the URL matches the one run_dev.sh printed\n'
    '• Local Network is allowed for Live Training (Settings › Privacy & Security › Local Network)';

/// null if [url] looks like a usable backend URL, otherwise what is wrong with it.
String? validateBackendUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'Backend URL "$url" is not valid. It should look like http://192.168.1.23:8000';
  }
  if (uri.scheme == 'https') {
    return 'Use http:// (not https://). The local backend does not use TLS.';
  }
  if (uri.scheme != 'http') return 'Backend URL must start with http://';
  if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
    return 'On the phone, "localhost" is the phone itself. Use the Mac\'s Wi-Fi IP that run_dev.sh '
        'printed, e.g. http://192.168.1.23:8000';
  }
  return null;
}

// errno values: Darwin (iOS/macOS) and Linux (Android).
const _refused = {61, 111};
const _unreachable = {51, 65, 101, 113};
const _timedOut = {60, 110};

/// Message for a failed request to the backend. Always ends with the exact underlying error.
String describeConnectionError(Object error, String baseUrl) {
  final String summary;
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    if (_refused.contains(code)) {
      summary = 'Connection refused at $baseUrl: the Mac was reached but nothing is listening on that port. '
          'Is backend/run_dev.sh running?';
    } else if (_unreachable.contains(code)) {
      summary = 'No route to $baseUrl. The phone cannot reach the Mac on this network, or Local Network '
          'access is off for Live Training.\n$backendChecklist';
    } else if (_timedOut.contains(code)) {
      summary = 'Timed out connecting to $baseUrl.\n$backendChecklist';
    } else {
      summary = 'Backend not reachable at $baseUrl.\n$backendChecklist';
    }
  } else if (error is TimeoutException) {
    summary = 'No answer from $baseUrl in time.\n$backendChecklist';
  } else if (error is HandshakeException || error is TlsException) {
    summary = 'TLS error talking to $baseUrl. Use http:// (not https://) for the local backend.';
  } else {
    summary = 'Backend not reachable at $baseUrl.\n$backendChecklist';
  }
  return '$summary\n\nDetails: $error';
}

/// Message for a non-success HTTP status from the backend.
String describeHttpStatus(int status, String path, {int? athleteId, String? detail}) {
  final extra = detail == null || detail.isEmpty ? '' : '\nServer said: $detail';
  if (path.startsWith('/athletes/') && status == 404) {
    return 'Athlete ID $athleteId not found on the backend. Copy your Athlete ID from the status page '
        '(http://localhost:8000 on the Mac).$extra';
  }
  if (status == 401) {
    return 'WHOOP is not connected for athlete $athleteId (or the connection expired). On the Mac, open '
        'http://localhost:8000 and click Connect WHOOP.$extra';
  }
  if (status == 429) return 'WHOOP rate limit reached. Try again in a minute.$extra';
  if (path == '/health') {
    return 'Something answered, but returned HTTP $status. Is this the Live Training backend?$extra';
  }
  return 'Backend returned HTTP $status.$extra';
}
