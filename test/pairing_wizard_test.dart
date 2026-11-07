import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_car_app/main.dart';
import 'package:open_car_app/providers/ble_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _id = 'D4:F9:8D:1F:17:E4';

/// Finds one device, advertising [name].
class _OneDeviceBle implements FlutterReactiveBle {
  _OneDeviceBle(this.name);

  final String name;

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    ScanMode scanMode = ScanMode.balanced,
    bool requireLocationServicesEnabled = true,
  }) => Stream.value(
    DiscoveredDevice(
      id: _id,
      name: name,
      serviceData: const {},
      manufacturerData: Uint8List(0),
      rssi: -50,
      serviceUuids: const [],
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Grants every permission `permission_handler` is asked for.
void _grantPermissions() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async => call.method == 'requestPermissions'
            ? {for (final p in call.arguments as List) p as int: 1}
            : 1,
      );
}

Future<void> _scan(WidgetTester tester, String name) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bleProvider.overrideWithValue(_OneDeviceBle(name))],
      child: const OpenCarApp(),
    ),
  );
  await tester.tap(find.text('Start'));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _grantPermissions();
  });

  testWidgets('a device found without its name is outside pairing mode', (
    tester,
  ) async {
    // Android reports a device it cached while paired, even though the
    // device advertises neither its name nor its service outside pairing mode.
    await _scan(tester, '');

    expect(find.text('Vehicle found'), findsOneWidget);
    expect(find.textContaining('not in pairing mode'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
    expect(find.text('Pair'), findsOneWidget);
  });

  testWidgets('a device found with its name is in pairing mode', (
    tester,
  ) async {
    await _scan(tester, 'OpenCar-17E4');

    expect(find.text('OpenCar-17E4'), findsOneWidget);
    expect(find.textContaining('not in pairing mode'), findsNothing);
    expect(find.text('Help'), findsNothing);
  });
}
