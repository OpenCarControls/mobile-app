import 'package:flutter/widgets.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/cars/virtual_car/constants.g.dart';
import 'package:open_car_app/cars/virtual_car/screens/virtual_car_dashboard.dart';
import 'package:open_car_app/cars/virtual_car/skin.dart';
import 'package:open_car_app/cars/virtual_car/stub_transport.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';

class VirtualCarDefinition implements VehicleDefinition {
  const VirtualCarDefinition();

  @override
  String get platformName => kPlatformName;

  @override
  int get platformId => kPlatformId;

  @override
  int get canBusCount => kCanBusCount;

  @override
  VehicleSkin get skin => virtualCarSkin;

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
  Widget buildDashboard() => const VirtualCarDashboardScreen();

  @override
  CarTransport? createStubTransport() => StubCarTransport();
}
