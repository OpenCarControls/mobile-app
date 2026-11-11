import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/egmp/catalog.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/models/connection_activity.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/connection_activity_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/phone_validation_screen.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/tiles/command_tile.dart';
import 'package:open_car_app/widgets/vehicle_command_feedback.dart';

const _command = (set: CommandSet.basic, id: 1);

const _config = PairedVehicleConfig(
  vehicleId: 'egmp',
  bleRemoteId: 'AA:BB:CC:DD:EE:FF',
  transportPreference: TransportPreference.ble,
);

class _Transport implements CarTransport {
  const _Transport(this.transportType);

  @override
  final TransportType transportType;
  @override
  Stream<DeviceToApp> get messages => const Stream.empty();
  @override
  Future<void> send(AppToDevice message) async {}
  @override
  void dispose() {}
}

CommandRejectedException _rejected(CommandStatusCode code) =>
    CommandRejectedException(
      CommandResponse(statusCode: code, errorMessage: 'raw device text'),
    );

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Future<Object?> Function() send,
  TransportType link = TransportType.ble,
  CommandUiState availability = CommandUiState.enabled,
  bool needsValidation = false,
  List<Override> scoped = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      initialPairedVehiclesProvider.overrideWithValue(
        PairedVehicles.of(_config),
      ),
      carTransportProvider.overrideWithValue(_Transport(link)),
      commandUiStateProvider.overrideWith((ref, key) => availability),
      commandUnavailableReasonProvider.overrideWith((ref, key) => 'Reason'),
      commandNeedsValidationProvider.overrideWithValue(needsValidation),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(defaultSkin, Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 100,
              height: 64,
              child: ProviderScope(
                overrides: scoped,
                child: CommandTile(
                  id: 'tile',
                  command: _command,
                  send: send,
                  activityName: 'Lock doors',
                  semanticLabel: 'Doors, unlocked',
                  child: const Text('Doors'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

Future<void> _tap(WidgetTester tester) async {
  await tester.tap(find.byType(InkWell));
  await tester.pump();
}

String _line(ConnectionActivityEntry entry) =>
    [entry.title, ?entry.detail].join(' · ');

List<String> _lines(ProviderContainer container) => [
  for (final entry in container.read(connectionActivityProvider)) _line(entry),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('commandOutcomeOf', () {
    CommandOutcome outcome(Object error, {bool needsApproval = false}) =>
        commandOutcomeOf(error, needsApproval: needsApproval);

    test('a timeout is no answer', () {
      expect(
        outcome(TimeoutException('Command timed out')),
        CommandOutcome.noAnswer,
      );
    });

    test('a phone the device refuses is not validated', () {
      expect(
        outcome(
          _rejected(
            CommandStatusCode.COMMAND_STATUS_CODE_REJECTED_NOT_VALIDATED,
          ),
        ),
        CommandOutcome.notValidated,
      );
    });

    test('a device not accepting commands is unavailable or unapproved', () {
      final refusal = _rejected(
        CommandStatusCode.COMMAND_STATUS_CODE_REJECTED_UNAVAILABLE,
      );
      expect(outcome(refusal), CommandOutcome.vehicleUnavailable);
      expect(
        outcome(refusal, needsApproval: true),
        CommandOutcome.needsApproval,
      );
    });

    test('not reaching the vehicle is unavailable', () {
      expect(
        outcome(const CarTransportException('Not connected')),
        CommandOutcome.vehicleUnavailable,
      );
    });

    test('anything else failed', () {
      expect(
        outcome(_rejected(CommandStatusCode.COMMAND_STATUS_CODE_FAILED)),
        CommandOutcome.failed,
      );
      expect(outcome('Provider disposed'), CommandOutcome.failed);
    });
  });

  group('tapping a command', () {
    testWidgets('records the result once it is known', (tester) async {
      final answer = Completer<void>();
      final container = await _pump(tester, send: () => answer.future);

      await _tap(tester);
      expect(_lines(container), isEmpty);

      answer.complete();
      await tester.pump();
      expect(_lines(container), ['Lock doors · Done']);
    });

    testWidgets('says when it was sent remotely', (tester) async {
      final container = await _pump(
        tester,
        link: TransportType.mqtt,
        send: () async => null,
      );

      await _tap(tester);

      expect(_lines(container), ['Lock doors · Done · sent remotely']);
    });

    testWidgets('records a failure in plain words only', (tester) async {
      final container = await _pump(
        tester,
        send: () async =>
            throw _rejected(CommandStatusCode.COMMAND_STATUS_CODE_FAILED),
      );

      await _tap(tester);

      expect(_lines(container), ['Lock doors · Failed']);
    });

    testWidgets('a command that never left is not "sent remotely"', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        link: TransportType.mqtt,
        send: () async => throw const CarTransportException('Not connected'),
      );

      await _tap(tester);

      expect(_lines(container), ['Lock doors · Vehicle unavailable']);
    });

    testWidgets('a greyed-out control is recorded and sends nothing', (
      tester,
    ) async {
      var sends = 0;
      final container = await _pump(
        tester,
        availability: CommandUiState.disabled,
        send: () async => sends++,
      );

      await _tap(tester);

      expect(sends, 0);
      expect(_lines(container), ['Lock doors · Vehicle unavailable']);
    });

    testWidgets('a phone that needs validating is recorded', (tester) async {
      final container = await _pump(
        tester,
        availability: CommandUiState.disabled,
        needsValidation: true,
        send: () async => null,
      );

      await _tap(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(PhoneValidationScreen), findsOneWidget);
      expect(_lines(container), ['Lock doors · Phone not validated']);
    });

    testWidgets('the galleries\' fake commands are not recorded', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        send: () async => null,
        scoped: [
          connectionActivityLogsProvider.overrideWith(
            DiscardedConnectionActivity.new,
          ),
        ],
      );

      await _tap(tester);

      expect(_lines(container), isEmpty);
    });
  });

  group('activity names follow what the tap does', () {
    String name(String tile, BasicState basic) {
      final definition = egmpCommandTiles.singleWhere((t) => t.id == tile);
      return definition.command.activityName(
        VehicleSnapshot(basicState: basic, advancedState: AdvancedState()),
      );
    }

    test('doors', () {
      expect(name('doors', BasicState(areDoorsLocked: false)), 'Lock doors');
      expect(name('doors', BasicState(areDoorsLocked: true)), 'Unlock doors');
    });

    test('charge port', () {
      expect(name('charge_port', BasicState()), 'Open charge port');
      expect(
        name(
          'charge_port',
          BasicState(
            chargePortState: BasicState_ChargePortState.CHARGE_PORT_STATE_OPEN,
          ),
        ),
        'Close charge port',
      );
    });

    test('momentary commands', () {
      expect(name('lights', BasicState()), 'Flash lights');
    });
  });
}
