import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/config/mqtt_broker_config.g.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/ble_provider.dart';
import 'package:open_car_app/transport/ble_transport.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/transport/http_transport.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/transport/mqtt_transport.dart';

/// Returned by [carTransportProvider] during the brief window between
/// unpairing and provider disposal, so that dependent providers don't crash.
class _NullCarTransport implements CarTransport {
  const _NullCarTransport();
  @override
  TransportType get transportType => TransportType.stub;
  @override
  Stream<DeviceToApp> get messages => const Stream.empty();
  @override
  Future<void> send(AppToDevice message) async {}
  @override
  void dispose() {}
}

final carTransportProvider = Provider<CarTransport>((ref) {
  final vehicle = ref.watch(selectedVehicleProvider);
  if (vehicle == null) return const _NullCarTransport();
  final config = ref.watch(pairedVehicleProvider);

  if (kIsWeb || kDebugMode) {
    dev.log('Using Stub transport for testing', name: 'TransportProvider');
    return vehicle.createStubTransport() ?? const _NullCarTransport();
  }

  // Debug-only: HTTP transport is used when the vehicle was paired via the
  // HTTP debug path. Host and port come from the persisted pairing config.
  if (kDebugMode &&
      config?.transportPreference == TransportPreference.http &&
      config?.httpHost != null) {
    final transport = HttpCarTransport(
      host: config!.httpHost!,
      port: config.httpPort ?? kDebugServerPort,
      pollingIntervalMs: kDebugServerPollingIntervalMs,
    );
    dev.log(
      'Using HTTP transport (${config.httpHost}:${config.httpPort})',
      name: 'TransportProvider',
    );
    ref.onDispose(transport.dispose);
    return transport;
  }

  final ble = ref.watch(bleConnectionProvider);

  if (ble is BleReady) {
    final transport = BleCarTransport(
      ble: ref.read(bleProvider),
      deviceId: ble.deviceId,
      serviceUuid: vehicle.bleServiceUuid,
      appToDeviceCharacteristicUuid: vehicle.bleAppToDeviceCharacteristicUuid,
      deviceToAppCharacteristicUuid: vehicle.bleDeviceToAppCharacteristicUuid,
    );
    dev.log(
      'Using BLE transport (device: ${ble.deviceId})',
      name: 'TransportProvider',
    );
    ref.onDispose(transport.dispose);
    return transport;
  }

  // Fall back to MQTT. Use persisted broker config if available (reserved for
  // the future MQTT setup wizard step); otherwise use compile-time defaults.
  final transport = MqttCarTransport(
    commandTopicTemplate: vehicle.mqttCommandTopicTemplate,
    dataTopicTemplate: vehicle.mqttDataTopicTemplate,
    connectionClientId: String.fromCharCodes(
      ref.read(bleSourceDeviceIdProvider),
    ),
    platformId: vehicle.platformId,
    sourceDeviceId: ref.read(bleSourceDeviceIdProvider),
  );
  dev.log('Using MQTT transport', name: 'TransportProvider');
  ref.onDispose(transport.dispose);
  return transport;
});

final transportTypeProvider = Provider<TransportType>(
  (ref) => ref.watch(carTransportProvider).transportType,
);
