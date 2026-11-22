import 'package:flutter/foundation.dart' show visibleForTesting;

import '../quran_constants.dart';
import '../thumn_data.dart';

/// The index's own words: each thumn's opening and each hizb's title, with
/// any correction from our server laid over the bundled text.
///
/// The bundled text is `thumnEntries` (generated from
/// `assets/data/athman_page_hizb.csv`) and `hizbTitles`. Corrections arrive
/// in the `quran_data` server item as `thumnTexts` / `hizbTitles` (see
/// `QuranDataPatch`), so a typo in a label no longer needs a store release.
/// A user found 15 such typos and a missing hizb title on 2026-11-21.
class IndexText {
  IndexText._();

  static Map<int, String> _thumn = const {};
  static Map<int, String> _hizb = const {};

  /// Bumped when corrections arrive, so an open index can redraw.
  static int generation = 0;

  /// Lays the server's corrections over the bundle (thumn 1..480, hizb 1..60).
  static void apply({Map<int, String>? thumn, Map<int, String>? hizb}) {
    _thumn = Map.unmodifiable(thumn ?? const {});
    _hizb = Map.unmodifiable(hizb ?? const {});
    generation++;
  }

  /// The opening words shown for thumn [e].
  static String thumn(ThumnEntry e) => _thumn[e.number] ?? e.text;

  /// The title of hizb [hizb] (1..60), or '' when there is none.
  static String hizbTitle(int hizb) =>
      _hizb[hizb] ??
      (hizb >= 1 && hizb <= hizbTitles.length ? hizbTitles[hizb - 1] : '');

  @visibleForTesting
  static void debugReset() => apply();
}
