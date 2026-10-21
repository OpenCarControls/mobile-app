import 'package:flutter/material.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';

/// The advanced state only arrives over BLE, so a cached value could be long out of
/// date: when it isn't live the values are hidden rather than shown as current.
class BatteryMenu extends StatelessWidget {
  const BatteryMenu({
    super.key,
    required this.advancedState,
    required this.isLive,
    required this.formatTemperature,
    required this.onBack,
    this.onPreconditioningChanged,
    this.isPreconditioningPending = false,
    this.shrinkWrap = false,
    this.physics,
  });

  final AdvancedState advancedState;
  final bool isLive;
  final String Function(double celsius) formatTemperature;
  final VoidCallback onBack;

  /// Sends the preconditioning command. Null when it can't be sent (advanced commands
  /// are BLE-only), which disables the toggle.
  final ValueChanged<bool>? onPreconditioningChanged;

  /// A preconditioning command is in flight.
  final bool isPreconditioningPending;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String title, String? value) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(
        isLive && value != null ? value : '—',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ListView(
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: onBack,
            ),
            title: Text(
              'Battery & Drivetrain',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (!isLive)
            const ListTile(
              leading: Icon(Icons.bluetooth_disabled),
              title: Text('Not live'),
              subtitle: Text(
                'These values are only available while connected over Bluetooth.',
              ),
            ),
          _buildPreconditioningToggle(context),
          row(
            Icons.bolt,
            'Battery voltage',
            advancedState.hasBatteryVoltage()
                ? '${advancedState.batteryVoltage} V'
                : null,
          ),
          row(
            Icons.electric_meter,
            'Battery power',
            advancedState.hasInstantaneousPowerWatt()
                ? _formatBatteryPower(advancedState.instantaneousPowerWatt)
                : null,
          ),
          row(
            Icons.thermostat,
            'Battery temperature (min)',
            advancedState.hasBatteryMinimumTemperature()
                ? formatTemperature(advancedState.batteryMinimumTemperature)
                : null,
          ),
          row(
            Icons.thermostat,
            'Battery temperature (max)',
            advancedState.hasBatteryMaximumTemperature()
                ? formatTemperature(advancedState.batteryMaximumTemperature)
                : null,
          ),
          row(Icons.settings_applications, 'Gear', _gearLabel(advancedState)),
          row(
            Icons.power_settings_new,
            'Power state',
            _powerStateLabel(advancedState),
          ),
        ],
      ),
    );
  }

  /// The switch follows the car's reported state (including the "preparing" step, where
  /// the heater isn't on yet) rather than the last tap, so it can't drift from the car.
  Widget _buildPreconditioningToggle(BuildContext context) {
    final preconditioning = isLive && advancedState.hasPreconditioningState()
        ? advancedState.preconditioningState
        : AdvancedState_PreconditioningState.PRECONDITIONING_STATE_UNSPECIFIED;
    final isOn =
        preconditioning ==
            AdvancedState_PreconditioningState
                .PRECONDITIONING_STATE_PREPARING ||
        preconditioning ==
            AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING;
    final subtitle = switch (preconditioning) {
      AdvancedState_PreconditioningState.PRECONDITIONING_STATE_PREPARING =>
        'Preparing: the battery heater isn\'t on yet',
      AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING =>
        'Heating the battery',
      AdvancedState_PreconditioningState.PRECONDITIONING_STATE_OFF => 'Off',
      _ => null,
    };
    final onChanged = onPreconditioningChanged;
    return SwitchListTile(
      secondary: isPreconditioningPending
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.local_fire_department),
      title: const Text('Battery preconditioning'),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: isOn,
      onChanged: !isLive || onChanged == null || isPreconditioningPending
          ? null
          : onChanged,
    );
  }
}

/// Positive means charging, negative discharging (the sign the contract uses).
String _formatBatteryPower(int watt) {
  final kw = (watt.abs() / 1000).toStringAsFixed(1);
  if (watt > 0) return '$kw kW (charging)';
  if (watt < 0) return '$kw kW (discharging)';
  return '0.0 kW';
}

String? _gearLabel(AdvancedState s) => !s.hasGear()
    ? null
    : switch (s.gear) {
        AdvancedState_Gear.GEAR_PARK => 'Park',
        AdvancedState_Gear.GEAR_REVERSE => 'Reverse',
        AdvancedState_Gear.GEAR_NEUTRAL => 'Neutral',
        AdvancedState_Gear.GEAR_DRIVE => 'Drive',
        _ => null,
      };

String? _powerStateLabel(AdvancedState s) => !s.hasPowerState()
    ? null
    : switch (s.powerState) {
        AdvancedState_PowerState.POWER_STATE_OFF => 'Off',
        AdvancedState_PowerState.POWER_STATE_ACCESSORY => 'Accessory',
        AdvancedState_PowerState.POWER_STATE_ON => 'On',
        AdvancedState_PowerState.POWER_STATE_READY => 'Ready',
        _ => null,
      };
