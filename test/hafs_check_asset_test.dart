import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/page_phoneme_service.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';

/// The shipped page data must keep the Hafs-habit check on the words Qalun
/// and Hafs really read differently (page 3: wa-ma yukhadi'una, Hafs
/// yakhda'una), and judge the Hafs form as wrong there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('page 3: yakhda-una for yukhadi-una is a Hafs reading', () async {
    final words = (await PagePhonemeService.forPage(3))!.collapsed();
    // Second occurrence in the ayah (the first is read alike in both).
    final hits = [
      for (var i = 0; i < words.length; i++)
        if (words[i].phon.startsWith('يُخَاادِعُ')) i,
    ];
    expect(hits.length, 2);
    final target = hits[1];
    expect(words[target].hafsAlt, isNotEmpty, reason: 'the Hafs check is on');
    expect(words[target].accept, isNot(contains(words[target].hafsAlt)));

    final ayah = words[target].ayah;
    final start = words.indexWhere((w) => w.ayah == ayah);
    final tracker = PhonemeTracker(
      PhonemeReference(words, PhonemeCostTable()),
      startAnywhere: false,
      startWord: start,
    );
    var frame = 0;
    for (var i = start; i < words.length && words[i].ayah == ayah; i++) {
      final said = i == target ? words[i].hafsAlt : words[i].phon;
      for (final r in said.runes) {
        tracker.feedOne(HeardChar(String.fromCharCode(r), frame += 2));
      }
    }
    final v = {
      for (final x in VerdictTracer(tracker).verdicts(settled: true)) x.word: x,
    };
    expect(v[target]!.state, VerdictState.wrong);
    expect(v[target]!.reason, 'hafs');
    expect(v[hits[0]]!.state, VerdictState.ok);
  });

  test('the check is on for several hundred words, off where the model cannot hear', () async {
    final all = await PagePhonemeService.loadAll();
    var on = 0;
    for (final p in all.values) {
      for (final w in p.words) {
        if (w.hafsAlt.isNotEmpty) on++;
        // wa-hwa: accepted both ways (the model hears wa-huwa from Qalun sheikhs).
        if (w.phon == 'وَهوَ') expect(w.hafsAlt, isEmpty);
      }
    }
    expect(on, greaterThan(400));
  });
}
