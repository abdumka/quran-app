import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../quran/page_image_crop.dart';

/// The little animated scenes shared by the welcome tour and the What's New
/// deck (owner picked stories + card deck, 2026-11-19). Every scene is drawn
/// from one clock ([TourSceneView]) and loops on its own period, so the
/// tours themselves only decide which scene is on screen.
///
/// The mushaf in the scenes is the real page 356 (and 355 for the page
/// turn), cropped the way the reader shows it; the ayah boxes are the
/// page's own ayah_regions.json rects.
class TourColors {
  TourColors._();
  static const Color charcoal = Color(0xFF1C1C1E);
  static const Color gold = Color(0xFFD2B97E);
  static const Color deepGold = Color(0xFF8A6D2F);
  static const Color paper = Color(0xFFFAF6EE);
  static const Color pagePaper = Color(0xFFFEFEDF);
  static const Color ink = Color(0xFF2A2216);
  static const Color muted = Color(0xFF6E6250);
  static const Color line = Color(0xFFDACDAE);
  static const Color card = Color(0xFFFFFDF6);
  static const Color green = Color(0xFF2E7D32);
  static const Color highlight = Color(0x57DEA834);
}

enum TourScene {
  welcome,
  swipe,
  longPress,
  listen,
  talqeen,
  tasmee,
  video,
  athkar,
  usul,
  remind,
  auto,
  finish,
}

class TourText {
  const TourText(this.title, this.body);
  final String title;
  final String body;
}

const Map<TourScene, TourText> kTourText = {
  TourScene.welcome: TourText(
    'المصحف الجامع',
    'مصحف برواية قالون عن نافع، بأصوات قرّاء كثيرين، مع أدوات للحفظ والتدبّر.',
  ),
  TourScene.swipe: TourText(
    'اقلب الصفحة',
    'اسحب لتنتقل بين الصفحات، واضغط مرة على الصفحة لتظهر الأشرطة.',
  ),
  TourScene.longPress: TourText(
    'اضغط مطوّلًا على الآية',
    'التفسير والتنزيلات وخلافات القراء والتلاوة والمشاركة، كلها من قائمة واحدة.',
  ),
  TourScene.listen: TourText(
    'استمع بصوت قارئك',
    'تتلوّن الآية المتلوّة وتُقلب الصفحة معها، مع تكرار الآية أو الصفحة أو المقطع.',
  ),
  TourScene.talqeen: TourText(
    'تلقين - استمع ثم ردّد',
    'يتلو القارئ الآية ثم يسكت لتردّدها بعده، ثم ينتقل إلى ما بعدها. فعّله من «خيارات التلاوة».',
  ),
  TourScene.tasmee: TourText(
    'التسميع',
    'اقرأ من حفظك والكلمات مغطّاة، فتظهر كل كلمة حين تقرؤها صحيحة.',
  ),
  TourScene.video: TourText(
    'فيديو الآية',
    'اضغط مطوّلًا على الآية ثم زر المشاركة، واختر الخلفية والقارئ، فيُنشأ الفيديو على هاتفك ويُحفظ في معرض الصور.',
  ),
  TourScene.athkar: TourText(
    'الأذكار',
    'أذكار الصباح والمساء وغيرها في القائمة الجانبية، مع عدّاد لكل ذكر، وتذكير يتبع الشروق والغروب في مدينتك.',
  ),
  TourScene.usul: TourText(
    'أحكام وأصول الرواية',
    'شرح ميسّر لأصول رواية قالون في القائمة الجانبية، ولكل حكم أمثلة تفتح موضعها في صفحتها.',
  ),
  TourScene.remind: TourText(
    'صفحة كل يوم',
    'تصلك «صفحة اليوم» وتذكير الأذكار في وقتهما، ويمكنك تغيير الوقت أو الإيقاف من الإعدادات.',
  ),
  TourScene.auto: TourText(
    'في السيارة',
    'مع Android Auto اختر السورة أو الجزء أو القارئ من شاشة السيارة، أو قل لمساعد Google: «شغّل سورة الكهف».',
  ),
  TourScene.finish: TourText(
    'كل شيء جاهز',
    'تعيد هذه الجولة متى شئت من القائمة الجانبية: «جولة في التطبيق».',
  ),
};

extension TourSceneTiming on TourScene {
  /// One loop of the scene. The welcome and finish scenes play once.
  Duration get period => Duration(
    milliseconds: switch (this) {
      TourScene.welcome => 3600,
      TourScene.swipe => 4200,
      TourScene.longPress => 5600,
      TourScene.listen => 6000,
      TourScene.talqeen => 6000,
      TourScene.tasmee => 6400,
      TourScene.video => 11000,
      TourScene.athkar => 5600,
      TourScene.usul => 6800,
      TourScene.remind => 5600,
      TourScene.auto => 6800,
      TourScene.finish => 3000,
    },
  );

