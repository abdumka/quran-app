import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:islamic_dawah_mushaf/models/athkar.dart';
import 'package:islamic_dawah_mushaf/services/app_update_service.dart';
import 'package:islamic_dawah_mushaf/services/athkar_service.dart';
import 'package:islamic_dawah_mushaf/services/content_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The promise behind shipping the athkar before their audio review ends:
/// fixed timings, re-cut clips and dropped voices reach a released build
/// through the `athkar` server item, with no store update.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = ContentUpdateService.instance;
  late Directory dir;
  late String bundled;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('athkar_update_');
    service.debugReset(dir: dir);
    AppUpdateService.instance.currentBuild = 151;
    bundled = File('assets/data/athkar.json').readAsStringSync();
    AthkarService.instance.debugSetData(AthkarData.parse(bundled));
  });

  tearDown(() async {
    service.debugReset();
    AppUpdateService.instance.currentBuild = 0;
    await dir.delete(recursive: true);
  });

  /// The bundled file with the server's fixes: one span moved, one clip
  /// moved to a re-cut folder, the last voice dropped.
  (String, String, String) fixed() {
    final j = json.decode(bundled) as Map<String, dynamic>;
    final ver = (j['ver'] as int) + 1;
    j['ver'] = ver;
    final voices = (j['reciters'] as List).cast<Map<String, dynamic>>();
    final first = voices.first;
    final spans = (first['spans'] as Map).cast<String, dynamic>();
    final id = spans.keys.first;
    spans[id] = [1.25, 4.5];
    first['url'] = (first['url'] as String).replaceFirst('/v2/', '/v3/');
    final dropped = voices.removeLast()['id'] as String;
    final body = json.encode(j);
    final bytes = utf8.encode(body);
    final manifest = json.encode({
      'v': 1,
      'items': {
        'athkar': {
          'ver': ver,
          'url': 'data/athkar/athkar_v$ver.json',
          'sha256': sha256.convert(bytes).toString(),
          'bytes': bytes.length,
          'minBuild': 148,
        },
      },
    });
    return (manifest, body, '$id|$dropped');
  }

  MockClient client(String manifest, String body) => MockClient((r) async {
    if (r.url.path == '/data/manifest.json') {
      return http.Response(manifest, 200);
    }
    if (r.url.path.endsWith('.json') && r.url.path.contains('athkar_v')) {
      return http.Response.bytes(utf8.encode(body), 200);
    }
    return http.Response('not found', 404);
  });

  test('a fixed athkar file reaches the app while it runs', () async {
    final (manifest, body, info) = fixed();
    final [id, dropped] = info.split('|');
    final before = AthkarService.instance.data;
    expect(before.reciters.any((r) => r.id == dropped), isTrue);

    final result = await service.check(
      manual: true,
      client: client(manifest, body),
    );
    expect(result.updated, ['athkar']);
    expect(result.pendingRestart, isEmpty);

    final now = AthkarService.instance.data;
    expect(now.version, before.version + 1);
    expect(now.reciters.any((r) => r.id == dropped), isFalse);
    final first = now.reciters.first;
    final item = now.item(int.parse(id))!;
    expect(first.spanFor(item), (
      const Duration(milliseconds: 1250),
      const Duration(milliseconds: 4500),
    ));
    expect(first.urlFor(item), contains('/v3/'));
  });

  test('a build older than minBuild keeps its own athkar', () async {
    AppUpdateService.instance.currentBuild = 147;
    final (manifest, body, _) = fixed();
    final result = await service.check(
      manual: true,
      client: client(manifest, body),
    );
    expect(result.updated, isEmpty);
  });

  test('the downloaded file is used at the next start too', () async {
    final (manifest, body, _) = fixed();
    await service.check(manual: true, client: client(manifest, body));
    expect(await service.readFor('athkar'), body);
  });
}
