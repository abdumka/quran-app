import 'dart:io';

void main() {
  final file = File('lib/widgets/settings_page.dart');
  final lines = file.readAsLinesSync();

  final settingsPageLines = lines.sublist(0, 779);
  final components1 = lines.sublist(779, 1215);
  final coachOverlay = lines.sublist(1215, 1725);
  final components2 = lines.sublist(1725, 2116);
  final downloadsPage = lines.sublist(2116);
  
  Directory('lib/widgets/settings').createSync(recursive: true);
  
  final componentsFile = File('lib/widgets/settings/settings_components.dart');
  componentsFile.writeAsStringSync([
    "import 'package:flutter/material.dart';",
    "import '../../services/high_quality_images_service.dart';",
    "import '../../services/margin_images_service.dart';",
    "import '../../utils/responsive_helper.dart';",
    ...components1,
    ...components2
  ].join('\n'));

  final coachFile = File('lib/widgets/settings/settings_coach_overlay.dart');
  coachFile.writeAsStringSync([
    "import 'package:flutter/material.dart';",
    "import 'dart:math' as math;",
    "import 'settings_page.dart';", 
    ...coachOverlay
  ].join('\n'));

  final downloadsFile = File('lib/widgets/settings/downloads_management_page.dart');
  downloadsFile.writeAsStringSync([
    "import 'package:flutter/material.dart';",
    "import '../../services/high_quality_images_service.dart';",
    "import '../../services/margin_images_service.dart';",
    ...downloadsPage
  ].join('\n'));
  
  settingsPageLines.insert(10, "import 'settings_components.dart';");
  settingsPageLines.insert(11, "import 'settings_coach_overlay.dart';");
  settingsPageLines.insert(12, "import 'downloads_management_page.dart';");
  
  final mainSettingsFile = File('lib/widgets/settings/settings_page.dart');
  mainSettingsFile.writeAsStringSync(settingsPageLines.join('\n'));
}
