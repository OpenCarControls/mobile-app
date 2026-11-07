import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';

/// Checks every vehicle this build supports.
void main() {
  final vehicles = ProviderContainer().read(availableVehiclesProvider);

  for (final vehicle in vehicles) {
    group(vehicle.platformName, () {
      test('tile ids are unique', () {
        final ids = [for (final tile in vehicle.tiles) tile.id];
        expect(ids.toSet(), hasLength(ids.length), reason: '$ids');
      });

      test('tiles offer only sizes their kind supports', () {
        for (final tile in vehicle.tiles) {
          expect(tile.sizes, isNotEmpty, reason: tile.id);
          for (final size in tile.sizes) {
            expect(tile.kind.sizes, contains(size), reason: tile.id);
          }
        }
      });

      test('basic tiles only send basic commands', () {
        // Over MQTT only basic commands go through.
        for (final tile in vehicle.tiles) {
          if (tile.tier != TileTier.basic) continue;
          final key = tile.command?.key;
          if (key != null) expect(key.set, CommandSet.basic, reason: tile.id);
          if (tile is ClimateTileDefinition) {
            expect(tile.climate.command.set, CommandSet.basic);
          }
        }
      });

      test('series ids are unique', () {
        final series = [for (final tile in vehicle.tiles) ...tile.series];
        final byId = <String, Object>{};
        for (final s in series) {
          final other = byId.putIfAbsent(s.id, () => s);
          // A series shared by two tiles must be the same series.
          expect(identical(other, s), isTrue, reason: s.id);
        }
      });

      test('energy and climate tiles use the vehicle description', () {
        for (final tile in vehicle.tiles) {
          if (tile is EnergyTileDefinition) {
            expect(vehicle.energy, contains(same(tile.energy)));
          }
          if (tile is ClimateTileDefinition) {
            expect(tile.climate, same(vehicle.climate));
          }
        }
      });

      test('climate extras are unique and well formed', () {
        final climate = vehicle.climate;
        if (climate == null) return;
        expect(climate.minCelsius, lessThan(climate.maxCelsius));
        expect(climate.stepCelsius, greaterThan(0));
        final ids = [for (final extra in climate.extras) extra.id];
        expect(ids.toSet(), hasLength(ids.length), reason: '$ids');
        for (final extra in climate.extras) {
          if (extra is LeveledClimateExtra) {
            expect(extra.levels, greaterThan(0), reason: extra.id);
          }
        }
      });

      for (final tier in DashboardTier.values) {
        group('the ${tier.name} default layout', () {
          final layout = vehicle.defaultLayout(tier);

          test('is not empty', () => expect(layout, isNotEmpty));

          test('references existing tiles at supported sizes', () {
            for (final entry in layout) {
              final tile = vehicle.tileById(entry.tileId);
              expect(tile, isNotNull, reason: entry.tileId);
              expect(tile!.sizes, contains(entry.span), reason: entry.tileId);
            }
          });

          test('has each tile once', () {
            final ids = [for (final entry in layout) entry.tileId];
            expect(ids.toSet(), hasLength(ids.length), reason: '$ids');
          });

          if (tier == DashboardTier.remote) {
            test('has no advanced tiles', () {
              for (final entry in layout) {
                expect(
                  vehicle.tileById(entry.tileId)?.tier,
                  TileTier.basic,
                  reason: entry.tileId,
                );
              }
            });
          }
        });
      }
    });
  }
}
