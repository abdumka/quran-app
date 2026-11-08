import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart' as session;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:vibration/vibration.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One error of a recitation: where, what kind, and what was heard.
class TasmeeError {
  TasmeeError({
    required this.surah,
    required this.ayah,
    required this.wordInAyah,
    required this.expected,
    required this.kind,
    this.heard = '',
    this.repaired = false,
  });

  final int surah;
  final int ayah;
  final int wordInAyah;
  final String expected;

  /// hafs | word | extra | distance | skipped | revealed | skippedAyah
  final String kind;
  final String heard;

  /// The reciter stumbled here but then said the word right (the hold was
  /// released by a repair), as opposed to moving on or asking for it.
  bool repaired;

  /// How the mistakes log files it: `asked` (uncovered or skipped with a
  /// button, or judged wrong in a self-test: the counted mistakes), or a
  /// microphone stop that was `repaired` (said right after) or `wrong`
  /// (never put right in that session).
  String get category => counts
      ? 'asked'
      : (repaired ? 'repaired' : 'wrong');

  /// Whether this counts as a mistake. Only what the reader asked for (a
  /// word or an ayah uncovered, an ayah skipped with the button) or judged
  /// wrong themself in a self-test counts. A stop the microphone made
  /// (the pink word) does not: the model misses some words that were said
  /// right, so a stop is an alert, kept in the report but not counted
  /// (owner, 2026-10-31).
  bool get counts =>
      kind == 'revealed' || kind == 'skippedAyah' || kind == 'recall';

  static String categoryLabel(String category) => switch (category) {
        // Only `asked` counts as a mistake (see [counts]); the other two
        // are the microphone's stops.
        'repaired' => 'تنبيه ثم أصاب',
        'asked' => 'تُحسب أخطاء',
        _ => 'تنبيه لم يُصحَّح',
      };

  String get kindLabel => switch (kind) {
        // A reading of another riwaya: the user is told only that the word
        // was not heard right (owner: never name another riwaya).
        'hafs' => 'لم تُسمع صحيحة',
        'word' => 'كلمة أخرى',
        'extra' => 'كلمة زائدة',
        'skipped' => 'كلمة متروكة',
        'revealed' => 'كُشفت بطلب',
        'skippedAyah' => 'آية متخطّاة',
        'haraka' => 'خطأ في حركة آخر الكلمة',
        // A text test: the ayah was not recalled (no recording involved).
        'recall' => 'لم تُستذكر',
        _ => 'لم تُسمع صحيحة',
      };

  Map<String, Object?> toJson() => {
        'surah': surah,
        'ayah': ayah,
        'word': wordInAyah,
        'expected': expected,
        'kind': kind,
        if (heard.isNotEmpty) 'heard': heard,
        if (repaired) 'repaired': true,
      };

  factory TasmeeError.fromJson(Map<String, dynamic> j) => TasmeeError(
        surah: j['surah'] as int? ?? 0,
        ayah: j['ayah'] as int? ?? 0,
        wordInAyah: j['word'] as int? ?? 0,
        expected: j['expected'] as String? ?? '',
        kind: j['kind'] as String? ?? 'distance',
        heard: j['heard'] as String? ?? '',
        repaired: j['repaired'] as bool? ?? false,
      );
}

/// The outcome of one page of Tasmee.
class TasmeeReport {
  TasmeeReport({
    required this.page,
    required this.at,
    required this.seconds,
    required this.words,
    required this.correct,
    required this.errors,
    required this.finished,
    this.holds = 0,
    this.repairs = 0,
  });

  final int page;
  final DateTime at;
  final int seconds;
  final int words;
  final int correct;
  final List<TasmeeError> errors;

  /// Whether the whole page was recited (false: the session was ended early).
  final bool finished;

  /// Times the session stopped at a word (wrong or skipped), and how many of
  /// those the reciter put right by saying the word again.
  final int holds;
  final int repairs;

  /// The errors that count as mistakes (see [TasmeeError.counts]).
  List<TasmeeError> get mistakes => [
        for (final e in errors)
          if (e.counts) e,
      ];

