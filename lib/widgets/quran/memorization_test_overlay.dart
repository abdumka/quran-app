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