  bool get loops => this != TourScene.welcome && this != TourScene.finish;
}

// ───────────────────────── the clock ─────────────────────────

class TourSceneView extends StatefulWidget {
  const TourSceneView({super.key, required this.scene, this.playing = true});

  final TourScene scene;

  /// False freezes the scene (a card waiting behind the top one).
  final bool playing;

  @override
  State<TourSceneView> createState() => _TourSceneViewState();
}

class _TourSceneViewState extends State<TourSceneView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  /// Scenes that play once still run their sparkles: the clock runs long
  /// and the scene clamps its own intro.
  static const Duration _onceLength = Duration(seconds: 60);

  Duration get _length =>
      widget.scene.loops ? widget.scene.period : _onceLength;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: _length);
    _run();
  }

  void _run() {
    _clock.duration = _length;
    _clock.value = 0;
    if (!widget.playing) return;
    if (widget.scene.loops) {
      _clock.repeat();
    } else {
      _clock.forward();
    }
  }

  @override
  void didUpdateWidget(TourSceneView old) {
    super.didUpdateWidget(old);
    if (old.scene != widget.scene || old.playing != widget.playing) _run();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _clock,
          builder: (context, _) {
            final ms = _clock.value * _length.inMilliseconds;
            return _sceneAt(widget.scene, ms);
          },
        ),
      ),
    );
  }
}

Widget _sceneAt(TourScene scene, double ms) => switch (scene) {
  TourScene.welcome => _Welcome(ms),
  TourScene.swipe => _Swipe(ms),
  TourScene.longPress => _LongPress(ms),
  TourScene.listen => _Listen(ms),
  TourScene.talqeen => _Talqeen(ms),
  TourScene.tasmee => _Tasmee(ms),
  TourScene.video => _Video(ms),
  TourScene.athkar => _Athkar(ms),
  TourScene.usul => _Usul(ms),
  TourScene.remind => _Remind(ms),
  TourScene.auto => _Auto(ms),
  TourScene.finish => _Finish(ms),
};

/// 0 → 1 between [start] and [start] + [length] milliseconds.
double _p(
  double ms,
  double start,
  double length, [
  Curve curve = Curves.easeOutCubic,
]) {
  final t = ((ms - start) / length).clamp(0.0, 1.0);
  return curve.transform(t);
}

/// 1 inside [from, to), fading in and out over [fade] ms.
double _window(double ms, double from, double to, [double fade = 300]) {
  if (ms < from || ms >= to + fade) return 0;
  if (ms < from + fade) return (ms - from) / fade;
  if (ms < to) return 1;
  return 1 - (ms - to) / fade;
}

const Cubic _swift = Cubic(0.3, 0.7, 0.2, 1);

// ───────────────────────── the mushaf page ─────────────────────────

/// Page width / height once cropped like the reader (PageCrop × scan size).
const double _aspect356 = 0.6976;
const double _aspect355 = 0.7008;

/// Ayah boxes on page 356 (ayah_regions.json): x, y, width, height.
const Map<int, List<List<double>>> _regions356 = {
  42: [
    [0.07639, 0.01098, 0.9, 0.06707],
  ],
  43: [
    [0.02361, 0.07805, 0.95278, 0.07012],
    [0.02361, 0.14817, 0.95278, 0.0628],
    [0.30417, 0.21098, 0.67222, 0.06341],
  ],
  44: [
    [0.02361, 0.21098, 0.22778, 0.06341],
    [0.19583, 0.27439, 0.78056, 0.06829],
  ],
  45: [
    [0.02361, 0.27439, 0.11944, 0.06829],
    [0.02361, 0.34268, 0.95278, 0.06463],
    [0.64722, 0.40732, 0.32917, 0.06585],
  ],
  46: [
    [0.02361, 0.40732, 0.57083, 0.06585],
    [0.47917, 0.47317, 0.49722, 0.06585],
  ],
  47: [
    [0.02361, 0.47317, 0.40278, 0.06585],
    [0.70417, 0.53902, 0.27222, 0.06341],
  ],
};

typedef _Overlay = List<Widget> Function(Size size);

class _Page extends StatelessWidget {
  const _Page({this.page = 356, this.overlay});

  final int page;
  final _Overlay? overlay;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: page == 355 ? _aspect355 : _aspect356,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              PageImageCrop(
                page: page,
                enabled: true,
                child: Image.asset(
                  'assets/images/page_$page.webp',
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              ...?overlay?.call(size),
            ],
          );
        },
      ),
    );
  }
}

