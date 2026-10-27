import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/segment_cached_audio_source.dart';

/// [SegmentCachedAudioSource] against a local server that answers byte-range
/// requests for one 1 MB file, counting what it is asked for.
void main() {
  const total = 1024 * 1024;
  final body = List<int>.generate(total, (i) => (i * 7 + i ~/ 1024) & 0xff);

  late HttpServer server;
  late Uri uri;
  late Directory dir;
  final served = <(int, int)>[]; // every range the server was asked for
  var servedBytes = 0;
  var etag = '"v1"';

  Future<void> handle(HttpRequest request) async {
    final header = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var endEx = total;
    if (header != null) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(header)!;
      start = int.parse(m.group(1)!);
      if (m.group(2)!.isNotEmpty) endEx = int.parse(m.group(2)!) + 1;
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${endEx - 1}/$total',
      );
    }
    served.add((start, endEx));
    servedBytes += endEx - start;
    request.response.headers.contentType = ContentType('audio', 'mpeg');
    request.response.headers.set(HttpHeaders.etagHeader, etag);
    request.response.contentLength = endEx - start;
    // Chunked, so the client sees several pieces as it would from a mirror.
    for (var at = start; at < endEx; at += 64 * 1024) {
      final to = at + 64 * 1024 < endEx ? at + 64 * 1024 : endEx;
      request.response.add(body.sublist(at, to));
      await request.response.flush();
    }
    await request.response.close();
  }

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
    uri = Uri.parse('http://127.0.0.1:${server.port}/053.mp3');
    dir = await Directory.systemTemp.createTemp('segment_cache_test');
    served.clear();
    servedBytes = 0;
    etag = '"v1"';
  });

  tearDown(() async {
    await server.close(force: true);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  File finalFile() => File('${dir.path}/053.mp3');
  File segFile() => File('${dir.path}/053.mp3.seg');
  File indexFile() => File('${dir.path}/053.mp3.seg.json');

  Future<List<int>> read(SegmentCachedAudioSource s, int start, int? end) async {
    final response = await s.request(start, end);
    expect(response.sourceLength, total);
    expect(response.offset, start);
    expect(response.contentLength, (end ?? total) - start);
    final out = <int>[];
    await for (final chunk in response.stream) {
      out.addAll(chunk);
    }
    return out;
  }

  // The index is written after each piece on a chained future; give it a tick.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 200));

  test('bytes heard once are never fetched again', () async {
    final first = SegmentCachedAudioSource(uri, finalFile: finalFile());
    expect(await read(first, 600 * 1024, 700 * 1024),
        body.sublist(600 * 1024, 700 * 1024));
    await settle();
    expect(servedBytes, 100 * 1024);
    expect(await segFile().exists(), isTrue);
    expect(await indexFile().exists(), isTrue);
    expect(await first.cachedFraction(), closeTo(100 / 1024, 0.001));

    // A new instance (a later playback) reads the same region from disk.
    served.clear();
    servedBytes = 0;
    final second = SegmentCachedAudioSource(uri, finalFile: finalFile());
    expect(await second.hasAnyBytes(), isTrue);
    expect(await read(second, 620 * 1024, 680 * 1024),
        body.sublist(620 * 1024, 680 * 1024));
    expect(servedBytes, 0, reason: 'served entirely from the cache');
  });

  test('a request straddling cached regions fetches only the holes', () async {
    final s = SegmentCachedAudioSource(uri, finalFile: finalFile());
    await read(s, 300 * 1024, 400 * 1024);
    await read(s, 500 * 1024, 600 * 1024);
    await settle();
    served.clear();
    servedBytes = 0;

    expect(await read(s, 250 * 1024, 650 * 1024),
        body.sublist(250 * 1024, 650 * 1024));
    expect(served, [
      (250 * 1024, 300 * 1024),
      (400 * 1024, 500 * 1024),
      (600 * 1024, 650 * 1024),
    ]);
    await settle();
    expect(await s.cachedFraction(), closeTo(400 / 1024, 0.001));
  });

  test('covering the whole file promotes it to the plain MP3', () async {
    var completed = 0;
    final s = SegmentCachedAudioSource(
      uri,
      finalFile: finalFile(),
      onComplete: () => completed++,
    );
    await read(s, 700 * 1024, null);
    expect(await read(s, 0, null), body);
    // The promotion is queued behind the index write; wait for it rather
    // than for a fixed time (slow under a full suite run).
    for (var i = 0; i < 100 && completed == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(completed, 1);
    expect(await finalFile().exists(), isTrue);
    expect(await finalFile().readAsBytes(), body);
    expect(await segFile().exists(), isFalse);
    expect(await indexFile().exists(), isFalse);
    expect(servedBytes, total, reason: 'the second pass skipped the cached tail');

    // From now on it is served from the complete file, with no network.
    served.clear();
    final again = SegmentCachedAudioSource(uri, finalFile: finalFile());
    expect(await read(again, 10, 20), body.sublist(10, 20));
    expect(served, isEmpty);
  });

  test('offline, a cached region plays and a missing one fails', () async {
    final s = SegmentCachedAudioSource(uri, finalFile: finalFile());
    await read(s, 0, 200 * 1024);
    await settle();
    await server.close(force: true);

    final later = SegmentCachedAudioSource(uri, finalFile: finalFile());
    expect(await read(later, 0, 100 * 1024), body.sublist(0, 100 * 1024));
    final response = await later.request(50 * 1024, 300 * 1024);
    final got = <int>[];
    await expectLater(
      response.stream.forEach(got.addAll),
      throwsA(isA<IOException>()),
    );
    expect(got, body.sublist(50 * 1024, 200 * 1024),
        reason: 'the cached part is delivered before the failure');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a file that changed on the mirror drops the stale cache', () async {
    final s = SegmentCachedAudioSource(uri, finalFile: finalFile());
    await read(s, 0, 100 * 1024);
    await settle();

    etag = '"v2"';
    final later = SegmentCachedAudioSource(uri, finalFile: finalFile());
    await read(later, 200 * 1024, 300 * 1024);
    await settle();
    expect(await later.cachedFraction(), closeTo(100 / 1024, 0.001),
        reason: 'only the new region remains');
    // The old region is fetched again rather than trusted.
    served.clear();
    await read(later, 0, 100 * 1024);
    expect(served, [(0, 100 * 1024)]);
  });

  test('the network is read only ~90 s ahead of the playhead', () async {
    // 1 MB over 1024 s: 1 KB per second of audio, so the lookahead is 90 KB.
    var position = Duration.zero;
    final s = SegmentCachedAudioSource(
      uri,
      finalFile: finalFile(),
      playerPosition: () => position,
      mediaDuration: const Duration(seconds: 1024),
    );
    final response = await s.request(0, null);
    var got = 0;
    final sub = response.stream.listen((c) => got += c.length);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(got, lessThan(200 * 1024),
        reason: 'held at the lookahead, not the whole file');
    expect(got, greaterThanOrEqualTo(90 * 1024));

    position = const Duration(seconds: 500); // the player moved on
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(got, greaterThan(500 * 1024));
    expect(got, lessThan(700 * 1024));
    await sub.cancel();
  });

  test('an index without its data file is discarded, not trusted', () async {
    final s = SegmentCachedAudioSource(uri, finalFile: finalFile());
    await read(s, 0, 100 * 1024);
    await settle();
    await segFile().delete();

    final later = SegmentCachedAudioSource(uri, finalFile: finalFile());
    expect(await later.hasAnyBytes(), isFalse);
    expect(await indexFile().exists(), isFalse);
    expect(await read(later, 0, 100 * 1024), body.sublist(0, 100 * 1024));
  });
}
