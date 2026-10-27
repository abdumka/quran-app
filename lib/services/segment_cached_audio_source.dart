// just_audio marks StreamAudioSource experimental; its own
// LockCachingAudioSource is built on the same API and the version is pinned.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// A whole-surah MP3 streamed from the reciter mirror, with every byte that
/// passes through kept on disk, so that nothing is ever fetched twice.
///
/// [AudioScheme.timedSurah] reciters keep a surah in ONE file, so the player
/// reaches an ayah with an HTTP range request straight to its offset and only
/// the bytes actually listened to are transferred. That is right for a phone
/// on a poor connection, but until now those bytes were thrown away: playing
/// the same surah tomorrow fetched it again, and offline nothing of it played.
///
/// This source sits between the player and the mirror (just_audio's local
/// proxy hands it each range request). Bytes are served from the cache where
/// they are present and from the network where they are not, and the fetched
/// ones are written as they arrive. The cache is sparse: a listener who taps
/// ayah 200 of al-Baqarah stores exactly that region, and the regions grow
/// and merge as more is heard. When they cover the whole file it is renamed to
/// the plain `SSS.mp3` the explicit download flow produces, so the surah shows
/// as downloaded in «تحميل الصوتيات» and plays from disk like any other.
///
/// On disk, beside the final file:
/// * `SSS.mp3.seg`       the sparse data file (holes where nothing is cached);
/// * `SSS.mp3.seg.json`  `{total, etag, ranges: [[start, endEx], ...]}`.
///
/// An index only ever describes bytes that were written and flushed, so a
/// stale or truncated index can lose cached regions but never invent them.
/// Every disk failure (full phone, deleted folder) turns the source into a
/// plain pass-through for the rest of its life: playback is never the thing
/// that suffers.
class SegmentCachedAudioSource extends StreamAudioSource {
  /// The remote file.
  final Uri uri;

  /// The complete file, if it exists: `SSS.mp3` in the reciter's cache folder.
  final File finalFile;

  /// Called once, when the cache has just become the complete file.
  final void Function()? onComplete;

  /// Where the player is in the file right now, if known. With [mediaDuration]
  /// it paces the network: the proxy between this source and the player
  /// buffers whatever it is handed without limit, so left alone a surah would
  /// be pulled whole the moment its first ayah played (measured: 7.5 MB in
  /// under 8 s). Fetching stops [_lookahead] beyond the playhead instead,
  /// which bounds memory and keeps the data cost to what is listened to.
  final Duration Function()? playerPosition;

  /// How long the whole file plays for, from the reciter's timing file.
  final Duration? mediaDuration;

  /// How far ahead of the playhead the network is read. ExoPlayer itself
  /// buffers up to 50 s, so this must stay comfortably above that.
  static const Duration _lookahead = Duration(seconds: 90);

  /// Byte rate assumed when [mediaDuration] is unknown: well above any
  /// reciter's real rate, so the pacing can only ever be too generous.
  static const int _fallbackBytesPerSecond = 40 * 1024;

  /// Number of fetched bytes between two writes of the index file.
  static const int _indexEvery = 512 * 1024;

  /// How many times a range fetch is tried on a connection error before the
  /// request is given up, the pause before a retry, and how often a piece
  /// that failed part-way is resumed. Kept small: with no network at all
  /// these add up to the silence before the offline notice (about 5 s).
  static const int _attempts = 2;
  static const int _resumes = 2;
  static const Duration _retryDelay = Duration(seconds: 1);

  late final File _dataFile = File('${finalFile.path}.seg');
  late final File _indexFile = File('${finalFile.path}.seg.json');

  int? _total;
  String? _etag;
  String _contentType = 'audio/mpeg';

  /// Cached regions as `[start, endEx)`, sorted and non-overlapping.
  List<List<int>> _ranges = [];

  Future<void>? _loading;
  bool _diskOk = true;
  bool _complete = false;

  /// Bumped by [_resetCache]: a piece opened against the previous data file
  /// must not record what it writes into the new one.
  int _generation = 0;
  Future<void> _indexWrites = Future.value();

  /// The `HttpClient` all fetches share; created lazily, closed with [dispose].
  HttpClient? _http;

  SegmentCachedAudioSource(
    this.uri, {
    required this.finalFile,
    this.onComplete,
    this.playerPosition,
    this.mediaDuration,
    super.tag,
  });

  /// The byte the network may be read up to right now, or null when there
  /// is nothing to pace against (no player position).
  int? _paceLimit() {
    final position = playerPosition?.call();
    final total = _total;
    if (position == null || total == null) return null;
    final seconds = mediaDuration?.inMilliseconds;
    final bytesPerSecond = (seconds != null && seconds > 0)
        ? total * 1000 / seconds
        : _fallbackBytesPerSecond.toDouble();
    final ahead = position + _lookahead;
    return (ahead.inMilliseconds / 1000 * bytesPerSecond).round();
  }

