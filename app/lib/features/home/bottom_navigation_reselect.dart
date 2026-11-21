import 'package:flutter/material.dart';

/// Scroll controllers for the pages behind the bottom navigation, so tapping
/// the tab that is already selected scrolls its page back to the top.
///
/// They live as long as the app, because the bottom navigation is always on
/// screen. Never dispose them while a page uses them.
class BottomNavigationReselect {
  BottomNavigationReselect._();

  static final ScrollController landingScrollController = ScrollController();
  static final ScrollController exploreListScrollController =
      ScrollController();
  static final ScrollController noticesScrollController = ScrollController();
  static final ScrollController mineScrollController = ScrollController();
  static final ScrollController profileScrollController = ScrollController();

  /// Scrolls [scroller] to the top, instantly when motion is reduced.
  static void scrollToTop(
    ScrollController scroller, {
    required bool reduceMotion,
  }) {
    final bool atTop = !scroller.hasClients || scroller.offset <= 0;
    if (atTop) return;

    if (reduceMotion) {
      scroller.jumpTo(0);
      return;
    }

    scroller.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
}
