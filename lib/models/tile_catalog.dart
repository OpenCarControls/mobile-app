import 'package:flutter/widgets.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

/// Which tiles a transport can show. Advanced tiles need advanced state or
/// commands, which only Bluetooth carries; over MQTT they are left out.
enum TileTier { basic, advanced }

/// The two dashboard layouts: remote (MQTT) shows basic tiles only, Bluetooth
/// shows both tiers. See `docs/ui.md`.
enum DashboardTier { remote, bluetooth }

/// The layouts a tile can take. Each kind supports a fixed set of sizes; a
/// tile may offer fewer.
enum TileKind {
  command([TileSpan(1, 1), TileSpan(2, 1)]),
  state([TileSpan(1, 1), TileSpan(2, 1), TileSpan(2, 2)]),
  energy([TileSpan(4, 1)]),
  // It grows to 4×3 while climate is on, by itself (see [spanFor]).
  climate([TileSpan(4, 1)]),
  chart([TileSpan(2, 1), TileSpan(2, 2), TileSpan(4, 1), TileSpan(4, 2)]),
  carView([TileSpan(2, 2), TileSpan(4, 2)]);

  const TileKind(this.sizes);

  /// The sizes a tile of this kind can be given.
  final List<TileSpan> sizes;
}

/// A command a tile sends: its key, for availability, and the message, built
/// from the state when tapped (a lock tile locks when unlocked).
@immutable
class TileCommand {
  const TileCommand({required this.key, required this.build});

  final CommandKey key;
  final GeneratedMessage Function(VehicleSnapshot snapshot) build;
}

/// The state a tile shows, from the vehicle state.
@immutable
class TileState {
  const TileState({required this.on, required this.caption});

  /// Gives the tile the accent fill and the icon's "on" look.
  final bool on;

  /// The state in words ("Locked"): the 2×1 caption, and part of the
  /// accessible label ("Doors, locked").
  final String caption;
}

/// The state of a tile the vehicle doesn't report yet.
const kUnknownTileState = TileState(on: false, caption: 'Unknown');

/// A value a state tile shows.
@immutable
class TileValue {
  const TileValue(this.value, {this.unit, this.note});

  /// The value ("697"), without its unit.
  final String value;

  /// The unit, drawn smaller after the value ("V").
  final String? unit;

  /// A short line under the value at 2×2 ("charging").
  final String? note;

  @override
  String toString() => [value, ?unit, ?note].join(' ');
}

/// One tile a platform offers. The catalog of a vehicle lists every tile it
/// has; a layout picks and orders them.
///
/// Tiles describe data and commands; the shared tile widgets draw them, so
/// every platform looks the same. Chart tiles are the exception: each chart is
/// its own custom tile with its own [ChartTileDefinition.builder].
@immutable
sealed class TileDefinition {
  const TileDefinition({
    required this.id,
    required this.label,
    required this.tier,
    this.icon,
    String? accessibleLabel,
    List<TileSpan>? sizes,
  }) : _accessibleLabel = accessibleLabel,
       _sizes = sizes;

  /// Stable and unique in the catalog: saved layouts reference it.
  final String id;

  /// The tile's one-word title ("Doors").
  final String label;

  final TileTier tier;
  final TileIcon? icon;

  /// For screen readers when [label] is too short to be clear ("Charge port"
  /// for "Port"). Tiles add their state to it.
  String get accessibleLabel => _accessibleLabel ?? label;
  final String? _accessibleLabel;

  TileKind get kind;

  /// The sizes this tile supports, from its [kind]'s.
  List<TileSpan> get sizes => _sizes ?? kind.sizes;
  final List<TileSpan>? _sizes;

  /// The command a tap sends, if any.
  TileCommand? get command => null;

  /// The series the tile draws, which the history records.
  List<HistorySeries> get series => const [];

  /// The span the tile takes at [span] for this state. Only the climate tile
  /// changes it by itself.
  TileSpan spanFor(TileSpan span, VehicleSnapshot snapshot) => span;
}

