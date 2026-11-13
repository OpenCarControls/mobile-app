import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/widgets/tiles/car_body_icons.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

Widget _wrap(Widget child) => MaterialApp(home: Center(child: child));

void main() {
  testWidgets('a symbol fills when on', (tester) async {
    await tester.pumpWidget(
      _wrap(const TileIconView(TileIcon.symbol(Symbols.lock), on: true)),
    );
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Symbols.lock);
    expect(icon.fill, 1);
  });

  testWidgets('a symbol with an on glyph switches glyph, unfilled', (
    tester,
  ) async {
    const icon = TileIcon.symbol(Symbols.lock_open, onSymbol: Symbols.lock);
    await tester.pumpWidget(_wrap(const TileIconView(icon)));
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Symbols.lock_open);
    await tester.pumpWidget(_wrap(const TileIconView(icon, on: true)));
    final on = tester.widget<Icon>(find.byType(Icon));
    expect(on.icon, Symbols.lock);
    expect(on.fill, 0);
  });

  testWidgets('drawn icons paint at the requested size', (tester) async {
    for (final icon in [
      CarBodyIcons.frunk,
      CarBodyIcons.trunk,
      CarBodyIcons.window,
    ]) {
      for (final on in [false, true]) {
        await tester.pumpWidget(_wrap(TileIconView(icon, on: on, size: 32)));
        final paint = find.descendant(
          of: find.byType(TileIconView),
          matching: find.byType(CustomPaint),
        );
        expect(tester.getSize(paint), const Size.square(32));
        expect(tester.takeException(), isNull);
      }
    }
  });
}
