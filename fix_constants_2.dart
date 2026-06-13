import 'dart:io';

void main() {
  final pageFile = File('lib/widgets/settings/settings_page.dart');
  var pageContent = pageFile.readAsStringSync();
  
  // Remove enum _SettingsCoachStep from page
  final enumRegex = RegExp(r'enum _SettingsCoachStep \{[^\}]+\}');
  final enumMatch = enumRegex.firstMatch(pageContent);
  if (enumMatch != null) {
      pageContent = pageContent.replaceFirst(enumMatch.group(0)!, '');
      
      // Append it to settings_constants.dart
      final constantsFile = File('lib/widgets/settings/settings_constants.dart');
      var constantsContent = constantsFile.readAsStringSync();
      constantsContent += '\n${enumMatch.group(0)!.replaceAll('_SettingsCoachStep', 'SettingsCoachStep')}\n';
      constantsFile.writeAsStringSync(constantsContent);
  }

  // Remove the static constants left in SettingsPage
  pageContent = pageContent.replaceAll(RegExp(r'\s*static const String [a-zA-Z0-9_]+ =[^\n]+;\n'), '\n');
  pageContent = pageContent.replaceAll(RegExp(r'\s*const Color settings[a-zA-Z0-9_]+ =[^\n]+;\n'), '\n');
  
  // Also replace references to _SettingsCoachStep with SettingsCoachStep
  pageContent = pageContent.replaceAll('_SettingsCoachStep', 'SettingsCoachStep');
  pageFile.writeAsStringSync(pageContent);

  // Replace _SettingsCoachStep in coach overlay
  final coachFile = File('lib/widgets/settings/settings_coach_overlay.dart');
  var coachContent = coachFile.readAsStringSync();
  coachContent = coachContent.replaceAll('_SettingsCoachStep', 'SettingsCoachStep');
  // ensure it imports settings_constants
  if (!coachContent.contains("import 'settings_constants.dart';")) {
    coachContent = "import 'settings_constants.dart';\n$coachContent";
  }
  coachFile.writeAsStringSync(coachContent);
}
