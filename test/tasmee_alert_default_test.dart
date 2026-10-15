import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_report_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('alerts default to tone and vibration until the reader changes them', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await TasmeeAlert.mode(), TasmeeAlertMode.vibrateAndSound);
    expect(await TasmeeAlert.mode(kind: TasmeeAlertKind.corrected), TasmeeAlertMode.vibrateAndSound);
    await TasmeeAlert.setMode(TasmeeAlertMode.vibrate);
    expect(await TasmeeAlert.mode(), TasmeeAlertMode.vibrate);
    expect(await TasmeeAlert.mode(kind: TasmeeAlertKind.corrected), TasmeeAlertMode.vibrateAndSound);
  });
}
