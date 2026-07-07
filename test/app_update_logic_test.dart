import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/app_update_service.dart';

void main() {
  group('AppUpdateInfo.fromManifest', () {
    const manifest = '''
    {
      "version": "2.1.0",
      "build": 21,
      "mandatory": false,
      "changes": ["a", "b", ""],
      "android": {"storeUrl": "https://play/x"},
      "ios": {"storeUrl": "https://apps/y", "version": "2.1.1"}
    }
    ''';

    test('android reads shared version + platform storeUrl', () {
      final info = AppUpdateInfo.fromManifest(
        jsonDecode(manifest) as Map<String, dynamic>,
        isIOS: false,
        fallbackStoreUrl: 'FB',
      );
      expect(info.latestVersion, '2.1.0');
      expect(info.latestBuild, 21);
      expect(info.storeUrl, 'https://play/x');
      expect(info.changes, ['a', 'b']); // empty dropped
      expect(info.mandatory, false);
    });

    test('ios override of version takes precedence', () {
      final info = AppUpdateInfo.fromManifest(
        jsonDecode(manifest) as Map<String, dynamic>,
        isIOS: true,
        fallbackStoreUrl: 'FB',
      );
      expect(info.latestVersion, '2.1.1');
      expect(info.storeUrl, 'https://apps/y');
    });

    test('missing storeUrl uses fallback', () {
      final info = AppUpdateInfo.fromManifest(
        {'version': '3.0.0'},
        isIOS: false,
        fallbackStoreUrl: 'FALLBACK',
      );
      expect(info.storeUrl, 'FALLBACK');
      expect(info.changes, isEmpty);
    });
  });
}
