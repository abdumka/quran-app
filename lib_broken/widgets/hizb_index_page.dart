import 'package:flutter/material.dart';

import '../quran_constants.dart';
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

    return Scaffold(
      backgroundColor: const Color(0xFFF6F1E5),
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFFF6F1E5),
        foregroundColor: const Color(0xFF3D3122),
        title: Text(
          'قائمة الأحزاب',
          style: TextStyle(
            fontSize: isTablet ? 24 : 21,
            fontWeight: FontWeight.w800,
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
                  final title = index < hizbTitles.length
                      ? hizbTitles[index]
                      : 'الحزب $hizbNumber';

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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isTablet ? 18 : 14,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF8D6E3F).withValues(alpha: 0.40),
            width: 1.4,
          ),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFFF8F3E8),
              Color(0xFFEADFC7),
            ],
          ),
          boxShadow: [
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
                color: const Color(0xFF8D6E3F).withValues(alpha: 0.75),
                size: isTablet ? 22 : 18,
              ),
            ),
            Positioned(
              left: 0,
              child: Icon(
                Icons.auto_awesome,
                color: const Color(0xFF8D6E3F).withValues(alpha: 0.75),
                size: isTablet ? 22 : 18,
              ),
            ),
            Text(
              'فهرس الأحزاب',
              style: TextStyle(
                color: const Color(0xFF3D3122),
                fontWeight: FontWeight.w800,
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
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 4 : 2,
        vertical: 5,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFFF3EFE6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF8D6E3F).withValues(alpha: 0.10),
              ),
              boxShadow: [
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
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF2F2418),
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
                            color: const Color(0xFF8D6E3F).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'الصفحة $page',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: isTablet ? 14 : 12,
                              color: const Color(0xFF6A5330),
                              fontWeight: FontWeight.w600,
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

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
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
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.2,
              ),
            ),
          ),
          Text(
            '$number',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: isTablet ? 22 : 18,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
