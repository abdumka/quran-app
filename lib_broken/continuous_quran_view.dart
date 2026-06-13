import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'models/reader_bookmark.dart';
import 'services/debug_log_service.dart';
import 'utils/responsive_helper.dart';

class ContinuousQuranView extends StatefulWidget {
  const ContinuousQuranView({
    super.key,
    required this.pages,
    required this.pageImageProviderBuilder,
    required this.initialPage,
    required this.viewportWidth,
    required this.pageAspectRatio,
    required this.autoScrollEnabled,
    required this.autoScrollPixelsPerSecond,
    required this.bookmarks,
    required this.onPageChanged,
    required this.onSaveBookmark,
    required this.onMoveBookmark,
    required this.onMoveBookmarkEnd,
    required this.onAutoScrollInterrupted,
    this.onTap,
  });

  final List<String> pages;
  final ImageProvider Function(int pageIndex) pageImageProviderBuilder;
  final int initialPage;
  final double viewportWidth;
  final double pageAspectRatio;
  final bool autoScrollEnabled;
  final double autoScrollPixelsPerSecond;
  final List<ReaderBookmark> bookmarks;
  final ValueChanged<int> onPageChanged;
  final Function(int page, double x, double y, double width, double height)
      onSaveBookmark;
  final void Function(
    int slot,
    int page,
    double x,
    double y,
    double width,
    double height,
  ) onMoveBookmark;
  final Future<void> Function() onMoveBookmarkEnd;
  final VoidCallback onAutoScrollInterrupted;
  final VoidCallback? onTap;

  @override
  State<ContinuousQuranView> createState() => ContinuousQuranViewState();
}

class ContinuousQuranViewState extends State<ContinuousQuranView> {
  static const bool _debugTransitions = false;
  static const int _precacheRadius = 1;


  late final ScrollController _controller;
  late int _lastReportedPage;
  bool _didLogFirstClientAttach = false;
  final Set<int> _loggedRenderedPages = <int>{};
  Timer? _autoScrollTimer;
  Timer? _pendingLongPressTimer;
  Offset? _pendingLongPressStart;
  int? _pendingLongPressPage;
  double? _pendingLongPressWidth;
  double? _pendingLongPressHeight;
  final Map<int, Offset> _draggingBookmarkOffsets = <int, Offset>{};
  Timer? _precacheDebounceTimer;
  int _lastPrecacheCenterPage = -1;

  void _debugEvent(String name, [Map<String, Object?> details = const {}]) {
    if (!_debugTransitions) return;
    DebugLogService.instance.event('ContinuousQuranView', name, {
      'initialPage': widget.initialPage,
      'lastReportedPage': _lastReportedPage,
      ...details,
    });
  }

  double get _displayPageWidth => widget.viewportWidth;

  double get _pageHeight {
    final height = _displayPageWidth / widget.pageAspectRatio;
    return math.max(height, 100.0);
  }

  Size _bookmarkBadgeSize(BuildContext context) {
    final base = ResponsiveHelper.overlayIconSize(context);
    return Size(base + 24, base + 8);
  }

  void _startBookmarkDrag(
    ReaderBookmark bookmark,
    double displayWidth,
    double displayHeight,
  ) {
    _draggingBookmarkOffsets[bookmark.slot] = Offset(
      bookmark.leftFor(displayWidth),
      bookmark.topFor(displayHeight),
    );
  }

  void _updateBookmarkDrag(
    BuildContext context,
    ReaderBookmark bookmark,
    DragUpdateDetails details,
    double displayWidth,
    double displayHeight,
  ) {
    final badgeSize = _bookmarkBadgeSize(context);
    final currentOffset =
        _draggingBookmarkOffsets[bookmark.slot] ??
        Offset(
          bookmark.leftFor(displayWidth),
          bookmark.topFor(displayHeight),
        );
    final maxLeft = math.max(0.0, displayWidth - badgeSize.width);
    final maxTop = math.max(0.0, displayHeight - badgeSize.height);
    final nextOffset = Offset(
      (currentOffset.dx + details.delta.dx).clamp(0.0, maxLeft),
      (currentOffset.dy + details.delta.dy).clamp(0.0, maxTop),
    );
    _draggingBookmarkOffsets[bookmark.slot] = nextOffset;
    widget.onMoveBookmark(
      bookmark.slot,
      bookmark.page,
      nextOffset.dx,
      nextOffset.dy,
      displayWidth,
      displayHeight,
    );
  }

