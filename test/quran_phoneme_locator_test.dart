import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/page_phoneme_service.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';
import 'package:islamic_dawah_mushaf/utils/quran_phoneme_locator.dart';

void main() {
  late Map<int, PagePhonemes> pages;
  late QuranPhonemeLocator locator;

  String run(int page, int from, int count) => [
        for (final w in pages[page]!.words.sublist(from, from + count)) collapseMadd(w.phon),
      ].join();

  setUpAll(() {
    pages = PagePhonemeService.parse(
      File('assets/data/page_phonemes.json').readAsStringSync(),
    );
    locator = QuranPhonemeLocator(pages);
  });

  test('covers the whole mushaf', () {
    expect(pages.length, 602);
    expect(locator.length, greaterThan(300000));
  });

  test('finds a run of words in the middle of a page, fast enough', () {
    final sw = Stopwatch()..start();
    final hit = locator.locate(run(255, 40, 4));
    sw.stop();
    expect(hit, isNotNull);
    expect(hit!.page, 255, reason: '$hit');
    expect(hit.wordOnPage, 40);
    expect(hit.ayahOnPage, pages[255]!.words[40].ayah);
    expect(hit.distance, 0);
    // One search is a fraction of a second even on the test machine.
    expect(sw.elapsedMilliseconds, lessThan(300));
  });

  test('a repeated phrase lands on its first page', () {
    // «فبأي آلاء ربكما تكذبان» is said thirty-one times in al-Rahman; heard
    // on a later page (531) it is answered with the first place it occurs.
    final needle = 'فَبِأَيِّ';
    final later = pages[531]!.words.indexWhere((w) => w.text.startsWith(needle));
    expect(later, greaterThanOrEqualTo(0));
    final phrase = [for (final w in pages[531]!.words.sublist(later, later + 4)) w.text];
    final hit = locator.locate(run(531, later, 4));
    expect(hit, isNotNull);
    expect(hit!.page, lessThan(531), reason: '$hit');
    expect(hit.distance, 0);
    final at = [for (final w in pages[hit.page]!.words.sublist(hit.wordOnPage, hit.wordOnPage + 4)) w.text];
    expect(at, phrase);
    // No earlier page carries the phrase.
    for (final n in pages.keys.where((n) => n < hit.page)) {
      final texts = pages[n]!.words.map((w) => w.text).join(' ');
      expect(texts.contains(phrase.join(' ')), isFalse, reason: 'page $n has it earlier');
    }
    // A different phrase that merely starts the same way stays its own.
    final other = pages[174]!.words.indexWhere((w) => w.text.startsWith(needle));
    expect(locator.locate(run(174, other, 4))!.page, 174);
  });

  test('a run heard with a mistake still lands on its page', () {
    final clean = run(255, 40, 5);
    final noisy = clean.replaceRange(6, 7, 'ت'); // one phoneme wrong
    final hit = locator.locate(noisy);
    expect(hit, isNotNull);
    expect(hit!.page, 255, reason: '$hit');
    expect(hit.distance, greaterThan(0));
    expect(hit.distance, lessThan(0.25));
  });

  test('noise that fits nowhere is rejected', () {
    expect(locator.locate('ءءءءءءءءءءءءءءءءءءءءءءءءءءءء'), isNull);
    expect(locator.locate(''), isNull);
  });
}
