import 'package:flutter/widgets.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/cars/egmp/constants.g.dart';
import 'package:open_car_app/cars/egmp/screens/egmp_dashboard.dart';
import 'package:open_car_app/cars/egmp/stub_transport.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/hero_placeholder.dart';

class EgmpDefinition implements VehicleDefinition {
  const EgmpDefinition();

  @override
  String get platformName => kPlatformName;

  @override
  int get platformId => kPlatformId;

  @override
  int get canBusCount => kCanBusCount;

  @override
  String get displayName => 'E-GMP';

  @override
  String get platformLabel => 'Hyundai Motor Group E-GMP';

  @override
  VehicleSkin get skin => defaultSkin;

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

  @override
  Widget buildHero(BuildContext context, VehicleSnapshot snapshot) =>
      HeroPlaceholder(dimmed: !snapshot.isStateLive);

  @override
  VehicleUnits units(VehicleSnapshot snapshot) => kMetricUnits;

  @override
  List<EnergyDescription> get energy => const [];

  @override
  int? drivingSpeedKmh(VehicleSnapshot snapshot) => null;

  @override
  String? statusLine(VehicleSnapshot snapshot) => null;

  @override
  List<TileDefinition> get tiles => const [];

  @override
  List<TileLayoutEntry> defaultLayout(DashboardTier tier) => const [];

  @override
  ClimateDescription? get climate => null;
}