  /// The microphone's stops, kept for the record but not counted.
  int get alerts => errors.length - mistakes.length;

  Map<String, Object?> toJson() => {
        'page': page,
        'at': at.toIso8601String(),
        'seconds': seconds,
        'words': words,
        'correct': correct,
        'finished': finished,
        'errors': [for (final e in errors) e.toJson()],
        'holds': holds,
        'repairs': repairs,
      };

  /// The same report with only the errors [keep] accepts.
  TasmeeReport withErrors(bool Function(TasmeeError e) keep) => TasmeeReport(
        page: page,
        at: at,
        seconds: seconds,
        words: words,
        correct: correct,
        errors: [
          for (final e in errors)
            if (keep(e)) e,
        ],
        finished: finished,
        holds: holds,
        repairs: repairs,
      );

  factory TasmeeReport.fromJson(Map<String, dynamic> j) => TasmeeReport(
        page: j['page'] as int? ?? 0,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2000),
        seconds: j['seconds'] as int? ?? 0,
        words: j['words'] as int? ?? 0,
        correct: j['correct'] as int? ?? 0,
        finished: j['finished'] as bool? ?? false,
        errors: [
          for (final e in (j['errors'] as List<dynamic>? ?? const []))
            TasmeeError.fromJson(e as Map<String, dynamic>),
        ],
        holds: j['holds'] as int? ?? 0,
        repairs: j['repairs'] as int? ?? 0,
      );
}

/// Saved Tasmee reports (one JSON file per recited page, newest first).
class TasmeeReportStore {
  static const int _keep = 300;

  /// Tests only: where the reports go instead of the app's support
  /// directory (which has no platform channel under `flutter test`).
  @visibleForTesting
  static Directory? directoryOverride;

  static Future<Directory> _dir() async {
    final dir = directoryOverride ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}tasmee_reports',
        );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<void> save(TasmeeReport report) async {
    try {
      final dir = await _dir();
      final stamp = report.at.toIso8601String().replaceAll(':', '-').split('.').first;
      final path =
          '${dir.path}${Platform.pathSeparator}report_${stamp}_p${report.page}.json';
      // Written beside and renamed into place, so a process killed mid-write
      // (an install over the running app, a crash) leaves no empty report.
      final tmp = File('$path.tmp')..writeAsStringSync(json.encode(report.toJson()));
      tmp.renameSync(path);
      final files = _reportFiles(dir);
      for (final f in files.skip(_keep)) {
        f.deleteSync();
      }
    } catch (e) {
      debugPrint('TasmeeReportStore: save failed: $e');
    }
  }

  static List<File> _reportFiles(Directory dir) =>
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
        ..sort((a, b) => b.path.compareTo(a.path));

  /// Every readable report, newest first. A report that cannot be read
  /// (an empty file from an interrupted write) is dropped, and an empty
  /// one deleted, instead of hiding all the others.
  static Future<List<TasmeeReport>> loadAll() async {
    try {
      final dir = await _dir();
      final out = <TasmeeReport>[];
      for (final f in _reportFiles(dir)) {
        try {
          final raw = f.readAsStringSync();
          if (raw.trim().isEmpty) {
            f.deleteSync();
            continue;
          }
          out.add(TasmeeReport.fromJson(json.decode(raw) as Map<String, dynamic>));
        } catch (e) {
          debugPrint('TasmeeReportStore: skipping ${f.path}: $e');
        }
      }
      return out;
    } catch (e) {
      debugPrint('TasmeeReportStore: load failed: $e');
      return const [];
    }
  }

  /// Runs [change] over every saved report: null deletes it, the same
  /// object keeps it, another report replaces it. Returns the original
  /// contents of every file it touched (path -> JSON), for [restore].
  static Future<Map<String, String>> edit(
    TasmeeReport? Function(TasmeeReport report) change,
  ) async {
    final originals = <String, String>{};
    try {
      final dir = await _dir();
      for (final f in _reportFiles(dir)) {
        final String raw;
        final TasmeeReport report;
        try {
          raw = f.readAsStringSync();
          report = TasmeeReport.fromJson(json.decode(raw) as Map<String, dynamic>);
        } catch (_) {
          continue;
        }
        final next = change(report);
        if (identical(next, report)) continue;
        originals[f.path] = raw;
        if (next == null) {
          f.deleteSync();
        } else {
          final tmp = File('${f.path}.tmp')
            ..writeAsStringSync(json.encode(next.toJson()));
          tmp.renameSync(f.path);
        }
      }
    } catch (e) {
      debugPrint('TasmeeReportStore: edit failed: $e');
    }
    return originals;
  }

  /// Puts back the files [edit] changed («تراجع»).
  static Future<void> restore(Map<String, String> originals) async {
    for (final e in originals.entries) {
      try {
        final tmp = File('${e.key}.tmp')..writeAsStringSync(e.value);
        tmp.renameSync(e.key);
      } catch (err) {
        debugPrint('TasmeeReportStore: restore failed: $err');
      }
    }
  }
}

