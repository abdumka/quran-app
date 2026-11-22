import 'package:flutter/material.dart';

import '../quran_constants.dart';
import '../services/app_look_service.dart';
import '../services/index_text.dart';
import '../theme/app_surfaces.dart';
import '../utils/responsive_helper.dart';

class HizbIndexPage extends StatelessWidget {
  final Function(int page) onGoToPage;

  const HizbIndexPage({
    super.key,
    required this.onGoToPage,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);
    // null in the previous look and in night mode: the old colours stay
    final s = AppSurfaces.maybeOf(context);
    final previous = AppLookScope.isPrevious(context);

    return Scaffold(
      backgroundColor: s?.page ?? const Color(0xFFF6F1E5),
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        backgroundColor: s?.page ?? const Color(0xFFF6F1E5),
        foregroundColor: s?.text ?? const Color(0xFF3D3122),
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
          'قائمة الأحزاب',
          style: TextStyle(
            fontSize: isTablet ? 24 : 21,
            fontWeight: previous ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 6),
            _ElegantHeader(isTablet: isTablet),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                itemCount: hizbStartPages.length,
                itemBuilder: (context, index) {
                  final hizbNumber = index + 1;
                  final page = hizbStartPages[index];
                  final named = IndexText.hizbTitle(hizbNumber);
                  final title = named.isNotEmpty ? named : 'الحزب $hizbNumber';

                  return _HizbCard(
                    isTablet: isTablet,
                    hizbNumber: hizbNumber,
                    title: title,
                    page: page,
                    onTap: () {
                      Navigator.pop(context);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        onGoToPage(page);
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElegantHeader extends StatelessWidget {
  final bool isTablet;

  const _ElegantHeader({
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSurfaces.maybeOf(context);
    final ornament =
        (s?.accent ?? const Color(0xFF8D6E3F)).withValues(alpha: 0.75);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isTablet ? 18 : 14,
        ),
        decoration: BoxDecoration(
          // the new look: a flat band with a hairline
          color: s?.band,
          borderRadius: BorderRadius.circular(
            s == null ? 20 : AppSurfaces.radius,
          ),
          border: Border.all(
            color: s?.border ??
                const Color(0xFF8D6E3F).withValues(alpha: 0.40),
            width: s == null ? 1.4 : 1,
          ),
          gradient: s != null
              ? null
              : const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFFF8F3E8),
                    Color(0xFFEADFC7),
                  ],
                ),
          boxShadow: s != null
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              right: 0,
              child: Icon(
                Icons.auto_awesome,
                color: ornament,
                size: isTablet ? 22 : 18,
              ),
            ),
            Positioned(
              left: 0,
              child: Icon(
                Icons.auto_awesome,
                color: ornament,
                size: isTablet ? 22 : 18,
              ),
            ),
            Text(
              'فهرس الأحزاب',
              style: TextStyle(
                color: s?.text ?? const Color(0xFF3D3122),
                fontWeight: s == null ? FontWeight.w800 : FontWeight.w600,
                fontSize: isTablet ? 28 : 23,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HizbCard extends StatelessWidget {
  final bool isTablet;
  final int hizbNumber;
  final String title;
  final int page;
  final VoidCallback onTap;

  const _HizbCard({
    required this.isTablet,
    required this.hizbNumber,
    required this.title,
    required this.page,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // null in the previous look and in night mode: the old colours stay
    final s = AppSurfaces.maybeOf(context);
    final radius = s == null ? 18.0 : AppSurfaces.cardRadius;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 4 : 2,
        vertical: 5,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: s?.card ?? const Color(0xFFF3EFE6),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: s?.border ??
                    const Color(0xFF8D6E3F).withValues(alpha: 0.10),
              ),
              boxShadow: s != null
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.035),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 16 : 14,
                vertical: isTablet ? 16 : 14,
              ),
              child: Row(
                children: [
                  _HizbBadge(
                    number: hizbNumber,
                    isTablet: isTablet,
                  ),
                  SizedBox(width: isTablet ? 14 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '﴿ $title ﴾',
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: isTablet ? 21 : 18,
                            fontWeight:
                                s == null ? FontWeight.w800 : FontWeight.w600,
                            color: s?.text ?? const Color(0xFF2F2418),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: s?.tile ??
                                const Color(0xFF8D6E3F).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'الصفحة $page',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: isTablet ? 14 : 12,
                              color: s?.muted ?? const Color(0xFF6A5330),
                              fontWeight:
                                  s == null ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HizbBadge extends StatelessWidget {
  final int number;
  final bool isTablet;

  const _HizbBadge({
    required this.number,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    final double size = isTablet ? 62 : 52;
    // the new look: the number in a gold outline, no gradient disc
    final s = AppSurfaces.maybeOf(context);

    return Container(
      width: size,
      height: size,
      decoration: s != null
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: s.accent, width: 2),
            )
          : BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xFFA8844A),
                  Color(0xFF8D6E3F),
                ],
              ),
              border: Border.all(
                color: const Color(0xFFE7D7B5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size - 12,
            height: size - 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: s == null
                    ? Colors.white.withValues(alpha: 0.18)
                    : Colors.transparent,
                width: 1.2,
              ),
            ),
          ),
          Text(
            '$number',
            style: TextStyle(
              color: s?.accent ?? Colors.white,
              fontWeight: s == null ? FontWeight.w900 : FontWeight.w600,
              fontSize: isTablet ? 22 : 18,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
