import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/constants.g.dart' as virtual_car;
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/models/paired_phone.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/vehicle_command_feedback.dart';

class _FakeTransport implements CarTransport {
  _FakeTransport(this.transportType);

  final _controller = StreamController<DeviceToApp>.broadcast();
  final sent = <AppToDevice>[];

  void emit(DeviceToApp msg) => _controller.add(msg);

  /// Answers the last command sent.
  Future<void> respond(CommandResponse response) async {
    await pumpEventQueue();
    emit(
      DeviceToApp(commandResponse: response..messageId = sent.last.messageId),
    );
  }

  @override
  final TransportType transportType;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async => sent.add(message);

  @override
  void dispose() => _controller.close();
}

/// The transport in use, which tests change to simulate a new connection.
class _Transport extends Notifier<_FakeTransport> {
  _Transport(this._initial);
  final _FakeTransport _initial;

  @override
  _FakeTransport build() => _initial;

  void use(_FakeTransport transport) => state = transport;
}

late NotifierProvider<_Transport, _FakeTransport> _transportProvider;

const _config = PairedVehicleConfig(
  vehicleId: virtual_car.kPlatformName,
  bleRemoteId: '00:11:22:33:44:55',
  transportPreference: TransportPreference.ble,
);

const _bonded = PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED;
const _validated = PhoneTrustLevel.PHONE_TRUST_LEVEL_VALIDATED;
const _inProgress = PhoneValidationStatus.PHONE_VALIDATION_STATUS_IN_PROGRESS;
const _failed = PhoneValidationStatus.PHONE_VALIDATION_STATUS_FAILED;
const _codeEntry =
    PhoneValidationMethodKind.PHONE_VALIDATION_METHOD_KIND_CODE_ENTRY;
const _notValidated =
    CommandStatusCode.COMMAND_STATUS_CODE_REJECTED_NOT_VALIDATED;
const _codeMethod = 'virtual_car.cluster_code';

PhoneValidationSession _codeSession({int attemptsLeft = 3}) =>
    PhoneValidationSession(
      methodId: _codeMethod,
      kind: _codeEntry,
      status: _inProgress,
      codeLength: virtual_car.kBlePhoneValidationCodeLength,
      attemptsLeft: attemptsLeft,
      expiresInS: 100,
    );

DeviceToApp _accessUpdate(PhoneAccessState state) => DeviceToApp(
  platformId: virtual_car.kPlatformId,
  stateUpdate: StateUpdate(systemState: SystemState(phoneAccess: state)),
);

