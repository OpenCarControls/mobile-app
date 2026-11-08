import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/constants.g.dart' as virtual_car;
import 'package:open_car_app/config/button_style_config.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/config/saved_layouts_config.dart';
import 'package:open_car_app/formatting/device_info.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/models/dashboard_layout.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/dashboard_layout_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/screens/dashboard/dashboard_screen.dart';
import 'package:open_car_app/screens/paired_phones_screen.dart';
import 'package:open_car_app/screens/settings_screen.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/tiles/tile_editing.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

const _bonded = PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED;
const _validated = PhoneTrustLevel.PHONE_TRUST_LEVEL_VALIDATED;

/// A device that answers the paired phones list, and nothing else.
class _FakeTransport implements CarTransport {
  _FakeTransport(this.transportType);

  final _controller = StreamController<DeviceToApp>.broadcast();
  final sent = <AppToDevice>[];
  var phones = <PairedPhone>[
    PairedPhone(deviceId: [1, 2, 0x3F, 0x9A], trust: _validated),
    PairedPhone(
      deviceId: [3, 4, 0x81, 0xC4],
      trust: _bonded,
      isRequester: true,
    ),
  ];

  /// What the device answers a phone removal with, if anything.
  CommandResponse? removalAnswer;

  void emit(DeviceToApp msg) => _controller.add(msg);

  void reportAccess(PhoneAccessState access, {CanAccessState? canAccess}) =>
      emit(
        DeviceToApp(
          platformId: virtual_car.kPlatformId,
          stateUpdate: StateUpdate(
            systemState: SystemState(
              firmwareVersion: 'v1.4.2',
              hardwareType: 'ESP32-S3',
              uptimeS: 273600,
              lteRssi: -70,
              phoneAccess: access,
              canAccess: canAccess,
            ),
          ),
        ),
      );

  void _answer(AppToDevice message, CommandResponse response) =>
      scheduleMicrotask(
        () => emit(
          DeviceToApp(
            platformId: virtual_car.kPlatformId,
            commandResponse: response..messageId = message.messageId,
          ),
        ),
      );

  @override
  final TransportType transportType;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async {
    sent.add(message);
    if (message.systemCommand.hasListPairedPhones()) {
      _answer(
        message,
        CommandResponse(
          success: true,
          systemResult: SystemCommandResult(
            pairedPhones: PairedPhones(phones: phones),
          ),
        ),
      );
    } else if (message.systemCommand.hasRemovePairedPhone()) {
      if (removalAnswer case final answer?) _answer(message, answer);
    }
  }

  @override
  void dispose() => _controller.close();
}

const _config = PairedVehicleConfig(
  vehicleId: virtual_car.kPlatformName,
  bleRemoteId: '00:11:22:33:44:55',
  transportPreference: TransportPreference.ble,
);

Future<(_FakeTransport, ProviderContainer)> _pump(
  WidgetTester tester, {
  TransportType type = TransportType.ble,
  Widget home = const SettingsScreen(),
}) async {
  // Tall enough that every row of the list is built.
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final transport = _FakeTransport(type);
  addTearDown(transport.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
        initialPairedVehicleConfigProvider.overrideWithValue(_config),
        carTransportProvider.overrideWithValue(transport),
      ],
      child: MaterialApp(
        theme: buildAppTheme(defaultSkin, Brightness.light),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(home.runtimeType)),
  );
  return (transport, container);
}

/// Ends the providers, which cancels the state liveness timer.
Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 16));
}

