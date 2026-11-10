import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/config/paired_vehicle_config.dart';

const _legacyKey = 'paired_vehicle_config';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('PairedVehicles round-trips through SharedPreferences', () async {
    const first = PairedVehicleConfig(
      id: 'a',
      name: 'Mine',
      vehicleId: 'virtual_car',
      bleRemoteId: '00:11:22:33:44:55',
      transportPreference: TransportPreference.ble,
      mqttClientId: 'dev-car',
    );
    const second = PairedVehicleConfig(
      id: 'b',
      vehicleId: 'virtual_car',
      bleRemoteId: '',
      transportPreference: TransportPreference.http,
      httpHost: '192.168.4.1',
      httpPort: 4242,
    );

    await const PairedVehicles(
      vehicles: [first, second],
      currentId: 'b',
    ).save();

    final loaded = await PairedVehicles.load();
    expect(loaded.vehicles.map((v) => v.id), ['a', 'b']);
    expect(loaded.current?.id, 'b');
    expect(loaded.vehicles.first.name, 'Mine');
    expect(loaded.vehicles.first.mqttClientId, 'dev-car');
    expect(loaded.vehicles.first.bleRemoteId, first.bleRemoteId);
    expect(loaded.vehicles.last.name, isNull);
    expect(loaded.vehicles.last.transportPreference, TransportPreference.http);
    expect(loaded.vehicles.last.httpHost, second.httpHost);
    expect(loaded.vehicles.last.httpPort, second.httpPort);
  });

  test('nothing stored reads as nothing paired', () async {
    final loaded = await PairedVehicles.load();
    expect(loaded.vehicles, isEmpty);
    expect(loaded.current, isNull);
  });

  test('corrupt data reads as nothing paired', () async {
    SharedPreferences.setMockInitialValues({'paired_vehicles': '{not json'});
    expect((await PairedVehicles.load()).vehicles, isEmpty);
  });

  test('an unknown current id falls back to the first vehicle', () {
    const vehicles = PairedVehicles(
      vehicles: [
        PairedVehicleConfig(
          id: 'a',
          vehicleId: 'virtual_car',
          bleRemoteId: 'A',
          transportPreference: TransportPreference.ble,
        ),
      ],
      currentId: 'gone',
    );
    expect(vehicles.current?.id, 'a');
  });

  group('migrating a single-vehicle install', () {
    void storeLegacy(Object value) => SharedPreferences.setMockInitialValues({
      _legacyKey: value is String ? value : jsonEncode(value),
    });

    test('keeps the pairing, with its platform name as its id', () async {
      storeLegacy({
        'vehicleId': 'virtual_car',
        'bleRemoteId': '00:11:22:33:44:55',
        'transportPreference': 'ble',
        'mqttClientId': 'dev-car',
      });

      final loaded = await PairedVehicles.load();

      expect(loaded.vehicles, hasLength(1));
      final vehicle = loaded.current!;
      expect(vehicle.id, 'virtual_car');
      // What was already stored under the platform name stays this vehicle's.
      expect(vehicle.storageKey, 'virtual_car');
      expect(vehicle.name, isNull);
      expect(vehicle.bleRemoteId, '00:11:22:33:44:55');
      expect(vehicle.mqttClientId, 'dev-car');
    });

    test('happens once and removes the old entry', () async {
      storeLegacy({
        'vehicleId': 'virtual_car',
        'bleRemoteId': 'A',
        'transportPreference': 'ble',
      });

      await PairedVehicles.load();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_legacyKey), isFalse);

      final again = await PairedVehicles.load();
      expect(again.current?.id, 'virtual_car');
    });

    test('a corrupt old entry reads as nothing paired', () async {
      storeLegacy('{not json');
      expect((await PairedVehicles.load()).vehicles, isEmpty);
    });
  });
}
