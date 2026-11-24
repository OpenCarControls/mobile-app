import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';

/// The health of each of the device's CAN buses, by bus id
/// (`SystemState.can_bus_health`, see the firmware's docs/can.md, "Bus
/// health").
///
/// Like [canAccessStateProvider], from the current connection only: null until
/// the device reports it on it, cleared whenever the transport or connection
/// changes, never cached. Always null over MQTT, which carries no system
/// state. The device repeats it every few seconds.
class CanBusHealthNotifier extends Notifier<Map<int, CanBusHealth>?> {
  @override
  Map<int, CanBusHealth>? build() {
    final transport = ref.watch(carTransportProvider);
    if (transport.transportType == TransportType.mqtt) return null;
    final platformId = ref.read(selectedVehicleProvider)?.platformId;
    final subscription = transport.messages.listen(
      (msg) => _onMessage(msg, platformId),
    );
    ref.onDispose(subscription.cancel);
    return null;
  }

  void _onMessage(DeviceToApp msg, int? platformId) {
    // Like vehicleStateProvider, ignore a device reporting another platform.
    if (platformId != null &&
        msg.platformId != 0 &&
        msg.platformId != platformId) {
      return;
    }
    if (!msg.hasStateUpdate() || !msg.stateUpdate.hasSystemState()) return;
    final buses = msg.stateUpdate.systemState.canBusHealth;
    if (buses.isEmpty) return;
    // Each entry is a whole report for its bus: replace it, keep the others.
    state = {...?state, ...buses};
  }
}

final canBusHealthProvider =
    NotifierProvider<CanBusHealthNotifier, Map<int, CanBusHealth>?>(
      CanBusHealthNotifier.new,
    );

/// The bus's status in a word or two.
String canBusStatusLabel(CanBusStatus status) => switch (status) {
  CanBusStatus.CAN_BUS_STATUS_OK => 'OK',
  CanBusStatus.CAN_BUS_STATUS_SILENT => 'Silent',
  CanBusStatus.CAN_BUS_STATUS_DEGRADED => 'Errors',
  CanBusStatus.CAN_BUS_STATUS_NO_VALID_FRAMES => 'No valid frames',
  CanBusStatus.CAN_BUS_STATUS_BUS_OFF => 'Bus-off',
  _ => 'Unknown',
};

/// What the status means, for the row's description.
String canBusStatusHint(CanBusStatus status) => switch (status) {
  CanBusStatus.CAN_BUS_STATUS_OK => 'Receiving frames with no errors.',
  CanBusStatus.CAN_BUS_STATUS_SILENT =>
    'Nothing received: the car is asleep, or the bus is not connected.',
  CanBusStatus.CAN_BUS_STATUS_DEGRADED =>
    'Receiving frames, but with errors or dropped frames.',
  CanBusStatus.CAN_BUS_STATUS_NO_VALID_FRAMES =>
    'Only errors: the device can\'t read this bus. Check its connection.',
  CanBusStatus.CAN_BUS_STATUS_BUS_OFF =>
    'The device went off the bus after too many errors and is restarting.',
  _ => 'Not reported yet.',
};

/// The bus's frame rate over the last few seconds, then its error counters
/// since the device started, in one line.
String canBusCounters(CanBusHealth health) {
  final frames = '${health.framesPerSecond} frames/s';
  final errors = '${health.rxErrors} errors';
  final overruns = '${health.overruns} overruns';
  final busOffs = '${health.busOffs} bus-offs';
  return '$frames · $errors · $overruns · $busOffs';
}
