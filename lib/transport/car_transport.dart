import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';

enum TransportType {
  /// Connected directly over BLE. Full access: basic + advanced state and commands.
  ble,

  /// Connected remotely over MQTT. Restricted: basic state and commands only.
  mqtt,

  /// Local stub/virtual transport used for UI development.
  /// Behaves like BLE — exposes full state and commands.
  stub,

  /// Debug HTTP transport that imitates BLE over a local HTTP server.
  /// Only available in debug builds. Full access: basic + advanced state and commands.
  http,
}

/// Thrown by [CarTransport.send] when the message can't be sent, e.g. the
/// transport is offline or doesn't carry that kind of message.
class CarTransportException implements Exception {
  final String message;
  const CarTransportException(this.message);

  @override
  String toString() => message;
}

abstract class CarTransport {
  TransportType get transportType;

  Stream<DeviceToApp> get messages;

  Future<void> send(AppToDevice message);

  void dispose();
}
