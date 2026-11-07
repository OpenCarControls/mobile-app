import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/theme_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/help_screen.dart';
import 'package:open_car_app/screens/theme_gallery_screen.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/transport/http_transport.dart';
import 'package:open_car_app/widgets/can_access_section.dart';
import 'package:open_car_app/widgets/phone_validation_debug_section.dart';

/// What the dashboard's settings button opens: the entries of the old
/// dashboards' menus, in one list. The settings screen (#69) replaces it.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final system = ref.watch(vehicleStateProvider.select((s) => s.system));
    final isHttp = ref.watch(transportTypeProvider) == TransportType.http;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionTitle('Dashboard'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
          const _SectionTitle('Car access'),
          const CanAccessSection(),
          if (kDebugMode) const PhoneValidationDebugSection(),
          if (system != null) ...[
            const _SectionTitle('Device'),
            ListTile(
              leading: const Icon(Symbols.memory),
              title: const Text('Firmware'),
              trailing: Text(system.firmwareVersion),
            ),
            ListTile(
              leading: const Icon(Symbols.developer_board),
              title: const Text('Hardware'),
              trailing: Text(system.hardwareType.toString()),
            ),
          ],
          if (kDebugMode) ...[
            const _SectionTitle('Debug'),
            ListTile(
              leading: const Icon(Symbols.palette),
              title: const Text('Theme gallery'),
              onTap: () => ThemeGalleryScreen.open(context),
            ),
            if (isHttp)
              ListTile(
                leading: const Icon(Symbols.bug_report),
                title: const Text('Toggle simulation'),
                onTap: () => _toggleSimulation(context, ref),
              ),
          ],
          const _SectionTitle('About'),
          ListTile(
            leading: const Icon(Symbols.help),
            title: const Text('Help'),
            onTap: () => HelpScreen.open(context),
          ),
          ListTile(
            leading: const Icon(Symbols.description),
            title: const Text('Open-source licenses'),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'Open Car'),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Symbols.link_off, color: tokens.danger),
            title: Text(
              'Unpair vehicle',
              style: TextStyle(color: tokens.danger),
            ),
            onTap: () => _unpair(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSimulation(BuildContext context, WidgetRef ref) async {
    final transport = ref.read(carTransportProvider);
    if (transport is! HttpCarTransport) return;
    try {
      await transport.simulate();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Simulation error: $e')));
      }
    }
  }

  Future<void> _unpair(BuildContext context, WidgetRef ref) async {
    final tokens = context.tokens;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unpair vehicle?'),
        content: const Text(
          'This will remove the vehicle from the app and return you to the '
          'setup wizard.\n\n'
          'To pair again, the device has to be in pairing mode (see Help).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
              foregroundColor: tokens.onDanger,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).pop();
    await ref.read(pairedVehicleProvider.notifier).unpair();
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: context.tokens.accent),
      ),
    );
  }
}