/// A tile that sends a command when tapped and shows its state by fill and
/// icon. Titled or icon-only; at 2×1 it adds a caption.
final class CommandTileDefinition extends TileDefinition {
  const CommandTileDefinition({
    required super.id,
    required super.label,
    required super.tier,
    required super.icon,
    super.accessibleLabel,
    super.sizes,
    required this.command,
    required this.state,
  }) : assert(icon != null);

  @override
  TileKind get kind => TileKind.command;

  @override
  TileIcon get icon => super.icon!;

  @override
  final TileCommand command;

  final TileState Function(VehicleSnapshot snapshot) state;
}

/// A value with a label. 2×1 adds a sparkline of [series]; 2×2 a large value,
/// a note and a chart.
final class StateTileDefinition extends TileDefinition {
  const StateTileDefinition({
    required super.id,
    required super.label,
    required super.tier,
    super.icon,
    super.accessibleLabel,
    super.sizes,
    required this.value,
    this.history,
  });

  @override
  TileKind get kind => TileKind.state;

  /// The value now, or null when unknown (shown as a dash).
  final TileValue? Function(VehicleSnapshot snapshot, VehicleUnits units) value;

  /// What the sparkline and the chart draw.
  final HistorySeries? history;

  @override
  List<HistorySeries> get series => [?history];
}

/// The level, range and charging state of one of the vehicle's energy stores.
final class EnergyTileDefinition extends TileDefinition {
  const EnergyTileDefinition({
    required super.id,
    required super.label,
    required super.tier,
    super.accessibleLabel,
    required this.energy,
  });

  @override
  TileKind get kind => TileKind.energy;

  /// One of the vehicle's [VehicleDefinition.energy] stores.
  final EnergyDescription energy;
}

/// The climate bar, and while climate is on, the target and the extras.
final class ClimateTileDefinition extends TileDefinition {
  const ClimateTileDefinition({
    required super.id,
    required super.label,
    required super.tier,
    super.icon,
    super.accessibleLabel,
    required this.climate,
  });

  /// The span while climate is on: the bar and two rows of panel.
  static const onSpan = TileSpan(4, 3);

  @override
  TileKind get kind => TileKind.climate;

  /// The vehicle's [VehicleDefinition.climate].
  final ClimateDescription climate;

  @override
  TileSpan spanFor(TileSpan span, VehicleSnapshot snapshot) =>
      climate.isOn(snapshot) ?? false ? onSpan : span;
}

/// What a chart tile's builder gets.
typedef ChartTileData = ({
  VehicleSnapshot snapshot,
  VehicleUnits units,
  TileSpan span,

  /// The recorded samples of each of the tile's series, by series id.
  Map<String, List<HistorySample>> history,
});

/// A chart, built per chart rather than from one generic graph tile.
final class ChartTileDefinition extends TileDefinition {
  const ChartTileDefinition({
    required super.id,
    required super.label,
    required super.tier,
    super.icon,
    super.accessibleLabel,
    super.sizes,
    required this.series,
    required this.describe,
    required this.builder,
  });

  @override
  TileKind get kind => TileKind.chart;

  @override
  final List<HistorySeries> series;

  /// The current value in words for screen readers ("7.2 kilowatts").
  final String Function(ChartTileData data) describe;

  /// The chart's content, drawn inside the shared tile surface.
  final Widget Function(BuildContext context, ChartTileData data) builder;
}

/// The vehicle's hero as a tile. A placeholder until the hero is built.
final class CarViewTileDefinition extends TileDefinition {
  const CarViewTileDefinition({
    required super.id,
    required super.label,
    required super.tier,
    super.accessibleLabel,
  });

  @override
  TileKind get kind => TileKind.carView;
}

/// A tile in a layout: which tile, at what size.
typedef TileLayoutEntry = ({String tileId, TileSpan span});
