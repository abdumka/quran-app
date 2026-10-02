import 'package:flutter/widgets.dart';

/// The app's navigator, so code above the [Navigator] can still reach the
/// overlay it owns. Only installed on TV; see [TvPopupObserver].
final GlobalKey<NavigatorState> kAppNavigatorKey = GlobalKey<NavigatorState>();

/// Tracks whether the route on top of the navigator is a popup — a dialog or
/// a modal bottom sheet — rather than a full page.
///
/// **Why TV needs this.** Every TV screen drives the D-pad itself, and Select
/// is blocked app-wide so one press cannot both run a handler and "click" the
/// focused widget. A popup has neither: nothing drives it, and Select is dead.
/// The result was a dialog whose buttons did nothing at all — the arrows moved
/// an invisible Flutter focus and the only way out was the Back button. That
/// was true of roughly twenty dialogs and sheets, so wrapping each call site
/// was the wrong shape; one driver at the root of the app covers them all, and
/// covers any added later.
///
/// It has to know when to engage, though, or it would fight the screens that
/// *do* drive themselves (the reader, الفهرس, the TV settings page). The
/// distinction it uses is the route type: `showDialog` and
/// `showModalBottomSheet` both push a [PopupRoute], while `Navigator.push` of
/// a page pushes a [PageRoute]. So the driver engages for popups only, and
/// stands down the moment one closes.
class TvPopupObserver extends NavigatorObserver {
  TvPopupObserver._();

  static final TvPopupObserver instance = TvPopupObserver._();

  /// True while the topmost route is a dialog or a modal bottom sheet.
  final ValueNotifier<bool> popupOnTop = ValueNotifier<bool>(false);

  final List<Route<dynamic>> _routes = [];

  void _sync() {
    popupOnTop.value = _routes.isNotEmpty && _routes.last is PopupRoute;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute == null) {
      if (i >= 0) _routes.removeAt(i);
    } else if (i >= 0) {
      _routes[i] = newRoute;
    } else {
      _routes.add(newRoute);
    }
    _sync();
  }
}
