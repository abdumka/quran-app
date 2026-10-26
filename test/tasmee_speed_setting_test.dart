import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/asr_model_manager.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_report_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('«دقة أعلى» is the default; «استجابة أسرع» is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await TasmeeSpeedSetting.mode(), TasmeeSpeed.accurate);
    await TasmeeSpeedSetting.set(TasmeeSpeed.fast);
    expect(await TasmeeSpeedSetting.mode(), TasmeeSpeed.fast);
    expect((await SharedPreferences.getInstance()).getInt('tasmee_speed'), TasmeeSpeed.fast.index);
    await TasmeeSpeedSetting.set(TasmeeSpeed.accurate);
  });

  test('the fast setting drops the judge dwell, halves the settle and picks the chunk-8 export', () {
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
    m.fast = false;
    expect(m.modelFile, 'zipformer_p_arabic_v3.1_c16.int8.onnx');
    expect(m.zipformerFiles.keys, contains('zipformer-tokens.txt'));
    m.fast = true;
    expect(m.modelFile, 'zipformer_p_arabic_v3.1_c8.int8.onnx');
    expect(m.zipformerFiles[m.modelFile], 72705392);
    m.fast = false;
  });
}
