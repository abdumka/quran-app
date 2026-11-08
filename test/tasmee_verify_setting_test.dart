import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_report_store.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

PhonemeWord _w(String phon, {List<String> accept = const [], bool wasl = false}) =>
    PhonemeWord(
      phon: phon,
      text: phon,
      ayah: 0,
      wordInAyah: 0,
      ayahWords: 1,
      accept: accept,
      wasl: wasl,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('«تحقّق قبل التنبيه» is the app\'s behaviour; the level names stay for the logs', () async {
    SharedPreferences.setMockInitialValues({});
    expect(TasmeeSpeed.values, [TasmeeSpeed.accurate, TasmeeSpeed.fast, TasmeeSpeed.verified]);
    expect(TasmeeSpeedSetting.label(TasmeeSpeed.verified), 'تحقّق قبل التنبيه');
    expect(TasmeeSpeedSetting.label(TasmeeSpeed.accurate), 'دقة أعلى');
    expect(TasmeeSpeedSetting.label(TasmeeSpeed.fast), 'استجابة أسرع');
    await TasmeeSpeedSetting.set(TasmeeSpeed.verified);
    expect(await TasmeeSpeedSetting.mode(), TasmeeSpeed.verified);
    expect((await SharedPreferences.getInstance()).getInt('tasmee_speed'), isNull);
  });

  group('verifyHears', () {
    // 36:6-7 on p440: the live decode dropped the ل of «لقد»; the fresh
    // decode of the clip heard it (research_2026-10-05/clips/p440_laqad).
    final words = [_w('غَاافِلُۥۥنَ'), _w('لَقَدڇ'), _w('حَققَ'), _w('لقَولُ')];

    test('the expected word anchored on the next word clears the stop', () {
      const fresh = 'ءُهُمفَهُمغَاافِلُۥۥۥۥنلَقَدڇحَققَلقَولُعَلَااااءَكثَرِهِم';
      expect(MemorizationTestService.verifyHears(fresh, words, 1), isTrue);
    });

    test('anchored on the previous word too', () {
      expect(MemorizationTestService.verifyHears('لُۥۥنَلَقَدڇ', words, 1), isTrue);
    });

    test('the live reading (first sound dropped) does not clear it', () {
      expect(MemorizationTestService.verifyHears('غَاافِلُۥۥنقَدڇحَققَ', words, 1), isFalse);
    });

    test('a bare substring inside another word is no match: لمن read as من', () {
      final w = [_w('ءِننننَكَ'), _w('لَمِنَ'), _w('لمُرسَلِۦۦنَ')];
      expect(MemorizationTestService.verifyHears('ءِننننَكَمِنَلمُرسَلِۦۦنَ', w, 1), isFalse);
      expect(MemorizationTestService.verifyHears('ءِننننَكَلَمِنَلمُرسَلِۦۦنَ', w, 1), isTrue);
    });

    test('a particle the page does not have is not cleared: وأحل read for أحل', () {
      // 5:89, a real slip the next-word anchor used to hide.
      final w = [_w('مَاا'), _w('ءَحَللَ'), _w('للَااهُ')];
      expect(MemorizationTestService.verifyHears('طَييِبَتِوَءَحَللَللَااهُلَكُم', w, 1), isFalse);
      expect(MemorizationTestService.verifyHears('طَييِبَتِمَااءَحَللَللَااهُلَكُم', w, 1), isTrue);
      expect(MemorizationTestService.verifyHears('ءَحَللَللَااهُلَكُم', w, 1), isTrue);
    });

    test('a later occurrence without the particle still clears it', () {
      final w = [_w('مَاا'), _w('ءَحَللَ'), _w('للَااهُ')];
      expect(MemorizationTestService.verifyHears('وَءَحَللَللَااهُءَحَللَللَااهُ', w, 1), isTrue);
    });

    test('the sound before the match may belong to the word before', () {
      final w = [_w('قَاالَ'), _w('مَاا'), _w('كَاانَ')];
      expect(MemorizationTestService.verifyHears('لَمَااكَاانَ', w, 1), isTrue);
    });

    test('accepted forms and the connected form of a wasl word count', () {
      final w = [_w('وَهُوَ', accept: ['وَهوَ']), _w('ءَلقَااهِرُ', wasl: true), _w('فَوقَ')];
      expect(MemorizationTestService.verifyHears('وَهوَلقَااهِرُفَوقَ', w, 1), isTrue);
      expect(MemorizationTestService.verifyHears('وَهوَلقَااهِرُفَوقَ', w, 0), isTrue);
      expect(MemorizationTestService.verifyHears('وَهوَلغَااهِرُفَوقَ', w, 1), isFalse);
    });

    test('madd runs are collapsed on both sides', () {
      expect(MemorizationTestService.verifyHears('غَااااافِلُۥۥۥۥۥنَلَقَدڇ', words, 1), isTrue);
    });

    test('out-of-range words are never cleared', () {
      expect(MemorizationTestService.verifyHears('لَقَدڇ', words, 9), isFalse);
      expect(MemorizationTestService.verifyHears('', words, 1), isFalse);
    });
  });
}
