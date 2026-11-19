import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/athkar.dart';
import 'content_update_service.dart';

/// Loads «الأذكار» (`assets/data/athkar.json`, or a newer file fetched from
/// our server: the `athkar` content item, which is also how voices are
/// added).
class AthkarService {
  AthkarService._() {
    ContentUpdateService.instance.registerItem(
      'athkar',
      apply: reload,
      isLoaded: () => _loaded || _loading != null,
    );
  }
  static final AthkarService instance = AthkarService._();

  static const String _assetPath = 'assets/data/athkar.json';

  AthkarData _data = AthkarData.empty;
  Future<void>? _loading;
  bool _loaded = false;

  AthkarData get data => _data;
  bool get isLoaded => _loaded;

  /// Bumped when the data is swapped live (a server update).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> reload() async {
    if (!_loaded && _loading == null) return;
    await load();
    await _load();
    revision.value++;
  }

  Future<void> _load() async {
    final downloaded = await ContentUpdateService.instance.readFor('athkar');
    if (downloaded != null) {
      try {
        _data = await compute(AthkarData.parse, downloaded);
        _loaded = true;
        return;
      } catch (error) {
        debugPrint('AthkarService: downloaded file refused: $error');
      }
    }
    try {
      _data = await compute(
        AthkarData.parse,
        await rootBundle.loadString(_assetPath),
      );
    } catch (error) {
      debugPrint('AthkarService: failed to load $_assetPath: $error');
      _data = AthkarData.empty;
    }
    _loaded = true;
  }

  /// Tests only.
  @visibleForTesting
  void debugSetData(AthkarData data) {
    _data = data;
    _loaded = true;
    revision.value++;
  }
}

enum AthkarView { list, single }

/// What the reader does with the athkar: today's counters, the favourites
/// and the chosen view. Kept on the phone only.
///
/// The counters are for one day: the first use on a new day starts them at
/// zero again.
class AthkarStore extends ChangeNotifier {
  AthkarStore._();
  static final AthkarStore instance = AthkarStore._();

  static const String _dayKey = 'athkar.day';
  static const String _countsKey = 'athkar.counts';
  static const String _favouritesKey = 'athkar.favourites';
  static const String _viewKey = 'athkar.view';
  static const String _reciterKey = 'athkar.reciter';
  static const String _quranReciterKey = 'athkar.quranReciter';
  static const String _continuousKey = 'athkar.continuous';
  static const String _speedKey = 'athkar.speed';

  SharedPreferences? _prefs;
  Future<void>? _loading;
  String _day = '';
  final Map<int, int> _counts = {};
  final List<int> _favourites = [];
  AthkarView _view = AthkarView.list;
  String? _reciterId;
  String? _quranReciterId;
  bool _continuous = true;
  double _speed = 1;
  Timer? _saveTimer;

