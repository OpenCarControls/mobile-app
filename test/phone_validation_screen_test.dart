import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/cars/virtual_car/constants.g.dart' as virtual_car;
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';
import 'package:open_car_app/screens/phone_validation_screen.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';

const _codeEntry =
    PhoneValidationMethodKind.PHONE_VALIDATION_METHOD_KIND_CODE_ENTRY;
const _inCar =
    PhoneValidationMethodKind.PHONE_VALIDATION_METHOD_KIND_IN_CAR_ACTION;
const _inProgress = PhoneValidationStatus.PHONE_VALIDATION_STATUS_IN_PROGRESS;
const _succeeded = PhoneValidationStatus.PHONE_VALIDATION_STATUS_SUCCEEDED;
const _failed = PhoneValidationStatus.PHONE_VALIDATION_STATUS_FAILED;
const _timedOut = PhoneValidationStatus.PHONE_VALIDATION_STATUS_TIMED_OUT;
const _cancelled = PhoneValidationStatus.PHONE_VALIDATION_STATUS_CANCELLED;

const _codeMethod = 'virtual_car.cluster_code';
const _buttonMethod = 'virtual_car.button';
const _codeTitle = 'Code on the simulated cluster';
const _buttonTitle = 'Simulated button';

const _config = PairedVehicleConfig(
  vehicleId: virtual_car.kPlatformName,
  bleRemoteId: '00:11:22:33:44:55',
  transportPreference: TransportPreference.ble,
);

PhoneValidationSession _codeSession({int attemptsLeft = 3}) =>
    PhoneValidationSession(
      methodId: _codeMethod,
      kind: _codeEntry,
      status: _inProgress,
      codeLength: 6,
      attemptsLeft: attemptsLeft,
      expiresInS: 100,
    );

PhoneValidationSession _buttonSession() => PhoneValidationSession(
  methodId: _buttonMethod,
  kind: _inCar,
  status: _inProgress,
  expiresInS: 100,
);

CommandResponse _ok([SystemCommandResult? result]) =>
    CommandResponse(success: true, systemResult: result);

CommandResponse _session(PhoneValidationSession session) =>
    _ok(SystemCommandResult(validationSession: session));

CommandResponse _wrongCode(PhoneValidationSession session) => CommandResponse(
  errorMessage: 'wrong code',
  statusCode: CommandStatusCode.COMMAND_STATUS_CODE_FAILED,
  systemResult: SystemCommandResult(validationSession: session),
);

CommandResponse _refused(
  PhoneValidationRefusalReason reason, {
  int cooldownS = 0,
}) => CommandResponse(
  errorMessage: 'text from the device',
  statusCode: CommandStatusCode.COMMAND_STATUS_CODE_FAILED,
  systemResult: SystemCommandResult(
    validationRefusal: PhoneValidationRefusal(
      reason: reason,
      cooldownS: cooldownS,
    ),
  ),
);

/// A device that answers the validation commands.
class _Device implements CarTransport {
  final _controller = StreamController<DeviceToApp>.broadcast();
  final sent = <SystemCommand>[];

  var methods = <PhoneValidationMethod>[
    PhoneValidationMethod(
      methodId: _codeMethod,
      kind: _codeEntry,
      needsApproval: true,
      available: true,
    ),
    PhoneValidationMethod(
      methodId: _buttonMethod,
      kind: _inCar,
      available: true,
    ),
  ];

  /// The answer to a start, by method.
  CommandResponse Function(String methodId) onStart = (id) =>
      _session(id == _codeMethod ? _codeSession() : _buttonSession());

  CommandResponse Function(String code) onSubmit = (_) => _session(
    PhoneValidationSession(
      methodId: _codeMethod,
      kind: _codeEntry,
      status: _succeeded,
    ),
  );

  void report({PhoneValidationSession? session, CanAccessState? canAccess}) {
    _controller.add(
      DeviceToApp(
        platformId: virtual_car.kPlatformId,
        stateUpdate: StateUpdate(
          systemState: SystemState(
            canAccess: canAccess,
            phoneAccess: PhoneAccessState(
              trust: PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED,
              validation: session,
            ),
          ),
        ),
      ),
    );
  }

