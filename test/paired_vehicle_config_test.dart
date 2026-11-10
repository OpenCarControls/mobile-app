import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/config/paired_vehicle_config.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('PairedVehicleConfig round-trips through SharedPreferences', () async {
    final original = PairedVehicleConfig(
      vehicleId: 'virtual_car',
      bleRemoteId: '00:11:22:33:44:55',
      transportPreference: TransportPreference.http,
      httpHost: '192.168.4.1',
      httpPort: 4242,
      mqttClientId: 'dev-car',
    );

    await original.save();

    final loaded = await PairedVehicleConfig.load();
    expect(loaded, isNotNull);
    expect(loaded!.vehicleId, original.vehicleId);
    expect(loaded.bleRemoteId, original.bleRemoteId);
    expect(loaded.transportPreference, original.transportPreference);
    expect(loaded.httpHost, original.httpHost);
    expect(loaded.mqttClientId, 'dev-car');
    expect(loaded.httpPort, original.httpPort);

    await PairedVehicleConfig.clear();
    expect(await PairedVehicleConfig.load(), isNull);
  });
}
