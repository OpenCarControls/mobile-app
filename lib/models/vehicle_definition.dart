import 'package:flutter/widgets.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';

abstract class VehicleDefinition {
  String get platformName;
  int get platformId;
  int get canBusCount;

  /// The platform's accent colours and shapes.
  VehicleSkin get skin;

  String get mqttCommandTopicTemplate;
  String get mqttDataTopicTemplate;

  String get bleServiceUuid;
  String get bleAppToDeviceCharacteristicUuid;
  String get bleDeviceToAppCharacteristicUuid;

  /// Decode vehicle-specific basic state bytes into a typed proto instance.
  /// Called once per incoming message; result is stored and merged into state.
  GeneratedMessage decodeBasicState(List<int> bytes);

  /// Decode vehicle-specific advanced state bytes into a typed proto instance.
  /// Called once per incoming message; result is stored and merged into state.
  GeneratedMessage decodeAdvancedState(List<int> bytes);

  /// Build the vehicle's dashboard screen widget.
  Widget buildDashboard();

  /// Return a stub transport for this vehicle, or null if none is available.
  /// Used as a fallback when MQTT (and later BLE) are unavailable.
  CarTransport? createStubTransport();
}
