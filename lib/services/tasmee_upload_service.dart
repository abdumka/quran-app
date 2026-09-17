import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Uploads Tasmee session files (WAV + JSONL) straight to a private R2
/// bucket with an S3 signature-v4 `PUT`, so the owner can collect real
/// recitations without the share sheet.
///
/// Credentials are baked in at build time from a gitignored JSON file:
///
///     flutter build apk --dart-define-from-file=tools/r2_upload.json
///
/// with keys `R2_UPLOAD_ENDPOINT` (`https://<account>.r2.cloudflarestorage.com`),
/// `R2_UPLOAD_BUCKET`, `R2_UPLOAD_KEY_ID`, `R2_UPLOAD_SECRET`. The token must
/// be *object-write only* and scoped to that one bucket: it ships inside the
/// app, so it must not be able to read, list or delete anything. Without
/// the defines the service reports [isConfigured] false and the UI keeps
/// offering the share sheet only.
///
/// Objects land at `<installId>/<file name>`; the file name already carries
/// the install id, timestamp and page.
class TasmeeUploadService {
  TasmeeUploadService._();
  static final TasmeeUploadService instance = TasmeeUploadService._();

  static const String _endpoint = String.fromEnvironment('R2_UPLOAD_ENDPOINT');
  static const String _bucket = String.fromEnvironment('R2_UPLOAD_BUCKET');
  static const String _keyId = String.fromEnvironment('R2_UPLOAD_KEY_ID');
  static const String _secret = String.fromEnvironment('R2_UPLOAD_SECRET');

  bool get isConfigured =>
      _endpoint.isNotEmpty && _bucket.isNotEmpty && _keyId.isNotEmpty && _secret.isNotEmpty;

  /// 0..1 across the files of the current [uploadAll] call.
  final ValueNotifier<double> progress = ValueNotifier(0);
  final ValueNotifier<bool> busy = ValueNotifier(false);

  /// Uploads every file; returns the paths that failed (empty on success).
  Future<List<String>> uploadAll(List<String> paths, {required String installId}) async {
    if (!isConfigured) return List.of(paths);
    busy.value = true;
    progress.value = 0;
    final failed = <String>[];
    final client = http.Client();
    try {
      var done = 0;
      for (final path in paths) {
        final file = File(path);
        if (!await file.exists()) {
          done++;
          continue;
        }
        final name = path.split(Platform.pathSeparator).last;
        try {
          await _put(client, '$installId/$name', await file.readAsBytes(), _contentTypeFor(name));
        } catch (error) {
          debugPrint('TasmeeUploadService: $name failed: $error');
          failed.add(path);
        }
        done++;
        progress.value = done / paths.length;
      }
    } finally {
      client.close();
      busy.value = false;
    }
    return failed;
  }

  static String _contentTypeFor(String name) {
    if (name.endsWith('.wav')) return 'audio/wav';
    if (name.endsWith('.jsonl')) return 'application/x-ndjson';
    if (name.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }

  Future<void> _put(http.Client client, String key, List<int> body, String contentType) async {
    final uri = Uri.parse('$_endpoint/$_bucket/${Uri.encodeComponent(key).replaceAll('%2F', '/')}');
    final now = DateTime.now().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final payloadHash = sha256.convert(body).toString();
    final headers = <String, String>{
      'host': uri.host,
      'content-type': contentType,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
    };
    final signedHeaderNames = headers.keys.toList()..sort();
    final canonicalHeaders = signedHeaderNames.map((h) => '$h:${headers[h]!.trim()}\n').join();
    final signedHeaders = signedHeaderNames.join(';');
    final canonicalRequest = [
      'PUT',
      uri.path,
      '',
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');
    const region = 'auto';
    final scope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    final kDate = _hmac(utf8.encode('AWS4$_secret'), dateStamp);
    final kRegion = _hmac(kDate, region);
    final kService = _hmac(kRegion, 's3');
    final kSigning = _hmac(kService, 'aws4_request');
    final signature = Hmac(sha256, kSigning).convert(utf8.encode(stringToSign)).toString();
    final authorization =
        'AWS4-HMAC-SHA256 Credential=$_keyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature';
    final response = await client.put(
      uri,
      headers: {
        ...headers,
        'authorization': authorization,
        'content-length': body.length.toString(),
      },
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: ${response.body}', uri: uri);
    }
  }

  static List<int> _hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  static String _amzDate(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  }
}
