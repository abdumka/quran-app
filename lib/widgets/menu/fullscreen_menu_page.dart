import 'package:flutter/material.dart';

import '../../services/app_look_service.dart';
import '../../theme/app_surfaces.dart';

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
    // null in the previous look and in night mode: the old colours stay
    final s = AppSurfaces.maybeOf(context);
    final previous = AppLookScope.isPrevious(context);
    final backgroundColor =
        isDarkMode ? const Color(0xFF111111) : s?.page ?? const Color(0xFFF6F1E5);
    final foregroundColor =
        isDarkMode ? Colors.white : s?.text ?? const Color(0xFF35250E);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        elevation: 0,
        centerTitle: true,
        // On an Arabic page "back" sits on the right, pointing right; the
        // previous look keeps Flutter's own arrow.
        automaticallyImplyLeading: previous,
        actions: previous
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  tooltip: 'رجوع',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 4),
              ],
        title: Text(
          title,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontWeight: previous ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(child: child),
    );
  }
}
