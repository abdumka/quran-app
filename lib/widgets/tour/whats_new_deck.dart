import 'package:flutter/material.dart';

import 'tour_scenes.dart';

/// The What's New tour as a deck of tilted cards (owner picked option A,
/// 2026-11-19). One card per new feature with its animated scene; «التالي»
/// or a swipe sends the top card flying, «تخطّ» closes the deck.
/// «كل التغييرات» closes it and returns [allChangesId] (no «جرّبها الآن»
/// buttons: owner, 2026-11-19).
class WhatsNewDeck extends StatefulWidget {
  const WhatsNewDeck({super.key, required this.cards});

  /// Card ids, see [WhatsNewService.tourCards].
  final List<String> cards;

  static const String allChangesId = 'all';

  static TourScene? sceneFor(String id) => switch (id) {
    'talqeen' => TourScene.talqeen,
    'video' => TourScene.video,
    'athkar' => TourScene.athkar,
    'usul' => TourScene.usul,
    'khilaf' => TourScene.khilaf,
    'auto' => TourScene.auto,
    _ => null,
  };

  /// Shows the deck; returns [allChangesId] when «كل التغييرات» was
  /// pressed, or null when it was simply closed.
  static Future<String?> show(BuildContext context, List<String> cards) {
    final known = [
      for (final c in cards)
        if (sceneFor(c) != null) c,
    ];
    return Navigator.of(context).push<String>(
      PageRouteBuilder<String>(
        opaque: false,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => WhatsNewDeck(cards: known),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  State<WhatsNewDeck> createState() => _WhatsNewDeckState();
}

class _WhatsNewDeckState extends State<WhatsNewDeck> {
  int _index = 0;

  bool get _isLast => _index >= widget.cards.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF6EEDB), Color(0xFFEADCB8)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    _topRow(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                        child: GestureDetector(
                          onHorizontalDragEnd: (d) {
                            if ((d.primaryVelocity ?? 0).abs() > 200) _next();
                          },
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // the farthest card first, so the top card
                              // paints last; a card leaving stays on top
                              for (var k = cards.length - 1; k >= 0; k--)
                                if (k - _index <= 3 && k >= _index) _card(k),
                              for (var k = 0; k < _index; k++)
                                if (_index - k <= 1) _card(k),
                            ],
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(WhatsNewDeck.allChangesId),
                      child: const Text(
                        'كل التغييرات في هذا الإصدار',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          color: TourColors.deepGold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _bottomRow(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 0),
      child: Row(
        children: [
          const Text(
            'الجديد',
            style: TextStyle(
              fontFamily: 'Tajawal',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: TourColors.ink,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: TourColors.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'في هذا التحديث',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: TourColors.deepGold,
                ),
              ),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              backgroundColor: TourColors.charcoal.withValues(alpha: 0.08),
              foregroundColor: TourColors.ink,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'تخطّ',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(int k) {
    final d = k - _index;
    final id = widget.cards[k];
    final scene = WhatsNewDeck.sceneFor(id)!;
    final text = kTourText[scene]!;

    final Offset slide;
    final double scale;
    final double turns;
    final double opacity;
    if (d < 0) {
      slide = const Offset(1.3, 0);
      scale = 1;
      turns = 0.05;
      opacity = 0;
    } else if (d == 0) {
      slide = Offset.zero;
      scale = 1;
      turns = 0;
      opacity = 1;
    } else {
      slide = Offset(0, 0.028 * d);
      scale = 1 - 0.05 * d;
      turns = d.isOdd ? -0.007 : 0.007;
      opacity = d >= 3 ? 0 : 1;
    }
    const duration = Duration(milliseconds: 550);
    const curve = Cubic(0.3, 0.7, 0.2, 1);

    return Positioned.fill(
      key: ValueKey(id),
      child: AnimatedSlide(
        offset: slide,
        duration: duration,
        curve: curve,
        child: AnimatedRotation(
          turns: turns,
          duration: duration,
          curve: curve,
          alignment: const Alignment(0, 2.4),
          child: AnimatedScale(
            scale: scale,
            duration: duration,
            curve: curve,
            alignment: Alignment.bottomCenter,
            child: AnimatedOpacity(
              opacity: opacity,
              duration: duration,
              child: Container(
                decoration: BoxDecoration(
                  color: TourColors.card,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33503C14),
                      blurRadius: 26,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 62,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: TourColors.paper,
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFEFE5CC)),
                          ),
                        ),
                        child: d <= 0
                            ? TourSceneView(scene: scene)
                            : const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      flex: 38,
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC62828),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'جديد',
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              text.title,
                              style: const TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: TourColors.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              text.body,
                              style: const TextStyle(
                                fontFamily: 'Tajawal',
                                fontSize: 13.5,
                                height: 1.6,
                                color: TourColors.muted,
                              ),
                            ),
                          ],
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
    );
  }

  Widget _bottomRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Row(
        children: [
          FilledButton(
            onPressed: _next,
            style: FilledButton.styleFrom(
              backgroundColor: TourColors.charcoal,
              foregroundColor: TourColors.gold,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _isLast ? 'حسنًا' : 'التالي',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          const Spacer(),
          for (var i = 0; i < widget.cards.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: i == _index ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == _index
                    ? TourColors.deepGold
                    : const Color(0xFFD8C9A4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}
