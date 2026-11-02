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
/// doesn't know once it has a paired phone, so the app can't find it.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: theme.textTheme.titleLarge),
    );
    Widget paragraph(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
    Widget step(String number, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(number, style: theme.textTheme.bodyMedium),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            heading('Pairing mode'),
            paragraph(
              'A phone can only pair while the device is in pairing mode:',
            ),
            step(
              '•',
              'A device that has no paired phone yet is in pairing mode for '
                  '${duration(kBleFirstSetupPairingWindowSeconds)} after it is '
                  'powered on.',
            ),
            step(
              '•',
              'A device with a pairing button is in pairing mode for '
                  '$kBlePairingWindowSeconds seconds after you hold the '
                  'button for a few seconds.',
            ),
            paragraph('Then tap Start in the pairing wizard.'),
            heading('The app can\'t find or connect to the device'),
            paragraph(
              'If the app was reinstalled, you changed phones, or the device '
              'was forgotten in Android\'s Bluetooth settings, the device no '
              'longer recognises this phone. Outside pairing mode it stays '
              'hidden from phones it doesn\'t know, so the app can\'t find it. '
              'To pair again:',
            ),
            step(
              '1.',
              'In Android\'s Bluetooth settings, forget the OpenCar device if '
                  'it is listed.',
            ),
            step(
              '2.',
              'If the app still shows the vehicle, choose Unpair vehicle in '
                  'the dashboard menu.',
            ),
            step(
              '3.',
              'Put the device back in pairing mode. With a pairing button, '
                  'hold it. Without one, reset its paired phones as below.',
            ),
            step('4.', 'Tap Start in the pairing wizard.'),
            heading('Resetting the paired phones'),
            paragraph(
              'On a device without a pairing button, cutting its power quickly '
              'a few times in a row makes it forget every paired phone:',
            ),
            step(
              '1.',
              'Plug the device in, and unplug it again less than '
                  '$kBlePowerCycleResetUptimeSeconds seconds later.',
            ),
            step(
              '2.',
              'Do this $kBlePowerCycleResetShortBoots times in a row.',
            ),
            step(
              '3.',
              'Plug it in again and leave it plugged in. It forgets every '
                  'paired phone and is in pairing mode for '
                  '${duration(kBleFirstSetupPairingWindowSeconds)}.',
            ),
            paragraph(
              'Every phone that was paired with the device has to pair again '
              'afterwards. The device keeps its other settings.',
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
