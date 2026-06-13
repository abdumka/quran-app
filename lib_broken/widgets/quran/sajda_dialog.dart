import 'package:flutter/material.dart';

import '../../quran_data.dart';

/// Shows the sajda dua dialog.
Future<void> showSajdaDuaDialog(BuildContext context) async {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;

  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: isDarkMode
            ? const Color(0xFF19130A)
            : const Color(0xFFF8F1DE),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: isDarkMode
                ? const Color(0xFFD6B35D).withValues(alpha: 0.55)
                : const Color(0xFFE2D2A5),
          ),
        ),
        // "دعاء السجود"
        title: Text(
          '\u062F\u0639\u0627\u0621 \u0627\u0644\u0633\u062C\u0648\u062F',
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: isDarkMode ? const Color(0xFFFFF4D6) : const Color(0xFF35250E),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          '${QuranData.sajdaDua}\n\n${QuranData.dawudSajdaDua}',
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            height: 1.9,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDarkMode ? Colors.white : const Color(0xFF35250E),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            // "إغلاق"
            child: const Text(
              '\u0625\u063A\u0644\u0627\u0642',
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      );
    },
  );
}