  /// Whether anything at all of this file is on disk (the complete file or
  /// any cached region). Used by the playback path to decide whether an
  /// offline attempt stands any chance.
  Future<bool> hasAnyBytes() async {
    await _load();
    return _complete || _ranges.isNotEmpty;
  }

  /// Fraction of the file that is cached, 0..1 (1 when complete).
  Future<double> cachedFraction() async {
    await _load();
    if (_complete) return 1;
    final total = _total;
    if (total == null || total <= 0) return 0;
    var sum = 0;
    for (final r in _ranges) {
      sum += r[1] - r[0];
    }
    return (sum / total).clamp(0, 1).toDouble();
  }

  /// Reads the index once. Safe to call repeatedly.
  Future<void> _load() => _loading ??= _loadIndex();

  Future<void> _loadIndex() async {
    try {
      if (await finalFile.exists()) {
        _complete = true;
        _total = await finalFile.length();
        // The complete file makes the partial pair redundant.
        _deleteQuietly(_dataFile);
        _deleteQuietly(_indexFile);
        return;
      }
      if (!await _indexFile.exists() || !await _dataFile.exists()) {
        // One without the other means nothing trustworthy: start over.
        _deleteQuietly(_dataFile);
        _deleteQuietly(_indexFile);
        return;
      }
      final json =
          jsonDecode(await _indexFile.readAsString()) as Map<String, dynamic>;
      final total = (json['total'] as num?)?.toInt();
      final dataLength = await _dataFile.length();
      if (total == null || total <= 0 || dataLength > total) {
        _resetCache();
        return;
      }
      _total = total;
      _etag = json['etag'] as String?;
      final ranges = <List<int>>[];
      for (final r in (json['ranges'] as List? ?? const [])) {
        if (r is! List || r.length < 2) continue;
        final start = (r[0] as num).toInt();
        final end = (r[1] as num).toInt();
        // A region past what the data file holds was never written.
        if (start < 0 || end <= start || end > dataLength) continue;
        ranges.add([start, end]);
      }
      _ranges = _merge(ranges);
    } catch (e) {
      debugPrint('segment cache: index unreadable for ${finalFile.path}: $e');
      _resetCache();
    }
  }

  void _resetCache() {
    _generation++;
    _ranges = [];
    _total = null;
    _etag = null;
    _deleteQuietly(_dataFile);
    _deleteQuietly(_indexFile);
  }

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  static List<List<int>> _merge(List<List<int>> ranges) {
    if (ranges.length < 2) return ranges;
    ranges.sort((a, b) => a[0].compareTo(b[0]));
    final out = <List<int>>[ranges.first];
    for (final r in ranges.skip(1)) {
      final last = out.last;
      if (r[0] <= last[1]) {
        if (r[1] > last[1]) last[1] = r[1];
      } else {
        out.add(r);
      }
    }
    return out;
  }

  void _addRange(int start, int end) {
    if (end <= start) return;
    _ranges = _merge([..._ranges, [start, end]]);
  }

  /// The cached region containing [pos], if any.
  List<int>? _rangeAt(int pos) {
    for (final r in _ranges) {
      if (pos >= r[0] && pos < r[1]) return r;
      if (r[0] > pos) break;
    }
    return null;
  }

  /// Where the first cached byte at or after [pos] is, or null if none.
  int? _nextCachedStart(int pos) {
    for (final r in _ranges) {
      if (r[0] >= pos) return r[0];
    }
    return null;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    await _load();
    start ??= 0;

    // The explicit download flow may have completed the file since this
    // source was created (it writes `.part` and renames, so an existing file
    // is always whole): read from it rather than the mirror from now on.
    if (!_complete && finalFile.existsSync()) {
      _complete = true;
      _total = finalFile.lengthSync();
    }

    if (_complete) {
      final total = _total ?? await finalFile.length();
      final endEx = end ?? total;
      return StreamAudioResponse(
        sourceLength: total,
        contentLength: endEx - start,
        offset: start,
        stream: finalFile.openRead(start, endEx),
        contentType: _contentType,
      );
    }

    // The player's first request arrives before the file's size is known.
    // Open the network fetch for it now, learn the size from the response,
    // and let the body serve as the first piece rather than probing twice.
    HttpClientResponse? opened;
    if (_total == null) {
      opened = await _openRange(start, end); // learns the size
    }
    final total = _total!;
    final endEx = end == null ? total : (end < total ? end : total);
    return StreamAudioResponse(
      sourceLength: total,
      contentLength: endEx - start,
      offset: start,
      stream: _serve(start, endEx, opened),
      contentType: _contentType,
    );
  }

