import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A random, persistent identifier for this installation, generated on
/// first use. It distinguishes recitation sessions of different users in
/// shared or uploaded logs without identifying anyone: it carries no
/// account, device serial or personal data, and a reinstall gets a new one.
class InstallId {
  InstallId._();

  static const String _key = 'tasmee_install_id';
  static String? _cached;

  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.length < 8) {
      id = generate();
      await prefs.setString(_key, id);
    }
    _cached = id;
    return id;
  }

  /// 16 random bytes as 32 hex characters.
  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    final b = StringBuffer();
    for (var i = 0; i < 16; i++) {
      b.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  /// The short form used in file names.
  static String short(String id) => id.length > 8 ? id.substring(0, 8) : id;
}
