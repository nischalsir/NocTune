import 'package:flutter/widgets.dart';

/// Width classes that pick a layout, following Material's window size classes.
enum WindowClass {
  /// Phones in portrait: bottom navigation, single pane.
  compact,

  /// Large phones in landscape and tablets in portrait: navigation rail.
  medium,

  /// Tablets in landscape: rail plus a second pane.
  expanded;

  static WindowClass of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return WindowClass.compact;
    if (width < 840) return WindowClass.medium;
    return WindowClass.expanded;
  }
}

/// Widest a single column of content should grow before it is centred.
const double kMaxContentWidth = 1100;
