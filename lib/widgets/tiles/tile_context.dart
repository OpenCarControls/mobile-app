import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

/// What every catalog tile reads: the vehicle, its state and its history.
@immutable
class TileContext {
  const TileContext({
    required this.vehicle,
    required this.snapshot,
    this.history = const {},
    this.iconOnly = false,
  });

  final VehicleDefinition vehicle;
  final VehicleSnapshot snapshot;

  /// The recorded series, by id.
  final Map<String, List<HistorySample>> history;

  /// Command tiles show only their icon.
  final bool iconOnly;

  VehicleUnits get units => vehicle.units(snapshot);

  List<HistorySample> samplesOf(HistorySeries? series) =>
      series == null ? const [] : history[series.id] ?? const [];
}

/// Sends a tile's command message. Completes when the vehicle answers and
/// throws if it doesn't accept it.
typedef TileCommandSender =
    Future<Object?> Function(CommandKey key, GeneratedMessage message);

/// Sends tile commands to the vehicle, in the command set of their key. The
/// debug gallery overrides it with fake sends.
final tileCommandSenderProvider = Provider<TileCommandSender>((ref) {
  return (key, message) {
    final vehicle = ref.read(vehicleStateProvider.notifier);
    final bytes = message.writeToBuffer();
    return switch (key.set) {
      CommandSet.basic => vehicle.sendBasicCommand(bytes),
      CommandSet.advanced => vehicle.sendAdvancedCommand(bytes),
    };
  };
});
