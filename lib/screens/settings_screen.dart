import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:open_car_app/config/button_style_config.dart';
import 'package:open_car_app/formatting/device_info.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/models/dashboard_layout.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/dashboard_layout_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/theme_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/dashboard/dashboard_header.dart'
    show formatUpdatedAgo;
import 'package:open_car_app/screens/dashboard/dashboard_screen.dart'
    show dashboardTierFor;
import 'package:open_car_app/screens/help_screen.dart';
import 'package:open_car_app/screens/paired_phones_screen.dart';
import 'package:open_car_app/screens/theme_gallery_screen.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/transport/http_transport.dart';
import 'package:open_car_app/widgets/can_access_section.dart';
import 'package:open_car_app/widgets/settings_rows.dart';

/// Shown for what the device hasn't reported.
const _notReported = '—';

final _appVersionProvider = FutureProvider.autoDispose<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
  retry: (_, _) => null,
);

/// The settings of the current vehicle and the app. See "Settings" in
/// `docs/ui-screens.md`.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Completes with whether the user asked to edit the dashboard.
  static Future<bool> open(BuildContext context) async =>
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const SettingsScreen()),
      ) ??
      false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(selectedVehicleProvider);
    // Briefly null while unpairing, before the router shows the wizard.
    if (vehicle == null) return const SizedBox.shrink();
    final transport = ref.watch(transportTypeProvider);
    final tier = dashboardTierFor(transport);
    final bluetooth = tier == DashboardTier.bluetooth;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _VehicleSummary(vehicle: vehicle, tier: tier),
          const SettingsSectionTitle('Dashboard'),
          _dashboardCard(context, ref, tier),
          const SettingsSectionTitle('Vehicle'),
          _vehicleCard(context, ref, vehicle, bluetooth: bluetooth),
          if (bluetooth) ...[
            const SettingsSectionTitle('Car access'),
            const CanAccessSection(),
            const SettingsSectionTitle('Device'),
            _deviceCard(context, ref),
          ] else ...[
            const SettingsSectionTitle('Device'),
            const _ConnectOverBluetoothNote(),
          ],
          if (kDebugMode) ...[
            const SettingsSectionTitle('Debug'),
            _debugCard(context, ref, transport),
          ],
          const SettingsSectionTitle('About'),
          _aboutCard(context, ref),
        ],
      ),
    );
  }

  Widget _dashboardCard(
    BuildContext context,
    WidgetRef ref,
    DashboardTier tier,
  ) {
    final editable = DashboardGrid.of(tier).editing != TileGridEditing.none;
    return SettingsCard(
      children: [
        SettingsControlRow(
          title: 'Theme',
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {ref.watch(themeModeProvider)},
            onSelectionChanged: (picked) =>
                ref.read(themeModeProvider.notifier).set(picked.single),
          ),
        ),
        SettingsControlRow(
          title: 'Button style',
          child: SegmentedButton<DashboardButtonStyle>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: DashboardButtonStyle.titled,
                label: Text('Icon and title'),
              ),
              ButtonSegment(
                value: DashboardButtonStyle.iconOnly,
                label: Text('Icon only'),
              ),
            ],
            selected: {ref.watch(buttonStyleProvider)},
            onSelectionChanged: (picked) =>
                ref.read(buttonStyleProvider.notifier).set(picked.single),
          ),
        ),
        SettingsRow(
          title: 'Edit dashboard',
          subtitle: editable
              ? 'Rearrange, resize, add or remove tiles'
              : 'Connect over Bluetooth to edit the tiles',
          enabled: editable,
          opensScreen: true,
          onTap: () => Navigator.of(context).pop(true),
        ),
        SettingsRow(
          title: 'Reset dashboard layout',
          subtitle: 'Puts every layout back to its default',
          onTap: () => _resetLayouts(context, ref),
        ),
        const SettingsRow(title: 'Units', value: 'Follow the car'),
      ],
    );
  }

  Widget _vehicleCard(
    BuildContext context,
    WidgetRef ref,
    VehicleDefinition vehicle, {
    required bool bluetooth,
  }) {
    final phones = bluetooth ? ref.watch(pairedPhonesProvider).value : null;
    return SettingsCard(
      children: [
        if (bluetooth)
          SettingsRow(
            title: 'Paired phones',
            value: phones == null
                ? null
                : '${phones.length} · '
                      '${phones.where((p) => p.isValidated).length} validated',
            opensScreen: true,
            onTap: () => PairedPhonesScreen.open(context),
          ),
        SettingsRow(
          title: 'Unpair vehicle',
          subtitle: 'Forgets it in this app',
          danger: true,
          onTap: () => _unpair(context, ref, vehicle),
        ),
      ],
    );
  }

  Widget _deviceCard(BuildContext context, WidgetRef ref) {
    final system = ref.watch(vehicleStateProvider.select((s) => s.system));
    String reported(String? value) =>
        value == null || value.isEmpty ? _notReported : value;
    return SettingsCard(
      children: [
        SettingsRow(
          title: 'Firmware',
          value: reported(system?.firmwareVersion),
        ),
        SettingsRow(title: 'Hardware', value: reported(system?.hardwareType)),
        SettingsRow(
          title: 'Running for',
          value: reported(formatRunningTime(system?.uptimeS ?? 0)),
        ),
        SettingsRow(
          title: 'Mobile signal',
          value: reported(formatMobileSignal(system?.lteRssi ?? 0)),
        ),
        SettingsRow(
          title: 'Restart device',
          onTap: () => _restart(context, ref),
        ),
      ],
    );
  }

  Widget _debugCard(
    BuildContext context,
    WidgetRef ref,
    TransportType transport,
  ) {
    return SettingsCard(
      children: [
        SettingsRow(
          title: 'Theme gallery',
          opensScreen: true,
          onTap: () => ThemeGalleryScreen.open(context),
        ),
        if (transport == TransportType.http)
          SettingsRow(
            title: 'Toggle simulation',
            onTap: () => _toggleSimulation(context, ref),
          ),
      ],
    );
  }

  Widget _aboutCard(BuildContext context, WidgetRef ref) {
    return SettingsCard(
      children: [
        SettingsRow(
          title: 'Help',
          subtitle:
              "Pairing mode, and what to do when the app can't find the "
              'device',
          opensScreen: true,
          onTap: () => HelpScreen.open(context),
        ),
        SettingsRow(
          title: 'Open-source licenses',
          opensScreen: true,
          onTap: () =>
              showLicensePage(context: context, applicationName: 'Open Car'),
        ),
        SettingsRow(
          title: 'App version',
          value: ref.watch(_appVersionProvider).value ?? _notReported,
        ),
      ],
    );
  }

  Future<void> _resetLayouts(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmSettingsAction(
      context,
      title: 'Reset every layout?',
      message:
          "All of this vehicle's dashboard layouts go back to their defaults, "
          'and your changes to them are lost.',
      action: 'Reset',
    );
    if (!confirmed || !context.mounted) return;
    ref.read(savedLayoutsProvider.notifier).resetAll();
    _showMessage(context, 'Dashboard layouts reset.');
  }

  Future<void> _unpair(
    BuildContext context,
    WidgetRef ref,
    VehicleDefinition vehicle,
  ) async {
    final confirmed = await confirmSettingsAction(
      context,
      title: 'Unpair ${vehicle.displayName}?',
      message:
          'The vehicle is removed from this app. To use it again, put the '
          'device in pairing mode and pair again (see Help).',
      action: 'Unpair',
      danger: true,
    );
    if (!confirmed || !context.mounted) return;
    Navigator.of(context).pop(false);
    await ref.read(pairedVehicleProvider.notifier).unpair();
  }

  Future<void> _restart(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmSettingsAction(
      context,
      title: 'Restart the device?',
      message:
          'It stops listening to the car for a moment, and the Bluetooth '
          'connection drops until it is back.',
      action: 'Restart',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(vehicleStateProvider.notifier)
          .sendUnansweredSystemCommand(
            SystemCommand(restartCommand: RestartCommand()),
          );
      if (context.mounted) _showMessage(context, 'Restart requested.');
    } catch (e) {
      if (context.mounted) _showMessage(context, '$e');
    }
  }

  Future<void> _toggleSimulation(BuildContext context, WidgetRef ref) async {
    final transport = ref.read(carTransportProvider);
    if (transport is! HttpCarTransport) return;
    try {
      await transport.simulate();
    } catch (e) {
      if (context.mounted) _showMessage(context, 'Simulation error: $e');
    }
  }

  void _showMessage(BuildContext context, String message) =>
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
}

