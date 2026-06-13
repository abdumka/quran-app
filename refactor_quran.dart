import 'dart:io';

void main() {
  final quranFile = File('lib/quran_pages.dart');
  final lines = quranFile.readAsLinesSync();

  // Lines 32-328 are elements 31 to 327 (inclusive). 
  // Wait, my Select-String output said:
  // 32:class _BookmarkPickerResult {
  // 68:class _BookmarkPickerDialogState extends State<_BookmarkPickerDialog> {
  // 294:class _BookmarkRibbonPainter extends CustomPainter {
  // 329:class _QuranPagesState extends State<QuranPages>
  // So lines 32 to 328 are index 31 to 327.
  
  final bookmarkPickerLines = lines.sublist(31, 293);
  final ribbonPainterLines = lines.sublist(293, 328);
  
  // Write bookmark_picker_dialog.dart
  final pickerFile = File('lib/widgets/quran/bookmark_picker_dialog.dart');
  pickerFile.writeAsStringSync([
    "import 'package:flutter/material.dart';",
    "import '../../models/reader_bookmark.dart';",
    "import 'dart:ui';",
    ...bookmarkPickerLines
  ].join('\n').replaceAll('_BookmarkPicker', 'BookmarkPicker'));

  // Write bookmark_ribbon_painter.dart
  final painterFile = File('lib/widgets/quran/bookmark_ribbon_painter.dart');
  painterFile.writeAsStringSync([
    "import 'package:flutter/material.dart';",
    ...ribbonPainterLines
  ].join('\n').replaceAll('_BookmarkRibbonPainter', 'BookmarkRibbonPainter'));

  // Remove the extracted lines from quran_pages.dart
  lines.removeRange(31, 328);

  // Insert imports at the top
  lines.insert(10, "import 'widgets/quran/bookmark_picker_dialog.dart';");
  lines.insert(11, "import 'widgets/quran/bookmark_ribbon_painter.dart';");

  var content = lines.join('\n');
  content = content.replaceAll('_BookmarkPickerDialog', 'BookmarkPickerDialog');
  content = content.replaceAll('_BookmarkRibbonPainter', 'BookmarkRibbonPainter');
  content = content.replaceAll('_BookmarkPickerResult', 'BookmarkPickerResult');

  quranFile.writeAsStringSync(content);
}
