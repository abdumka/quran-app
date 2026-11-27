import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../models/tafsir_edition.dart';
import 'content_update_service.dart';

/// Switches and numbers the owner can change from our server without a
/// store release: the `app_config` item of [ContentUpdateService], built
/// from `tools/content_updates/app_config.json`:
///
///     {"ver": 3, "values": {"chat.enabled": false, "tasmee.okDistance": 0.17}}
///
/// Only the keys listed in [keys] exist. Each has the value this build uses
/// when the server says nothing, and for a number the range a server value
/// must fall in. A value of the wrong type, out of range or under an unknown
/// key is ignored (the default stays), never an error, so a typo on the
/// server can only fail to change something.
///
/// The file is read once, at launch ([load], before the first frame, one
/// small local file). A newer one downloaded during a run waits for the next
/// launch: a switch never flips under the reader mid-session.
class RemoteConfig {
  RemoteConfig._();
  static final RemoteConfig instance = RemoteConfig._();

  /// Every key a server file may set, with its default and range.
  static const Map<String, RemoteKey> keys = {
    // ── Kill switches (true = the feature is offered, as bundled) ──
    // «راسلنا مباشرة»: off hides the entry and stops the reply checks.
    'chat.enabled': RemoteKey.flag(true),
    // «تقوية الحفظ» drills in أدوات الحفظ (hidden in the bundle for now).
    'tasmee.drillsEnabled': RemoteKey.flag(false),
    // «التسميع من أي موضع» search over the whole mushaf.
    'tasmee.locateEnabled': RemoteKey.flag(true),
    // The pause on the Tasmee bar's green dot, and the session pausing
    // itself when the app loses the screen or the audio. Off: the dot is
    // the plain listening light again, as before the pause existed.
    'tasmee.pauseEnabled': RemoteKey.flag(true),
    // Android: the session also pauses while the phone rings or a call is
    // under way (read from the audio mode). Off if a phone misreports it.
    'tasmee.pauseOnCall': RemoteKey.flag(true),

    // ── Tasmee judge (see TrackerConfig; defaults = the bundled values) ──
    'tasmee.okDistance': RemoteKey.number(0.15, 0.05, 0.3),
    'tasmee.unsureDistance': RemoteKey.number(0.4, 0.2, 0.6),
    'tasmee.minMargin': RemoteKey.number(0.35, 0.1, 0.6),
    'tasmee.minHeardFraction': RemoteKey.number(0.34, 0.2, 0.6),
    'tasmee.lexiconDistance': RemoteKey.number(0.12, 0.05, 0.25),
    'tasmee.commitDwell': RemoteKey.integer(6, 0, 12),
    'tasmee.settleFrames': RemoteKey.integer(25, 8, 50),
    'tasmee.fastSettleFrames': RemoteKey.integer(12, 6, 30),
    'tasmee.settleMs': RemoteKey.integer(1000, 300, 2000),
    'tasmee.fastSettleMs': RemoteKey.integer(500, 200, 1500),
    'tasmee.earlyCommit': RemoteKey.flag(true),
    'tasmee.orphanVowel': RemoteKey.flag(true),
    // «تحقّق قبل التنبيه»: the audio window re-checked before a stop.
    'tasmee.verifyBeforeMs': RemoteKey.integer(3000, 1000, 5000),
    'tasmee.verifyAfterMs': RemoteKey.integer(800, 300, 2000),
    'tasmee.verifyMaxMs': RemoteKey.integer(6000, 3000, 6500),

    // ── Server checks ──
    // How often the silent content check runs (hours).
    'content.checkHours': RemoteKey.integer(24, 6, 168),
  };

  Map<String, Object> _values = const {};
  bool _loaded = false;
  Future<void>? _loading;

