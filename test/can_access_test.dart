import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/constants.g.dart' as virtual_car;
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/can_access_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/can_access_banner.dart';
import 'package:open_car_app/widgets/can_access_section.dart';

class _FakeTransport implements CarTransport {
  _FakeTransport(this.transportType);

  final _controller = StreamController<DeviceToApp>.broadcast();
  final sent = <AppToDevice>[];

  void emit(DeviceToApp msg) => _controller.add(msg);

  @override
  final TransportType transportType;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async => sent.add(message);

  @override
  void dispose() => _controller.close();
}

const _config = PairedVehicleConfig(
  vehicleId: virtual_car.kPlatformName,
  bleRemoteId: '00:11:22:33:44:55',
  transportPreference: TransportPreference.ble,
);

CanAccessState _identifiedNotApproved() => CanAccessState(
  platformConfirmed: true,
  carIdentityConfirmed: true,
  approval: CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_NOT_APPROVED,
  devLockAvailable: true,
  devUnlocked: false,
  logging: false,
  readOnly: true,
);

DeviceToApp _accessUpdate(CanAccessState state) => DeviceToApp(
  platformId: virtual_car.kPlatformId,
  stateUpdate: StateUpdate(systemState: SystemState(canAccess: state)),
);

ProviderContainer _container(_FakeTransport transport) {
  final container = ProviderContainer(
    overrides: [
      bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
      initialPairedVehicleConfigProvider.overrideWithValue(_config),
      carTransportProvider.overrideWithValue(transport),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(transport.dispose);
  container.listen(vehicleStateProvider, (_, _) {});
  container.listen(canAccessStateProvider, (_, _) {});
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('canAccessStateProvider', () {
    test('is null until the device reports it live', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      expect(container.read(canAccessStateProvider), isNull);

      transport.emit(_accessUpdate(_identifiedNotApproved()));
      await pumpEventQueue();
      final state = container.read(canAccessStateProvider)!;
      expect(state.readOnly, isTrue);
      expect(canAccessNeedsApproval(state), isTrue);
    });

    test('merges partial updates', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(_accessUpdate(_identifiedNotApproved()));
      transport.emit(_accessUpdate(CanAccessState(devUnlocked: true)));
      await pumpEventQueue();
      final state = container.read(canAccessStateProvider)!;
      expect(state.devUnlocked, isTrue);
      expect(state.carIdentityConfirmed, isTrue);
    });

    test('is null over MQTT, which carries no system state', () async {
      final transport = _FakeTransport(TransportType.mqtt);
      final container = _container(transport);
      transport.emit(_accessUpdate(_identifiedNotApproved()));
      await pumpEventQueue();
      expect(container.read(canAccessStateProvider), isNull);
    });
  });

  group('CanAccessActions', () {
    test('sends the approval as a system command and awaits it', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);

      final future = container.read(canAccessActionsProvider).setApproval(true);
      await pumpEventQueue();
      final sent = transport.sent.single;
      expect(sent.systemCommand.setCanReadWriteApproval.approved, isTrue);
      expect(sent.sourceDeviceId, const [1, 2, 3]);

      transport.emit(
        DeviceToApp(
          commandResponse: CommandResponse(
            messageId: sent.messageId,
            success: true,
          ),
        ),
      );
      await future;
    });

    test('reports the device refusing', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);

      final future = container
          .read(canAccessActionsProvider)
          .setDevWriteUnlocked(true);
      await pumpEventQueue();
      final sent = transport.sent.single;
      expect(sent.systemCommand.setCanDevWriteUnlock.unlocked, isTrue);

      transport.emit(
        DeviceToApp(
          commandResponse: CommandResponse(
            messageId: sent.messageId,
            success: false,
            errorMessage: 'this is a release build: it has no dev lock',
          ),
        ),
      );
      await expectLater(future, throwsA(contains('release build')));
    });

    test('never sends over MQTT', () async {
      final transport = _FakeTransport(TransportType.mqtt);
      final container = _container(transport);

      await expectLater(
        container.read(canAccessActionsProvider).setApproval(true),
        throwsA(isA<CarTransportException>()),
      );
      expect(transport.sent, isEmpty);
    });
  });

  group('canAccessSummary', () {
    test('names the first unmet condition', () {
      final state = _identifiedNotApproved();
      expect(canAccessSummary(state), contains('not approved'));

      state.approval = CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_OTHER_CAR;
      expect(canAccessSummary(state), contains('different car'));
      expect(canAccessNeedsApproval(state), isTrue);

      state.approval = CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_APPROVED;
      expect(canAccessSummary(state), contains('write lock'));
      expect(canAccessNeedsApproval(state), isFalse);

      state.carIdentityConfirmed = false;
      expect(canAccessSummary(state), contains('not identified'));

      state.logging = true;
      expect(canAccessSummary(state), contains('logging'));

      state.readOnly = false;
      expect(canAccessSummary(state), 'Control enabled');
    });
  });

  group('widgets', () {
    Future<_FakeTransport> pump(WidgetTester tester, Widget child) async {
      final transport = _FakeTransport(TransportType.ble);
      addTearDown(transport.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
            initialPairedVehicleConfigProvider.overrideWithValue(_config),
            carTransportProvider.overrideWithValue(transport),
          ],
          child: MaterialApp(
            home: Scaffold(body: ListView(children: [child])),
          ),
        ),
      );
      return transport;
    }

    testWidgets('approval needs the risks acknowledged', (tester) async {
      final transport = await pump(tester, const CanAccessBanner());
      expect(find.text('Review'), findsNothing);

      transport.emit(_accessUpdate(_identifiedNotApproved()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      final allow = find.widgetWithText(FilledButton, 'Allow control');
      expect(tester.widget<FilledButton>(allow).onPressed, isNull);
      await tester.tap(find.text('I understand the risks'));
      await tester.pump();
      expect(tester.widget<FilledButton>(allow).onPressed, isNotNull);

      await tester.tap(allow);
      await tester.pump();
      final sent = transport.sent.single;
      expect(sent.systemCommand.setCanReadWriteApproval.approved, isTrue);
      transport.emit(
        DeviceToApp(
          commandResponse: CommandResponse(
            messageId: sent.messageId,
            success: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Allow control of this car?'), findsNothing);

      // Dispose the providers, which cancels the state liveness timer.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the dev lock shows only when the firmware has it', (
      tester,
    ) async {
      final transport = await pump(tester, const CanAccessSection());
      expect(find.textContaining('Connect over Bluetooth'), findsOneWidget);

      transport.emit(_accessUpdate(_identifiedNotApproved()));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsOneWidget);

      transport.emit(_accessUpdate(CanAccessState(devLockAvailable: false)));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