  void _endBookmarkDrag(int slot) {
    _draggingBookmarkOffsets.remove(slot);
    unawaited(widget.onMoveBookmarkEnd());
  }

  double _offsetForPage(int pageIndex) {
    final safePage = pageIndex.clamp(0, widget.pages.length - 1);
    return safePage * _pageHeight;
  }

  int _pageFromOffset(double offset) {
    if (_pageHeight <= 0) return 0;
    return (offset / _pageHeight)
        .floor()
        .clamp(0, math.max(widget.pages.length - 1, 0));
  }

  @override
  void initState() {
    super.initState();
    _lastReportedPage = widget.initialPage.clamp(0, widget.pages.length - 1);
    _controller = ScrollController(
      initialScrollOffset: _offsetForPage(_lastReportedPage),
      keepScrollOffset: false,
    );
    _controller.addListener(_handleScroll);
    _debugEvent('initState', {
      'viewportWidth': widget.viewportWidth.toStringAsFixed(1),
      'initialOffset': _controller.initialScrollOffset.toStringAsFixed(1),
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _debugEvent('postFrameAfterInit', {
        'hasClients': _controller.hasClients,
        'offset': _controller.hasClients
            ? _controller.offset.toStringAsFixed(1)
            : 'no-clients',
        'positionCount': _controller.positions.length,
      });
      _syncAutoScroll();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _debugEvent('didChangeDependencies', {
      'viewportWidth': widget.viewportWidth.toStringAsFixed(1),
      'devicePixelRatio': MediaQuery.devicePixelRatioOf(context)
          .toStringAsFixed(2),
    });
  }

  @override
  void didUpdateWidget(covariant ContinuousQuranView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _debugEvent('didUpdateWidget', {
      'oldInitialPage': oldWidget.initialPage,
      'newInitialPage': widget.initialPage,
      'oldViewportWidth': oldWidget.viewportWidth.toStringAsFixed(1),
      'newViewportWidth': widget.viewportWidth.toStringAsFixed(1),
      'hasClients': _controller.hasClients,
      'offset': _controller.hasClients
          ? _controller.offset.toStringAsFixed(1)
          : 'no-clients',
    });
    if (widget.initialPage != oldWidget.initialPage &&
        widget.initialPage != _lastReportedPage &&
        _controller.hasClients) {
      scrollToPage(widget.initialPage);
    }

    if ((widget.viewportWidth != oldWidget.viewportWidth ||
            widget.pageAspectRatio != oldWidget.pageAspectRatio) &&
        _controller.hasClients) {
      final double oldPageHeight =
          oldWidget.viewportWidth / oldWidget.pageAspectRatio;
      final double newPageHeight = _pageHeight;

      if (oldPageHeight > 0 && newPageHeight > 0) {
        final double exactPage = _controller.offset / oldPageHeight;
        final double newOffset = exactPage * newPageHeight;
        _controller.jumpTo(newOffset.clamp(
          0.0,
          math.max(0.0, _controller.position.maxScrollExtent),
        ));
      }
    }

    if (widget.autoScrollEnabled != oldWidget.autoScrollEnabled ||
        widget.autoScrollPixelsPerSecond != oldWidget.autoScrollPixelsPerSecond) {
      _syncAutoScroll();
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pendingLongPressTimer?.cancel();
    _precacheDebounceTimer?.cancel();
    _controller.removeListener(_handleScroll);
    _controller.dispose();
    super.dispose();
  }

  void _cancelPendingLongPress() {
    _pendingLongPressTimer?.cancel();
    _pendingLongPressTimer = null;
    _pendingLongPressStart = null;
    _pendingLongPressPage = null;
    _pendingLongPressWidth = null;
    _pendingLongPressHeight = null;
  }

  void _schedulePendingLongPress({
    required int pageIndex,
    required Offset localPosition,
    required double width,
    required double height,
  }) {
    _cancelPendingLongPress();
    _pendingLongPressStart = localPosition;
    _pendingLongPressPage = pageIndex;
    _pendingLongPressWidth = width;
    _pendingLongPressHeight = height;
    _pendingLongPressTimer = Timer(const Duration(milliseconds: 450), () {
      final pendingPage = _pendingLongPressPage;
      final pendingPosition = _pendingLongPressStart;
      final pendingWidth = _pendingLongPressWidth;
      final pendingHeight = _pendingLongPressHeight;
      if (!mounted ||
          pendingPage == null ||
          pendingPosition == null ||
          pendingWidth == null ||
          pendingHeight == null) {
        _cancelPendingLongPress();
        return;
      }
      widget.onSaveBookmark(
        pendingPage,
        pendingPosition.dx,
        pendingPosition.dy,
        pendingWidth,
        pendingHeight,
      );
    });
  }

  void _handlePendingLongPressMove(PointerMoveEvent event) {
    final start = _pendingLongPressStart;
    if (start == null) return;
    if ((event.localPosition - start).distance > 12) {
      _cancelPendingLongPress();
    }
  }

  void _syncAutoScroll() {
    _autoScrollTimer?.cancel();

    if (!widget.autoScrollEnabled || !_controller.hasClients) {
      return;
    }

    const frameInterval = Duration(milliseconds: 16);
    final double deltaPerTick =
        widget.autoScrollPixelsPerSecond * (frameInterval.inMilliseconds / 1000);

    _autoScrollTimer = Timer.periodic(frameInterval, (_) {
      if (!mounted || !_controller.hasClients || !widget.autoScrollEnabled) {
        _autoScrollTimer?.cancel();
        return;
      }

      final maxScroll = _controller.position.maxScrollExtent;
      final nextOffset = (_controller.offset + deltaPerTick).clamp(0.0, maxScroll);

      if ((nextOffset - _controller.offset).abs() < 0.1 ||
          nextOffset >= maxScroll) {
        _autoScrollTimer?.cancel();
        if (widget.autoScrollEnabled) {
          widget.onAutoScrollInterrupted();
        }
        return;
      }

      _controller.jumpTo(nextOffset);
      _reportVisiblePageFromOffset();
    });
  }

  void _pauseAutoScrollTemporarily() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _handleScroll() {
    if (!_controller.hasClients) return;

    if (!_didLogFirstClientAttach) {
      _didLogFirstClientAttach = true;
      _debugEvent('firstClientAttach', {
        'offset': _controller.offset.toStringAsFixed(1),
        'positionCount': _controller.positions.length,
      });
    }

    final page = _pageFromOffset(_controller.offset);
    if (page == _lastReportedPage) return;

    _lastReportedPage = page;
    _precacheNearbyPages(page);
    _debugEvent('reportVisiblePage', {
      'page': page,
      'offset': _controller.offset.toStringAsFixed(1),
    });
    Future.microtask(() {
      if (mounted) widget.onPageChanged(page);
    });
  }

  void _reportVisiblePageFromOffset() {
    if (!_controller.hasClients) return;

    final page = _pageFromOffset(_controller.offset);
    if (page == _lastReportedPage) return;

    _lastReportedPage = page;
    _precacheNearbyPages(page);
    _debugEvent('reportVisiblePage', {
      'page': page,
      'offset': _controller.offset.toStringAsFixed(1),
    });
    Future.microtask(() {
      if (mounted) widget.onPageChanged(page);
    });
  }

  void _precacheNearbyPages(int centerPage) {
    if (!mounted) return;
    if (centerPage == _lastPrecacheCenterPage) return;

    _precacheDebounceTimer?.cancel();
    _precacheDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _lastPrecacheCenterPage = centerPage;
      final ctx = context;
      for (int i = centerPage - _precacheRadius;
          i <= centerPage + _precacheRadius;
          i++) {
        if (i < 0 || i >= widget.pages.length) continue;
        if (!mounted) return;
        precacheImage(
          widget.pageImageProviderBuilder(i),
          ctx,
        );
      }
    });
  }

  void scrollToPage(int pageIndex, {double yOffsetRatio = 0.0}) {
    if (!_controller.hasClients) return;

    final safePage = pageIndex.clamp(0, widget.pages.length - 1);
    final targetOffset = _offsetForPage(safePage) + (yOffsetRatio * _pageHeight);
    _lastReportedPage = safePage;
    _debugEvent('scrollToPage', {
      'page': safePage,
      'targetOffset': targetOffset.toStringAsFixed(1),
    });
    _controller.jumpTo(targetOffset);
  }

  Future<void> scrollToBookmark(
    ReaderBookmark bookmark, {
    bool animate = true,
  }) async {
    if (!_controller.hasClients) return;
    if (bookmark.page < 0 || bookmark.page >= widget.pages.length) {
      return;
    }

    final viewportHeight =
        context.size?.height ?? _controller.position.viewportDimension;
    final bookmarkOffsetWithinPage =
        bookmark.topFor(_pageHeight).clamp(0.0, _pageHeight);
    final pageStartOffset = _offsetForPage(bookmark.page);
    final minimumBookmarkOffset =
        (pageStartOffset + 1.0).clamp(0.0, _controller.position.maxScrollExtent);
    final targetOffset = (
      pageStartOffset +
      bookmarkOffsetWithinPage -
      (viewportHeight / 2)
    ).clamp(
      minimumBookmarkOffset,
      _controller.position.maxScrollExtent,
    );
    _lastReportedPage = bookmark.page;
    _debugEvent('scrollToBookmark', {
      'page': bookmark.page,
      'targetOffset': targetOffset.toStringAsFixed(1),
      'bookmarkY': bookmarkOffsetWithinPage.toStringAsFixed(1),
    });
    if (!animate) {
      _controller.jumpTo(targetOffset);
      return;
    }

    await _controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    _debugEvent('buildState', {
      'viewportWidth': widget.viewportWidth.toStringAsFixed(1),
      'pageHeight': _pageHeight.toStringAsFixed(1),
      'hasClients': _controller.hasClients,
      'offset': _controller.hasClients
          ? _controller.offset.toStringAsFixed(1)
          : 'no-clients',
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _debugEvent('postFrameBuildState', {
        'hasClients': _controller.hasClients,
        'offset': _controller.hasClients
            ? _controller.offset.toStringAsFixed(1)
            : 'no-clients',
        'positionCount': _controller.positions.length,
      });
    });

    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (widget.autoScrollEnabled) {
          if (notification.direction == ScrollDirection.idle) {
            _syncAutoScroll();
          } else {
            _pauseAutoScrollTemporarily();
          }
        }
        _debugEvent('userScrollNotification', {
          'direction': notification.direction.name,
          'hasClients': _controller.hasClients,
          'offset': _controller.hasClients
              ? _controller.offset.toStringAsFixed(1)
              : 'no-clients',
        });
        return false;
      },
      child: ListView.builder(
        controller: _controller,
        physics: const ClampingScrollPhysics(),
        cacheExtent: _pageHeight,
        itemExtent: _pageHeight,
        itemCount: widget.pages.length,
        itemBuilder: (context, index) {
          final pageBookmarks = widget.bookmarks
              .where((bookmark) => bookmark.page == index)
              .toList(growable: false);
          return SizedBox(
            width: widget.viewportWidth,
            height: _pageHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  _schedulePendingLongPress(
                    pageIndex: index,
                    localPosition: event.localPosition,
                    width: widget.viewportWidth,
                    height: _pageHeight,
                  );
                },
                onPointerMove: _handlePendingLongPressMove,
                onPointerUp: (_) => _cancelPendingLongPress(),
                onPointerCancel: (_) => _cancelPendingLongPress(),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF6EE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Image(
                            image: widget.pageImageProviderBuilder(index),
                            width: _displayPageWidth,
                            height: _pageHeight,
                            fit: BoxFit.fill,
                            alignment: Alignment.center,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.low,
                            frameBuilder: (
                              context,
                              child,
                              frame,
                              wasSynchronouslyLoaded,
                            ) {
                              if (!_loggedRenderedPages.contains(index) &&
                                  (wasSynchronouslyLoaded || frame != null)) {
                                _loggedRenderedPages.add(index);
                                _debugEvent('imageFirstFrame', {
                                  'page': index,
                                  'frame': frame,
                                  'sync': wasSynchronouslyLoaded,
                                });
                              }
                              return child;
                            },
                          ),
                        ),
                      ),
                    ),
                    for (final bookmark in pageBookmarks)
                      Positioned(
                        left: _draggingBookmarkOffsets[bookmark.slot]?.dx ??
                            bookmark.leftFor(widget.viewportWidth),
                        top: _draggingBookmarkOffsets[bookmark.slot]?.dy ??
                            bookmark.topFor(_pageHeight),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onPanStart: (_) => _startBookmarkDrag(
                            bookmark,
                            widget.viewportWidth,
                            _pageHeight,
                          ),
                          onPanUpdate: (details) => _updateBookmarkDrag(
                            context,
                            bookmark,
                            details,
                            widget.viewportWidth,
                            _pageHeight,
                          ),
                          onPanEnd: (_) => _endBookmarkDrag(bookmark.slot),
                          onPanCancel: () => _endBookmarkDrag(bookmark.slot),
                          child: _BookmarkBadge(slot: bookmark.slot),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BookmarkBadge extends StatelessWidget {
  final int slot;

  const _BookmarkBadge({required this.slot});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF8B7355), // ذهبي بدل أحمر
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: const Icon(
        Icons.bookmark,
        color: Colors.white,
        size: 16,
      ),
    );
  }
}
