import 'package:flutter/material.dart';

import '../../models/word_position_data.dart';
import '../../services/memorization_test_service.dart';
import '../../utils/quran_word_aligner.dart';

/// The word-reveal layer of the memorization test: draws one cover box per
/// not-yet-recited word directly on top of the page image, in the page's
/// paper color, so unrevealed words are indistinguishable from blank paper.
///
/// Must be placed inside the same box that renders the page `Image` (the
/// image uses `BoxFit.fill`, so this widget's own layout size IS the page
/// image's size and ratio coordinates map straight onto it — the same
/// convention as `AyahHighlightRect`).
///
/// Rendering rules per [WordStatus]:
///  * `pending` / `unclear` — opaque paper-colored mask (word hidden). The
///    word the reciter should say next gets a faint gold border as a
///    "you are here" hint (position only; reveals nothing of the word).
///  * `correct` — nothing drawn; the word on the page shows through.
///  * `mistake` — translucent red wash over the now-visible word.
///  * `skipped` — translucent amber wash over the now-visible word.
class MemorizationTestOverlay extends StatelessWidget {
  const MemorizationTestOverlay({super.key});

  /// Sampled from blank paper inside page_1.webp's text panel (the scan's
  /// paper tone, NOT the 0xFFFAF6EE used behind the image widget — the
  /// image fully covers that, so masks must match the scan itself).
  static const Color _paperColor = Color(0xFFFCFCD8);

  static const Color _mistakeWash = Color(0x59CC2222);
  static const Color _skippedWash = Color(0x59E09000);
  static const Color _currentWordBorder = Color(0x80B99B5B);

  @override
  Widget build(BuildContext context) {
    final service = MemorizationTestService.instance;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable: Listenable.merge([service.status, service.revision]),
          builder: (context, _) {
            if (!service.isActive) return const SizedBox.shrink();
            final pageData = service.pageData;
            if (pageData == null) return const SizedBox.shrink();

            final words = pageData.wordsInRecitationOrder;
            final statuses = service.statuses;
            if (statuses.length != words.length) {
              return const SizedBox.shrink();
            }

            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final currentIndex = service.currentWordIndex;

            return Stack(
              children: [
                for (var i = 0; i < words.length; i++)
                  ..._buildWordLayer(
                    words[i],
                    statuses[i],
                    isCurrent: i == currentIndex,
                    pageWidth: width,
                    pageHeight: height,
                  ),
                // Live "the app hears you" indicator, floating near the
                // bottom of the page area (below the text panel).
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

  List<Widget> _buildWordLayer(
    WordPositionRect word,
    WordStatus status, {
    required bool isCurrent,
    required double pageWidth,
    required double pageHeight,
  }) {
    // Expand beyond the (deliberately tight) stored box so glyph parts that
    // exceed the main body — ascenders, the superscript-alef marks, and the
    // small end-of-word closing flourishes (e.g. the ص atop نستعينۖ) — don't
    // peek out around an opaque mask. Vertical padding is larger than
    // horizontal because those overhangs are mostly vertical; both stay
    // within the inter-line / inter-word gaps so a mask never bites deeply
    // into a neighboring revealed word. (Overlap between two *masked* words
    // is invisible — both are paper-colored — so erring generous is safe;
    // the only cost is a mask clipping a few px of an already-revealed
    // neighbor, which the reading order top-to-bottom keeps minimal.)
    final base = word.toPixelRect(pageWidth, pageHeight);
    final rect = Rect.fromLTRB(
      base.left - pageWidth * 0.012,
      base.top - base.height * 0.32,
      base.right + pageWidth * 0.012,
      base.bottom + base.height * 0.24,
    );

    switch (status) {
      case WordStatus.correct:
        return const [];
      case WordStatus.pending:
      case WordStatus.unclear:
        return [
          Positioned.fromRect(
            rect: rect,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _paperColor,
                borderRadius: BorderRadius.circular(3),
                border: isCurrent
                    ? Border.all(color: _currentWordBorder, width: 1.5)
                    : null,
              ),
            ),
          ),
        ];
      case WordStatus.mistake:
      case WordStatus.skipped:
        return [
          Positioned.fromRect(
            rect: rect,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: status == WordStatus.mistake
                    ? _mistakeWash
                    : _skippedWash,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ];
    }
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