/// «التسميع من أي موضع»: open any page and recite from anywhere in the
/// mushaf; after the first words the session moves to where the reciter
/// is. Off unless the reader turns it on; never used in the tests.
class TasmeeLocateAnywhere {
  static const String _pref = 'tasmee_locate_anywhere';
  static bool? _value;

  static Future<bool> enabled() async {
    final v = _value;
    if (v != null) return v;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _value = prefs.getBool(_pref) ?? false;
    } catch (_) {
      return _value = false;
    }
  }

  static Future<void> set(bool on) async {
    _value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pref, on);
    } catch (_) {}
  }
}

/// How the judge runs. Since 2026-11-07 the app has one behaviour,
/// [TasmeeSpeed.verified]; the other two were user-selectable levels from
/// 2026-10-23 to 2026-11-07 and stay here for the session logs, the replay
/// harness and the tests.
///
/// `accurate`: the plain judge. `fast`: the 8-frame recogniser export plus a
/// judge that commits without waiting, 0.12 s sooner for about 8 % more
/// false stops. `verified`: the plain judge plus a second opinion before a
/// wrong-word stop: the last few seconds are decoded once more with a fresh
/// recognizer state, and a stop whose fresh decode hears the expected word in
/// place is withdrawn (the live decode carries the memory of what came before
/// and can drop a word's first sound). About 11 % fewer stops at the same
/// reveal lag; costs about half a second at a stop, nothing elsewhere
/// (`research_2026-10-05/RESULTS.txt`, 2026-11-06 and 2026-11-07).
enum TasmeeSpeed { accurate, fast, verified }

class TasmeeSpeedSetting {
  static TasmeeSpeed? _value;

  static String label(TasmeeSpeed m) => switch (m) {
        TasmeeSpeed.fast => 'استجابة أسرع',
        TasmeeSpeed.verified => 'تحقّق قبل التنبيه',
        TasmeeSpeed.accurate => 'دقة أعلى',
      };

  /// Always [TasmeeSpeed.verified] in the app; a stored `tasmee_speed`
  /// preference from an earlier build is ignored.
  static Future<TasmeeSpeed> mode() async => _value ?? TasmeeSpeed.verified;

  /// In-memory override for tests of the other two behaviours.
  @visibleForTesting
  static Future<void> set(TasmeeSpeed m) async {
    _value = m;
  }
}

/// How «تحقّق قبل التنبيه» judges a stop. `redecode`: the window is decoded
/// once more with a fresh recognizer and the stop is withdrawn when the
/// expected word is read in place (shipped behaviour). `posterior`: the same
/// window is also run through ONNX Runtime directly and the expected word is
/// force-aligned over the model's log posteriors; a word the model nearly
/// chose clears the stop too (`ZipformerPosterior`; replay 2026-11-06: 52
/// more of 741 phone stops cleared, planted look-alikes pass 0.7 %).
enum TasmeeVerifyMethod { redecode, posterior }

