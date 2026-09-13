import 'package:flutter/material.dart';

import '../../models/ayah_region_data.dart';
import '../../services/memorization_test_service.dart';

/// The reveal layer of the memorization test: covers every not-yet-recited
/// ayah with paper-colored boxes drawn directly on top of the page image, so
/// hidden ayahs are indistinguishable from blank paper. The ayah-end markers
/// sit between the region rects and stay visible, so the reciter keeps their
/// place on the concealed page.
///
/// Must be placed inside the same box that renders the page `Image` (the
/// image uses `BoxFit.fill`, so this widget's own layout size IS the page
/// image's size and ratio coordinates map straight onto it — the same
/// convention as `AyahHighlightRect`). It also has to sit under the reader's
/// `ColorFiltered`, so the masks are re-tinted exactly like the paper in
/// dark mode and the paper-color themes.
///
/// Rendering rules per [AyahRevealState]:
///  * `hidden` — opaque paper-colored mask.
///  * `current` — masked too, with a faint gold border as a "you are here"
///    hint (position only; reveals nothing of the text).
///  * `revealed` — nothing drawn; the ayah on the page shows through.
///  * `flagged` — translucent amber wash over the now-visible ayah.
class MemorizationTestOverlay extends StatelessWidget {
  const MemorizationTestOverlay({super.key});

  /// Sampled from blank paper inside the page scans (the scan's paper tone,
  /// NOT the 0xFFFAF6EE used behind the image widget — the image fully
  /// covers that, so masks must match the scan itself).
  static const Color _paperColor = Color(0xFFFCFCD8);

  static const Color _flaggedWash = Color(0x59E09000);
  static const Color _currentBorder = Color(0x80B99B5B);

  @override
  Widget build(BuildContext context) {
    final service = MemorizationTestService.instance;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable: Listenable.merge([service.status, service.revision]),
          builder: (context, _) {
            if (!service.isActive) return const SizedBox.shrink();
            final regions = service.regions;
            if (regions == null) return const SizedBox.shrink();

            final states = service.ayahStates;
            if (states.length != regions.ayahs.length) {
              return const SizedBox.shrink();
            }

            final width = constraints.maxWidth;
            final height = constraints.maxHeight;

            return Stack(
              children: [
                for (var i = 0; i < regions.ayahs.length; i++)
                  ..._buildAyahLayer(
                    regions.ayahs[i],
                    states[i],
                    pageWidth: width,
                    pageHeight: height,
                  ),
                // Live "the app hears you" indicator, floating near the
                // bottom of the page area.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: height * 0.035,
                  child: Center(child: _ListeningChip(service: service)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _buildAyahLayer(
    AyahRegion ayah,
    AyahRevealState state, {
    required double pageWidth,
    required double pageHeight,
  }) {
    if (state == AyahRevealState.revealed) return const [];

    return [
      for (final r in ayah.rects)
        Positioned.fromRect(
          // The rects span the full line height already; a little
          // horizontal slack hides glyph tails that lean into the marker
          // gap without ever reaching the marker itself.
          rect: Rect.fromLTRB(
            (r.x * pageWidth) - pageWidth * 0.006,
            r.y * pageHeight,
            (r.x + r.width) * pageWidth + pageWidth * 0.006,
            (r.y + r.height) * pageHeight,
          ),
          child: DecoratedBox(
            decoration: switch (state) {
              AyahRevealState.flagged => const BoxDecoration(
                  color: _flaggedWash,
                ),
              AyahRevealState.current => BoxDecoration(
                  color: _paperColor,
                  border: Border.all(color: _currentBorder, width: 1.5),
                ),
              _ => const BoxDecoration(color: _paperColor),
            },
          ),
        ),
    ];
  }
}

/// Floating status pill: tells the reciter, at a glance, that the app is
/// preparing / hearing them (mic pulses with their voice) / analyzing.
/// Without it, the inevitable decode delay reads as the app being deaf.
class _ListeningChip extends StatelessWidget {
  const _ListeningChip({required this.service});

  final MemorizationTestService service;

  static const Color _gold = Color(0xFF8A6D2F);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        service.status,
        service.audioLevel,
        service.engineBusy,
      ]),
      builder: (context, _) {
        final status = service.status.value;
        if (status == MemorizationTestStatus.completed) {
          return _pill(
            icon: const Icon(Icons.check_circle_rounded,
                color: Color(0xFF2E7D32), size: 18),
            label: 'أحسنت! اكتمل التسميع',
          );
        }
        if (status == MemorizationTestStatus.preparing) {
          return _pill(
            icon: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _gold,
              ),
            ),
            label: 'جارٍ التحضير…',
          );
        }
        if (status != MemorizationTestStatus.listening) {
          return const SizedBox.shrink();
        }

        final busy = service.engineBusy.value;
        final level = service.audioLevel.value;
        return _pill(
          // Mic glyph swells with the reciter's own voice level -- the
          // most direct "I hear you" signal possible.
          icon: AnimatedScale(
            scale: 1.0 + level * 0.5,
            duration: const Duration(milliseconds: 90),
            child: Icon(
              Icons.mic_rounded,
              size: 18,
              color: Color.lerp(
                _gold.withValues(alpha: 0.45),
                _gold,
                (0.3 + level).clamp(0.0, 1.0),
              ),
            ),
          ),
          label: busy ? 'جارٍ التحليل…' : 'يستمع إليك',
        );
      },
    );
  }

  Widget _pill({required Widget icon, required String label}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF2FFFDF3),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.rtl,
          children: [
            icon,
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: _gold,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