  /// Reads the downloaded `app_config` file, if any. Idempotent; later calls
  /// (and a file downloaded meanwhile) change nothing until the next launch.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    ContentUpdateService.instance.registerItem(
      'app_config',
      isLoaded: () => _loaded,
    );
    try {
      final text = await ContentUpdateService.instance.readFor('app_config');
      if (text != null) {
        _values = parse(text);
        TafsirEdition.remote = parseTafsirEditions(text);
      }
    } catch (e) {
      debugPrint('RemoteConfig: server values ignored: $e');
    } finally {
      _loaded = true;
    }
  }

  /// Whether [load] has finished (values before it are the defaults).
  bool get loaded => _loaded;

  /// The accepted values of an `app_config` file: only known keys, each of
  /// the right type and in range. Throws [FormatException] when the file
  /// itself is not `{"ver": int, "values": {...}}`.
  static Map<String, Object> parse(String source) {
    final decoded = json.decode(source);
    if (decoded is! Map<String, dynamic> || decoded['ver'] is! int) {
      throw const FormatException('app_config: not a config file');
    }
    final values = decoded['values'];
    if (values is! Map<String, dynamic>) {
      throw const FormatException('app_config: no values');
    }
    final out = <String, Object>{};
    values.forEach((name, value) {
      final key = keys[name];
      if (key == null) return;
      final accepted = key.accept(value);
      if (accepted != null) out[name] = accepted;
    });
    return out;
  }

  /// The `tafsirEditions` list of an `app_config` file, each checked by
  /// [TafsirEdition.fromJson]; bad or duplicate entries are dropped.
  static List<TafsirEdition> parseTafsirEditions(String source) {
    final decoded = json.decode(source);
    final list = decoded is Map ? decoded['tafsirEditions'] : null;
    if (list is! List) return const [];
    final out = <TafsirEdition>[];
    for (final item in list) {
      final e = TafsirEdition.fromJson(item);
      if (e != null && !out.any((x) => x.id == e.id)) out.add(e);
    }
    return List.unmodifiable(out);
  }

  bool flag(String name) {
    final key = keys[name];
    assert(key != null && key.kind == RemoteKind.flag, name);
    final v = _values[name];
    return v is bool ? v : (key?.defaultValue as bool? ?? false);
  }

  double number(String name) {
    final key = keys[name];
    assert(key != null && key.kind == RemoteKind.number, name);
    final v = _values[name];
    return v is double ? v : (key?.defaultValue as num? ?? 0).toDouble();
  }

  int integer(String name) {
    final key = keys[name];
    assert(key != null && key.kind == RemoteKind.integer, name);
    final v = _values[name];
    return v is int ? v : (key?.defaultValue as int? ?? 0);
  }

  /// The values a server file changed, for the tester tools page.
  Map<String, Object> get overridden => Map.unmodifiable(_values);

  /// Tests only: use [values] (already accepted) as if loaded at launch.
  @visibleForTesting
  void debugSet(Map<String, Object> values) {
    _values = Map.of(values);
    _loaded = true;
    _loading = Future.value();
  }
}

enum RemoteKind { flag, number, integer }

/// One server-settable value: its type, the bundled default and, for a
/// number, the range a server value must fall in.
class RemoteKey {
  const RemoteKey.flag(bool this.defaultValue)
    : kind = RemoteKind.flag,
      min = null,
      max = null;
  const RemoteKey.number(double this.defaultValue, double this.min, double this.max)
    : kind = RemoteKind.number;
  const RemoteKey.integer(int this.defaultValue, int this.min, int this.max)
    : kind = RemoteKind.integer;

  final RemoteKind kind;
  final Object defaultValue;
  final num? min;
  final num? max;

  /// [value] as this key stores it, or null when it is not acceptable.
  Object? accept(Object? value) {
    switch (kind) {
      case RemoteKind.flag:
        return value is bool ? value : null;
      case RemoteKind.number:
        if (value is! num || !value.isFinite) return null;
        final d = value.toDouble();
        return d >= min! && d <= max! ? d : null;
      case RemoteKind.integer:
        if (value is! int) return null;
        return value >= min! && value <= max! ? value : null;
    }
  }
}
