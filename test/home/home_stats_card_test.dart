import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/models/playlist.dart';
import 'package:noctune/features/home/home_feed.dart';

void main() {
  Widget card(int plays) => MaterialApp(
    theme: buildNocTheme(Brightness.dark, NocAccent.red),
    home: Scaffold(
      body: HomeStatsCard(
        stats: LibraryStats(
          trackCount: 12,
          albumCount: 3,
          artistCount: 2,
          totalDuration: const Duration(hours: 1),
          playCount: plays,
        ),
        onOpenLibrary: () {},
      ),
    ),
  );

  testWidgets('shows the saved play count at once, without counting up from '
      'zero', (tester) async {
    await tester.pumpWidget(card(57));

    expect(find.text('57'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('57'), findsOneWidget);
  });

  testWidgets('a new play while the card is showing counts up to it', (
    tester,
  ) async {
    await tester.pumpWidget(card(57));
    await tester.pumpWidget(card(58));

    await tester.pumpAndSettle();
    expect(find.text('58'), findsOneWidget);
  });
}
