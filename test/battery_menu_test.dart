import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/cars/egmp/widgets/battery_menu.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';

Future<void> _pump(
  WidgetTester tester, {
  required AdvancedState state,
  required bool isLive,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: BatteryMenu(
        advancedState: state,
        isLive: isLive,
        formatTemperature: (c) => '${c.toStringAsFixed(1)}°C',
        onBack: () {},
      ),
    ),
  ),
);

final _state = AdvancedState(
  batteryVoltage: 798,
  instantaneousPowerWatt: -12500,
  batteryMinimumTemperature: 21.5,
  batteryMaximumTemperature: 24.0,
  gear: AdvancedState_Gear.GEAR_DRIVE,
  powerState: AdvancedState_PowerState.POWER_STATE_READY,
);

void main() {
  testWidgets('shows every advanced value when live', (tester) async {
    await _pump(tester, state: _state, isLive: true);

    expect(find.text('Not live'), findsNothing);
    expect(find.text('798 V'), findsOneWidget);
    expect(find.text('12.5 kW (discharging)'), findsOneWidget);
    expect(find.text('21.5°C'), findsOneWidget);
    expect(find.text('24.0°C'), findsOneWidget);
    expect(find.text('Drive'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('hides cached values and says so when not live', (tester) async {
    await _pump(tester, state: _state, isLive: false);

    expect(find.text('Not live'), findsOneWidget);
    expect(find.text('798 V'), findsNothing);
    expect(find.text('—'), findsNWidgets(6));
  });

  testWidgets('shows a dash for fields the car has not reported', (
    tester,
  ) async {
    await _pump(
      tester,
      state: AdvancedState(batteryVoltage: 800),
      isLive: true,
    );

    expect(find.text('800 V'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(5));
  });

  testWidgets('labels charging power', (tester) async {
    await _pump(
      tester,
      state: AdvancedState(instantaneousPowerWatt: 7200),
      isLive: true,
    );

    expect(find.text('7.2 kW (charging)'), findsOneWidget);
  });

  _preconditioningTests();
}

Future<void> _pumpToggle(
  WidgetTester tester, {
  required AdvancedState_PreconditioningState? state,
  bool isLive = true,
  ValueChanged<bool>? onChanged,
  bool pending = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: BatteryMenu(
        advancedState: state == null
            ? AdvancedState()
            : AdvancedState(preconditioningState: state),
        isLive: isLive,
        formatTemperature: (c) => '$c',
        onBack: () {},
        onPreconditioningChanged: onChanged,
        isPreconditioningPending: pending,
      ),
    ),
  ),
);

bool _switchValue(WidgetTester tester) =>
    tester.widget<Switch>(find.byType(Switch)).value;

void _preconditioningTests() {
  group('preconditioning toggle', () {
    testWidgets('is off and sends enable when tapped', (tester) async {
      final sent = <bool>[];
      await _pumpToggle(
        tester,
        state: AdvancedState_PreconditioningState.PRECONDITIONING_STATE_OFF,
        onChanged: sent.add,
      );

      expect(_switchValue(tester), isFalse);
      await tester.tap(find.byType(Switch));
      expect(sent, [true]);
    });

    testWidgets('is on while preparing and says the heater is not on', (
      tester,
    ) async {
      final sent = <bool>[];
      await _pumpToggle(
        tester,
        state:
            AdvancedState_PreconditioningState.PRECONDITIONING_STATE_PREPARING,
        onChanged: sent.add,
      );

      expect(_switchValue(tester), isTrue);
      expect(find.textContaining('Preparing'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      expect(sent, [false]);
    });

    testWidgets('is on while heating', (tester) async {
      await _pumpToggle(
        tester,
        state: AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING,
        onChanged: (_) {},
      );

      expect(_switchValue(tester), isTrue);
      expect(find.text('Heating the battery'), findsOneWidget);
    });

    testWidgets('is disabled without a command callback (not BLE)', (
      tester,
    ) async {
      await _pumpToggle(
        tester,
        state: AdvancedState_PreconditioningState.PRECONDITIONING_STATE_OFF,
      );

      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    });

    testWidgets('is disabled and off when the state is not live', (
      tester,
    ) async {
      await _pumpToggle(
        tester,
        state: AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING,
        isLive: false,
        onChanged: (_) {},
      );

      expect(_switchValue(tester), isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    });

    testWidgets('is disabled while a command is pending', (tester) async {
      await _pumpToggle(
        tester,
        state: AdvancedState_PreconditioningState.PRECONDITIONING_STATE_OFF,
        onChanged: (_) {},
        pending: true,
      );

      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
