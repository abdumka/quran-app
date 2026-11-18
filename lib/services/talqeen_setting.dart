import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «تلقين - استمع ثم ردّد» (owner, 2026-11-11): after each ayah the recitation
/// goes quiet for as long as the reciter took, so the listener repeats it,
/// then moves on. A reciter who joins ayat in one breath (Habti waqf) has one
/// clip for the whole group, so the turn comes after the group.
///
/// Off by default; once ticked it stays on until it is unticked. The app
/// never listens during the turn: it only leaves the time.
class TalqeenSetting {
  TalqeenSetting._();

  /// Full name, for the options sheet and the button guide.
  static const String fullName = 'تلقين - استمع ثم ردّد';

  /// Where the full name does not fit (the badge on the play button).
  static const String shortName = 'تلقين';

  static const String _enabledKey = 'talqeenEnabled';
  static const String _factorKey = 'talqeenTurnFactor';

  /// How long the turn is against what was heard: shorter than the reciter
  /// (0.75×, for someone who reads faster than the tarteel; owner,
  /// 2026-11-13), «مثل القارئ», 1.5×, 2×.
  static const List<double> factors = [0.75, 1.0, 1.5, 2.0];

  static final ValueNotifier<bool> enabled = ValueNotifier(false);
  static final ValueNotifier<double> factor = ValueNotifier(1.0);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledKey) ?? false;
    final f = prefs.getDouble(_factorKey) ?? 1.0;
    factor.value = factors.contains(f) ? f : 1.0;
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  static Future<void> setFactor(double value) async {
    if (!factors.contains(value)) return;
    factor.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_factorKey, value);
  }

  static String factorLabel(double f) {
    if (f == 1.0) return 'مثل القارئ';
    final text = f == f.roundToDouble() ? f.toInt().toString() : '$f';
    return '$text×'; // the app's way of writing a factor, as in 1.5× speed
  }
}

/// The listener's turn, as the bar and the page show it.
@immutable
class TalqeenTurn {
  const TalqeenTurn({
    required this.left,
    required this.secondsLeft,
    required this.paused,
  });

  /// Share of the turn still to go, from 1 down to 0.
  final double left;

  /// Whole seconds still to go, in real time (playback speed included).
  final int secondsLeft;

  /// The countdown is paused (the listener tapped the ring).
  final bool paused;

  @override
  bool operator ==(Object other) =>
      other is TalqeenTurn &&
      other.left == left &&
      other.secondsLeft == secondsLeft &&
      other.paused == paused;

  @override
  int get hashCode => Object.hash(left, secondsLeft, paused);
}

/// A WAV file of silence the player plays during the turn.
///
/// The turn is real (silent) audio rather than a paused player on purpose: a
/// phone drops the media service out of the foreground on pause, and a
/// recitation running with the screen off, in a car or on earbuds would then
/// have to restart it from the background, which Android may refuse. Playing
/// keeps the session, the notification and the lock-screen controls alive,
/// and the player's speed applies to it like any ayah.
class TalqeenSilence {
  TalqeenSilence._();

  static const int _sampleRate = 8000; // mono, 16-bit: 16 KB a second
  static const String fileName = 'talqeen_silence.wav';

  static Duration _length = Duration.zero;

  /// A silence file at least [length] long (one is made, or lengthened, when
  /// needed; whole minutes, at least one).
  static Future<File> atLeast(Duration length) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    if (file.existsSync()) {
      if (_length == Duration.zero) {
        final bytes = file.lengthSync() - 44;
        if (bytes > 0) {
          _length = Duration(
            milliseconds: bytes * 1000 ~/ (_sampleRate * 2),
          );
        }
      }
      if (_length >= length) return file;
    }
    final minutes = math.max(1, (length.inSeconds ~/ 60) + 1);
    final seconds = minutes * 60;
    await _write(file, seconds);
    _length = Duration(seconds: seconds);
    return file;
  }

  static Future<void> _write(File file, int seconds) async {
    final dataBytes = seconds * _sampleRate * 2;
    final sink = file.openWrite();
    sink.add(wavHeader(dataBytes, sampleRate: _sampleRate));
    final zeros = Uint8List(64 * 1024);
    var left = dataBytes;
    while (left > 0) {
      final n = math.min(left, zeros.length);
      sink.add(n == zeros.length ? zeros : Uint8List(n));
      left -= n;
    }
    await sink.close();
  }

  /// The 44-byte header of a mono 16-bit PCM WAV holding [dataBytes].
  @visibleForTesting
  static Uint8List wavHeader(int dataBytes, {required int sampleRate}) {
    final h = ByteData(44);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        h.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    h.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    h.setUint32(16, 16, Endian.little); // fmt chunk size
    h.setUint16(20, 1, Endian.little); // PCM
    h.setUint16(22, 1, Endian.little); // mono
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    h.setUint16(32, 2, Endian.little); // block align
    h.setUint16(34, 16, Endian.little); // bits per sample
    ascii(36, 'data');
    h.setUint32(40, dataBytes, Endian.little);
    return h.buffer.asUint8List();
  }
}
