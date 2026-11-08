import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/asr_model_manager.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_report_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('«تحقّق قبل التنبيه» is the only behaviour; an old stored level is ignored', () async {
    SharedPreferences.setMockInitialValues({'tasmee_speed': TasmeeSpeed.fast.index});
    expect(await TasmeeSpeedSetting.mode(), TasmeeSpeed.verified);
    // Tests may still force the other two, in memory only.
    await TasmeeSpeedSetting.set(TasmeeSpeed.fast);
    expect(await TasmeeSpeedSetting.mode(), TasmeeSpeed.fast);
    expect((await SharedPreferences.getInstance()).getInt('tasmee_speed'), TasmeeSpeed.fast.index);
    await TasmeeSpeedSetting.set(TasmeeSpeed.verified);
    expect(await TasmeeSpeedSetting.mode(), TasmeeSpeed.verified);
  });

  test('the fast judge knobs still exist for the replay tests; the app loads the chunk-16 export', () {
    final slow = MemorizationTestService.trackerConfigFor(fast: false);
    final fast = MemorizationTestService.trackerConfigFor(fast: true);
    expect(slow.commitDwell, 6);
    expect(slow.settleFrames, 25);
    expect(fast.commitDwell, 0);
    expect(fast.settleFrames, 12);
    expect(fast.earlyCommit, slow.earlyCommit);
    expect(fast.okDistance, slow.okDistance);
    expect(fast.unsureDistance, slow.unsureDistance);
    expect(MemorizationTestService.settleMsFor(fast: false), 1000);
    expect(MemorizationTestService.settleMsFor(fast: true), 500);
    final m = AsrModelManager.instance;
    expect(m.modelFile, 'zipformer_p_arabic_v3.1_c16.int8.onnx');
    expect(m.zipformerFiles[m.modelFile], 72705392);
    expect(m.zipformerFiles.keys, contains('zipformer-tokens.txt'));
    // The chunk-8 export of the retired «استجابة أسرع» level is cleaned up.
    expect(AsrModelManager.obsoleteFiles, contains('zipformer_p_arabic_v3.1_c8.int8.onnx'));
  });
}