ProviderContainer _container(_FakeTransport transport) {
  _transportProvider = NotifierProvider<_Transport, _FakeTransport>(
    () => _Transport(transport),
  );
  final container = ProviderContainer(
    overrides: [
      bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
      initialPairedVehiclesProvider.overrideWithValue(
        PairedVehicles.of(_config),
      ),
      carTransportProvider.overrideWith((ref) => ref.watch(_transportProvider)),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(transport.dispose);
  container.listen(vehicleStateProvider, (_, _) {}, onError: (_, _) {});
  container.listen(phoneAccessStateProvider, (_, _) {});
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the limits come from the contract', () {
    expect(virtual_car.kBlePhoneValidationSessionSeconds, greaterThan(0));
    expect(virtual_car.kBlePhoneValidationCodeLength, greaterThan(0));
    expect(virtual_car.kBlePhoneValidationMaxCodeAttempts, greaterThan(0));
    expect(virtual_car.kBlePhoneValidationCooldownSeconds, greaterThan(0));
    expect(virtual_car.kBlePhoneValidationResultKeepSeconds, greaterThan(0));
  });

  group('phoneAccessStateProvider', () {
    test('is null until the device reports it live', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      expect(container.read(phoneAccessStateProvider), isNull);

      transport.emit(
        _accessUpdate(
          PhoneAccessState(trust: _bonded, carHasValidatedPhone: false),
        ),
      );
      await pumpEventQueue();
      final state = container.read(phoneAccessStateProvider)!;
      expect(state.trust, _bonded);
      expect(state.carHasValidatedPhone, isFalse);
      expect(state.hasValidation(), isFalse);
    });

    test('merges partial updates', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(
        _accessUpdate(
          PhoneAccessState(trust: _bonded, carHasValidatedPhone: true),
        ),
      );
      transport.emit(_accessUpdate(PhoneAccessState(trust: _validated)));
      await pumpEventQueue();
      final state = container.read(phoneAccessStateProvider)!;
      expect(state.trust, _validated);
      expect(state.carHasValidatedPhone, isTrue);
    });

    test('takes the session whole: zero values replace old ones', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(
        _accessUpdate(
          PhoneAccessState(
            trust: _bonded,
            validation: _codeSession(attemptsLeft: 1),
          ),
        ),
      );
      await pumpEventQueue();
      expect(
        container.read(phoneAccessStateProvider)!.validation.attemptsLeft,
        1,
      );

      // The last attempt is used. The firmware's encoder leaves zero values
      // out of the message, so the attempts and the time left aren't set.
      transport.emit(
        _accessUpdate(
          PhoneAccessState(
            trust: _bonded,
            validation: PhoneValidationSession(
              methodId: _codeMethod,
              kind: _codeEntry,
              status: _failed,
              codeLength: virtual_car.kBlePhoneValidationCodeLength,
              cooldownS: 300,
            ),
          ),
        ),
      );
      await pumpEventQueue();
      final session = container.read(phoneAccessStateProvider)!.validation;
      expect(session.status, _failed);
      expect(session.attemptsLeft, 0);
      expect(session.expiresInS, 0);
      expect(session.cooldownS, 300);
    });

    test('drops the session once the device stops reporting it', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(
        _accessUpdate(
          PhoneAccessState(trust: _bonded, validation: _codeSession()),
        ),
      );
      transport.emit(_accessUpdate(PhoneAccessState(trust: _bonded)));
      await pumpEventQueue();
      final state = container.read(phoneAccessStateProvider)!;
      expect(state.hasValidation(), isFalse);
      expect(state.trust, _bonded);
    });

    test('is cleared by a transport change', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(_accessUpdate(PhoneAccessState(trust: _validated)));
      await pumpEventQueue();
      expect(container.read(phoneAccessStateProvider), isNotNull);

      final mqtt = _FakeTransport(TransportType.mqtt);
      addTearDown(mqtt.dispose);
      container.read(_transportProvider.notifier).use(mqtt);
      await pumpEventQueue();
      expect(container.read(phoneAccessStateProvider), isNull);
    });

    test('is cleared by a new connection on the same transport', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(_accessUpdate(PhoneAccessState(trust: _validated)));
      await pumpEventQueue();

      final reconnected = _FakeTransport(TransportType.ble);
      addTearDown(reconnected.dispose);
      container.read(_transportProvider.notifier).use(reconnected);
      await pumpEventQueue();
      expect(container.read(phoneAccessStateProvider), isNull);

      // The old connection can't report any more.
      transport.emit(_accessUpdate(PhoneAccessState(trust: _validated)));
      await pumpEventQueue();
      expect(container.read(phoneAccessStateProvider), isNull);

      reconnected.emit(_accessUpdate(PhoneAccessState(trust: _bonded)));
      await pumpEventQueue();
      expect(container.read(phoneAccessStateProvider)!.trust, _bonded);
    });

    test('ignores a cached one', () async {
      final cached = SystemState(
        phoneAccess: PhoneAccessState(trust: _validated),
      );
      SharedPreferences.setMockInitialValues({
        'vehicle_state_${virtual_car.kPlatformName}': jsonEncode({
          'basicStateBytes': '',
          'advancedStateBytes': '',
          'systemStateBytes': base64Encode(cached.writeToBuffer()),
        }),
      });
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      await pumpEventQueue();
      final system = container.read(vehicleStateProvider).system;
      expect(system?.hasPhoneAccess(), isTrue);
      expect(container.read(phoneAccessStateProvider), isNull);
    });

    test('ignores a device reporting another platform', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(
        _accessUpdate(PhoneAccessState(trust: _validated))..platformId = 7,
      );
      await pumpEventQueue();
      expect(container.read(phoneAccessStateProvider), isNull);
    });

    test('is null over MQTT, which carries no system state', () async {
      final transport = _FakeTransport(TransportType.mqtt);
      final container = _container(transport);
      transport.emit(_accessUpdate(PhoneAccessState(trust: _validated)));
      await pumpEventQueue();
      expect(container.read(phoneAccessStateProvider), isNull);
    });
  });

  group('PhoneValidationActions', () {
    late _FakeTransport transport;
    late PhoneValidationActions actions;

    setUp(() {
      transport = _FakeTransport(TransportType.ble);
      actions = _container(transport).read(phoneValidationActionsProvider);
    });

    test('lists the methods in the order the device gives', () async {
      final future = actions.listMethods();
      await transport.respond(
        CommandResponse(
          success: true,
          systemResult: SystemCommandResult(
            validationMethods: PhoneValidationMethods(
              methods: [
                PhoneValidationMethod(
                  methodId: _codeMethod,
                  kind: _codeEntry,
                  needsApproval: true,
                ),
                PhoneValidationMethod(
                  methodId: 'virtual_car.button',
                  available: true,
                ),
              ],
            ),
          ),
        ),
      );
      final methods = await future;
      expect(
        transport.sent.single.systemCommand.hasListPhoneValidationMethods(),
        isTrue,
      );
      expect(transport.sent.single.sourceDeviceId, const [1, 2, 3]);
      expect(methods.map((m) => m.methodId), [
        _codeMethod,
        'virtual_car.button',
      ]);
      expect(methods.first.available, isFalse);
      expect(methods.first.needsApproval, isTrue);
    });

    test('starts a session', () async {
      final future = actions.start(_codeMethod);
      await transport.respond(
        CommandResponse(
          success: true,
          systemResult: SystemCommandResult(validationSession: _codeSession()),
        ),
      );
      final session = await future;
      expect(
        transport.sent.single.systemCommand.startPhoneValidation.methodId,
        _codeMethod,
      );
      expect(session.status, _inProgress);
      expect(session.attemptsLeft, 3);
    });

    test('submits a code', () async {
      final future = actions.submitCode('042917');
      await transport.respond(
        CommandResponse(
          success: true,
          systemResult: SystemCommandResult(
            validationSession: _codeSession()
              ..status =
                  PhoneValidationStatus.PHONE_VALIDATION_STATUS_SUCCEEDED,
          ),
        ),
      );
      final session = await future;
      expect(
        transport.sent.single.systemCommand.submitPhoneValidationCode.code,
        '042917',
      );
      expect(
        session.status,
        PhoneValidationStatus.PHONE_VALIDATION_STATUS_SUCCEEDED,
      );
    });

    test('a wrong code fails with the session', () async {
      final future = actions.submitCode('000000');
      final refused = expectLater(
        future,
        throwsA(
          isA<CommandRejectedException>()
              .having((e) => e.message, 'message', 'wrong code')
              .having((e) => e.needsValidation, 'needsValidation', isFalse)
              .having(
                (e) => e.validationSession?.attemptsLeft,
                'attempts left',
                2,
              ),
        ),
      );
      await transport.respond(
        CommandResponse(
          success: false,
          errorMessage: 'wrong code',
          statusCode: CommandStatusCode.COMMAND_STATUS_CODE_FAILED,
          systemResult: SystemCommandResult(
            validationSession: _codeSession(attemptsLeft: 2),
          ),
        ),
      );
      await refused;
    });

    test('a refusal without a session has none', () async {
      final refused = expectLater(
        actions.start(_codeMethod),
        throwsA(
          isA<CommandRejectedException>()
              .having((e) => '$e', 'text', 'another phone is validating')
              .having((e) => e.validationSession, 'session', isNull),
        ),
      );
      await transport.respond(
        CommandResponse(
          success: false,
          errorMessage: 'another phone is validating',
        ),
      );
      await refused;
    });

    test('cancels, which answers with no data', () async {
      final future = actions.cancel();
      await transport.respond(CommandResponse(success: true));
      await future;
      expect(
        transport.sent.single.systemCommand.hasCancelPhoneValidation(),
        isTrue,
      );
    });

    test('lists the paired phones, with this one and their trust', () async {
      final future = actions.listPairedPhones();
      await transport.respond(
        CommandResponse(
          success: true,
          systemResult: SystemCommandResult(
            pairedPhones: PairedPhones(
              phones: [
                PairedPhone(deviceId: [1], trust: _validated),
                PairedPhone(deviceId: [2], trust: _bonded, isRequester: true),
              ],
            ),
          ),
        ),
      );
      final phones = await future;
      expect(transport.sent.single.systemCommand.hasListPairedPhones(), isTrue);
      expect(phones.map((p) => p.deviceId), [
        [1],
        [2],
      ]);
      expect(phones.map((p) => p.isValidated), [true, false]);
      expect(phones.map((p) => p.isThisPhone), [false, true]);
    });

    test('a success without the expected data fails', () async {
      final failed = expectLater(
        actions.listMethods(),
        throwsA(isA<CarTransportException>()),
      );
      await transport.respond(CommandResponse(success: true));
      await failed;
    });
  });

  group('over MQTT', () {
    final calls = <String, Future<Object?> Function(PhoneValidationActions)>{
      'listMethods': (a) => a.listMethods(),
      'start': (a) => a.start(_codeMethod),
      'submitCode': (a) => a.submitCode('042917'),
      'cancel': (a) => a.cancel(),
      'listPairedPhones': (a) => a.listPairedPhones(),
    };
    for (final MapEntry(key: name, value: call) in calls.entries) {
      test('$name fails without sending', () async {
        final transport = _FakeTransport(TransportType.mqtt);
        final container = _container(transport);
        await expectLater(
          call(container.read(phoneValidationActionsProvider)),
          throwsA(isA<CarTransportException>()),
        );
        expect(transport.sent, isEmpty);
      });
    }
  });

  group('REJECTED_NOT_VALIDATED', () {
    CommandRejectedException rejected() => CommandRejectedException(
      CommandResponse(
        success: false,
        errorMessage: 'command rejected: this phone is not validated',
        statusCode: _notValidated,
      ),
    );

    test('is recognised on a vehicle command', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      final refused = expectLater(
        container.read(vehicleStateProvider.notifier).sendBasicCommand(const [
          1,
        ]),
        throwsA(
          isA<CommandRejectedException>().having(
            (e) => e.needsValidation,
            'needsValidation',
            isTrue,
          ),
        ),
      );
      await transport.respond(
        CommandResponse(success: false, statusCode: _notValidated),
      );
      await refused;
    });

    test('is recognised on a system command', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      final refused = expectLater(
        container
            .read(vehicleStateProvider.notifier)
            .sendSystemCommand(
              SystemCommand(
                removePairedPhone: RemovePairedPhoneCommand(deviceId: [1]),
              ),
            ),
        throwsA(
          isA<CommandRejectedException>().having(
            (e) => e.needsValidation,
            'needsValidation',
            isTrue,
          ),
        ),
      );
      await transport.respond(
        CommandResponse(success: false, statusCode: _notValidated),
      );
      await refused;
    });

    test('tells the user to validate the phone in the car', () {
      expect(vehicleCommandErrorText(rejected()), contains('validating'));
      expect(vehicleCommandErrorText(rejected()), contains('in the car'));
    });

    test('other refusals keep the device\'s reason', () {
      final other = CommandRejectedException(
        CommandResponse(
          success: false,
          errorMessage: 'the car is driving',
          statusCode:
              CommandStatusCode.COMMAND_STATUS_CODE_REJECTED_UNAVAILABLE,
        ),
      );
      expect(vehicleCommandErrorText(other), 'The car is driving');
    });

    test('an empty failure still has a text', () {
      final empty = CommandRejectedException(CommandResponse(success: false));
      expect(vehicleCommandErrorText(empty), 'Command failed');
    });
  });

  test('PairedPhoneInfo keeps the device id', () {
    final info = PairedPhoneInfo.fromProto(
      PairedPhone(deviceId: [9, 8], trust: _bonded),
    );
    expect(info.deviceId, [9, 8]);
    expect(info.isValidated, isFalse);
    expect(info.isThisPhone, isFalse);
  });
}
