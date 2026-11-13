import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/screens/vehicle_layouts_gallery_section.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/widgets/tiles/catalog_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_context.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

Widget _app(Widget child, {double textScale = 1}) => ProviderScope(
  overrides: [
    commandUiStateProvider.overrideWith((ref, key) => CommandUiState.enabled),
  ],
  child: MaterialApp(
    theme: buildAppTheme(defaultSkin, Brightness.dark),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: app!,
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  final vehicles = ProviderContainer().read(availableVehiclesProvider);

  // A small phone, or a small tablet for the wide layout: the layouts must
  // fit without overflowing.
  void setWidth(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final vehicle in vehicles) {
    test('${vehicle.platformName} has sample states', () {
      expect(vehicle.sampleSnapshots, isNotEmpty);
    });

    for (final sample in vehicle.sampleSnapshots) {
      for (final tier in DashboardTier.values) {
        for (final (columns, textScale) in [
          (kTileColumnsPhone, 1.0),
          (kTileColumnsPhone, 1.5),
          (kTileColumnsWide, 1.0),
        ]) {
          testWidgets('${vehicle.displayName}, ${sample.name}, ${tier.name}, '
              '$columns columns, text ×$textScale', (tester) async {
            setWidth(tester, columns == kTileColumnsPhone ? 360 : 720);
            final data = TileContext(
              vehicle: vehicle,
              snapshot: sample.snapshot,
              history: sampleHistory(vehicle, sample.snapshot),
            );
            final items = catalogGridItems(
              vehicle.defaultLayout(tier),
              data,
              tiers: tier == DashboardTier.remote
                  ? {TileTier.basic}
                  : {TileTier.basic, TileTier.advanced},
            );
            expect(items, hasLength(vehicle.defaultLayout(tier).length));
            await tester.pumpWidget(
              _app(
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TileGrid(columns: columns, items: items),
                ),
                textScale: textScale,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }

  testWidgets('the gallery section switches vehicle', (tester) async {
    await tester.pumpWidget(_app(const VehicleLayoutsGallerySection()));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogTile), findsWidgets);
    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    final other = vehicles.last;
    await tester.tap(
      find.text('${other.displayName} (${other.platformLabel})').last,
    );
    await tester.pumpAndSettle();
    expect(find.text(other.displayName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