  /// Tests set the clock.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _day = prefs.getString(_dayKey) ?? '';
    _counts.clear();
    try {
      final raw = json.decode(prefs.getString(_countsKey) ?? '{}');
      if (raw is Map) {
        raw.forEach((k, v) {
          final id = int.tryParse('$k');
          if (id != null && v is int && v > 0) _counts[id] = v;
        });
      }
    } catch (_) {
      // a damaged value only loses today's counters
    }
    _favourites
      ..clear()
      ..addAll([
        for (final s in prefs.getStringList(_favouritesKey) ?? const <String>[])
          if (int.tryParse(s) != null) int.parse(s),
      ]);
    _view = prefs.getString(_viewKey) == 'single'
        ? AthkarView.single
        : AthkarView.list;
    _reciterId = prefs.getString(_reciterKey);
    _quranReciterId = prefs.getString(_quranReciterKey);
    _continuous = prefs.getBool(_continuousKey) ?? true;
    _speed = (prefs.getDouble(_speedKey) ?? 1).clamp(0.5, 4).toDouble();
    _rollDay();
    notifyListeners();
  }

  static String _dayOf(DateTime t) =>
      '${t.year}-${'${t.month}'.padLeft(2, '0')}-${'${t.day}'.padLeft(2, '0')}';

  /// Starts the counters again when the day has changed.
  void _rollDay() {
    final today = _dayOf(now());
    if (today == _day) return;
    _day = today;
    _counts.clear();
    _saveCounts(immediately: true);
  }

  void _saveCounts({bool immediately = false}) {
    void write() {
      final prefs = _prefs;
      if (prefs == null) return;
      prefs.setString(_dayKey, _day);
      prefs.setString(
        _countsKey,
        json.encode({for (final e in _counts.entries) '${e.key}': e.value}),
      );
    }

    _saveTimer?.cancel();
    if (immediately) {
      write();
    } else {
      // a fast run of taps (100 tasbih) is one write
      _saveTimer = Timer(const Duration(milliseconds: 400), write);
    }
  }

  // ---- counters ----

  int countOf(AthkarItem item) {
    _rollDay();
    final c = _counts[item.id] ?? 0;
    return c > item.count ? item.count : c;
  }

  bool isDone(AthkarItem item) => countOf(item) >= item.count;

  int doneIn(Iterable<AthkarItem> items) => items.where(isDone).length;

  /// One more. Returns true when this tap completed the dhikr; a completed
  /// dhikr is not counted further.
  bool increment(AthkarItem item) {
    final c = countOf(item);
    if (c >= item.count) return false;
    _counts[item.id] = c + 1;
    _saveCounts();
    notifyListeners();
    return c + 1 >= item.count;
  }

  void reset(AthkarItem item) {
    if (_counts.remove(item.id) == null) return;
    _saveCounts();
    notifyListeners();
  }

  // ---- favourites ----

  /// Newest first.
  List<int> get favourites => List.unmodifiable(_favourites);

  bool isFavourite(AthkarItem item) => _favourites.contains(item.id);

  /// Returns true when [item] is a favourite after the call.
  bool toggleFavourite(AthkarItem item) {
    final had = _favourites.remove(item.id);
    if (!had) _favourites.insert(0, item.id);
    _prefs?.setStringList(_favouritesKey, [
      for (final id in _favourites) '$id',
    ]);
    notifyListeners();
    return !had;
  }

  // ---- choices ----

  AthkarView get view => _view;

  set view(AthkarView value) {
    if (value == _view) return;
    _view = value;
    _prefs?.setString(_viewKey, value == AthkarView.single ? 'single' : 'list');
    notifyListeners();
  }

  /// Listening goes on to the next dhikr by itself (the default), or stops
  /// after the one that was played.
  bool get continuous => _continuous;

  set continuous(bool value) {
    if (value == _continuous) return;
    _continuous = value;
    _prefs?.setBool(_continuousKey, value);
    notifyListeners();
  }

  /// How fast the athkar play: 1 for everyone; only the hidden «أدوات
  /// الاختبار» page changes it (to go through the recordings quickly).
  double get speed => _speed;

  set speed(double value) {
    if (value == _speed) return;
    _speed = value;
    _prefs?.setDouble(_speedKey, value);
    notifyListeners();
  }

  /// The chosen voice, or the first one when none was chosen (or the chosen
  /// one is gone).
  AthkarReciter? reciterOf(AthkarData data) {
    if (data.reciters.isEmpty) return null;
    for (final r in data.reciters) {
      if (r.id == _reciterId) return r;
    }
    return data.reciters.first;
  }

  /// The voice [item] plays in: the chosen one when it recorded it, else
  /// the first in the list that did (a voice that skipped a dhikr is just
  /// not used for it). Null when no voice has it.
  AthkarReciter? voiceFor(AthkarData data, AthkarItem item) {
    final chosen = reciterOf(data);
    if (chosen != null && chosen.has(item)) return chosen;
    for (final r in data.reciters) {
      if (r.has(item)) return r;
    }
    return null;
  }

  /// The id of the app reciter the verses play in: the reader's choice,
  /// else the one the data names (النهي).
  String quranReciterIdOf(AthkarData data) =>
      _quranReciterId ?? data.quranReciterId;

  void chooseQuranReciter(String id) {
    if (_quranReciterId == id) return;
    _quranReciterId = id;
    _prefs?.setString(_quranReciterKey, id);
    notifyListeners();
  }

  void chooseReciter(AthkarReciter reciter) {
    if (_reciterId == reciter.id) return;
    _reciterId = reciter.id;
    _prefs?.setString(_reciterKey, reciter.id);
    notifyListeners();
  }

  /// Tests only: forget everything in memory.
  @visibleForTesting
  void debugReset() {
    _saveTimer?.cancel();
    _prefs = null;
    _loading = null;
    _day = '';
    _counts.clear();
    _favourites.clear();
    _view = AthkarView.list;
    _reciterId = null;
    _quranReciterId = null;
    _continuous = true;
    _speed = 1;
    now = DateTime.now;
  }
}
