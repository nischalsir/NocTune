import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/third_party/spotiflac/mornye_selection_pill.dart';

/// How the bottom bar marks the selected tab: a flat pill at rest, a glass
/// lens while the selection moves, and never both.
///
/// The lens needs a renderer with shader filters, which the default test
/// renderer is not. Run this file with `flutter test --enable-impeller`;
/// without it the lens tests are skipped, not passed.
void main() {
  final glass = ui.ImageFilter.isShaderFilterSupported;
  const labels = ['Home', 'Library', 'Search', 'Settings'];
  const frame = Duration(milliseconds: 16);

  Future<ValueNotifier<int>> pumpPill(WidgetTester tester) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 64,
              child: ValueListenableBuilder(
                valueListenable: selected,
                builder: (context, index, _) => MornyeSelectionPill(
                  liquidInteraction: true,
                  labels: labels,
                  selectedIndex: index,
                  onChanged: (value) => selected.value = value,
                  itemBuilder: (context, index, selected) =>
                      Center(child: Text(labels[index])),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return selected;
  }

  Iterable<BoxDecoration> decorations(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(MornyeSelectionPill),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>();

  // The flat pill is the decoration with a shadow.
  final flatPill = find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).boxShadow != null,
  );

  /// How visible the flat pill is, from 0 to 1.
  double pill(WidgetTester tester) =>
      decorations(tester).firstWhere((d) => d.boxShadow != null).color!.a /
      0.12;

  /// How far up the glass lens is, from 0 to 1, read from its rim.
  double lens(WidgetTester tester) {
    final rims = decorations(tester)
        .where((d) => d.boxShadow == null && d.border is Border);
    return rims.isEmpty ? 0 : (rims.first.border! as Border).top.color.a / 0.6;
  }

  double centre(WidgetTester tester, String label) =>
      tester.getCenter(find.text(label)).dx;

  testWidgets('at rest the flat pill marks the selection', (tester) async {
    await pumpPill(tester);

    expect(pill(tester), closeTo(1, 1e-6));
    expect(lens(tester), 0);
    expect(tester.getCenter(flatPill).dx, closeTo(centre(tester, 'Home'), 0.5));
  });

  testWidgets('a quick tap carries the selection across in glass', (
    tester,
  ) async {
    final selected = await pumpPill(tester);

    final finger = await tester.startGesture(
      tester.getCenter(find.text('Search')),
    );
    await tester.pump(frame);
    await tester.pump(const Duration(milliseconds: 50));
    await finger.up();
    await tester.pump(frame);
    expect(selected.value, 2);

    // The finger has gone, the selection is still on its way: glass, and
    // no flat pill.
    await tester.pump(const Duration(milliseconds: 100));
    expect(lens(tester), greaterThan(0.85));
    expect(pill(tester), lessThan(0.15));

    // Arrived: the glass has gone and the pill is back, on the new tab.
    await tester.pumpAndSettle();
    expect(lens(tester), 0);
    expect(pill(tester), closeTo(1, 1e-6));
    expect(
      tester.getCenter(flatPill).dx,
      closeTo(centre(tester, 'Search'), 0.5),
    );
  }, skip: !glass);

  testWidgets('a slide stays glass until the selection has settled', (
    tester,
  ) async {
    final selected = await pumpPill(tester);

    final finger = await tester.startGesture(
      tester.getCenter(find.text('Home')),
    );
    await tester.pump(frame);
    await finger.moveBy(const Offset(30, 0));
    await tester.pump(frame);
    await finger.moveBy(const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(lens(tester), closeTo(1, 1e-6));
    expect(pill(tester), 0);

    await finger.up();
    await tester.pump(frame);
    expect(selected.value, 2);
    // Settling onto its tab: still glass, still no pill.
    await tester.pump(const Duration(milliseconds: 150));
    expect(lens(tester), closeTo(1, 1e-6));
    expect(pill(tester), 0);

    await tester.pumpAndSettle();
    expect(lens(tester), 0);
    expect(pill(tester), closeTo(1, 1e-6));
  }, skip: !glass);

  testWidgets('a page changed from elsewhere moves in glass too', (
    tester,
  ) async {
    final selected = await pumpPill(tester);

    selected.value = 3;
    await tester.pump(frame);
    await tester.pump(const Duration(milliseconds: 150));
    expect(lens(tester), greaterThan(0.85));
    expect(pill(tester), lessThan(0.15));

    await tester.pumpAndSettle();
    expect(lens(tester), 0);
    expect(pill(tester), closeTo(1, 1e-6));
    expect(
      tester.getCenter(flatPill).dx,
      closeTo(centre(tester, 'Settings'), 0.5),
    );
  }, skip: !glass);

  testWidgets('a held press gives way as soon as the finger lifts', (
    tester,
  ) async {
    await pumpPill(tester);

    final finger = await tester.startGesture(
      tester.getCenter(find.text('Home')),
    );
    await tester.pump(frame);
    await tester.pump(const Duration(milliseconds: 400));
    expect(lens(tester), closeTo(1, 1e-6));

    await finger.up();
    await tester.pump(frame);
    await tester.pump(const Duration(milliseconds: 120));
    expect(lens(tester), lessThan(0.5));

    await tester.pumpAndSettle();
    expect(pill(tester), closeTo(1, 1e-6));
  }, skip: !glass);

  testWidgets('without glass the pill is always there and simply moves', (
    tester,
  ) async {
    final selected = await pumpPill(tester);

    await tester.tap(find.text('Library'));
    await tester.pump(frame);
    await tester.pump(const Duration(milliseconds: 100));
    expect(selected.value, 1);
    expect(pill(tester), closeTo(1, 1e-6));

    await tester.pumpAndSettle();
    expect(
      tester.getCenter(flatPill).dx,
      closeTo(centre(tester, 'Library'), 0.5),
    );
  }, skip: glass);
}
