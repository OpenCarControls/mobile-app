import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

/// How the user can edit a grid. See "Editing" in `docs/ui.md`.
enum TileGridEditing {
  /// The grid is locked.
  none,

  /// Holding a tile starts editing.
  implicit,

  /// Holding a tile starts editing, and an edit tile ends the grid.
  explicit,
}

/// A grid on the dashboard. Its [name] keys the saved layouts, so it must not
/// change.
enum DashboardGrid {
  remote(TileGridEditing.none),
  bluetooth(TileGridEditing.explicit);

  const DashboardGrid(this.editing);

  /// The grid shown on [tier].
  factory DashboardGrid.of(DashboardTier tier) => switch (tier) {
    DashboardTier.remote => remote,
    DashboardTier.bluetooth => bluetooth,
  };

  final TileGridEditing editing;
}

/// A saved layout as [tier] can show it on [vehicle]: without tiles the catalog
/// no longer has, tiles of another tier and duplicates, and with every tile at
/// a size it supports. Tiles the catalog gained are not added; they are in
/// [tilesNotInLayout].
List<TileLayoutEntry> sanitizeLayout(
  List<TileLayoutEntry> saved,
  VehicleDefinition vehicle,
  DashboardTier tier,
) {
  final seen = <String>{};
  return [
    for (final entry in saved)
      if (vehicle.tileById(entry.tileId) case final tile?
          when tier.tileTiers.contains(tile.tier) && seen.add(tile.id))
        (
          tileId: tile.id,
          span: tile.sizes.contains(entry.span) ? entry.span : tile.sizes.first,
        ),
  ];
}

/// The catalog tiles [tier] can show that aren't in [layout], for "Add a tile".
List<TileDefinition> tilesNotInLayout(
  List<TileLayoutEntry> layout,
  VehicleDefinition vehicle,
  DashboardTier tier,
) {
  final used = {for (final entry in layout) entry.tileId};
  return [
    for (final tile in vehicle.tiles)
      if (tier.tileTiers.contains(tile.tier) && !used.contains(tile.id)) tile,
  ];
}

/// The edits a user can make to a layout. Each returns a new list.
extension TileLayoutEdits on List<TileLayoutEntry> {
  /// Without the tile [tileId].
  List<TileLayoutEntry> withoutTile(String tileId) => [
    for (final entry in this)
      if (entry.tileId != tileId) entry,
  ];

  /// With [tile] added at the end, at its first size.
  List<TileLayoutEntry> withTile(TileDefinition tile) => [
    ...this,
    (tileId: tile.id, span: tile.sizes.first),
  ];

  /// With the tile [tileId] moved [offset] places: negative is earlier. A move
  /// past either end stops there.
  List<TileLayoutEntry> withTileMoved(String tileId, int offset) {
    final from = indexWhere((entry) => entry.tileId == tileId);
    if (from < 0) return this;
    final to = (from + offset).clamp(0, length - 1);
    final moved = [...this];
    moved.insert(to, moved.removeAt(from));
    return moved;
  }

  /// With [tile] at the size after its current one, wrapping around.
  List<TileLayoutEntry> withNextSize(TileDefinition tile) => [
    for (final entry in this)
      if (entry.tileId == tile.id)
        (tileId: tile.id, span: _nextSize(tile.sizes, entry.span))
      else
        entry,
  ];
}

TileSpan _nextSize(List<TileSpan> sizes, TileSpan current) =>
    sizes[(sizes.indexOf(current) + 1) % sizes.length];
