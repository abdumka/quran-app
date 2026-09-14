import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/recitation_engine.dart';
import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';

/// Hand-driven engine: the test pushes segments explicitly.
class _ManualEngine extends RecitationEngine {
  final _controller = StreamController<RecognizedSegment>.broadcast();
  bool started = false;
  bool stopped = false;

  void emit(String segment, {bool isFinal = true}) =>
      _controller.add(RecognizedSegment(segment, isFinal: isFinal));

  @override
  Stream<RecognizedSegment> get segments => _controller.stream;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async {
    stopped = true;
    await _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = MemorizationTestService.instance;

  tearDown(() async {
    await service.stop();
  });

  test('start loads real page-1 data and reaches listening', () async {
    final engine = _ManualEngine();
    final started = await service.start(
      pageNumber: 1,
      engineOverride: engine,
      stopPlayback: false,
    );

    expect(started, isTrue);
    expect(service.status.value, MemorizationTestStatus.listening);
    expect(engine.started, isTrue);
    expect(service.activePage, 1);
    expect(service.regions!.ayahs.length, 7);
    expect(service.statuses.length, 25);
    expect(service.statuses.every((s) => s == WordStatus.pending), isTrue);
    expect(service.currentWordIndex, 0);
    expect(service.currentAyahIndex, 0);
    expect(service.ayahStates.first, AyahRevealState.current);
    expect(
      service.ayahStates.skip(1).every((s) => s == AyahRevealState.hidden),
      isTrue,
    );
  });

  test('start works on a page with two surahs and Qalun ayah ends', () async {
    // Page 600 holds the end of 105, all of 106 and 107, and 108.
    final started = await service.start(
      pageNumber: 600,
      engineOverride: _ManualEngine(),
      stopPlayback: false,
    );
    expect(started, isTrue);
    final regions = service.regions!;
    expect(regions.ayahs.first.surah, 105);
    expect(regions.ayahs.last.surah, 108);
    expect(regions.ayahs.every((a) => a.marker != null), isTrue);
    expect(service.statuses.length, greaterThan(regions.ayahs.length));
  });

  test('start fails cleanly for a page that does not exist', () async {
    final started = await service.start(
      pageNumber: 603,
      engineOverride: _ManualEngine(),
      stopPlayback: false,
    );
    expect(started, isFalse);
    expect(service.status.value, MemorizationTestStatus.failed);
    expect(service.isActive, isFalse);
  });

  test('segments from the engine reveal ayahs and complete the session',
      () async {
    final engine = _ManualEngine();
    await service.start(
      pageNumber: 1,
      engineOverride: engine,
      stopPlayback: false,
    );

    final revisionsSeen = <int>[];
    service.revision.addListener(
      () => revisionsSeen.add(service.revision.value),
    );

    // Recite ayah 1 (verbatim from output.json via the service's own data).
    engine.emit('الحمد لله رب العالمين');
    await Future<void>.delayed(Duration.zero);

    expect(
      service.statuses.take(4).every((s) => s == WordStatus.correct),
      isTrue,
    );
    expect(service.currentWordIndex, 4);
    expect(service.currentAyahIndex, 1);
    expect(service.ayahStates[0], AyahRevealState.revealed);
    expect(service.ayahStates[1], AyahRevealState.current);
    expect(revisionsSeen, isNotEmpty);

    // Recite the remaining ayahs.
    for (final segment in [
      'الرحمن الرحيم',
      'ملك يوم الدين',
      'اياك نعبد واياك نستعين',
      'اهدنا الصراط المستقيم',
      'صراط الذين انعمت عليهم',
      'غير المغضوب عليهم ولا الضالين',
    ]) {
      engine.emit(segment);
      await Future<void>.delayed(Duration.zero);
    }

    expect(service.status.value, MemorizationTestStatus.completed);
    expect(service.statuses.every((s) => s == WordStatus.correct), isTrue);
    expect(
      service.ayahStates.every((s) => s == AyahRevealState.revealed),
      isTrue,
    );
    // Completion stops the engine but keeps the final state visible.
    expect(engine.stopped, isTrue);
    expect(service.regions, isNotNull);
  });

  test('an ayah with a mistaken word is revealed as flagged', () async {
    final engine = _ManualEngine();
    await service.start(
      pageNumber: 1,
      engineOverride: engine,
      stopPlayback: false,
    );

    // Two unrecognizable segments promote the first word to a mistake,
    // then the rest of ayah 1 is recited correctly.
    engine.emit('كلام آخر');
    await Future<void>.delayed(Duration.zero);
    engine.emit('كلام آخر');
    await Future<void>.delayed(Duration.zero);
    engine.emit('لله رب العالمين');
    await Future<void>.delayed(Duration.zero);

    expect(service.statuses.first, WordStatus.mistake);
    expect(service.ayahStates[0], AyahRevealState.flagged);
    expect(service.ayahStates[1], AyahRevealState.current);
  });

  test('a newer start supersedes one still preparing', () async {
    final first = service.start(
      pageNumber: 1,
      engineOverride: _ManualEngine(),
      stopPlayback: false,
    );
    final second = service.start(
      pageNumber: 2,
      engineOverride: _ManualEngine(),
      stopPlayback: false,
    );
    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(service.activePage, 2);
    expect(service.status.value, MemorizationTestStatus.listening);
  });

  test('stop clears everything back to idle', () async {
    await service.start(
      pageNumber: 1,
      engineOverride: _ManualEngine(),
      stopPlayback: false,
    );
    await service.stop();
    expect(service.status.value, MemorizationTestStatus.idle);
    expect(service.statuses, isEmpty);
    expect(service.regions, isNull);
    expect(service.activePage, isNull);
    expect(service.currentWordIndex, -1);
    expect(service.ayahStates, isEmpty);
  });
}