/// Lab switch (test builds only, like [TasmeeMicSourceSetting]); the session
/// log header carries it as `verifyMethod`.
class TasmeeVerifyMethodSetting {
  static const String _pref = 'tasmee_verify_method';
  static TasmeeVerifyMethod? _value;

  static String label(TasmeeVerifyMethod m) => switch (m) {
        TasmeeVerifyMethod.redecode => 'إعادة التفريغ',
        TasmeeVerifyMethod.posterior => 'ثقة النموذج',
      };

  static Future<TasmeeVerifyMethod> mode() async {
    final v = _value;
    if (v != null) return v;
    if (!TasmeeMicSourceSetting.labBuild) return _value = TasmeeVerifyMethod.redecode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final i = prefs.getInt(_pref);
      return _value = i != null && i >= 0 && i < TasmeeVerifyMethod.values.length
          ? TasmeeVerifyMethod.values[i]
          : TasmeeVerifyMethod.redecode;
    } catch (_) {
      return _value = TasmeeVerifyMethod.redecode;
    }
  }

  static Future<void> set(TasmeeVerifyMethod m) async {
    _value = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pref, m.index);
    } catch (_) {}
  }

  /// Tests only: forget the cached value so [mode] reads afresh.
  @visibleForTesting
  static void reset() => _value = null;
}

/// Which Android audio source the Tasmee microphone opens. `system` is the
/// recorder default (the phone may apply noise suppression and gain control
/// tuned for calls, which can swallow the first sound of a word);
/// `unprocessed` asks for the raw microphone (Android 7+; a phone without
/// support records as default); `voiceRecognition` is the source tuned for
/// speech recognisers. iOS ignores the setting. مُكث (2026-11-07 teardown)
/// records unprocessed with a voice-recognition fallback.
enum TasmeeMicSource { system, unprocessed, voiceRecognition }

/// Lab switch: shown only in test builds (`--dart-define=TASMEE_LAB=true`),
/// so the shipped app keeps one behaviour while a candidate is tried on the
/// owner's phone. The session log header carries the value as `micSource`.
class TasmeeMicSourceSetting {
  static const bool labBuild = bool.fromEnvironment('TASMEE_LAB');
  static const String _pref = 'tasmee_mic_source';
  static TasmeeMicSource? _value;

  static String label(TasmeeMicSource m) => switch (m) {
        TasmeeMicSource.system => 'افتراضي',
        TasmeeMicSource.unprocessed => 'بدون معالجة',
        TasmeeMicSource.voiceRecognition => 'تعرّف على الكلام',
      };

  /// [TasmeeMicSource.system] unless a lab build stored another value.
  static Future<TasmeeMicSource> mode() async {
    final v = _value;
    if (v != null) return v;
    if (!labBuild) return _value = TasmeeMicSource.system;
    try {
      final prefs = await SharedPreferences.getInstance();
      final i = prefs.getInt(_pref);
      return _value = i != null && i >= 0 && i < TasmeeMicSource.values.length
          ? TasmeeMicSource.values[i]
          : TasmeeMicSource.system;
    } catch (_) {
      return _value = TasmeeMicSource.system;
    }
  }

  static Future<void> set(TasmeeMicSource m) async {
    _value = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pref, m.index);
    } catch (_) {}
  }
}

/// How the app signals a mistake during Tasmee.
enum TasmeeAlertMode { vibrateAndSound, vibrate, sound, none }

/// What an alert is for: a mistake (a firm double buzz / the alert tone) or
/// a mistake just put right (one soft pulse / a soft chime), so the session
/// can be followed without looking at the screen.
enum TasmeeAlertKind { mistake, corrected }

class TasmeeAlert {
  static const Map<TasmeeAlertKind, String> _prefs = {
    TasmeeAlertKind.mistake: 'tasmee_alert_mode',
    TasmeeAlertKind.corrected: 'tasmee_alert_ok_mode',
  };
  /// Tone and vibration unless the reader chooses otherwise in the
  /// settings (owner, 2026-10-12).
  static final Map<TasmeeAlertKind, TasmeeAlertMode> _modes = {
    TasmeeAlertKind.mistake: TasmeeAlertMode.vibrateAndSound,
    TasmeeAlertKind.corrected: TasmeeAlertMode.vibrateAndSound,
  };
  static bool _loaded = false;

