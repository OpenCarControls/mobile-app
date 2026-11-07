import 'package:flutter/material.dart';

import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/widgets/tiles/catalog_command_tile.dart';
import 'package:open_car_app/widgets/tiles/climate_tile.dart';
import 'package:open_car_app/widgets/tiles/energy_tile.dart';
import 'package:open_car_app/widgets/tiles/state_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_context.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_surface.dart';

/// The widget for a catalog [tile] at [span].
class CatalogTile extends StatelessWidget {
  const CatalogTile({
    super.key,
    required this.tile,
    required this.span,
    required this.data,
  });

  final TileDefinition tile;
  final TileSpan span;
  final TileContext data;

  @override
  Widget build(BuildContext context) {
    return switch (tile) {
      final CommandTileDefinition tile => CatalogCommandTile(
        tile: tile,
        span: span,
        data: data,
      ),
      final StateTileDefinition tile => StateTile(
        tile: tile,
        span: span,
        data: data,
      ),
      final EnergyTileDefinition tile => EnergyTile(tile: tile, data: data),
      final ClimateTileDefinition tile => ClimateTile(tile: tile, data: data),
      final ChartTileDefinition tile => _ChartTile(
        tile: tile,
        span: span,
        data: data,
      ),
      final CarViewTileDefinition tile => _CarViewTile(tile: tile, data: data),
    };
  }
}

/// [items] for a [TileGrid] from a layout, at the spans the state gives them.
/// Entries whose tile isn't in [data]'s catalog, or whose [TileTier] isn't
/// in [tiers], are left out.
List<TileGridItem> catalogGridItems(
  List<TileLayoutEntry> layout,
  TileContext data, {
  Set<TileTier> tiers = const {TileTier.basic, TileTier.advanced},
}) {
  final vehicle = data.vehicle;
  return [
    for (final entry in layout)
      if (vehicle.tileById(entry.tileId) case final tile?
          when tiers.contains(tile.tier))
        () {
          final span = tile.spanFor(entry.span, data.snapshot);
          return TileGridItem(
            id: tile.id,
            span: span,
            child: CatalogTile(tile: tile, span: span, data: data),
          );
        }(),
  ];
}

class _ChartTile extends StatelessWidget {
  const _ChartTile({
    required this.tile,
    required this.span,
    required this.data,
  });

  final ChartTileDefinition tile;
  final TileSpan span;
  final TileContext data;

  @override
  Widget build(BuildContext context) {
    final chart = (
      snapshot: data.snapshot,
      units: data.units,
      span: span,
      history: {for (final s in tile.series) s.id: data.samplesOf(s)},
    );
    return Semantics(
      container: true,
      label: '${tile.accessibleLabel}, ${tile.describe(chart)}',
      excludeSemantics: true,
      child: TileSurface(child: tile.builder(context, chart)),
    );
  }
}

/// The vehicle's hero in a tile.
class _CarViewTile extends StatelessWidget {
  const _CarViewTile({required this.tile, required this.data});

  final CarViewTileDefinition tile;
  final TileContext data;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: tile.accessibleLabel,
      excludeSemantics: true,
      child: TileSurface(
        padding: const EdgeInsets.all(4),
        child: data.vehicle.buildHero(context, data.snapshot),
      ),
    );
  }
}