/// The boxes of [ayah] on page 356 in [color].
List<Widget> _ayahBoxes(Size s, int ayah, Color color, {double opacity = 1}) {
  if (opacity <= 0) return const [];
  return [
    for (final r in _regions356[ayah]!)
      Positioned(
        left: r[0] * s.width,
        top: r[1] * s.height,
        width: r[2] * s.width,
        height: r[3] * s.height,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
  ];
}

class _Finger extends StatelessWidget {
  const _Finger({this.scale = 1});
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.62),
          border: Border.all(
            color: TourColors.charcoal.withValues(alpha: 0.55),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x47000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }
}

/// A finger centred on a point given as ratios of [s].
Widget _fingerAt(
  Size s,
  double x,
  double y,
  double opacity, {
  double scale = 1,
}) {
  return Positioned(
    left: x * s.width - 14,
    top: y * s.height - 14,
    child: IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: _Finger(scale: scale),
      ),
    ),
  );
}

TextStyle _t(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color color = TourColors.ink,
  double? height,
}) => TextStyle(
  fontFamily: 'Tajawal',
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

/// The dark recitation pill of the reader, drawn small.
class _ReciteBar extends StatelessWidget {
  const _ReciteBar({
    required this.lead,
    required this.title,
    required this.subtitle,
    this.trailing = const [],
  });

  final Widget lead;
  final Widget title;
  final String subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsetsDirectional.only(start: 6, end: 12),
      decoration: BoxDecoration(
        color: TourColors.charcoal.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        children: [
          lead,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle(
                  style: _t(12, color: const Color(0xFFF4EAD2)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: title,
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(10.5, color: const Color(0xFFB9AB8A)),
                ),
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

Widget _goldCircle(Widget child, {Color color = TourColors.gold}) => Container(
  width: 32,
  height: 32,
  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  alignment: Alignment.center,
  child: child,
);

// ───────────────────────── scenes ─────────────────────────

class _Welcome extends StatelessWidget {
  const _Welcome(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    final ring = _p(ms, 200, 1600, const Cubic(0.5, 0, 0.2, 1));
    final icon = _p(ms, 500, 700, Curves.easeOutBack);
    final title = _p(ms, 1000, 600);
    final sub = _p(ms, 1250, 600);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.25),
          radius: 0.9,
          colors: [Color(0xFFFFF8E6), Color(0xFFF3E8CC), Color(0xFFE9DCBC)],
        ),
      ),
      child: Stack(
        children: [
          for (var i = 0; i < 5; i++) _spark(i),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 118,
                    height: 118,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(118, 118),
                          painter: _RingPainter(ring, TourColors.deepGold, 3),
                        ),
                        Opacity(
                          opacity: icon.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * icon,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.asset(
                                'assets/images/share_app_icon.png',
                                width: 84,
                                height: 84,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _rise(
                    title,
                    Text(
                      'المصحف الجامع',
                      style: _t(26, weight: FontWeight.w800),
                    ),
                  ),
                  _rise(
                    sub,
                    Text(
                      'برواية قالون عن نافع',
                      style: _t(14, color: TourColors.deepGold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _spark(int i) {
    final local = ((ms + i * 450) % 2400) / 2400;
    final opacity = local < 0.3 ? local / 0.3 : 1 - (local - 0.3) / 0.7;
    return Align(
      alignment: Alignment(
        -0.76 + i * 0.37,
        -0.4 + (i % 3) * 0.28 - local * 0.25,
      ),
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: TourColors.gold,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

Widget _rise(double t, Widget child) => Opacity(
  opacity: t.clamp(0.0, 1.0),
  child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
);

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color, this.width, [this.track]);
  final double progress;
  final Color color;
  final double width;
  final Color? track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(width / 2 + 2);
    if (track != null) {
      canvas.drawArc(
        r,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = track!
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }
    if (progress <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

class _Swipe extends StatelessWidget {
  const _Swipe(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    final turn = _p(ms, 700, 750, _swift);
    final bars = _p(ms, 2200, 300);
    return LayoutBuilder(
      builder: (context, box) {
        final s = box.biggest;
        final fingerX = ms < 700
            ? 0.18
            : ms < 1700
            ? 0.18 + 0.64 * _p(ms, 700, 700, Curves.easeInOut)
            : 0.82 - 0.32 * _p(ms, 1700, 400);
        final fingerY = ms < 1700 ? 0.6 : 0.6 - 0.1 * _p(ms, 1700, 400);
        final fingerOn = ms < 1500
            ? 1.0
            : ms < 1700
            ? 0.0
            : _window(ms, 1750, 3000, 200);
        return Stack(
          children: [
            // the next page comes in from the left, as in a printed mushaf
            FractionalTranslation(
              translation: Offset(1.04 * turn, 0),
              child: const Center(child: _Page(page: 355)),
            ),
            FractionalTranslation(
              translation: Offset(-1.04 * (1 - turn), 0),
              child: const Center(child: _Page()),
            ),
            _bar(top: true, t: bars),
            _bar(top: false, t: bars),
            _fingerAt(
              s,
              fingerX,
              fingerY,
              fingerOn,
              scale: ms > 2000 && ms < 2300 ? 0.8 : 1,
            ),
          ],
        );
      },
    );
  }

  Widget _bar({required bool top, required double t}) {
    final bar = Container(
      height: 30,
      color: TourColors.charcoal.withValues(alpha: 0.92),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: top
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(
                  Icons.menu_rounded,
                  color: TourColors.gold,
                  size: 18,
                ),
                Text(
                  'سورة النور · صفحة 356',
                  style: _t(11, color: TourColors.gold),
                ),
                const Icon(
                  Icons.fullscreen_rounded,
                  color: TourColors.gold,
                  size: 18,
                ),
              ],
            )
          : const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Icon(
                  Icons.format_list_bulleted_rounded,
                  color: TourColors.gold,
                  size: 18,
                ),
                Icon(Icons.search_rounded, color: TourColors.gold, size: 18),
                Icon(
                  Icons.headphones_rounded,
                  color: TourColors.gold,
                  size: 18,
                ),
                Icon(Icons.mic_rounded, color: TourColors.gold, size: 18),
                Icon(Icons.bookmark_rounded, color: TourColors.gold, size: 18),
              ],
            ),
    );
    return Positioned(
      left: 0,
      right: 0,
      top: top ? -30 * (1 - t) : null,
      bottom: top ? null : -30 * (1 - t),
      child: Opacity(opacity: t, child: bar),
    );
  }
}

class _LongPress extends StatelessWidget {
  const _LongPress(this.ms);
  final double ms;

  static const _items = [
    (Icons.bookmark_add_rounded, 'إضافة علامة هنا'),
    (Icons.menu_book_rounded, 'تفسير الآية'),
    (Icons.compare_arrows_rounded, 'تنزيلات ومتشابهات'),
    (Icons.groups_rounded, 'خلافات القراء'),
    (Icons.play_arrow_rounded, 'تلاوة'),
  ];

  @override
  Widget build(BuildContext context) {
    final finger = _window(ms, 300, 1700, 250);
    final press = ms >= 700 && ms < 1700 ? (ms - 700) / 1000 : -1.0;
    final glow = _p(ms, 1300, 350);
    final sheet = _p(ms, 1700, 450, Curves.easeOutBack);
    return Stack(
      children: [
        Center(
          child: _Page(
            overlay: (s) => [
              ..._ayahBoxes(s, 42, TourColors.highlight, opacity: glow),
              if (press >= 0)
                Positioned(
                  left: 0.5 * s.width - 10,
                  top: 0.045 * s.height - 10,
                  child: Opacity(
                    opacity: 1 - press,
                    child: Transform.scale(
                      scale: 0.6 + 2.6 * press,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: TourColors.gold, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              _fingerAt(s, 0.5, 0.045, finger),
            ],
          ),
        ),
        if (sheet > 0)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: FractionalTranslation(
              translation: Offset(0, 1.2 * (1 - sheet)),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                decoration: BoxDecoration(
                  color: TourColors.card,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'سورة النور · الآية 42',
                            style: _t(13, weight: FontWeight.w700),
                          ),
                        ),
                        const Icon(
                          Icons.share_rounded,
                          size: 18,
                          color: TourColors.deepGold,
                        ),
                      ],
                    ),
                    const Divider(height: 10, color: Color(0xFFEEE3C8)),
                    for (var i = 0; i < _items.length; i++)
                      Opacity(
                        opacity: _p(ms, 1750 + i * 80, 300),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.5),
                          child: Row(
                            children: [
                              Icon(
                                _items[i].$1,
                                size: 17,
                                color: TourColors.deepGold,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _items[i].$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _t(12.5),
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
      ],
    );
  }
}

const List<String> _reciters = [
  'الحصري',
  'الحذيفي',
  'أحمد صالح رجب',
  'الطرابلسي',
  'المسلاتي',
  'الزروق',
];

class _Listen extends StatelessWidget {
  const _Listen(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    final chips = 1 - _p(ms, 800, 300);
    final ayah = ms < 2600 ? 43 : (ms < 4300 ? 44 : 45);
    return Stack(
      children: [
        Center(
          child: _Page(
            overlay: (s) => [
              ..._ayahBoxes(
                s,
                43,
                TourColors.highlight,
                opacity: _window(ms, 900, 2600),
              ),
              ..._ayahBoxes(
                s,
                44,
                TourColors.highlight,
                opacity: _window(ms, 2600, 4300),
              ),
              ..._ayahBoxes(
                s,
                45,
                TourColors.highlight,
                opacity: _window(ms, 4300, 6000),
              ),
            ],
          ),
        ),
        if (chips > 0)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Opacity(
              opacity: chips,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 5,
                children: [
                  for (var i = 0; i < _reciters.length; i++)
                    _chip(_reciters[i], on: i == 0),
                ],
              ),
            ),
          ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: _ReciteBar(
            lead: _goldCircle(
              const Icon(
                Icons.pause_rounded,
                size: 22,
                color: TourColors.charcoal,
              ),
            ),
            title: const Text('محمود خليل الحصري'),
            subtitle: 'الآية $ayah',
            trailing: const [
              Icon(Icons.repeat_rounded, size: 18, color: TourColors.gold),
              SizedBox(width: 8),
              Icon(Icons.tune_rounded, size: 18, color: TourColors.gold),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _chip(String label, {bool on = false, double size = 11}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
  decoration: BoxDecoration(
    color: on ? TourColors.gold : TourColors.card,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: on ? TourColors.gold : TourColors.line),
  ),
  child: Text(label, style: _t(size)),
);

class _Talqeen extends StatelessWidget {
  const _Talqeen(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    final turn = ms >= 3000;
    final turnT = turn ? (ms - 3000) / 3000 : 0.0;
    final count = turn ? 3 - ((ms - 3000) ~/ 1000) : 3;
    return Stack(
      children: [
        Center(
          child: _Page(
            overlay: (s) => [
              ..._ayahBoxes(
                s,
                43,
                TourColors.highlight,
                opacity: _window(ms, 200, 3000),
              ),
              ..._ayahBoxes(
                s,
                43,
                const Color(0x382E7D32),
                opacity: _window(ms, 3000, 6000),
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Opacity(
            opacity: _window(ms, 3000, 6000),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'دورك: ردّد الآية',
                style: _t(11, weight: FontWeight.w700, color: TourColors.green),
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: _ReciteBar(
            lead: SizedBox(
              width: 38,
              height: 38,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _goldCircle(
                    const Icon(
                      Icons.hearing_rounded,
                      size: 20,
                      color: TourColors.charcoal,
                    ),
                    color: turn ? const Color(0xFF43A047) : TourColors.gold,
                  ),
                  if (turn)
                    CustomPaint(
                      size: const Size(38, 38),
                      painter: _RingPainter(
                        1 - turnT,
                        const Color(0xFFA5D6A7),
                        3,
                      ),
                    ),
                ],
              ),
            ),
            title: turn
                ? Text(
                    'دورك  $count',
                    style: _t(
                      12.5,
                      weight: FontWeight.w800,
                      color: const Color(0xFFA5D6A7),
                    ),
                  )
                : const Text('القارئ يتلو'),
            subtitle: 'تلقين - استمع ثم ردّد',
            trailing: [if (!turn) _wave(ms)],
          ),
        ),
      ],
    );
  }

  Widget _wave(double ms) => Row(
    children: [
      for (var i = 0; i < 5; i++)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: 3,
          height: 6 + 11 * (0.5 + 0.5 * math.sin(ms / 130 + i * 1.3)).abs(),
          decoration: BoxDecoration(
            color: TourColors.gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
    ],
  );
}

class _Tasmee extends StatelessWidget {
  const _Tasmee(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    final pulse = (ms % 1200) / 1200;
    return Stack(
      children: [
        Center(
          child: _Page(
            overlay: (s) {
              final masks = <Widget>[];
              var k = 0;
              for (final ayah in const [44, 45, 46]) {
                for (final r in _regions356[ayah]!) {
                  final n = math.max(1, (r[2] * 5).round());
                  for (var j = 0; j < n; j++) {
                    final x = r[0] + r[2] - (j + 1) * r[2] / n;
                    final shown = 1 - _p(ms, 400 + k * 230.0, 250);
                    k++;
                    if (shown <= 0) continue;
                    masks.add(
                      Positioned(
                        left: x * s.width,
                        top: r[1] * s.height,
                        width: r[2] / n * s.width + 1,
                        height: r[3] * s.height,
                        child: Opacity(
                          opacity: shown,
                          child: const ColoredBox(color: TourColors.pagePaper),
                        ),
                      ),
                    );
                  }
                }
              }
              return masks;
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: Center(
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 12, 5),
              decoration: BoxDecoration(
                color: TourColors.charcoal.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF43A047),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF43A047,
                          ).withValues(alpha: 0.6 * (1 - pulse)),
                          spreadRadius: 9 * pulse,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mic_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'سمّع من حفظك، تظهر الكلمة حين تقرؤها',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(11.5, color: const Color(0xFFF4EAD2)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Video extends StatelessWidget {
  const _Video(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    final out = _p(ms, 5600, 500);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (out < 1)
          Opacity(
            opacity: 1 - out,
            child: ColoredBox(
              color: const Color(0xFFF7F1E3),
              child: Align(
                alignment: Alignment.topCenter,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: 260, child: _maker()),
                ),
              ),
            ),
          ),
        if (out > 0)
          Opacity(
            opacity: out,
            child: ColoredBox(
              color: const Color(0xFF0D0F14),
              child: Center(child: _result()),
            ),
          ),
      ],
    );
  }

  Widget _maker() {
    final picked = ms >= 900;
    final reciter = ms >= 2000;
    final pressing = ms >= 3200 && ms < 3400;
    final making = ms >= 3200;
    final progress = _p(ms, 3400, 1900, Curves.linear);
    const thumbs = ['clouds', 'minarets', 'waves'];
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.movie_rounded,
                size: 18,
                color: TourColors.deepGold,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'فيديو الآية · النور 42',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(14, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('الخلفية', style: _t(11, color: TourColors.muted)),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < thumbs.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Transform.scale(
                    scale: picked && i == 0 ? 1.04 : 1,
                    child: AspectRatio(
                      aspectRatio: 4 / 5,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            width: 2,
                            color: picked && i == 0
                                ? TourColors.deepGold
                                : Colors.transparent,
                          ),
                          image: DecorationImage(
                            image: AssetImage(
                              'assets/images/tour_bg_${thumbs[i]}.jpg',
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text('القارئ', style: _t(11, color: TourColors.muted)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _chip('الحصري', on: reciter),
              _chip('الحذيفي'),
              _chip('الزروق'),
              _chip('المسلاتي'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final shape in const ['9:16', '4:5', '1:1', '16:9'])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: shape == '4:5'
                          ? TourColors.charcoal
                          : TourColors.card,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: shape == '4:5'
                            ? TourColors.charcoal
                            : TourColors.line,
                      ),
                    ),
                    child: Text(
                      shape,
                      textDirection: TextDirection.ltr,
                      style: _t(
                        10.5,
                        weight: FontWeight.w600,
                        color: shape == '4:5'
                            ? TourColors.gold
                            : TourColors.ink,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Transform.scale(
            scale: pressing ? 0.95 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: TourColors.charcoal,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                'إنشاء الفيديو',
                style: _t(13, weight: FontWeight.w700, color: TourColors.gold),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: making ? 1 : 0,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE7DCC2),
                    color: TourColors.deepGold,
                  ),
                ),
                const SizedBox(height: 4),
                Text('يُنشأ على هاتفك', style: _t(11, color: TourColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _result() {
    final saved = _p(ms, 6500, 400);
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return Stack(
                fit: StackFit.expand,
                children: [
                  // the real clouds background + the app's surah title + An-Nur
                  // 42 cut from pages 355-356, as the video maker builds it
                  Image.asset(
                    'assets/images/tour_ayah_video.webp',
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: box.maxHeight * 0.315,
                    child: Text(
                      'بصوت محمود خليل الحصري',
                      textAlign: TextAlign.center,
                      style: _t(w * 0.042, color: Colors.white).copyWith(
                        shadows: const [
                          Shadow(color: Color(0x99000000), blurRadius: 3),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Opacity(
                      opacity: 0.85,
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: Image.asset(
                              'assets/images/share_app_icon.png',
                              width: w * 0.06,
                              height: w * 0.06,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'المصحف الجامع',
                            style: _t(w * 0.036, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Opacity(
                        opacity: saved,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: TourColors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'حُفظ في معرض الصور',
                                style: _t(10.5, weight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Athkar extends StatelessWidget {
  const _Athkar(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    final taps = ms < 660 ? 0 : math.min(11, ((ms - 300) ~/ 360));
    final n = 100 - taps;
    final local = ms < 660 ? 1.0 : ((ms - 300) % 360) / 350;
    final ripple = taps > 0 && taps <= 11 && ms < 300 + 12 * 360
        ? (1 - local).clamp(0.0, 1.0)
        : 0.0;
    final reminder = _p(ms, 3200, 400);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDF6E3), Color(0xFFF4E7C6)],
        ),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wb_twilight_rounded,
                      size: 18,
                      color: TourColors.deepGold,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'أذكار الصباح',
                      style: _t(
                        13,
                        weight: FontWeight.w700,
                        color: TourColors.deepGold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'سُبْحَانَ اللهِ وَبِحَمْدِهِ',
                  style: _t(19, weight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 118,
                  height: 118,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(118, 118),
                        painter: _RingPainter(
                          n / 100,
                          TourColors.deepGold,
                          7,
                          const Color(0xFFEADFC3),
                        ),
                      ),
                      if (ripple > 0)
                        Opacity(
                          opacity: ripple,
                          child: Transform.scale(
                            scale: 0.7 + 0.45 * (1 - ripple),
                            child: Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                color: TourColors.gold.withValues(alpha: 0.35),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        '$n',
                        style: _t(30, weight: FontWeight.w800).copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _rise(
                  reminder,
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: TourColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: TourColors.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.notifications_active_rounded,
                          size: 16,
                          color: Color(0xFFE0A100),
                        ),
                        const SizedBox(width: 6),
                        Text('تذكير قبل الشروق بـ50 دقيقة', style: _t(11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Usul extends StatelessWidget {
  const _Usul(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    final tapped = ms >= 700;
    final detail = _p(ms, 1500, 450, _swift);
    final mini = _p(ms, 3100, 450, _swift);
    final blink = ms >= 3600 ? 0.5 + 0.5 * math.cos((ms - 3600) / 160) : 1.0;
    return ColoredBox(
      color: const Color(0xFFFAF3E2),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(width: 250, child: _list(tapped)),
            ),
          ),
          FractionalTranslation(
            translation: Offset(-1.02 * (1 - detail), 0),
            child: _detail(),
          ),
          FractionalTranslation(
            translation: Offset(0, 1.02 * (1 - mini)),
            child: ColoredBox(
              color: TourColors.paper,
              child: Center(
                child: _Page(
                  overlay: (s) => _ayahBoxes(
                    s,
                    47,
                    Color.lerp(
                      TourColors.highlight,
                      const Color(0xCCD2B97E),
                      1 - blink,
                    )!,
                    opacity: _p(ms, 3500, 300),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(bool tapped) {
    Widget group(String title, [List<String> rows = const []]) => Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
      decoration: BoxDecoration(
        color: TourColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: TourColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: _t(12, weight: FontWeight.w700)),
          for (final r in rows)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: r == 'ميم الجمع' && tapped
                    ? TourColors.gold
                    : const Color(0xFFF6EEDB),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(r, style: _t(11.5)),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.menu_book_rounded,
                size: 18,
                color: TourColors.deepGold,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'أحكام وأصول الرواية',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(14, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          group('أحكام التلاوة'),
          group('الأصول', const [
            'البسملة',
            'المد والقصر',
            'ميم الجمع',
            'هاء الكناية',
            'إبدال الهمز',
          ]),
          group('كلمات متكررة'),
        ],
      ),
    );
  }

  Widget _detail() {
    Widget bar(double f) => Padding(
      padding: const EdgeInsets.only(top: 7),
      child: FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: f,
        child: Container(
          height: 7,
          decoration: BoxDecoration(
            color: const Color(0xFFECE2C8),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: TourColors.card,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ميم الجمع', style: _t(15, weight: FontWeight.w700)),
            bar(1),
            bar(0.86),
            bar(0.92),
            bar(0.6),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: TourColors.charcoal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 15,
                    color: TourColors.gold,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'مثال: النور 47',
                    style: _t(
                      11,
                      weight: FontWeight.w600,
                      color: TourColors.gold,
                    ),
                  ),
                ],
              ),
            ),
            bar(0.78),
            bar(0.7),
          ],
        ),
      ),
    );
  }
}

class _Remind extends StatelessWidget {
  const _Remind(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    Widget note(double t, String title, String body) => _rise(
      t,
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xF0FFFDF6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/images/share_app_icon.png',
                width: 24,
                height: 24,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _t(11.5, weight: FontWeight.w700)),
                  Text(body, style: _t(10.5, color: TourColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF2C3A4F), Color(0xFF6D5A3F), Color(0xFFC99A52)],
          stops: [0, 0.7, 1],
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 260,
            child: Column(
              children: [
                const SizedBox(height: 20),
                Text(
                  '05:12',
                  textDirection: TextDirection.ltr,
                  style: _t(46, weight: FontWeight.w300, color: Colors.white),
                ),
                Text(
                  'الخميس',
                  style: _t(12, color: Colors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 18),
                note(
                  _p(ms, 700, 450, Curves.easeOutBack),
                  'أذكار الصباح',
                  'الشروق بعد 50 دقيقة',
                ),
                note(
                  _p(ms, 1800, 450, Curves.easeOutBack),
                  'صفحة اليوم',
                  'صفحة 356 · سورة النور',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Auto extends StatelessWidget {
  const _Auto(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    final voice = _window(ms, 700, 2300, 400);
    final kahf = ms >= 2300;
    final progress = 0.08 + 0.38 * _p(ms, 2300, 4000, Curves.linear);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE9E3D4), Color(0xFFD9D0BB)],
        ),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 264,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF101114),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(color: Color(0xFF2A2B30), spreadRadius: 5),
                        BoxShadow(
                          color: Color(0x59000000),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 58,
                              color: const Color(0xFF17181C),
                              padding: const EdgeInsets.all(4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (final (i, tab) in const [
                                    'الرئيسية',
                                    'السور',
                                    'الأجزاء',
                                    'القرّاء',
                                  ].indexed)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 2),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: i == 0
                                            ? const Color(0xFF2B2D33)
                                            : null,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        tab,
                                        textAlign: TextAlign.center,
                                        style: _t(
                                          8.5,
                                          color: i == 0
                                              ? TourColors.gold
                                              : const Color(0xFFAAAAAA),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            gradient: const LinearGradient(
                                              colors: [
                                                TourColors.gold,
                                                TourColors.deepGold,
                                              ],
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            'ح',
                                            style: _t(
                                              16,
                                              weight: FontWeight.w800,
                                              color: TourColors.charcoal,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                kahf
                                                    ? 'سورة الكهف'
                                                    : 'سورة النور',
                                                style: _t(
                                                  11,
                                                  weight: FontWeight.w700,
                                                  color: const Color(
                                                    0xFFEEEEEE,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                kahf
                                                    ? 'الآية 1 · الحصري'
                                                    : 'الآية 42 · الحصري',
                                                style: _t(
                                                  9,
                                                  color: const Color(
                                                    0xFFAAAAAA,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 3,
                                        backgroundColor: const Color(
                                          0xFF333333,
                                        ),
                                        color: TourColors.gold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Directionality(
                                      textDirection: TextDirection.ltr,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceAround,
                                        children: [
                                          const Icon(
                                            Icons.skip_previous_rounded,
                                            size: 20,
                                            color: Color(0xFFDDDDDD),
                                          ),
                                          const Icon(
                                            Icons.replay_10_rounded,
                                            size: 20,
                                            color: Color(0xFFDDDDDD),
                                          ),
                                          Container(
                                            width: 30,
                                            height: 30,
                                            decoration: const BoxDecoration(
                                              color: TourColors.gold,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.pause_rounded,
                                              size: 20,
                                              color: Color(0xFF111111),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.forward_10_rounded,
                                            size: 20,
                                            color: Color(0xFFDDDDDD),
                                          ),
                                          const Icon(
                                            Icons.skip_next_rounded,
                                            size: 20,
                                            color: Color(0xFFDDDDDD),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: 8,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Opacity(
                              opacity: voice,
                              child: Transform.translate(
                                offset: Offset(0, -20 * (1 - voice)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.graphic_eq_rounded,
                                        size: 14,
                                        color: TourColors.deepGold,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        '«شغّل سورة الكهف»',
                                        style: _t(
                                          10.5,
                                          weight: FontWeight.w600,
                                          color: const Color(0xFF222222),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Android Auto',
                  style: _t(
                    11,
                    weight: FontWeight.w600,
                    color: TourColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Finish extends StatelessWidget {
  const _Finish(this.ms);
  final double ms;

  @override
  Widget build(BuildContext context) {
    final check = _p(ms, 200, 700);
    final breathe = 1 + 0.05 * math.sin(ms / 290);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          colors: [Color(0xFFFFF8E6), Color(0xFFEFE2C2)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: ms > 900 ? breathe : 1,
              child: CustomPaint(
                size: const Size(76, 76),
                painter: _CheckPainter(check),
              ),
            ),
            const SizedBox(height: 14),
            Text('كل شيء جاهز', style: _t(19, weight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      size.width / 2 - 3,
      Paint()
        ..color = TourColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final path = Path()
      ..moveTo(size.width * 0.3, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.65)
      ..lineTo(size.width * 0.71, size.height * 0.36);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = TourColors.deepGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}