  Iterable<SystemCommand> get starts =>
      sent.where((c) => c.hasStartPhoneValidation());
  Iterable<SystemCommand> get cancels =>
      sent.where((c) => c.hasCancelPhoneValidation());
  Iterable<SystemCommand> get lists =>
      sent.where((c) => c.hasListPhoneValidationMethods());

  CommandResponse _answer(SystemCommand command) {
    if (command.hasStartPhoneValidation()) {
      return onStart(command.startPhoneValidation.methodId);
    }
    if (command.hasSubmitPhoneValidationCode()) {
      return onSubmit(command.submitPhoneValidationCode.code);
    }
    if (command.hasListPhoneValidationMethods()) {
      return _ok(
        SystemCommandResult(
          validationMethods: PhoneValidationMethods(methods: methods),
        ),
      );
    }
    return _ok();
  }

  @override
  final TransportType transportType = TransportType.ble;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async {
    if (!message.hasSystemCommand()) return;
    sent.add(message.systemCommand);
    final response = _answer(message.systemCommand)
      ..messageId = message.messageId;
    scheduleMicrotask(
      () => _controller.add(
        DeviceToApp(
          platformId: virtual_car.kPlatformId,
          commandResponse: response,
        ),
      ),
    );
  }

  @override
  void dispose() => _controller.close();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

/// The screen on top of a page, so that closing it can be seen.
Future<_Device> _pump(
  WidgetTester tester, {
  _Device? device,
  void Function(_Device)? before,
}) async {
  tester.view.physicalSize = const Size(400, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final transport = device ?? _Device();
  addTearDown(transport.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
        initialPairedVehiclesProvider.overrideWithValue(
          PairedVehicles.of(_config),
        ),
        carTransportProvider.overrideWithValue(transport),
      ],
      child: MaterialApp(
        theme: buildAppTheme(defaultSkin, Brightness.light),
        // Keeps what the device reports, as the dashboard does.
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(phoneAccessStateProvider);
            return Scaffold(
              body: TextButton(
                onPressed: () => PhoneValidationScreen.open(context),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  before?.call(transport);
  await tester.pump();
  await tester.pump();
  await tester.tap(find.text('open'));
  await _settle(tester);
  return transport;
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(ValueKey('validation-key-$digit')));
    await tester.pump();
  }
  await tester.pump();
  await tester.pump();
}

/// Ends the providers and what they still wait for.
Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 16));
}

bool get _isOpen => find.byType(PhoneValidationScreen).evaluate().isNotEmpty;

