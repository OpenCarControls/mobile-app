import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/widgets/tiles/tile_grid.dart';

List<(int, int)> _origins(List<TileSpan> spans, [int columns = 4]) => [
  for (final cell in packTiles(spans, columns)) (cell.column, cell.row),
];

void main() {
  group('packTiles', () {
    test('flows left to right and wraps', () {
      expect(_origins(List.filled(5, const TileSpan(1, 1))), [
        (0, 0),
        (1, 0),
        (2, 0),
        (3, 0),
        (0, 1),
      ]);
    });

    test('later tiles fill the gaps earlier ones left', () {
      expect(_origins(const [TileSpan(3, 1), TileSpan(2, 1), TileSpan(1, 1)]), [
        (0, 0),
        (0, 1),
        (3, 0),
      ]);
    });

    test('tiles can span any columns and rows', () {
      expect(
        _origins(const [
          TileSpan(2, 2),
          TileSpan(1, 3),
          TileSpan(1, 1),
          TileSpan(1, 1),
          TileSpan(3, 1),
        ]),
        [(0, 0), (2, 0), (3, 0), (3, 1), (0, 3)],
      );
    });

    test('a tile does not overlap one that spans into its row', () {
      expect(_origins(const [TileSpan(1, 2), TileSpan(4, 1)]), [
        (0, 0),
        (0, 2),
      ]);
    });

    test('narrows a tile wider than the grid', () {
      final cell = packTiles(const [TileSpan(8, 1)], 4).single;
      expect(cell.columns, 4);
    });
  });

  group('TileGrid', () {
    const key = Key('second tile');

    Future<void> pumpGrid(
      WidgetTester tester, {
      required TileSpan first,
      double textScale = 1,
      bool disableAnimations = false,
    }) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                // Four 92 dp columns with three 8 dp gaps.
                width: 392,
                child: TileGrid(
                  items: [
                    TileGridItem(
                      id: 'first',
                      span: first,
                      child: const SizedBox.expand(),
                    ),
                    const TileGridItem(
                      id: 'second',
                      span: TileSpan(1, 1),
                      child: SizedBox.expand(key: key),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Rect second(WidgetTester tester) => tester.getRect(find.byKey(key));

    testWidgets('sizes tiles in whole columns and rows, with gaps', (
      tester,
    ) async {
      await pumpGrid(tester, first: const TileSpan(2, 2));

      expect(second(tester), const Rect.fromLTWH(200, 0, 92, 64));
      expect(tester.getSize(find.byType(AnimatedContainer)).height, 136);
    });

    testWidgets('a tile that grows pushes the next one and slides it back', (
      tester,
    ) async {
      await pumpGrid(tester, first: const TileSpan(4, 1));
      expect(second(tester).top, 72);

      await pumpGrid(tester, first: const TileSpan(4, 3));
      await tester.pump(const Duration(milliseconds: 100));
      expect(second(tester).top, inExclusiveRange(72, 216));
      await tester.pumpAndSettle();
      expect(second(tester).top, 216);

      await pumpGrid(tester, first: const TileSpan(4, 1));
      await tester.pumpAndSettle();
      expect(second(tester).top, 72);
    });

    testWidgets('moves at once with reduced motion', (tester) async {
      await pumpGrid(
        tester,
        first: const TileSpan(4, 1),
        disableAnimations: true,
      );
      await pumpGrid(
        tester,
        first: const TileSpan(4, 3),
        disableAnimations: true,
      );
      await tester.pump();

      expect(second(tester).top, 216);
    });

    testWidgets('rows stay equal and grow with the font size', (tester) async {
      await pumpGrid(tester, first: const TileSpan(4, 1), textScale: 1.5);

      expect(second(tester).height, 96);
      expect(second(tester).top, 104);
    });
  });
}
