import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/egmp/constants.g.dart' as egmp;
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/providers/ble_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';

const _remoteId = '00:11:22:33:44:55';

/// A BLE stack whose link comes up instantly but never exposes the car's
/// service, so post-connect setup always fails ([mtuFails] makes it fail
/// earlier). Each call to [connectToDevice] counts as one attempt and
/// cancelling its stream counts as a disconnect.
class _FakeBle implements FlutterReactiveBle {
  _FakeBle({this.mtuFails = false});

  final bool mtuFails;
  int connectCalls = 0;
  int disconnects = 0;

  @override
  Stream<BleStatus> get statusStream => Stream.value(BleStatus.ready);

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    connectCalls++;
    late final StreamController<ConnectionStateUpdate> controller;
    controller = StreamController<ConnectionStateUpdate>(
      onListen: () => controller.add(
        ConnectionStateUpdate(
          deviceId: id,
          connectionState: DeviceConnectionState.connected,
          failure: null,
        ),
      ),
      onCancel: () => disconnects++,
    );
    return controller.stream;
  }

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) async =>
      mtuFails ? throw Exception('MTU request failed') : mtu;

  @override
  Future<void> clearGattCache(String deviceId) async {}

  @override
  Future<void> discoverAllServices(String deviceId) async {}

  @override
  Future<List<Service>> getDiscoveredServices(
    String deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_FakeBle ble) {
  final container = ProviderContainer(
    overrides: [
      bleProvider.overrideWithValue(ble),
      initialPairedVehicleConfigProvider.overrideWithValue(
        const PairedVehicleConfig(
          vehicleId: egmp.kPlatformName,
          bleRemoteId: _remoteId,
          transportPreference: TransportPreference.ble,
        ),
      ),
    ],
  );
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    // permission_handler: report every permission as granted.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => call.method == 'requestPermissions'
              ? {
                  for (final id in (call.arguments as List).cast<int>())
                    id: PermissionStatusValue.granted,
                }
              : null,
        );
  });

  for (final (name, mtuFails) in [
    ('the car\'s service is missing', false),
    ('the MTU request fails', true),
  ]) {
    testWidgets('drops the link and retries when $name', (tester) async {
      final ble = _FakeBle(mtuFails: mtuFails);
      final container = _container(ble);
      container.listen(bleConnectionProvider, (_, _) {});

      await tester.pump(const Duration(seconds: 1));
      expect(ble.connectCalls, 1);
      expect(ble.disconnects, 1, reason: 'the half-set-up link is dropped');
      expect(container.read(bleConnectionProvider), isA<BleConnecting>());

      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      expect(ble.connectCalls, 2);
      expect(ble.disconnects, 2);

      // Disposing cancels the pending retry; the test binding checks for it.
      container.dispose();
    });
  }
}

/// permission_handler's `PermissionStatus.granted` as sent over its channel.
abstract final class PermissionStatusValue {
  static const granted = 1;
}