  static String label(TasmeeAlertMode m) => switch (m) {
        TasmeeAlertMode.vibrateAndSound => 'اهتزاز وصوت',
        TasmeeAlertMode.vibrate => 'اهتزاز فقط',
        TasmeeAlertMode.sound => 'صوت فقط',
        TasmeeAlertMode.none => 'بلا تنبيه',
      };

  static Future<TasmeeAlertMode> mode({
    TasmeeAlertKind kind = TasmeeAlertKind.mistake,
  }) async {
    if (!_loaded) {
      try {
        final prefs = await SharedPreferences.getInstance();
        for (final k in TasmeeAlertKind.values) {
          final i = prefs.getInt(_prefs[k]!);
          if (i != null && i >= 0 && i < TasmeeAlertMode.values.length) {
            _modes[k] = TasmeeAlertMode.values[i];
          }
        }
      } catch (_) {}
      _loaded = true;
    }
    return _modes[kind]!;
  }

  static Future<void> setMode(
    TasmeeAlertMode m, {
    TasmeeAlertKind kind = TasmeeAlertKind.mistake,
  }) async {
    await mode(); // load the other kind first, so it is not lost
    _modes[kind] = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefs[kind]!, m.index);
    } catch (_) {}
  }

  static AudioPlayer? _player;

  /// Signals a mistake according to the chosen mode. Uses the vibrator
  /// itself (not the system's touch-feedback setting, which many phones
  /// switch off) and a bundled tone on the media stream that neither takes
  /// audio focus nor stops the microphone.
  static Future<void> fire({
    TasmeeAlertKind kind = TasmeeAlertKind.mistake,
  }) async {
    final m = await mode(kind: kind);
    final corrected = kind == TasmeeAlertKind.corrected;
    if (m == TasmeeAlertMode.vibrate || m == TasmeeAlertMode.vibrateAndSound) {
      if (!kIsWeb && Platform.isIOS) {
        // iOS keeps haptics silent while the app records unless this is set;
        // the recorder sets it, and it is set again here in case the session
        // was reconfigured since. Then Apple's own feedback generator, which
        // is the most dependable haptic on an iPhone, alongside the plugin.
        try {
          await session.AVAudioSession()
              .setAllowHapticsAndSystemSoundsDuringRecording(true);
        } catch (_) {}
        try {
          if (corrected) {
            await HapticFeedback.lightImpact();
          } else {
            await HapticFeedback.heavyImpact();
            await Future<void>.delayed(const Duration(milliseconds: 180));
            await HapticFeedback.heavyImpact();
          }
        } catch (e) {
          debugPrint('TasmeeAlert: haptic failed: $e');
        }
      }
      try {
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(
            pattern: corrected ? [0, 60] : [0, 140, 90, 140],
          );
        }
      } catch (e) {
        debugPrint('TasmeeAlert: vibrate failed: $e');
      }
    }
    if (m == TasmeeAlertMode.sound || m == TasmeeAlertMode.vibrateAndSound) {
      try {
        final player = _player ??= AudioPlayer(playerId: 'tasmee_alert');
        await player.setAudioContext(AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.none,
          ),
          // The same category and options the recorder set on the shared
          // session (record's IosRecordConfig defaults plus mixWithOthers),
          // so playing the tone does not re-route or interrupt the mic.
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.allowBluetooth,
              AVAudioSessionOptions.allowBluetoothA2DP,
            },
          ),
        ));
        await player.stop();
        await player.play(
          AssetSource(corrected ? 'audio/tasmee_ok.wav' : 'audio/tasmee_alert.wav'),
          volume: corrected ? 0.6 : 1.0,
        );
      } catch (e) {
        debugPrint('TasmeeAlert: tone failed: $e');
      }
    }
  }
}