  /// Yields `[from, toEx)`: cached regions from disk, the rest from the
  /// network. [opened] is a response already opened at [from] (see
  /// [request]), used as the first network piece.
  Stream<List<int>> _serve(
    int from,
    int toEx,
    HttpClientResponse? opened,
  ) async* {
    final cursor = _Cursor(from);
    var resumes = 0;
    while (cursor.pos < toEx) {
      final pos = cursor.pos;
      if (_complete) {
        yield* finalFile.openRead(pos, toEx);
        return;
      }
      final cached = _rangeAt(pos);
      if (cached != null && opened == null) {
        final pieceEnd = cached[1] < toEx ? cached[1] : toEx;
        try {
          yield* _dataFile.openRead(pos, pieceEnd);
          cursor.pos = pieceEnd;
          continue;
        } catch (e) {
          // The data file is gone or unreadable (downloads deleted while a
          // surah was playing, a file-system error): forget the cache and
          // carry on from the network.
          debugPrint('segment cache: read failed, falling back: $e');
          _ranges = [];
          _diskOk = false;
        }
      }
      // A network piece runs up to the next cached region (or the end).
      final nextCached = _nextCachedStart(pos + 1);
      var pieceEnd = toEx;
      if (opened == null && nextCached != null && nextCached < pieceEnd) {
        pieceEnd = nextCached;
      }
      try {
        final response = opened ?? await _openRange(pos, pieceEnd);
        opened = null;
        yield* _fetchPiece(response, cursor, pieceEnd);
      } on IOException catch (e) {
        // The link dropped part-way through a piece. Everything up to
        // cursor.pos was delivered (and cached), so pick up from there.
        opened = null;
        if (++resumes > _resumes) rethrow;
        debugPrint('segment cache: resuming at ${cursor.pos} after: $e');
        await Future<void>.delayed(_retryDelay);
      }
    }
  }

