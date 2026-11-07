import 'package:flutter/widgets.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/cars/virtual_car/catalog.dart';
import 'package:open_car_app/cars/virtual_car/constants.g.dart';
import 'package:open_car_app/cars/virtual_car/screens/virtual_car_dashboard.dart';
import 'package:open_car_app/cars/virtual_car/skin.dart';
import 'package:open_car_app/cars/virtual_car/stub_transport.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/hero_placeholder.dart';

class VirtualCarDefinition implements VehicleDefinition {
  const VirtualCarDefinition();

  @override
  String get platformName => kPlatformName;

  @override
  int get platformId => kPlatformId;

  @override
  int get canBusCount => kCanBusCount;

  @override
  String get displayName => 'Virtual car';

  @override
  String get platformLabel => 'Virtual car (test platform)';

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

  @override
  Widget buildHero(BuildContext context, VehicleSnapshot snapshot) =>
      HeroPlaceholder(dimmed: !snapshot.isStateLive);

  @override
  VehicleUnits units(VehicleSnapshot snapshot) => kMetricUnits;

  @override
  List<EnergyDescription> get energy => const [];

  @override
  int? drivingSpeedKmh(VehicleSnapshot snapshot) =>
      (snapshot.basicState as BasicState).isDriving
      ? virtualCarSpeedKmh(snapshot)
      : null;

  @override
  String? statusLine(VehicleSnapshot snapshot) =>
      (snapshot.basicState as BasicState).isDriving ? 'Driving' : null;

  @override
  List<TileDefinition> get tiles => virtualCarTiles;

  @override
  List<TileLayoutEntry> defaultLayout(DashboardTier tier) => switch (tier) {
    DashboardTier.remote => virtualCarRemoteLayout,
    DashboardTier.bluetooth => virtualCarBluetoothLayout,
  };

  @override
  ClimateDescription? get climate => null;
}
