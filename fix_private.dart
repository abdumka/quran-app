import 'dart:io';

void main() {
  final dir = Directory('lib/widgets/settings');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dart'));

  final replacements = {
    '_SectionHeader': 'SectionHeader',
    '_SettingsCard': 'SettingsCard',
    '_SwitchTile': 'SwitchTile',
    '_ActionTile': 'ActionTile',
    '_ModeTile': 'ModeTile',
    '_TabletLayoutTile': 'TabletLayoutTile',
    '_DownloadsManagementTile': 'DownloadsManagementTile',
    '_HighQualityImagesTile': 'HighQualityImagesTile',
    '_MarginImagesTile': 'MarginImagesTile',
    '_SettingsCoachOverlay': 'SettingsCoachOverlay',
    '_DownloadsManagementPage': 'DownloadsManagementPage',
    '_CoachOverlayPainter': 'CoachOverlayPainter',
    '_CoachVisual': 'CoachVisual',
    '_BrowseModeCoachVisual': 'BrowseModeCoachVisual',
    '_AutoScrollCoachVisual': 'AutoScrollCoachVisual',
    '_MarginCoachVisual': 'MarginCoachVisual',
    '_VisualPageCard': 'VisualPageCard',
    '_DownloadedPackageCard': 'DownloadedPackageCard',
    '_InfoChip': 'InfoChip',
  };

  for (var file in files) {
    var content = file.readAsStringSync();
    replacements.forEach((key, value) {
      // Replace whole word matches to avoid partial replacements (though they start with _)
      content = content.replaceAll(RegExp(r'\b' + key + r'\b'), value);
    });
    file.writeAsStringSync(content);
  }
}