void main() {
  group('the methods', () {
    testWidgets('are listed in the device order', (tester) async {
      await _pump(tester);
      final code = tester.getTopLeft(find.text(_codeTitle)).dy;
      final button = tester.getTopLeft(find.text(_buttonTitle)).dy;
      expect(code, lessThan(button));
      await _end(tester);
    });

    testWidgets('an unknown one gets the generic text of its kind', (
      tester,
    ) async {
      final device = _Device()
        ..methods = [
          PhoneValidationMethod(
            methodId: 'future.car',
            kind: _codeEntry,
            available: true,
          ),
          PhoneValidationMethod(methodId: 'future.other', available: true),
        ];
      await _pump(tester, device: device);
      expect(find.text('Code shown in the car'), findsOneWidget);
      expect(find.text('Action in the car'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('a greyed-out one does nothing and offers nothing', (
      tester,
    ) async {
      final device = _Device()
        ..methods = [
          PhoneValidationMethod(methodId: _buttonMethod, kind: _inCar),
        ];
      await _pump(tester, device: device);
      await tester.tap(find.text(_buttonTitle));
      await _settle(tester);
      expect(device.starts, isEmpty);
      expect(find.text('Review'), findsNothing);
      await _end(tester);
    });

    testWidgets('one waiting for the approval offers it', (tester) async {
      final device = _Device()
        ..methods = [
          PhoneValidationMethod(
            methodId: _codeMethod,
            kind: _codeEntry,
            needsApproval: true,
          ),
        ];
      await _pump(tester, device: device);
      expect(find.text('Review'), findsNothing);
      device.report(
        canAccess: CanAccessState(
          carIdentityConfirmed: true,
          approval: CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_NOT_APPROVED,
        ),
      );
      await _settle(tester);
      expect(find.text('Needs vehicle control approval'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('are read again, so one can become available', (tester) async {
      final device = _Device()
        ..methods = [
          PhoneValidationMethod(methodId: _buttonMethod, kind: _inCar),
        ];
      await _pump(tester, device: device);
      final before = device.lists.length;
      device.methods = [
        PhoneValidationMethod(
          methodId: _buttonMethod,
          kind: _inCar,
          available: true,
        ),
      ];
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      expect(device.lists.length, greaterThan(before));
      await tester.tap(find.text(_buttonTitle));
      await _settle(tester);
      expect(device.starts, hasLength(1));
      await _end(tester);
    });

    testWidgets("an old result isn't shown as this validation's end", (
      tester,
    ) async {
      final device = _Device();
      await _pump(tester, device: device);
      device.report(
        session: PhoneValidationSession(
          methodId: _codeMethod,
          kind: _codeEntry,
          status: _timedOut,
        ),
      );
      await _settle(tester);
      expect(find.text(_codeTitle), findsOneWidget);
      expect(find.text("Time's up"), findsNothing);
      await _end(tester);
    });

    testWidgets('Not now closes', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Not now'));
      await _settle(tester);
      expect(_isOpen, isFalse);
      await _end(tester);
    });
  });

  group('code entry', () {
    Future<_Device> startCode(WidgetTester tester, {_Device? device}) async {
      final transport = await _pump(tester, device: device);
      await tester.tap(find.text(_codeTitle));
      await _settle(tester);
      return transport;
    }

    testWidgets('submits once every digit is in, then says it worked', (
      tester,
    ) async {
      final device = await startCode(tester);
      expect(find.text('Enter the code shown in the car'), findsOneWidget);
      expect(device.starts.single.startPhoneValidation.methodId, _codeMethod);

      await _type(tester, '12345');
      expect(
        device.sent.where((c) => c.hasSubmitPhoneValidationCode()),
        isEmpty,
      );
      await _type(tester, '6');
      await _settle(tester);
      expect(device.sent.last.submitPhoneValidationCode.code, '123456');
      expect(find.text('This phone is validated'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(_isOpen, isFalse);
      expect(device.cancels, isEmpty, reason: 'nothing is running any more');
      await _end(tester);
    });

    testWidgets('delete removes the last digit', (tester) async {
      final device = await startCode(tester);
      await _type(tester, '12345');
      await tester.tap(find.byKey(const ValueKey('validation-key-delete')));
      await tester.pump();
      await _type(tester, '79');
      await _settle(tester);
      expect(device.sent.last.submitPhoneValidationCode.code, '123479');
      await _end(tester);
    });

    testWidgets('a wrong code says how many attempts are left', (tester) async {
      final device = _Device()
        ..onSubmit = (_) => _wrongCode(_codeSession(attemptsLeft: 2));
      await startCode(tester, device: device);
      await _type(tester, '000000');
      await _settle(tester);
      expect(find.text('Wrong code. 2 attempts left.'), findsOneWidget);

      // Typing starts over and clears the message.
      await _type(tester, '1');
      expect(find.textContaining('Wrong code'), findsNothing);
      expect(find.text('0'), findsOneWidget, reason: 'only the keypad 0');
      await _end(tester);
    });

    testWidgets('the last wrong code starts the cooldown', (tester) async {
      final device = _Device()
        ..onSubmit = (_) => _wrongCode(
          PhoneValidationSession(
            methodId: _codeMethod,
            kind: _codeEntry,
            status: _failed,
            cooldownS: 252,
          ),
        );
      await startCode(tester, device: device);
      await _type(tester, '000000');
      await _settle(tester);
      expect(find.text('Too many wrong codes'), findsOneWidget);
      expect(find.textContaining('try again in 4:1'), findsOneWidget);

      await tester.pump(const Duration(seconds: 15));
      expect(find.textContaining('try again in 3:5'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('shows a new code', (tester) async {
      final device = await startCode(tester);
      await _type(tester, '12');
      await tester.tap(find.text('Show a new code'));
      await _settle(tester);
      expect(device.starts, hasLength(2));
      expect(find.text('1'), findsOneWidget, reason: 'only the keypad 1');
      await _end(tester);
    });

    testWidgets('counts the time left down', (tester) async {
      await startCode(tester);
      expect(find.textContaining(RegExp(r'^1:[34]')), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      expect(find.textContaining(RegExp(r'^1:[12]')), findsOneWidget);
      await _end(tester);
    });

    testWidgets('timing out offers to start again', (tester) async {
      final device = await startCode(tester);
      device.report(
        session: PhoneValidationSession(
          methodId: _codeMethod,
          kind: _codeEntry,
          status: _timedOut,
        ),
      );
      await _settle(tester);
      expect(find.text("Time's up"), findsOneWidget);

      await tester.tap(find.text('Start again'));
      await _settle(tester);
      expect(device.starts, hasLength(2));
      expect(find.text('Enter the code shown in the car'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('a session the car ended goes back to the methods', (
      tester,
    ) async {
      final device = await startCode(tester);
      device.report(
        session: PhoneValidationSession(
          methodId: _codeMethod,
          kind: _codeEntry,
          status: _cancelled,
        ),
      );
      await _settle(tester);
      expect(find.text(_codeTitle), findsOneWidget);
      await _end(tester);
    });

    testWidgets('Cancel ends the session and goes back', (tester) async {
      final device = await startCode(tester);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(device.cancels, hasLength(1));
      expect(find.text(_codeTitle), findsOneWidget);
      await _end(tester);
    });

    testWidgets('closing the screen ends the session', (tester) async {
      final device = await startCode(tester);
      await tester.tap(find.byTooltip('Close'));
      await _settle(tester);
      expect(_isOpen, isFalse);
      expect(device.cancels, hasLength(1));
      await _end(tester);
    });

    testWidgets('picks up a session already running', (tester) async {
      await _pump(tester, before: (d) => d.report(session: _codeSession()));
      expect(find.text('Enter the code shown in the car'), findsOneWidget);
      await _end(tester);
    });
  });

  group('in-car action', () {
    testWidgets('gives the instructions and waits for the car', (tester) async {
      final device = await _pump(tester);
      await tester.tap(find.text(_buttonTitle));
      await _settle(tester);
      expect(find.text('Do this in the car'), findsOneWidget);
      expect(find.textContaining('0x400'), findsOneWidget);
      expect(find.text('Waiting for the car…'), findsOneWidget);

      device.report(session: _buttonSession());
      await _settle(tester);
      expect(find.text('Do this in the car'), findsOneWidget);

      device.report(
        session: PhoneValidationSession(
          methodId: _buttonMethod,
          kind: _inCar,
          status: _succeeded,
        ),
      );
      await _settle(tester);
      expect(find.text('This phone is validated'), findsOneWidget);
      await _end(tester);
    });
  });

  group('a refused start', () {
    const other = PhoneValidationRefusalReason
        .PHONE_VALIDATION_REFUSAL_REASON_OTHER_PHONE_VALIDATING;
    const cooling = PhoneValidationRefusalReason
        .PHONE_VALIDATION_REFUSAL_REASON_COOLING_DOWN;
    const notNow = PhoneValidationRefusalReason
        .PHONE_VALIDATION_REFUSAL_REASON_METHOD_NOT_AVAILABLE_NOW;

    testWidgets('another phone is validating, and trying again', (
      tester,
    ) async {
      final device = _Device()..onStart = (_) => _refused(other);
      await _pump(tester, device: device);
      await tester.tap(find.text(_codeTitle));
      await _settle(tester);
      expect(find.text('Another phone is validating'), findsOneWidget);

      device.onStart = (_) => _session(_codeSession());
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(device.starts, hasLength(2));
      expect(find.text('Enter the code shown in the car'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('the cooldown, even from another phone', (tester) async {
      final device = _Device()
        ..onStart = (_) => _refused(cooling, cooldownS: 90);
      await _pump(tester, device: device);
      await tester.tap(find.text(_codeTitle));
      await _settle(tester);
      expect(find.text('Too many wrong codes'), findsOneWidget);
      expect(find.textContaining('try again in 1:'), findsOneWidget);
      await _end(tester);
    });

    testWidgets("says it in the app's own words", (tester) async {
      final device = _Device()..onStart = (_) => _refused(notNow);
      await _pump(tester, device: device);
      await tester.tap(find.text(_codeTitle));
      await _settle(tester);
      expect(find.textContaining("can't start right now"), findsOneWidget);
      expect(find.textContaining('text from the device'), findsNothing);
      expect(find.text(_codeTitle), findsOneWidget);
      await _end(tester);
    });
  });
}
