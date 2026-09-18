import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/ayah_region_data.dart';
import '../../models/word_region_data.dart';
import '../../services/memorization_test_service.dart';
import '../../utils/quran_word_aligner.dart';

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
  // Opaque tinted paper for words that must stay hidden but flagged.
  static const Color _mistakeMask = Color(0xFFF2C4B8);
  static const Color _skippedMask = Color(0xFFF0D9A6);
  static const Color _unclearMask = Color(0xFFF6EBC4);
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
                    wordBoxes: service.wordBoxesFor(i),
                    wordStatuses: service.wordStatusesOf(i),
                  ),
                // Live feedback + help buttons, floating near the bottom of
                // the page area (over the page's lower margin).
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: height * 0.012,
                  child: Center(child: _SessionPanel(service: service)),
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
    List<WordBox>? wordBoxes,
    List<WordStatus> wordStatuses = const [],
  }) {
    if (state == AyahRevealState.revealed) return const [];

    // Word-level rendering wherever word boxes exist: each box is the
    // word's own ink (letters and marks), so masking it hides exactly that
    // word without clipping the tall letters of the lines above and below
    // the way a full line band did. Hidden ayahs mask every word; the ayah
    // being recited masks the words still to come and washes wrong/skipped
    // ones; a flagged ayah washes only its wrong/skipped words.
    if (wordBoxes != null && wordBoxes.length == wordStatuses.length) {
      return [
        for (var w = 0; w < wordBoxes.length; w++)
          if (wordStatuses[w] != WordStatus.correct)
            Positioned.fromRect(
              rect: Rect.fromLTRB(
                wordBoxes[w].x * pageWidth,
                wordBoxes[w].y * pageHeight,
                (wordBoxes[w].x + wordBoxes[w].width) * pageWidth,
                (wordBoxes[w].y + wordBoxes[w].height) * pageHeight,
              ),
              // Every non-correct word stays fully covered (opaque paper):
              // a mistake or a skip is shown by the tint of its box, never
              // by letting the ink show through.
              child: DecoratedBox(
                decoration: switch (wordStatuses[w]) {
                  WordStatus.mistake => const BoxDecoration(color: _mistakeMask),
                  WordStatus.skipped => const BoxDecoration(color: _skippedMask),
                  WordStatus.unclear => const BoxDecoration(color: _unclearMask),
                  _ => const BoxDecoration(color: _paperColor),
                },
              ),
            ),
        if (state == AyahRevealState.current)
          for (final r in ayah.rects)
            Positioned.fromRect(
              rect: Rect.fromLTRB(
                (r.x * pageWidth) - pageWidth * 0.006,
                r.y * pageHeight,
                (r.x + r.width) * pageWidth + pageWidth * 0.006,
                (r.y + r.height) * pageHeight,
              ),
              // Position hint only (no fill): a faint gold frame around
              // the ayah being recited. Wrapped so it is not counted as a
              // mask box.
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: _currentBorder, width: 1.5),
                  ),
                ),
              ),
            ),
      ];
    }

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

/// The floating panel under the page: status line (hearing you /
/// analyzing / done), the current feedback message, what the recognizer
/// heard last, and the help buttons (hint, reveal, skip, restart, end,
/// share log). Without it the inevitable decode delay reads as deafness
/// and a wrong verdict has no explanation.
class _SessionPanel extends StatelessWidget {
  const _SessionPanel({required this.service});

  final MemorizationTestService service;

