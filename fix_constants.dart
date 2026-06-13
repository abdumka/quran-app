import 'dart:io';

void main() {
  final dir = Directory('lib/widgets/settings');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dart'));

  final replacements = {
    '_settingsPrimaryTextColor': 'settingsPrimaryTextColor',
    '_settingsSecondaryTextColor': 'settingsSecondaryTextColor',
    '_SettingsPageState._readingSettingsTitle': 'readingSettingsTitle',
    '_SettingsPageState._autoScrollTitle': 'autoScrollTitle',
    '_SettingsPageState._autoScrollSubtitle': 'autoScrollSubtitle',
    '_SettingsPageState._autoScrollUnavailableNotice': 'autoScrollUnavailableNotice',
    '_SettingsPageState._tabletOnlyNotice': 'tabletOnlyNotice',
    '_SettingsPageState._scrollUnavailableInTabletNotice': 'scrollUnavailableInTabletNotice',
    '_SettingsPageState._browseModeTitle': 'browseModeTitle',
    '_SettingsPageState._browseModeSubtitle': 'browseModeSubtitle',
    '_SettingsPageState._pagesLabel': 'pagesLabel',
    '_SettingsPageState._scrollLabel': 'scrollLabel',
    '_SettingsPageState._tabletModeTitle': 'tabletModeTitle',
    '_SettingsPageState._tabletModeSubtitle': 'tabletModeSubtitle',
    '_readingSettingsTitle': 'readingSettingsTitle',
    '_autoScrollTitle': 'autoScrollTitle',
    '_autoScrollSubtitle': 'autoScrollSubtitle',
    '_autoScrollUnavailableNotice': 'autoScrollUnavailableNotice',
    '_tabletOnlyNotice': 'tabletOnlyNotice',
    '_scrollUnavailableInTabletNotice': 'scrollUnavailableInTabletNotice',
    '_browseModeTitle': 'browseModeTitle',
    '_browseModeSubtitle': 'browseModeSubtitle',
    '_pagesLabel': 'pagesLabel',
    '_scrollLabel': 'scrollLabel',
    '_tabletModeTitle': 'tabletModeTitle',
    '_tabletModeSubtitle': 'tabletModeSubtitle',
  };

  for (var file in files) {
    if (file.path.endsWith('settings_constants.dart')) continue;
    
    var content = file.readAsStringSync();
    
    // Add import if not present
    if (!content.contains("import 'settings_constants.dart';")) {
      content = content.replaceFirst("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'settings_constants.dart';");
    }
    
    replacements.forEach((key, value) {
      content = content.replaceAll(key, value);
    });
    
    // Also remove the old static const String declarations from settings_page.dart
    if (file.path.endsWith('settings_page.dart')) {
      content = content.replaceAll(RegExp(r'\s*static const String [a-zA-Z0-9_]+ =[^\n]+;\n'), '\n');
      content = content.replaceAll(RegExp(r'\s*const Color _settings[a-zA-Z0-9_]+ =[^\n]+;\n'), '\n');
    }
    
    file.writeAsStringSync(content);
  }
}
