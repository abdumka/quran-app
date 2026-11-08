import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// «ملاحظاتي» in the «تنزيلات ومتشابهات» sheet: the reader's own note on the
/// mutashabihat of one ayah, kept on the phone only. One JSON map under one
/// key ("surah:ayah" -> text); an empty note is removed.
class TanzilatNotesStore {
  TanzilatNotesStore._();
  static final TanzilatNotesStore instance = TanzilatNotesStore._();

  static const String _key = 'tanzilatNotes_v1';

  Map<String, String>? _notes;

  Future<void> load() async {
    if (_notes != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final map = <String, String>{};
    if (raw != null) {
      try {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          if (v is String && v.isNotEmpty) map[k] = v;
        });
      } catch (_) {
        // A damaged value is dropped rather than blocking the sheet.
      }
    }
    _notes = map;
  }

  /// The note of [surah]:[ayah], '' when none (or before [load]).
  String noteOf(int surah, int ayah) => _notes?['$surah:$ayah'] ?? '';

  Future<void> setNote(int surah, int ayah, String text) async {
    await load();
    final key = '$surah:$ayah';
    if (text.trim().isEmpty) {
      if (_notes!.remove(key) == null) return;
    } else {
      if (_notes![key] == text) return;
      _notes![key] = text;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_notes));
  }
}