Future<void> _tapAndConfirm(
  WidgetTester tester,
  String row,
  String action,
) async {
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, action),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Open Car',
      packageName: 'test',
      version: '0.9.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('tiers', () {
    const bluetoothOnly = [
      'Paired phones',
      'CAR ACCESS',
      'Firmware',
      'Restart device',
    ];

    testWidgets('Bluetooth shows every section and what the device reports', (
      tester,
    ) async {
      final (transport, _) = await _pump(tester);
      transport.reportAccess(PhoneAccessState(trust: _bonded));
      await tester.pumpAndSettle();

      for (final text in bluetoothOnly) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.textContaining('Stand near the vehicle'), findsNothing);
      expect(find.text('Connected over Bluetooth'), findsOneWidget);
      expect(find.text('Unpair vehicle'), findsOneWidget);
      expect(find.text('v1.4.2'), findsOneWidget);
      expect(find.text('ESP32-S3'), findsOneWidget);
      expect(find.text('3 d 4 h'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('0.9.0'), findsOneWidget);
      expect(find.text('2 · 1 validated'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('remote replaces the Bluetooth-only sections with a note', (
      tester,
    ) async {
      final (transport, _) = await _pump(tester, type: TransportType.mqtt);
      transport.emit(
        DeviceToApp(
          platformId: virtual_car.kPlatformId,
          stateUpdate: StateUpdate(
            systemState: SystemState(firmwareVersion: 'v1.4.2'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final text in bluetoothOnly) {
        expect(find.text(text), findsNothing, reason: text);
      }
      expect(find.textContaining('Stand near the vehicle'), findsOneWidget);
      expect(find.text('Connected remotely'), findsOneWidget);
      // What both tiers have.
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Unpair vehicle'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
      expect(transport.sent, isEmpty);
      await _end(tester);
    });
  });

  group('dashboard section', () {
    testWidgets('saves the button style', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Icon only'));
      await tester.pumpAndSettle();
      expect(await loadButtonStyle(), DashboardButtonStyle.iconOnly);
      await _end(tester);
    });

    testWidgets('the button style reaches the command tiles', (tester) async {
      await _pump(tester, home: const DashboardScreen());
      expect(find.text('Custom 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Icon only'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Custom 1'), findsNothing);
      await _end(tester);
    });

    testWidgets('reset puts every grid back to its default', (tester) async {
      final (_, container) = await _pump(tester);
      final layouts = container.read(savedLayoutsProvider.notifier);
      const custom = <TileLayoutEntry>[(tileId: 'x', span: TileSpan(1, 1))];
      layouts
        ..save(DashboardGrid.remote, custom)
        ..save(DashboardGrid.bluetooth, custom);

      await tester.tap(find.text('Reset dashboard layout'));
      await tester.pumpAndSettle();
      expect(container.read(savedLayoutsProvider), hasLength(2));
      await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(container.read(savedLayoutsProvider), isEmpty);
      expect(await loadSavedLayouts(), isEmpty);
      await _end(tester);
    });

    testWidgets('edit goes back to the dashboard in edit mode', (tester) async {
      await _pump(tester, home: const DashboardScreen());
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit dashboard'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(EditActionsTile), findsOneWidget);
      await _end(tester);
    });

    testWidgets("edit says why it's off on the locked remote grid", (
      tester,
    ) async {
      await _pump(tester, type: TransportType.mqtt);
      expect(
        find.text('Connect over Bluetooth to edit the tiles'),
        findsOneWidget,
      );
      await tester.tap(find.text('Edit dashboard'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await _end(tester);
    });
  });

  group('restart', () {
    testWidgets('asks, then sends it without waiting for an answer', (
      tester,
    ) async {
      final (transport, _) = await _pump(tester);
      await _tapAndConfirm(tester, 'Restart device', 'Restart');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(
        transport.sent.where((m) => m.systemCommand.hasRestartCommand()),
        hasLength(1),
      );
      expect(find.text('Restart requested.'), findsOneWidget);
      await _end(tester);
    });
  });

  group('car access', () {
    final notApproved = CanAccessState(
      carIdentityConfirmed: true,
      approval: CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_NOT_APPROVED,
    );

    testWidgets('a bonded phone can approve before any phone is validated', (
      tester,
    ) async {
      final (transport, _) = await _pump(tester);
      transport.reportAccess(
        PhoneAccessState(trust: _bonded, carHasValidatedPhone: false),
        canAccess: notApproved,
      );
      await tester.pumpAndSettle();
      final row = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Approve control of this car'),
      );
      expect(row.enabled, isTrue);
      expect(find.text('Not validated'), findsOneWidget);
      await _end(tester);
    });

    testWidgets('a bonded phone is told why once a phone is validated', (
      tester,
    ) async {
      final (transport, _) = await _pump(tester);
      transport.reportAccess(
        PhoneAccessState(trust: _bonded, carHasValidatedPhone: true),
        canAccess: notApproved,
      );
      await tester.pumpAndSettle();
      final row = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Approve control of this car'),
      );
      expect(row.enabled, isFalse);
      expect(find.textContaining('Only a validated phone'), findsOneWidget);
      await _end(tester);
    });
  });

  group('paired phones', () {
    Finder removeButton() => find.widgetWithText(OutlinedButton, 'Remove');

    testWidgets('marks this phone and each trust', (tester) async {
      await _pump(tester, home: const PairedPhonesScreen());
      expect(find.text('This phone'), findsOneWidget);
      expect(find.text('Another phone'), findsOneWidget);
      expect(find.text('ID …3F9A'), findsOneWidget);
      expect(find.text('ID …81C4'), findsOneWidget);
      expect(find.text('Validated'), findsOneWidget);
      expect(find.text('Not validated'), findsOneWidget);
      // Only the other phone can be removed.
      expect(removeButton(), findsOneWidget);
      await _end(tester);
    });

    testWidgets("a validated phone can't be removed by a bonded one", (
      tester,
    ) async {
      final (transport, _) = await _pump(
        tester,
        home: const PairedPhonesScreen(),
      );
      transport.reportAccess(
        PhoneAccessState(trust: _bonded, carHasValidatedPhone: true),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(removeButton()).onPressed, isNull);
      expect(
        find.text('Only a validated phone can remove a validated phone.'),
        findsOneWidget,
      );
      await _end(tester);
    });

    Future<void> remove(WidgetTester tester, _FakeTransport transport) async {
      await tester.tap(removeButton());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('removes the phone and updates the list', (tester) async {
      final (transport, _) = await _pump(
        tester,
        home: const PairedPhonesScreen(),
      );
      final removed = transport.phones.first;
      // The device has dropped it by the time the list is read again.
      transport.phones = [transport.phones.last];
      await remove(tester, transport);

      final sent = transport.sent.singleWhere(
        (m) => m.systemCommand.hasRemovePairedPhone(),
      );
      expect(sent.systemCommand.removePairedPhone.deviceId, removed.deviceId);
      expect(find.text('Another phone'), findsNothing);
      expect(find.textContaining('kept this phone'), findsNothing);
      await _end(tester);
    });

    testWidgets('says so when the device keeps the phone', (tester) async {
      final (transport, _) = await _pump(
        tester,
        home: const PairedPhonesScreen(),
      );
      await remove(tester, transport);
      expect(find.textContaining('kept this phone'), findsOneWidget);
      expect(find.text('Another phone'), findsOneWidget);
      await _end(tester);
    });

    testWidgets("shows the device's refusal", (tester) async {
      final (transport, _) = await _pump(
        tester,
        home: const PairedPhonesScreen(),
      );
      transport.removalAnswer = CommandResponse(
        success: false,
        errorMessage: 'Refused',
      );
      await tester.tap(removeButton());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Refused'), findsOneWidget);
      await _end(tester);
    });
  });

  test('switches use the accent when on and stay visible when off', () {
    final theme = buildAppTheme(defaultSkin, Brightness.dark);
    final tokens = theme.extension<AppTokens>()!;
    final switches = theme.switchTheme;
    const on = {WidgetState.selected};
    expect(switches.trackColor!.resolve(on), tokens.accentContainer);
    expect(switches.thumbColor!.resolve(on), tokens.onAccentContainer);
    expect(switches.thumbColor!.resolve({}), tokens.textSecondary);
    expect(switches.trackOutlineColor!.resolve({}), tokens.textSecondary);
    // Disabled keeps Material's colours.
    expect(switches.thumbColor!.resolve({WidgetState.disabled}), isNull);
    expect(switches.trackColor!.resolve({...on, WidgetState.disabled}), isNull);
  });

  group('formatting', () {
    test('running time', () {
      expect(formatRunningTime(0), isNull);
      expect(formatRunningTime(30), 'Under a minute');
      expect(formatRunningTime(720), '12 min');
      expect(formatRunningTime(14700), '4 h 5 min');
      expect(formatRunningTime(273600), '3 d 4 h');
    });

    test('mobile signal', () {
      expect(formatMobileSignal(0), isNull);
      expect(formatMobileSignal(-60), 'Excellent');
      expect(formatMobileSignal(-70), 'Good');
      expect(formatMobileSignal(-80), 'Fair');
      expect(formatMobileSignal(-100), 'Poor');
    });
  });
}
