import 'package:flutter/widgets.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/cars/egmp/constants.g.dart';
import 'package:open_car_app/cars/egmp/screens/egmp_dashboard.dart';
import 'package:open_car_app/cars/egmp/stub_transport.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/transport/car_transport.dart';

class EgmpDefinition implements VehicleDefinition {
  const EgmpDefinition();

  @override
  String get platformName => kPlatformName;

  @override
  int get platformId => kPlatformId;

  @override
  int get canBusCount => kCanBusCount;

  @override
  String get mqttCommandTopicTemplate => kMqttCommandTopicTemplate;

  @override
  String get mqttDataTopicTemplate => kMqttDataTopicTemplate;

  @override
  String get bleServiceUuid => kBleServiceUuid;

  @override
  String get bleAppToDeviceCharacteristicUuid =>
      kBleAppToDeviceCharacteristicUuid;

  @override
  String get bleDeviceToAppCharacteristicUuid =>
      kBleDeviceToAppCharacteristicUuid;

  @override
  GeneratedMessage decodeBasicState(List<int> bytes) =>
      BasicState.fromBuffer(bytes);

  @override
  GeneratedMessage decodeAdvancedState(List<int> bytes) =>
      AdvancedState.fromBuffer(bytes);

  @override
  Widget buildDashboard() => const EgmpDashboardScreen();

  @override
  CarTransport? createStubTransport() => StubCarTransport();
}
