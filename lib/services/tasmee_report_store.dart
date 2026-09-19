import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
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
  });

  final int surah;
  final int ayah;
  final int wordInAyah;
  final String expected;

  /// hafs | word | extra | distance | skipped | revealed | skippedAyah
  final String kind;
  final String heard;

  String get kindLabel => switch (kind) {
        'hafs' => 'قراءة حفص بدل قالون',
        'word' => 'كلمة أخرى',
        'extra' => 'كلمة زائدة',
        'skipped' => 'كلمة متروكة',
        'revealed' => 'كُشفت بطلب',
        'skippedAyah' => 'آية متخطّاة',
        'haraka' => 'خطأ في حركة آخر الكلمة',
        _ => 'خطأ في النطق',
      };

  Map<String, Object?> toJson() => {
        'surah': surah,
        'ayah': ayah,
        'word': wordInAyah,
        'expected': expected,
        'kind': kind,
        if (heard.isNotEmpty) 'heard': heard,
      };

  factory TasmeeError.fromJson(Map<String, dynamic> j) => TasmeeError(
        surah: j['surah'] as int? ?? 0,
        ayah: j['ayah'] as int? ?? 0,
        wordInAyah: j['word'] as int? ?? 0,
        expected: j['expected'] as String? ?? '',
        kind: j['kind'] as String? ?? 'distance',
        heard: j['heard'] as String? ?? '',
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
  });

  final int page;
  final DateTime at;
  final int seconds;
  final int words;
  final int correct;
  final List<TasmeeError> errors;

  /// Whether the whole page was recited (false: the session was ended early).
  final bool finished;

  Map<String, Object?> toJson() => {
        'page': page,
        'at': at.toIso8601String(),
        'seconds': seconds,
        'words': words,
        'correct': correct,
        'finished': finished,
        'errors': [for (final e in errors) e.toJson()],
      };

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
      );
}

/// Saved Tasmee reports (one JSON file per recited page, newest first).
class TasmeeReportStore {
  static const int _keep = 300;

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}tasmee_reports');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<void> save(TasmeeReport report) async {
    try {
      final dir = await _dir();
      final stamp = report.at.toIso8601String().replaceAll(':', '-').split('.').first;
      File('${dir.path}${Platform.pathSeparator}report_${stamp}_p${report.page}.json')
          .writeAsStringSync(json.encode(report.toJson()));
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(_keep)) {
        f.deleteSync();
      }
    } catch (e) {
      debugPrint('TasmeeReportStore: save failed: $e');
    }
  }

  static Future<List<TasmeeReport>> loadAll() async {
    try {
      final dir = await _dir();
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return [
        for (final f in files)
          TasmeeReport.fromJson(
            json.decode(f.readAsStringSync()) as Map<String, dynamic>,
          ),
      ];
    } catch (e) {
      debugPrint('TasmeeReportStore: load failed: $e');
      return const [];
    }
  }
}

/// How the app signals a mistake during Tasmee.
enum TasmeeAlertMode { vibrateAndSound, vibrate, sound, none }

class TasmeeAlert {
  static const String _pref = 'tasmee_alert_mode';
  static TasmeeAlertMode _mode = TasmeeAlertMode.vibrate;
  static bool _loaded = false;

  static String label(TasmeeAlertMode m) => switch (m) {
        TasmeeAlertMode.vibrateAndSound => 'اهتزاز وصوت',
        TasmeeAlertMode.vibrate => 'اهتزاز فقط',
        TasmeeAlertMode.sound => 'صوت فقط',
        TasmeeAlertMode.none => 'بلا تنبيه',
      };

  static Future<TasmeeAlertMode> mode() async {
    if (!_loaded) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final i = prefs.getInt(_pref);
        if (i != null && i >= 0 && i < TasmeeAlertMode.values.length) {
          _mode = TasmeeAlertMode.values[i];
        }
      } catch (_) {}
      _loaded = true;
    }
    return _mode;
  }

  static Future<void> setMode(TasmeeAlertMode m) async {
    _mode = m;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pref, m.index);
    } catch (_) {}
  }

  static AudioPlayer? _player;

  /// Signals a mistake according to the chosen mode. Uses the vibrator
  /// itself (not the system's touch-feedback setting, which many phones
  /// switch off) and a bundled tone on the media stream that neither takes
  /// audio focus nor stops the microphone.
  static Future<void> fire() async {
    final m = await mode();
    if (m == TasmeeAlertMode.vibrate || m == TasmeeAlertMode.vibrateAndSound) {
      try {
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(pattern: [0, 140, 90, 140]);
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
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.defaultToSpeaker,
            },
          ),
        ));
        await player.stop();
        await player.play(AssetSource('audio/tasmee_alert.wav'), volume: 1.0);
      } catch (e) {
        debugPrint('TasmeeAlert: tone failed: $e');
      }
    }
  }
}
