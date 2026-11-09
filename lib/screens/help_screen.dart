import 'package:flutter/material.dart';
// Transport constants are identical in every vehicle's constants.g.dart.
import 'package:open_car_app/cars/virtual_car/constants.g.dart'
    show
        kBleFirstSetupPairingWindowSeconds,
        kBlePairingWindowSeconds,
        kBlePowerCycleResetShortBoots,
        kBlePowerCycleResetUptimeSeconds;

/// How to pair, and how to recover when the device no longer knows this phone
/// (firmware#54): a device without a pairing button hides from phones it
/// doesn't know once it has a paired phone, so the app can't pair with it.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));

  @override
  Widget build(BuildContext context) {
    final firstSetupWindow = duration(kBleFirstSetupPairingWindowSeconds);

    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HelpCard(
              icon: Icons.bluetooth_searching,
              title: 'Pairing mode',
              children: [
                const _HelpText(
                  'A phone can only pair while the device is in pairing mode.',
                ),
                _HelpPoint(
                  icon: Icons.power_settings_new,
                  text:
                      'A device with no paired phone yet is in pairing mode '
                      'for $firstSetupWindow after it is powered on.',
                ),
                _HelpPoint(
                  icon: Icons.touch_app_outlined,
                  text:
                      'A device with a pairing button is in pairing mode for '
                      '$kBlePairingWindowSeconds seconds after you hold the '
                      'button for a few seconds.',
                ),
                const _HelpText('Then tap Start in the pairing wizard.'),
              ],
            ),
            const _HelpCard(
              icon: Icons.bluetooth_disabled,
              title: 'The app can\'t find or pair with the device',
              children: [
                _HelpText(
                  'After the app is reinstalled, on a new phone, or once the '
                  'device is forgotten in Android\'s Bluetooth settings, the '
                  'device no longer recognises this phone. Outside pairing '
                  'mode it doesn\'t accept phones it doesn\'t know. To pair '
                  'again:',
                ),
                _HelpStep(
                  number: 1,
                  text:
                      'In Android\'s Bluetooth settings, forget the OpenCar '
                      'device if it is listed.',
                ),
                _HelpStep(
                  number: 2,
                  text:
                      'If the app still shows the vehicle, choose Unpair '
                      'vehicle in the dashboard menu.',
                ),
                _HelpStep(
                  number: 3,
                  text:
                      'Put the device in pairing mode: hold its pairing '
                      'button, or, without one, reset its paired phones '
                      '(below).',
                ),
                _HelpStep(number: 4, text: 'Tap Start in the pairing wizard.'),
              ],
            ),
            _HelpCard(
              icon: Icons.restart_alt,
              title: 'Resetting the paired phones',
              children: [
                const _HelpText(
                  'For a device without a pairing button: cutting its power '
                  'quickly a few times in a row makes it forget every paired '
                  'phone.',
                ),
                _HelpStep(
                  number: 1,
                  text:
                      'Plug the device in, and unplug it again less than '
                      '$kBlePowerCycleResetUptimeSeconds seconds later.',
                ),
                _HelpStep(
                  number: 2,
                  text:
                      'Do this $kBlePowerCycleResetShortBoots times in a row.',
                ),
                _HelpStep(
                  number: 3,
                  text:
                      'Plug it in again and leave it plugged in. It is now in '
                      'pairing mode for $firstSetupWindow.',
                ),
                const _HelpNote(
                  'Every phone that was paired with the device has to pair '
                  'again afterwards, then validate again. The device keeps '
                  'its other settings.',
                ),
              ],
            ),
            const _HelpCard(
              icon: Icons.verified_user_outlined,
              title: 'Validating a phone again',
              children: [
                _HelpText(
                  'Only a phone validated in the car can send commands and '
                  'see the full dashboard. A phone has to validate again '
                  'after it pairs again, after the paired phones are reset, '
                  'and when the device moves to another car.',
                ),
                _HelpText(
                  'Tap Validate on the dashboard, or Validate this phone in '
                  'settings, while connected over Bluetooth.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// [seconds] as a duration in words: "5 minutes", "90 seconds".
  static String duration(int seconds) {
    if (seconds % 60 != 0) return '$seconds seconds';
    final minutes = seconds ~/ 60;
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }
}

class _HelpCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _HelpCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
          ],
        ),
      ),
    );
  }
}

class _HelpText extends StatelessWidget {
  final String text;
  const _HelpText(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodyMedium);
}

/// A point with an icon in front, for facts that aren't steps.
class _HelpPoint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HelpPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// A numbered step, its number in a badge.
class _HelpStep extends StatelessWidget {
  final int number;
  final String text;
  const _HelpStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            '$number',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ),
      ],
    );
  }
}

class _HelpNote extends StatelessWidget {
  final String text;
  const _HelpNote(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
