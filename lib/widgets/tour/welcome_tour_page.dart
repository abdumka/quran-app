import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tour_scenes.dart';

/// «جولة في التطبيق»: the welcome tour as full-screen stories (owner picked
/// option A, 2026-11-19). Shown once before the mushaf on a fresh install,
/// and replayable, in full, from the side menu.
///
/// Each story plays its scene and moves on by itself when its gold bar is
/// full; a tap or «التالي» moves on sooner, holding a finger on the scene
/// pauses it, and «تخطّ» (or Back) ends the whole tour at once.
class WelcomeTourPage extends StatefulWidget {
  const WelcomeTourPage({super.key, required this.onFinish});

  /// Called once, when the tour is watched to the end or skipped.
  final VoidCallback onFinish;

  static const List<TourScene> stories = [
    TourScene.welcome,
    TourScene.swipe,
    TourScene.longPress,
    TourScene.listen,
    TourScene.talqeen,
    TourScene.tasmee,
    TourScene.video,
    TourScene.athkar,
    TourScene.usul,
    TourScene.remind,
    TourScene.auto,
    TourScene.finish,
  ];

  /// The replay from the side menu: pops itself when done.
  static Future<void> replay(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (routeContext, _, _) => WelcomeTourPage(
          onFinish: () => Navigator.of(routeContext).maybePop(),
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<WelcomeTourPage> createState() => _WelcomeTourPageState();
}

class _WelcomeTourPageState extends State<WelcomeTourPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _bar;
  int _index = 0;
  bool _finished = false;

  List<TourScene> get _stories => WelcomeTourPage.stories;
  bool get _isLast => _index == _stories.length - 1;

  /// How long a story stays before moving on by itself.
  Duration _dwell(TourScene scene) => switch (scene) {
    TourScene.welcome => const Duration(milliseconds: 3600),
    TourScene.video => const Duration(milliseconds: 9500),
    _ => scene.period,
  };

  @override
  void initState() {
    super.initState();
    _bar = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_isLast) _next();
      });
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  /// Leaving the app mid-story pauses the bar, so the story is not skipped
  /// by the time spent away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_isLast && !_finished) _bar.forward();
    } else {
      _bar.stop();
    }
  }

  void _start() {
    _bar.duration = _dwell(_stories[_index]);
    _bar.value = 0;
    if (!_isLast) _bar.forward();
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    setState(() => _index++);
    _start();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _bar.stop();
    widget.onFinish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _stories[_index];
    final text = kTourText[scene]!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _finish();
        },
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: TourColors.charcoal,
            body: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -1.1),
                  radius: 1.3,
                  colors: [Color(0xFF3A3222), TourColors.charcoal],
                  stops: [0, 0.6],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final wide = box.maxWidth > box.maxHeight * 1.1;
                        final stage = _stage(scene);
                        final words = _words(text);
                        return Column(
                          children: [
                            _topRow(),
                            Expanded(
                              child: wide
                                  ? Row(
                                      children: [
                                        Expanded(child: stage),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [words, _navRow()],
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        Expanded(child: stage),
                                        words,
                                        _navRow(),
                                      ],
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _bar,
              builder: (context, _) => Row(
                children: [
                  for (var i = 0; i < _stories.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(child: _segment(i)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: _finish,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              foregroundColor: const Color(0xFFEEEEEE),
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

  Widget _segment(int i) {
    final fill = i < _index
        ? 1.0
        : i == _index
        ? (_isLast ? 1.0 : _bar.value)
        : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.22)),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: fill,
              child: const ColoredBox(color: TourColors.gold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage(TourScene scene) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _next,
        onLongPressStart: (_) => _bar.stop(),
        onLongPressEnd: (_) {
          if (!_isLast) _bar.forward();
        },
        child: Container(
          decoration: BoxDecoration(
            color: TourColors.paper,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 30,
                offset: Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: TourSceneView(key: ValueKey(scene), scene: scene),
          ),
        ),
      ),
    );
  }

  Widget _words(TourText text) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Padding(
        key: ValueKey(text.title),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: TourColors.gold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text.body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 14.5,
                  height: 1.6,
                  color: Color(0xFFD9CFB8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Row(
        children: [
          FilledButton(
            onPressed: _next,
            style: FilledButton.styleFrom(
              backgroundColor: TourColors.gold,
              foregroundColor: TourColors.charcoal,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 26),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _isLast ? 'ابدأ القراءة' : 'التالي',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          const Spacer(),
          Text(
            '${_index + 1} / ${_stories.length}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: Color(0xFF9D927B), fontSize: 13),
          ),
        ],
      ),
    );
  }
}