  static const Color _gold = Color(0xFF8A6D2F);
  static const Color _good = Color(0xFF2E7D32);
  static const Color _wrong = Color(0xFFB3261E);
  static const Color _unclear = Color(0xFFB26A00);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        service.status,
        service.audioLevel,
        service.engineBusy,
        service.feedback,
        service.lastHeard,
        service.lastDecodeMs,
        service.lastLagMs,
        service.lastSessionFiles,
      ]),
      builder: (context, _) {
        final status = service.status.value;
        if (status != MemorizationTestStatus.listening &&
            status != MemorizationTestStatus.completed &&
            status != MemorizationTestStatus.preparing) {
          return const SizedBox.shrink();
        }
        final fb = service.feedback.value;
        final heard = service.lastHeard.value;
        final listening = status == MemorizationTestStatus.listening;
        final completed = status == MemorizationTestStatus.completed;

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF2FFFDF3),
              borderRadius: BorderRadius.circular(16),
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _statusRow(status),
                  if (listening) _ayahProgress(),
                  if (fb != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      fb.message,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: switch (fb.kind) {
                          FeedbackKind.good => _good,
                          FeedbackKind.wrong => _wrong,
                          FeedbackKind.unclear => _unclear,
                          FeedbackKind.silent => _unclear,
                          FeedbackKind.info => _gold,
                        },
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (heard.isNotEmpty && !completed) ...[
                    const SizedBox(height: 2),
                    Text(
                      'سمعت: $heard',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: _gold.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    runSpacing: 0,
                    textDirection: TextDirection.rtl,
                    children: [
                      if (listening) ...[
                        _button(Icons.lightbulb_outline_rounded, 'تلميح',
                            service.showHint),
                        _button(Icons.visibility_rounded, 'كشف الآية',
                            service.revealCurrentAyah),
                        _button(Icons.skip_next_rounded, 'تخطي الآية',
                            service.skipCurrentAyah),
                      ],
                      if (listening || completed)
                        _button(Icons.replay_rounded, 'إعادة',
                            () => service.restart()),
                      if (service.lastSessionFiles.value.isNotEmpty &&
                          completed)
                        _button(Icons.ios_share_rounded, 'مشاركة السجل',
                            () => _shareSession(context)),
                      _button(Icons.close_rounded, 'إنهاء',
                          () => service.stop()),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The current ayah, word by word: recited words appear in the mushaf
  /// spelling, words still to come stay as dots -- so the reciter sees each
  /// word land the moment it is recognized, without unmasking the page.
  Widget _ayahProgress() {
    final words = service.currentAyahWords;
    if (words.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(fontSize: 17, height: 1.6, fontFamily: 'Tajawal'),
          children: [
            for (var i = 0; i < words.length; i++) ...[
              TextSpan(
                // Only correctly recited words are spelled out; a mistake
                // or a skip shows as a red/amber placeholder (the reciter
                // must not be handed the word).
                text: switch (words[i].$2) {
                  WordStatus.correct => words[i].$1,
                  WordStatus.mistake => '\u2716\u2716\u2716',
                  _ => '\u2022\u2022\u2022',
                },
                style: TextStyle(
                  color: switch (words[i].$2) {
                    WordStatus.correct => _good,
                    WordStatus.mistake => _wrong,
                    WordStatus.skipped => _unclear,
                    WordStatus.unclear => _unclear.withValues(alpha: 0.6),
                    WordStatus.pending => _gold.withValues(alpha: 0.35),
                  },
                  fontWeight: words[i].$2 == WordStatus.pending
                      ? FontWeight.w400
                      : FontWeight.w700,
                ),
              ),
              if (i + 1 < words.length) const TextSpan(text: ' '),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusRow(MemorizationTestStatus status) {
    final Widget icon;
    final String label;
    if (status == MemorizationTestStatus.completed) {
      icon = const Icon(Icons.check_circle_rounded, color: _good, size: 18);
      label = 'اكتمل التسميع';
    } else if (status == MemorizationTestStatus.preparing) {
      icon = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
      );
      label = 'جارٍ التحضير…';
    } else {
      final busy = service.engineBusy.value;
      final level = service.audioLevel.value;
      // Mic glyph swells with the reciter's own voice level -- the most
      // direct "I hear you" signal possible.
      icon = AnimatedScale(
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
      );
      label = busy ? 'جارٍ التحليل…' : 'يستمع إليك';
    }
    final ms = service.lastDecodeMs.value;
    final lag = service.lastLagMs.value;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
        if (ms > 0 && status == MemorizationTestStatus.listening) ...[
          const SizedBox(width: 8),
          Text(
            // decode time · lag behind the reciter's voice
            lag >= 0
                ? '⏱ ${(ms / 1000).toStringAsFixed(1)} ث · تأخر ${(lag / 1000).toStringAsFixed(1)} ث'
                : '⏱ ${(ms / 1000).toStringAsFixed(1)} ث',
            style: TextStyle(
              color: _gold.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Widget _button(IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: _gold,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _shareSession(BuildContext context) async {
    final files = service.lastSessionFiles.value;
    if (files.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [for (final f in files) XFile(f)],
          subject: 'سجل جلسة التسميع',
          text: 'تسجيل جلسة التسميع وسجل القرارات (للتحليل).',
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّرت مشاركة سجل الجلسة')),
      );
    }
  }
}
