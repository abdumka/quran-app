import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/recitation_engine.dart';
import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';

/// Hand-driven engine: the test pushes segments explicitly.
class _ManualEngine implements RecitationEngine {
  final _controller = StreamController<String>.broadcast();
  bool started = false;
  bool stopped = false;

  void emit(String segment) => _controller.add(segment);

  @override
  Stream<String> get segments => _controller.stream;

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
    expect(service.pageData, isNotNull);
    expect(service.statuses.length, 25);
    expect(service.statuses.every((s) => s == WordStatus.pending), isTrue);
    expect(service.currentWordIndex, 0);
  });

  test('start fails cleanly for a page with no word data', () async {
    final started = await service.start(
      pageNumber: 2,
      engineOverride: _ManualEngine(),
      stopPlayback: false,
    );
    expect(started, isFalse);
    expect(service.status.value, MemorizationTestStatus.failed);
    expect(service.isActive, isFalse);
  });

  test('segments from the engine reveal words and complete the session',
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
    // Completion stops the engine but keeps the final state visible.
    expect(engine.stopped, isTrue);
    expect(service.pageData, isNotNull);
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
    expect(service.pageData, isNull);
    expect(service.currentWordIndex, -1);
  });
}
