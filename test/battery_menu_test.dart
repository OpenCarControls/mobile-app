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
}