/// The current vehicle: its name, platform and how it is connected.
class _VehicleSummary extends ConsumerWidget {
  const _VehicleSummary({required this.vehicle, required this.tier});

  final VehicleDefinition vehicle;
  final DashboardTier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final snapshot = ref.watch(vehicleStateProvider);
    final live = snapshot.isStateLive;
    final connection = live
        ? switch (tier) {
            DashboardTier.remote => 'Connected remotely',
            DashboardTier.bluetooth => 'Connected over Bluetooth',
          }
        : [
            'Offline',
            if (snapshot.lastUpdated case final updated?)
              'Updated ${formatUpdatedAgo(updated, DateTime.now())}',
          ].join(' · ');
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            spacing: 16,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: ShapeDecoration(
                  color: tokens.accentContainer,
                  shape: tokens.radiusRound.shape(),
                ),
                child: Icon(
                  Symbols.directions_car,
                  color: tokens.onAccentContainer,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(vehicle.displayName, style: AppTextStyles.vehicleName),
                    Text(
                      vehicle.platformLabel,
                      style: AppTextStyles.caption.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    Row(
                      spacing: 6,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: live ? tokens.accent : tokens.textSecondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            connection,
                            style: AppTextStyles.caption.copyWith(
                              color: tokens.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Stands in for the Bluetooth-only sections on the remote tier.
class _ConnectOverBluetoothNote extends StatelessWidget {
  const _ConnectOverBluetoothNote();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Icon(Symbols.bluetooth, color: tokens.textSecondary),
              Expanded(
                child: Text(
                  'Stand near the vehicle and connect over Bluetooth to see '
                  'the paired phones, car access, the device and the '
                  'developer options.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
