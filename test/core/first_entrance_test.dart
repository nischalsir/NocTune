import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/core/widgets/first_entrance.dart';

void main() {
  Widget list(String id, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      // The test window is 800 × 600: rows 0 to 9 are in it.
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: EntranceScope(
        id: id,
        child: ListView.builder(
          itemCount: 60,
          itemExtent: 64,
          itemBuilder: (context, index) => EntranceItem(
            index: index,
            child: SizedBox(height: 64, child: Text('Row $index')),
          ),
        ),
      ),
    ),
  );

  /// How visible the row reading [label] is: 1 when fully shown.
  double shown(WidgetTester tester, String label) {
    final fades = find.ancestor(
      of: find.text(label, skipOffstage: false),
      matching: find.byType(Opacity, skipOffstage: false),
    );
    if (fades.evaluate().isEmpty) return 1;
    return tester.widget<Opacity>(fades.first).opacity;
  }

  testWidgets('rows on screen come in one after another', (tester) async {
    await tester.pumpWidget(list('stagger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(shown(tester, 'Row 0'), greaterThan(shown(tester, 'Row 8')));

    await tester.pumpAndSettle();
    expect(shown(tester, 'Row 0'), 1);
    expect(shown(tester, 'Row 8'), 1);
  });

  testWidgets('a row below the fold rises in as it is scrolled to', (
    tester,
  ) async {
    await tester.pumpWidget(list('scroll-in'));
    await tester.pumpAndSettle();

    // Built ahead of the window, but not yet in it: waiting, hidden.
    final waiting = find.text('Row 11', skipOffstage: false);
    expect(waiting, findsOneWidget);
    expect(shown(tester, 'Row 11'), 0);

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    // The frame that shows the row starts it; the next is its first step.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(shown(tester, 'Row 11'), inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(shown(tester, 'Row 11'), 1);
  });

  testWidgets('a row comes in once: scrolling back to it leaves it be', (
    tester,
  ) async {
    await tester.pumpWidget(list('once'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 2400));
    await tester.pump();

    expect(shown(tester, 'Row 2'), 1);
  });

  testWidgets('a later visit shows the rows on screen as they are', (
    tester,
  ) async {
    await tester.pumpWidget(list('again'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(list('again'));
    await tester.pump();

    expect(shown(tester, 'Row 0'), 1);
    expect(shown(tester, 'Row 8'), 1);
  });

  testWidgets('with reduced motion nothing waits or moves', (tester) async {
    await tester.pumpWidget(list('still', reduceMotion: true));
    await tester.pump();

    expect(shown(tester, 'Row 0'), 1);
    expect(shown(tester, 'Row 11'), 1);
  });
}
