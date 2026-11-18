import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/page_phoneme_service.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';

/// The Tasmee sounds (assets/data/page_phonemes.json) must follow the Qalun
/// rules the mushaf itself writes. They were generated from Hafs data, and
/// every Hafs rule that slipped through stopped a reader who was right
/// (owner, 2026-11-10: «قُلُ ادعوا» on p175, «يَصّالحا» on p99). Same rules as
/// tools/apply_qalun_phoneme_rules.py, which fixes what this test reports.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fatha = 'َ', damma = 'ُ', kasra = 'ِ';
  const shortVowels = {fatha, damma, kasra};
  const tanweenMarks = {
    'ً', 'ٌ', 'ٍ', 'ٖ', 'ٗ', 'ٞ', //
    'ࣰ', 'ࣱ', 'ࣲ', 'ۢ', 'ۭ',
  };
  const silahMarks = {'ۥ', 'ۦ'};
  const madda = 'ٓ';
  const letters = 'ءآأؤإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىيٱے';
  final trailing = RegExp('[ۖ-ۜ۞۩؀-؅‏ ]+\$');
  final waslAlif = RegExp('^ا([َُِ])[۪۟۬]');
  const ikhfa = 'ںںں';
  const ikhfaLetters = 'تثجدذزسشصضطظفقك';

  ({String letter, List<String> marks}) lastLetter(String text) {
    final t = text.replaceAll(trailing, '');
    final r = t.runes.map(String.fromCharCode).toList();
    var i = r.length - 1;
    final marks = <String>[];
    while (i >= 0 && !letters.contains(r[i])) {
      marks.add(r[i]);
      i--;
    }
    return (letter: i >= 0 ? r[i] : '', marks: marks);
  }

  String firstLetter(String text) =>
      text.runes.map(String.fromCharCode).firstWhere(letters.contains, orElse: () => '');

  /// The stored sound's final short vowel; '' after a consonant, null after a long vowel.
  String? tailVowel(String ph) {
    if (ph.isEmpty) return '';
    final last = String.fromCharCode(ph.runes.last);
    if (shortVowels.contains(last)) return last;
    if ('اۥۦ'.contains(last)) return null;
    return '';
  }

  test('every word follows the Qalun rules written in the mushaf', () {
    final pages = jsonDecode(File('assets/data/page_phonemes.json').readAsStringSync()) as List;
    final flat = <({String key, int wi, int n, List w})>[];
    for (final p in pages) {
      for (final a in (p as Map)['ayahs'] as List) {
        final ws = (a as Map)['w'] as List;
        for (var i = 0; i < ws.length; i++) {
          flat.add((key: a['key'] as String, wi: i, n: ws.length, w: ws[i] as List));
        }
      }
    }
    final broken = <String>[];
    for (var k = 0; k < flat.length; k++) {
      final it = flat[k];
      final text = it.w[0] as String, ph = it.w[1] as String;
      final nxt = k + 1 < flat.length && flat[k + 1].key == it.key ? flat[k + 1] : null;
      final atEnd = it.wi == it.n - 1;
      final (:letter, :marks) = lastLetter(text);
      final vowel = marks.firstWhere(shortVowels.contains, orElse: () => '');
      final core = text.replaceAll(trailing, '');
      final coreTail = core.length >= 3 ? core.substring(core.length - 3) : core;
      final tanween = marks.any(tanweenMarks.contains) ||
          ('اى'.contains(letter) && letter.isNotEmpty && coreTail.split('').any(tanweenMarks.contains));
      final silah = marks.any(silahMarks.contains);
      void fail(String rule) => broken.add('${it.key}:${it.wi} $text «$ph» breaks $rule');

      if (ph.endsWith('$fathaي') && 'يى'.contains(letter) && letter.isNotEmpty &&
          vowel.isEmpty && !marks.contains('ّ')) {
        fail('maqsura');
        continue;
      }
      if (atEnd || marks.contains(madda) || madda.allMatches(text).length >= 2) continue;
      final tv = tailVowel(ph);
      if (vowel.isNotEmpty && !tanween && tv == '' &&
          (ph.endsWith(vowel + ikhfa) || ph.endsWith('$vowel۾۾۾'))) {
        fail('no_tanween');
        continue;
      }
      if (vowel.isNotEmpty && !tanween && !silah && tv != null && tv != vowel) {
        fail('final_vowel');
        continue;
      }
      if (tanween && nxt != null) {
        final m = waslAlif.firstMatch(nxt.w[0] as String);
        if (m != null && m.group(1) != fatha) {
          final want = m.group(1)!;
          final wrong = 'ن${want == damma ? kasra : damma}';
          // At a pause sign readers often stop: the neutral «…ن» is fine there.
          final pause = RegExp('[ۖ-ۜ]').hasMatch(text);
          if (ph.endsWith(wrong) || (!pause && ph.endsWith('ن'))) {
            fail('joining_vowel');
            continue;
          }
        }
      }
      if (letter == 'ه' && (vowel == damma || vowel == kasra) && !silah &&
          (ph.endsWith('هُۥۥ') || ph.endsWith('هِۦۦ'))) {
        fail('silah');
        continue;
      }
      if (tanween && nxt != null && tv != null && tv.isNotEmpty) {
        final f = firstLetter(nxt.w[0] as String);
        final nph = nxt.w[1] as String;
        if (f.isNotEmpty && 'يو'.contains(f) && !nph.startsWith(f + f)) fail('tanween_tail');
        if (f.isNotEmpty && ikhfaLetters.contains(f)) fail('tanween_tail');
      }
    }
    expect(broken, isEmpty, reason: 'run tools/apply_qalun_phoneme_rules.py --write');
  });

  Future<Map<VerdictState, String>> readAyah(int page, String startsWith, int targetFromStart, String said) async {
    final words = (await PagePhonemeService.forPage(page))!.collapsed();
    final start = words.indexWhere((w) => w.phon.startsWith(startsWith));
    expect(start, greaterThanOrEqualTo(0));
    final ayah = words[start].ayah;
    final target = start + targetFromStart;
    final tracker = PhonemeTracker(
      PhonemeReference(words, PhonemeCostTable()),
      startAnywhere: false,
      startWord: words.indexWhere((w) => w.ayah == ayah),
    );
    var frame = 0;
    for (var i = words.indexWhere((w) => w.ayah == ayah); i < words.length && words[i].ayah == ayah; i++) {
      for (final r in (i == target ? said : words[i].phon).runes) {
        tracker.feedOne(HeardChar(String.fromCharCode(r), frame += 2));
      }
    }
    final v = VerdictTracer(tracker).verdicts(settled: true).firstWhere((x) => x.word == target);
    return {v.state: v.reason};
  }

  test('p99 4:127: «يَصّالحا» is right, the Hafs «يُصلحا» is a Hafs reading', () async {
    final words = (await PagePhonemeService.forPage(99))!.collapsed();
    final w = words.firstWhere((w) => w.phon.startsWith('يَصصَاالَحَا'));
    expect(w.hafsAlt, startsWith('يُصلِحَا'));
    // the whole ayah from its first word (وَإِنِ امرأة), the target is word 12
    expect((await readAyah(99, 'وَءِنِ', 12, w.phon)).keys.single, VerdictState.ok);
    final hafs = await readAyah(99, 'وَءِنِ', 12, w.hafsAlt);
    expect(hafs.keys.single, VerdictState.wrong);
    expect(hafs.values.single, 'hafs');
  });

  test('p175 7:195: «قُلُ ادعوا» is stored with the damma Qalun reads', () async {
    final words = (await PagePhonemeService.forPage(175))!.collapsed();
    final i = words.indexWhere((w) => w.text == 'قُلُ');
    expect(i, greaterThanOrEqualTo(0));
    expect(words[i].phon, 'قُلُ');
  });
}
