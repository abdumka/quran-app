import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What «تلاوة» in an ayah's options plays: on from that ayah («متابعة», the
/// default) or that ayah alone («آية فقط»). The reader's last choice is kept
/// between launches.
class AyahPlaySetting {
  static const String _onlyThisKey = 'ayahPlayOnlyThis';

  static final ValueNotifier<bool> onlyThisAyah = ValueNotifier(false);

  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    onlyThisAyah.value = prefs.getBool(_onlyThisKey) ?? false;
  }

  static Future<void> setOnlyThisAyah(bool value) async {
    onlyThisAyah.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onlyThisKey, value);
  }
}
