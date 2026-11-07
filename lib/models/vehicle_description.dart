import 'package:flutter/foundation.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

/// The units the car displays distances, speeds and temperatures in.
typedef VehicleUnits = ({DistanceUnit distance, TemperatureUnit temperature});

const kMetricUnits = (
  distance: DistanceUnit.kilometers,
  temperature: TemperatureUnit.celsius,
);

/// Where a vehicle's energy is stored.
enum EnergyKind { battery, fuel }

/// What the energy store is doing, which picks the Battery tile's content.
enum EnergyFlow {
  /// Not charging or exporting.
  idle,

  /// Charging.
  charging,

  /// Exporting power, as with V2L.
  exporting,
}

/// The charging detail of an energy store.
@immutable
class EnergyStatus {
  const EnergyStatus({
    this.flow = EnergyFlow.idle,
    this.powerWatts,
    this.limitPercent,
    this.timeToLimitMinutes,
    this.timeTo80PercentMinutes,
  });

  final EnergyFlow flow;

  /// The power in or out, always positive. Null when unknown.
  final int? powerWatts;

  /// The charge limit, when the car reports one.
  final int? limitPercent;

  /// While charging, the time to [limitPercent].
  final int? timeToLimitMinutes;

  /// While DC charging, the time to 80%, which the car shows besides the time
  /// to the limit.
  final int? timeTo80PercentMinutes;
}

/// One energy store: a battery or a fuel tank. Hybrids have two.
@immutable
class EnergyDescription {
  const EnergyDescription({
    required this.kind,
    required this.levelPercent,
    required this.rangeKm,
    this.status,
  });

  final EnergyKind kind;

  /// The level in percent, or null when unknown.
  final int? Function(VehicleSnapshot snapshot) levelPercent;

  /// The range in km, or null when unknown. Shown in the car's units.
  final int? Function(VehicleSnapshot snapshot) rangeKm;

  /// The charging detail; null for a store that can't charge or export.
  final EnergyStatus Function(VehicleSnapshot snapshot)? status;
}

/// Which side of the car a climate extra is for, shown as an L or R tag.
enum ClimateSide { none, left, right }

/// An extra of the climate panel (defrost, seat heating). Extras are part of
/// the climate command, so the panel only offers them while climate is on.
@immutable
sealed class ClimateExtra {
  const ClimateExtra({
    required this.id,
    required this.label,
    required this.icon,
    this.side = ClimateSide.none,
  });

  /// Stable and unique within the climate description.
  final String id;

  /// For screen readers ("Driver seat heating").
  final String label;
  final TileIcon icon;
  final ClimateSide side;
}

/// An extra that is on or off.
final class ToggleClimateExtra extends ClimateExtra {
  const ToggleClimateExtra({
    required super.id,
    required super.label,
    required super.icon,
    super.side,
    required this.isOn,
    required this.command,
  });

  /// Null when unknown.
  final bool? Function(VehicleSnapshot snapshot) isOn;

  /// The climate command that turns it [on].
  final GeneratedMessage Function(VehicleSnapshot snapshot, bool on) command;
}

/// An extra with levels from 0 (off) to [levels], like seat heating.
final class LeveledClimateExtra extends ClimateExtra {
  const LeveledClimateExtra({
    required super.id,
    required super.label,
    required super.icon,
    super.side,
    required this.levels,
    required this.level,
    required this.next,
    required this.command,
  });

  /// The highest level.
  final int levels;

  /// The level now, 0 for off; null when unknown.
  final int? Function(VehicleSnapshot snapshot) level;

  /// The level a tap sets, after [current] (null when unknown). Cars step
  /// differently: E-GMP goes off, 3, 2, 1, off.
  final int Function(int? current) next;

  /// The climate command that sets [level].
  final GeneratedMessage Function(VehicleSnapshot snapshot, int level) command;
}

/// The climate control: the Climate tile's bar and panel.
@immutable
class ClimateDescription {
  const ClimateDescription({
    required this.command,
    required this.isOn,
    required this.insideCelsius,
    required this.outsideCelsius,
    required this.targetCelsius,
    required this.minCelsius,
    required this.maxCelsius,
    required this.stepCelsius,
    required this.formatTarget,
    required this.power,
    required this.setTarget,
    this.extras = const [],
  });

  /// The command behind the power button, the target and every extra.
  final CommandKey command;

  /// Null when unknown.
  final bool? Function(VehicleSnapshot snapshot) isOn;
  final double? Function(VehicleSnapshot snapshot) insideCelsius;
  final double? Function(VehicleSnapshot snapshot) outsideCelsius;
  final double? Function(VehicleSnapshot snapshot) targetCelsius;

  /// The target's range and step, in °C. The car's own steps in its display
  /// unit come from [formatTarget].
  final double minCelsius;
  final double maxCelsius;
  final double stepCelsius;

  /// The target as the car shows it in [unit], which may not be a plain
  /// conversion (E-GMP steps 1 °F per 0.5 °C).
  final String Function(double celsius, TemperatureUnit unit) formatTarget;

  /// The command that turns climate [on].
  final GeneratedMessage Function(VehicleSnapshot snapshot, bool on) power;

  /// The command that sets the target to [celsius].
  final GeneratedMessage Function(VehicleSnapshot snapshot, double celsius)
  setTarget;

  final List<ClimateExtra> extras;
}
