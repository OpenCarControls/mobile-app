import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/theme_provider.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/theme/radius_token.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';

/// Debug-only screen for checking the design on a phone: the tokens and,
/// as they are added, the components, in every skin and both brightnesses.
class ThemeGalleryScreen extends ConsumerStatefulWidget {
  const ThemeGalleryScreen({super.key});

  static Future<void> open(BuildContext context) {
    assert(kDebugMode, 'the theme gallery is debug-only');
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ThemeGalleryScreen()));
  }

  @override
  ConsumerState<ThemeGalleryScreen> createState() => _ThemeGalleryScreenState();
}

class _ThemeGalleryScreenState extends ConsumerState<ThemeGalleryScreen> {
  // Null until the user picks one, so the gallery opens on what the app shows.
  VehicleSkin? _pickedSkin;
  Brightness? _pickedBrightness;

  @override
  Widget build(BuildContext context) {
    final skins = {
      defaultSkin,
      for (final vehicle in ref.watch(availableVehiclesProvider)) vehicle.skin,
    };
    final currentSkin = ref.watch(currentSkinProvider);
    final skin = _pickedSkin ?? currentSkin;
    final brightness = _pickedBrightness ?? Theme.of(context).brightness;

    return Theme(
      data: buildAppTheme(skin, brightness),
      child: Scaffold(
        appBar: AppBar(title: const Text('Theme gallery')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SegmentedButton<VehicleSkin>(
              showSelectedIcon: false,
              segments: [
                for (final option in skins)
                  ButtonSegment(value: option, label: Text(option.name)),
              ],
              selected: {skin},
              onSelectionChanged: (picked) =>
                  setState(() => _pickedSkin = picked.single),
            ),
            const SizedBox(height: 8),
            SegmentedButton<Brightness>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Brightness.light, label: Text('Light')),
                ButtonSegment(value: Brightness.dark, label: Text('Dark')),
              ],
              selected: {brightness},
              onSelectionChanged: (picked) =>
                  setState(() => _pickedBrightness = picked.single),
            ),
            const _Section('Colours', _ColoursSection()),
            const _Section('Glass', _GlassSection()),
            const _Section('Shapes', _ShapesSection()),
            const _Section('Type', _TypeSection()),
            const _Section('Icons', _IconsSection()),
            const _Section('Material widgets', _MaterialSection()),
            const _Section('Saved theme mode', _ThemeModeSection()),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.child);

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTextStyles.vehicleName),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ColoursSection extends StatelessWidget {
  const _ColoursSection();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colours = {
      'bg': tokens.bg,
      'surface': tokens.surface,
      'text': tokens.text,
      'textSecondary': tokens.textSecondary,
      'accent': tokens.accent,
      'accentContainer': tokens.accentContainer,
      'onAccentContainer': tokens.onAccentContainer,
      'outline': tokens.outline,
      'tileBorder': tokens.tileBorder,
      'glassFill': tokens.glassFill,
      'layerFill': tokens.layerFill,
      'headerFill': tokens.headerFill,
      'danger': tokens.danger,
      'onDanger': tokens.onDanger,
      'editScrim': tokens.editScrim,
      'modalScrim': tokens.modalScrim,
    };
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final MapEntry(key: name, value: colour) in colours.entries)
            SizedBox(
              width: (constraints.maxWidth - 8) / 2,
              child: _Swatch(name, colour),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.colour);

  final String name;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final argb = colour.toARGB32().toRadixString(16).padLeft(8, '0');
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: ShapeDecoration(
            color: colour,
            shape: tokens.radiusSmall.shape(
              side: BorderSide(color: tokens.outline),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: AppTextStyles.buttonTitle,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                argb,
                style: AppTextStyles.caption.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A sample tile, until the real tile widgets exist.
class _SampleTile extends StatelessWidget {
  const _SampleTile({
    required this.label,
    required this.value,
    this.on = false,
  });

  final String label;
  final String value;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: ShapeDecoration(
        color: on ? tokens.accentContainer : tokens.glassFill,
        shape: tokens.radiusMedium.shape(
          side: BorderSide(color: tokens.tileBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: on ? tokens.onAccentContainer : tokens.textSecondary,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.statValue.copyWith(
              color: on ? tokens.onAccentContainer : tokens.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// The remote tier's stack over the worst-case car colours: white, black and
/// a stand-in paint, under the frosted layer, the tiles and the header.
class _GlassSection extends StatelessWidget {
  const _GlassSection();

  static const _tiles = Row(
    children: [
      Expanded(
        child: _SampleTile(label: 'Doors', value: 'Locked', on: true),
      ),
      SizedBox(width: 8),
      Expanded(
        child: _SampleTile(label: 'Odometer', value: '22,916'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ClipRRect(
      borderRadius: tokens.radiusMedium.borderRadius,
      child: SizedBox(
        height: 240,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ColoredBox(color: Colors.white)),
                Expanded(child: ColoredBox(color: Colors.black)),
                Expanded(child: ColoredBox(color: Color(0xFF8A2432))),
              ],
            ),
            Positioned(
              top: 110,
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: tokens.radiusLarge.borderRadius.topLeft,
                  topRight: tokens.radiusLarge.borderRadius.topRight,
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: ColoredBox(
                    color: tokens.layerFill,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _tiles,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 64,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: ColoredBox(
                    color: tokens.headerFill,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '64%',
                            style: AppTextStyles.level.copyWith(
                              color: tokens.text,
                              height: 2.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '312 km',
                            style: AppTextStyles.range.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShapesSection extends StatelessWidget {
  const _ShapesSection();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget sample(String name, RadiusToken radius, double width) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: width,
          height: 56,
          decoration: ShapeDecoration(
            color: tokens.accentContainer,
            shape: radius.shape(side: BorderSide(color: tokens.accent)),
          ),
        ),
        const SizedBox(height: 4),
        Text('$name: $radius', style: AppTextStyles.caption),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        sample('Small', tokens.radiusSmall, 88),
        sample('Medium', tokens.radiusMedium, 88),
        sample('Large', tokens.radiusLarge, 88),
        sample('Pill', tokens.radiusPill, 120),
        sample('Round', tokens.radiusRound, 56),
      ],
    );
  }
}

class _TypeSection extends StatelessWidget {
  const _TypeSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text('Vehicle name 20/800', style: AppTextStyles.vehicleName),
        Text('Level 26/800', style: AppTextStyles.level),
        Text('Range 15/600', style: AppTextStyles.range),
        Text('Button title 12/700', style: AppTextStyles.buttonTitle),
        Text('Caption 12/400', style: AppTextStyles.caption),
        Text('Stat value 18/800', style: AppTextStyles.statValue),
        Text('Climate target 22/800', style: AppTextStyles.climateTarget),
      ],
    );
  }
}

class _IconsSection extends StatelessWidget {
  const _IconsSection();

  static const _groups = {
    'Defrost': {
      'windshield_defrost_front': Symbols.windshield_defrost_front,
      'windshield_defrost_rear': Symbols.windshield_defrost_rear,
      'windshield_defrost_auto': Symbols.windshield_defrost_auto,
      'windshield_heat_front': Symbols.windshield_heat_front,
      'hvac_max_defrost': Symbols.hvac_max_defrost,
      'car_mirror_heat': Symbols.car_mirror_heat,
    },
    'Climate': {
      'mode_fan': Symbols.mode_fan,
      'mode_fan_off': Symbols.mode_fan_off,
      'ac_unit': Symbols.ac_unit,
      'mode_heat': Symbols.mode_heat,
      'thermostat': Symbols.thermostat,
      'car_fan_recirculate': Symbols.car_fan_recirculate,
      'car_fan_low_left': Symbols.car_fan_low_left,
      'car_fan_mid_left': Symbols.car_fan_mid_left,
      'car_defrost_left': Symbols.car_defrost_left,
      'car_defrost_right': Symbols.car_defrost_right,
    },
    'Seats and wheel': {
      'seat_heat_left': Symbols.seat_heat_left,
      'seat_heat_right': Symbols.seat_heat_right,
      'seat_vent_left': Symbols.seat_vent_left,
      'seat_vent_right': Symbols.seat_vent_right,
      'steering_wheel_heat': Symbols.steering_wheel_heat,
    },
    'Body': {
      'lock': Symbols.lock,
      'lock_open': Symbols.lock_open,
      'car_lock': Symbols.car_lock,
      'door_open': Symbols.door_open,
      'door_front': Symbols.door_front,
      'sensor_window': Symbols.sensor_window,
      'lightbulb': Symbols.lightbulb,
      'tire_repair': Symbols.tire_repair,
      'directions_car': Symbols.directions_car,
    },
    'Energy': {
      'ev_charger': Symbols.ev_charger,
      'ev_station': Symbols.ev_station,
      'charging_station': Symbols.charging_station,
      'battery_horiz_075': Symbols.battery_horiz_075,
      'local_gas_station': Symbols.local_gas_station,
    },
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        const Text('Each glyph off and on', style: AppTextStyles.caption),
        for (final MapEntry(key: group, value: icons) in _groups.entries)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text(group, style: AppTextStyles.buttonTitle),
              Wrap(
                spacing: 8,
                runSpacing: 12,
                children: [
                  for (final MapEntry(key: name, value: icon) in icons.entries)
                    SizedBox(
                      width: 112,
                      child: Column(
                        spacing: 4,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 8,
                            children: [
                              Icon(icon, fill: 0, size: 28),
                              Icon(icon, fill: 1, size: 28),
                            ],
                          ),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class _MaterialSection extends StatefulWidget {
  const _MaterialSection();

  @override
  State<_MaterialSection> createState() => _MaterialSectionState();
}

class _MaterialSectionState extends State<_MaterialSection> {
  bool _switchOn = true;

  void _showDialog({required bool destructive}) {
    final tokens = context.tokens;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(destructive ? 'Unpair vehicle?' : 'A dialog'),
        content: const Text('Stock dialogs take their look from the skin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: tokens.danger,
                    foregroundColor: tokens.onDanger,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(destructive ? 'Unpair' : 'OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton(
          onPressed: () => _showDialog(destructive: false),
          child: const Text('Dialog'),
        ),
        OutlinedButton(
          onPressed: () => _showDialog(destructive: true),
          child: const Text('Unpair dialog'),
        ),
        TextButton(
          onPressed: () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('A snackbar'))),
          child: const Text('Snackbar'),
        ),
        ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => const SizedBox(
              height: 160,
              child: Center(child: Text('A bottom sheet')),
            ),
          ),
          child: const Text('Sheet'),
        ),
        const Chip(label: Text('Chip')),
        Switch(
          value: _switchOn,
          onChanged: (value) => setState(() => _switchOn = value),
        ),
        const SizedBox(
          width: double.infinity,
          child: TextField(
            decoration: InputDecoration(labelText: 'Text field'),
          ),
        ),
      ],
    );
  }
}

class _ThemeModeSection extends ConsumerWidget {
  const _ThemeModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ThemeMode>(
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
        const SizedBox(height: 4),
        const Text(
          'Applies to the whole app and survives a restart. '
          'The settings screen takes this over.',
          style: AppTextStyles.caption,
        ),
      ],
    );
  }
}
