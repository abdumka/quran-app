import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_pages.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _goNext();
  }

  Future<void> _goNext() async {
    // Read prefs first (instant), then precache image IN PARALLEL with the delay
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final lastPage = prefs.getInt('lastPage') ?? 0;
    final portraitScrollMode = prefs.getBool('portraitScrollMode') ?? false;

    // Pre-decode the page image DURING the wait (no extra time, no spinner freeze)
    final pageNum = lastPage + 1; // pages are 1-indexed in assets
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 5000)),
      if (pageNum >= 1 && pageNum <= 602)
        precacheImage(ResizeImage(AssetImage('assets/images/page_$pageNum.webp'), width: 720), context),
    ]);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, _, _) => QuranPages(
          initialPage: lastPage,
          initialPortraitScrollMode: portraitScrollMode,
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title =
        'مصحف الدعوة الاسلامية الجامع';
    const subtitle =
        '\u0646\u0633\u0623\u0644 \u0627\u0644\u0644\u0647 \u0623\u0646 \u064a\u0646\u0641\u0639 \u0628\u0647.';
    const prayer =
        '\u0627\u0644\u0631\u062c\u0627\u0621 \u0627\u0644\u062f\u0639\u0627\u0621 \u0644\u064a \u0648\u0644\u0648\u0627\u0644\u062f\u064a\u0651\u064e \u0628\u0627\u0644\u0645\u063a\u0641\u0631\u0629 \u0648\u0627\u0644\u0631\u062d\u0645\u0629.\n\u0628\u0627\u0631\u0643 \u0627\u0644\u0644\u0647 \u0641\u064a\u0643\u0645.';
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/mushaf_cover_ai_design.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -90,
              left: -60,
              child: _GlowCircle(
                size: 220,
                color: const Color(0x66FFFFFF),
              ),
            ),
            Positioned(
              bottom: -80,
              right: -30,
              child: _GlowCircle(
                size: 200,
                color: const Color(0x44FFF7E3),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        isLandscape ? 22 : 26,
                        isLandscape ? 22 : 30,
                        isLandscape ? 22 : 26,
                        isLandscape ? 18 : 24,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDFBF7).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: const Color(0xFF9A7442).withValues(alpha: 0.45),
                          width: 1.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 30,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: EdgeInsets.fromLTRB(
                          isLandscape ? 16 : 18,
                          isLandscape ? 16 : 20,
                          isLandscape ? 16 : 18,
                          isLandscape ? 12 : 16,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFFF5E2B8).withValues(alpha: 0.85),
                            width: 1.1,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.98),
                              const Color(0xFFF0DFC1).withValues(alpha: 0.65),
                            ],
                          ),
                        ),
                        child: isLandscape
                            ? Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const _Ornament(),
                                        const SizedBox(height: 10),
                                        const _Medallion(),
                                        const SizedBox(height: 14),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            title,
                                            maxLines: 1,
                                            textAlign: TextAlign.center,
                                            textDirection: TextDirection.rtl,
                                            style: const TextStyle(
                                              fontSize: 26,
                                              height: 1.2,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF3A2714),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Container(
                                          width: 110,
                                          height: 2,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(99),
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0x00A67C45),
                                                Color(0xFFA67C45),
                                                Color(0x00A67C45),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        const _BottomOrnament(),
                                        const SizedBox(height: 16),
                                        const SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3.2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Color(0xFF8D6E3F),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF9F2E2)
                                                .withValues(alpha: 0.62),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: const Color(0xFFB38A54)
                                                  .withValues(alpha: 0.28),
                                            ),
                                          ),
                                          child: Text(
                                            subtitle,
                                            textAlign: TextAlign.center,
                                            textDirection: TextDirection.rtl,
                                            style: const TextStyle(
                                              fontSize: 17,
                                              height: 1.6,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF5A4630),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          prayer,
                                          textAlign: TextAlign.center,
                                          textDirection: TextDirection.rtl,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            height: 1.75,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF6C4C24),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const _Ornament(),
                                  const SizedBox(height: 12),
                                  const _Medallion(),
                                  const SizedBox(height: 16),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                        fontSize: 29,
                                        height: 1.2,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF3A2714),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Container(
                                    width: 120,
                                    height: 2,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(99),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0x00A67C45),
                                          Color(0xFFA67C45),
                                          Color(0x00A67C45),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF9F2E2)
                                          .withValues(alpha: 0.62),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFB38A54)
                                            .withValues(alpha: 0.28),
                                      ),
                                    ),
                                    child: Text(
                                      subtitle,
                                      textAlign: TextAlign.center,
                                      textDirection: TextDirection.rtl,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        height: 1.7,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF5A4630),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    prayer,
                                    textAlign: TextAlign.center,
                                    textDirection: TextDirection.rtl,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      height: 1.85,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF6C4C24),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const _BottomOrnament(),
                                  const SizedBox(height: 20),
                                  const SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3.2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        Color(0xFF8D6E3F),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowCircle({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        _OrnamentLine(),
        SizedBox(width: 12),
        Icon(
          Icons.auto_awesome,
          color: Color(0xFF9A7442),
          size: 26,
        ),
        SizedBox(width: 12),
        _OrnamentLine(),
      ],
    );
  }
}

class _Medallion extends StatelessWidget {
  const _Medallion();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFD6B178),
            Color(0xFF9A7442),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8D6E3F).withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFF5E2B8),
          width: 2.2,
        ),
      ),
      child: Center(
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.32),
              width: 1.2,
            ),
          ),
          child: const Icon(
            Icons.menu_book_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _BottomOrnament extends StatelessWidget {
  const _BottomOrnament();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(
          Icons.auto_awesome,
          color: Color(0xFFB38A54),
          size: 16,
        ),
        SizedBox(width: 10),
        _OrnamentLine(),
        SizedBox(width: 10),
        Icon(
          Icons.auto_awesome,
          color: Color(0xFFB38A54),
          size: 16,
        ),
      ],
    );
  }
}

class _OrnamentLine extends StatelessWidget {
  const _OrnamentLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 2,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: const LinearGradient(
          colors: [
            Color(0x00A67C45),
            Color(0xFFA67C45),
            Color(0x00A67C45),
          ],
        ),
      ),
    );
  }
}
