import 'package:flutter/material.dart';

class FullscreenMenuPage extends StatelessWidget {
  final String title;
  final bool isDarkMode;
  final Widget child;

  const FullscreenMenuPage({
    super.key,
    required this.title,
    required this.isDarkMode,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        isDarkMode ? const Color(0xFF111111) : const Color(0xFFF6F1E5);
    final foregroundColor =
        isDarkMode ? Colors.white : const Color(0xFF35250E);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          title,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(child: child),
    );
  }
}