  /// Streams one network response from [cursor]'s position, writing every
  /// chunk to the data file as it passes, and stops at [toEx] (the response
  /// may run further when it was opened for a longer request). [cursor]
  /// always tells how far the bytes were delivered, also when the response
  /// fails part-way.
  Stream<List<int>> _fetchPiece(
    HttpClientResponse response,
    _Cursor cursor,
    int toEx,
  ) async* {
    RandomAccessFile? raf;
    final generation = _generation;
    if (_diskOk) {
      try {
        raf = await _dataFile.open(mode: FileMode.append);
      } catch (e) {
        debugPrint('segment cache: cannot open data file: $e');
        _diskOk = false;
      }
    }
    var sinceIndex = 0;
    try {
      await for (var chunk in response) {
        final pos = cursor.pos;
        if (pos >= toEx) break;
        // Hold the network (the await pauses the response, and TCP flow
        // control holds the server) while the player has enough ahead of it.
        // The empty yield is how a hold learns the request was dropped (the
        // player seeked elsewhere, or stopped): after a cancel a yield ends
        // the generator, so the connection is released instead of being
        // held for a playhead that is never coming.
        for (var limit = _paceLimit(); limit != null && pos > limit;
            limit = _paceLimit()) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          yield const <int>[];
        }
        if (pos + chunk.length > toEx) {
          chunk = chunk.sublist(0, toEx - pos);
        }
        if (raf != null && generation != _generation) {
          // The cache was reset under this piece: its file is gone.
          try {
            await raf.close();
          } catch (_) {}
          raf = null;
        }
        if (raf != null) {
          try {
            await raf.setPosition(pos);
            await raf.writeFrom(chunk);
            _addRange(pos, pos + chunk.length);
            sinceIndex += chunk.length;
            if (sinceIndex >= _indexEvery) {
              sinceIndex = 0;
              await raf.flush();
              _scheduleIndexWrite();
            }
          } catch (e) {
            // Out of space, folder removed... stop caching, keep playing.
            debugPrint('segment cache: write failed, caching off: $e');
            _diskOk = false;
            try {
              await raf.close();
            } catch (_) {}
            raf = null;
          }
        }
        cursor.pos = pos + chunk.length;
        yield chunk;
      }
    } finally {
      if (raf != null) {
        try {
          await raf.flush();
          await raf.close();
        } catch (_) {}
        if (generation == _generation) {
          _scheduleIndexWrite();
          _promoteIfComplete();
        }
      }
    }
  }

  /// Opens `GET uri` with `Range: bytes=from-(toEx-1)`, retrying connection
  /// failures a few times: a mobile link that drops for a second should not
  /// end the recitation.
  Future<HttpClientResponse> _openRange(int from, int? toEx) async {
    Object? lastError;
    for (var attempt = 0; attempt < _attempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_retryDelay * attempt);
      try {
        final client = _http ??= HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);
        final request = await client.getUrl(uri);
        final rangeEnd = toEx == null ? '' : '${toEx - 1}';
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-$rangeEnd');
        final response = await request.close();
        if (response.statusCode == HttpStatus.partialContent ||
            (response.statusCode == HttpStatus.ok && from == 0)) {
          // (A 200 to a range from byte 0 is the whole file, which is what
          // was asked for anyway.) Every response is checked against what
          // the index knows, not just the first: a file replaced on the
          // mirror must be noticed on the next playback, not only when the
          // size is still unknown.
          _learnFrom(response, from);
          return response;
        }
        await response.drain<void>();
        throw HttpException(
          'unexpected status ${response.statusCode} for range $from-',
          uri: uri,
        );
      } on SocketException catch (e) {
        lastError = e;
      } on HttpException catch (e) {
        lastError = e;
        // Our own verdicts about the response are final; only transport
        // failures ("connection closed before full header...") are retried.
        if (e.uri == uri) rethrow;
      } on TimeoutException catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const SocketException('range fetch failed');
  }

  /// Takes the file's size, type and ETag from the first response. A size or
  /// ETag that differs from the stored index means the mirror's file changed
  /// (re-encoded, re-cut): what is cached is of another file, so drop it.
  void _learnFrom(HttpClientResponse response, int from) {
    int? total;
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      final slash = contentRange.lastIndexOf('/');
      if (slash >= 0) total = int.tryParse(contentRange.substring(slash + 1));
    }
    if (total == null && from == 0 && response.contentLength > 0) {
      total = response.contentLength;
    }
    final type = response.headers.contentType?.mimeType;
    if (type != null && type.startsWith('audio/')) _contentType = type;
    final etag = response.headers.value(HttpHeaders.etagHeader);

    if (total == null || total <= 0) {
      throw HttpException('no usable length for range fetch', uri: uri);
    }
    if (_total != null &&
        (_total != total || (etag != null && _etag != null && etag != _etag))) {
      debugPrint('segment cache: ${finalFile.path} changed on the mirror');
      _resetCache();
    }
    _total = total;
    _etag ??= etag;
  }

  /// Writes the index, serialised so two pieces finishing together never
  /// interleave their writes. Merges with what is already on disk first: an
  /// older instance for the same file may have written since this one read
  /// it, and everything either of them recorded is really there.
  void _scheduleIndexWrite() {
    if (!_diskOk || _complete) return;
    final total = _total;
    if (total == null) return;
    _indexWrites = _indexWrites.then((_) async {
      try {
        if (_indexFile.existsSync()) {
          final json = jsonDecode(await _indexFile.readAsString())
              as Map<String, dynamic>;
          if ((json['total'] as num?)?.toInt() == total) {
            final others = <List<int>>[];
            for (final r in (json['ranges'] as List? ?? const [])) {
              if (r is List && r.length >= 2) {
                others.add([(r[0] as num).toInt(), (r[1] as num).toInt()]);
              }
            }
            _ranges = _merge([..._ranges, ...others]);
          }
        }
        final tmp = File('${_indexFile.path}.tmp');
        await tmp.writeAsString(
          jsonEncode({
            'total': total,
            if (_etag != null) 'etag': _etag,
            'ranges': _ranges,
          }),
          flush: true,
        );
        await tmp.rename(_indexFile.path);
      } catch (e) {
        debugPrint('segment cache: index write failed: $e');
      }
    });
  }

  /// When the cached regions cover the whole file, turns the data file into
  /// the complete `SSS.mp3` and drops the index.
  void _promoteIfComplete() {
    if (_complete || !_diskOk) return;
    final total = _total;
    if (total == null) return;
    if (_ranges.length != 1 || _ranges.first[0] != 0 || _ranges.first[1] != total) {
      return;
    }
    _indexWrites = _indexWrites.then((_) async {
      try {
        if (_complete) return;
        if (await _dataFile.length() != total) return;
        if (!await finalFile.exists()) {
          await _dataFile.rename(finalFile.path);
        } else {
          _deleteQuietly(_dataFile);
        }
        _deleteQuietly(_indexFile);
        _complete = true;
        onComplete?.call();
      } catch (e) {
        debugPrint('segment cache: promote failed: $e');
      }
    });
  }

  /// Releases the shared HTTP client. The player drops the source when the
  /// next one is set, so this is for tidiness, not correctness.
  void dispose() {
    _http?.close(force: true);
    _http = null;
  }
}

/// A byte position shared between [SegmentCachedAudioSource._serve] and the
/// piece it is streaming, so a piece that fails part-way leaves behind how
/// far it got.
class _Cursor {
  int pos;
  _Cursor(this.pos);
}
