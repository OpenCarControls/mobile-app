import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/cars/virtual_car/constants.g.dart' as virtual_car;
import 'package:open_car_app/cars/virtual_car/stub_transport.dart';
import 'package:open_car_app/main.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the pairing wizard when nothing is paired', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: OpenCarApp()));

    expect(find.text('Pair Your Vehicle'), findsOneWidget);
    expect(
      find.text('Hold the pairing button on your vehicle'),
      findsOneWidget,
    );
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('shows the dashboard when a vehicle is paired', (tester) async {
    final stubTransport = StubCarTransport();
    addTearDown(stubTransport.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialPairedVehicleConfigProvider.overrideWithValue(
            const PairedVehicleConfig(
              vehicleId: virtual_car.kPlatformName,
              bleRemoteId: '00:11:22:33:44:55',
              transportPreference: TransportPreference.ble,
            ),
          ),
          carTransportProvider.overrideWithValue(stubTransport),
        ],
        child: const OpenCarApp(),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Open Car'), findsOneWidget);
    expect(find.text('State'), findsOneWidget);
    expect(find.text('Controls'), findsOneWidget);
    expect(find.text('Odometer'), findsOneWidget);
    expect(find.text('Driving'), findsOneWidget);
  });
}
