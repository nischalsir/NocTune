import 'package:flutter/material.dart';

import 'artwork.dart';

/// A cover that grows into the page it opens, and shrinks back into its row
/// on the way back. The page's cover takes the same [tag].
///
/// On the way its corners round from the row's to the page's, so a round
/// artist picture turns into the page's square cover. Without a [tag] it is
/// just the cover.
class CoverHero extends StatelessWidget {
  const CoverHero({super.key, required this.tag, required this.child});

  /// Must be unique on its page: rows that can show the same collection
  /// twice, such as a shelf and a list, need tags of their own.
  final Object? tag;
  final Artwork child;

  @override
  Widget build(BuildContext context) {
    final tag = this.tag;
    if (tag == null) return child;
    return Hero(tag: tag, flightShuttleBuilder: _flight, child: child);
  }

  static Widget _flight(
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final from = (fromContext.widget as Hero).child;
    final to = (toContext.widget as Hero).child;
    if (from is! Artwork || to is! Artwork) return to;
    // The animation is the opened page's: 0 in the row, 1 on the page.
    final (row, page) = direction == HeroFlightDirection.push
        ? (from, to)
        : (to, from);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final corner = Tween(
          begin: row.radius / row.size,
          end: page.radius / page.size,
        ).transform(t);
        // Drawn at the page's size and scaled down, so the picture is the
        // one already decoded for the page and is not decoded again for
        // every size it passes through.
        return FittedBox(
          child: Artwork(
            path: page.path ?? row.path,
            size: page.size,
            radius: page.size * corner,
          ),
        );
      },
    );
  }
}
