import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/pending_command_controls_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/dashboard/connection_activity_popover.dart';
import 'package:open_car_app/screens/dashboard/vehicle_switcher.dart';
import 'package:open_car_app/screens/dashboard/dashboard_screen.dart'
    show dashboardTierFor;
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/stale_values.dart';
import 'package:open_car_app/widgets/tiles/command_control.dart';
import 'package:open_car_app/widgets/tiles/state_tile.dart';

/// The side padding of the dashboard.
const double kDashboardGutter = 16;

/// The blur behind the pinned header (see "Glass" in `docs/ui-theming.md`).
const double _headerBlur = 16;

/// The pinned, translucent header of the dashboard: the vehicle name, the
/// level rows, the connection pill and the settings button, plus the status
/// line and the speed on the remote tier. See "Header" in `docs/ui.md`.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.vehicle,
    required this.snapshot,
    required this.tier,
    required this.onSettings,
    this.name,
    this.onNameLongPress,
    this.blur = true,
  });

  final VehicleDefinition vehicle;

  /// The name to show; null shows the platform's.
  final String? name;
  final VehicleSnapshot snapshot;
  final DashboardTier tier;
  final VoidCallback onSettings;

  /// Opens the debug drawer, in debug builds.
  final VoidCallback? onNameLongPress;

  /// Whether to blur what scrolls under it. The wide remote layout's header
  /// sits over the hero alone, with nothing scrolling under it.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final content = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          kDashboardGutter,
          4,
          kDashboardGutter,
          8,
        ),
        child: StaleValues(
          stale: !snapshot.isStateLive,
          child: switch (tier) {
            DashboardTier.remote => _RemoteHeaderContent(
              vehicle: vehicle,
              name: name ?? vehicle.displayName,
              snapshot: snapshot,
              onSettings: onSettings,
              onNameLongPress: onNameLongPress,
            ),
            DashboardTier.bluetooth => _BluetoothHeaderContent(
              vehicle: vehicle,
              name: name ?? vehicle.displayName,
              snapshot: snapshot,
              onSettings: onSettings,
              onNameLongPress: onNameLongPress,
            ),
          },
        ),
      ),
    );
    if (!blur) return content;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _headerBlur, sigmaY: _headerBlur),
        child: ColoredBox(color: tokens.headerFill, child: content),
      ),
    );
  }
}

class _RemoteHeaderContent extends StatelessWidget {
  const _RemoteHeaderContent({
    required this.vehicle,
    required this.name,
    required this.snapshot,
    required this.onSettings,
    this.onNameLongPress,
  });

  final VehicleDefinition vehicle;
  final String name;
  final VehicleSnapshot snapshot;
  final VoidCallback onSettings;
  final VoidCallback? onNameLongPress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final units = vehicle.units(snapshot);
    final speed = vehicle.drivingSpeedKmh(snapshot);
    final status = vehicle.statusLine(snapshot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: VehicleNameButton(
                name: name,
                style: AppTextStyles.vehicleName.copyWith(color: tokens.text),
                onLongPress: onNameLongPress,
              ),
            ),
            _PillSlot(child: ConnectionPill(snapshot: snapshot)),
            SettingsButton(onPressed: onSettings),
          ],
        ),
        for (final (index, energy) in vehicle.energy.indexed)
          StaleDimmed(
            child: LevelRow(
              energy: energy,
              snapshot: snapshot,
              units: units,
              trailing: index == 0 && speed != null
                  ? Text(
                      formatSpeed(speed, units.distance),
                      style: AppTextStyles.level.copyWith(color: tokens.text),
                    )
                  : null,
            ),
          ),
        if (vehicle.energy.isEmpty && speed != null)
          StaleDimmed(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                formatSpeed(speed, units.distance),
                style: AppTextStyles.level.copyWith(color: tokens.text),
              ),
            ),
          ),
        if (status != null)
          StaleDimmed(
            child: Text(
              status,
              style: AppTextStyles.range.copyWith(color: tokens.accent),
            ),
          ),
      ],
    );
  }
}

class _BluetoothHeaderContent extends StatelessWidget {
  const _BluetoothHeaderContent({
    required this.vehicle,
    required this.name,
    required this.snapshot,
    required this.onSettings,
    this.onNameLongPress,
  });

  final VehicleDefinition vehicle;
  final String name;
  final VehicleSnapshot snapshot;
  final VoidCallback onSettings;
  final VoidCallback? onNameLongPress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final units = vehicle.units(snapshot);
    final energy = vehicle.energy;
    final controls = [
      _PillSlot(child: ConnectionPill(snapshot: snapshot)),
      SettingsButton(onPressed: onSettings),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        VehicleNameButton(
          name: name,
          style: AppTextStyles.caption.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w700,
          ),
          dense: true,
          onLongPress: onNameLongPress,
        ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: energy.isEmpty
                  ? const SizedBox.shrink()
                  : StaleDimmed(
                      child: LevelRow(
                        energy: energy.first,
                        snapshot: snapshot,
                        units: units,
                      ),
                    ),
            ),
            ...controls,
          ],
        ),
        for (final more in energy.skip(1))
          StaleDimmed(
            child: LevelRow(energy: more, snapshot: snapshot, units: units),
          ),
      ],
    );
  }
}

/// Keeps the pill at its natural width, so what's before it shrinks first,
/// up to a share of the screen's width.
class _PillSlot extends StatelessWidget {
  const _PillSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.5,
      ),
      child: child,
    );
  }
}

/// The vehicle name with its chevron, which opens the vehicle switcher.
class VehicleNameButton extends ConsumerWidget {
  const VehicleNameButton({
    super.key,
    required this.name,
    required this.style,
    this.dense = false,
    this.onLongPress,
  });

  final String name;
  final TextStyle style;

  /// The small name of the Bluetooth header.
  final bool dense;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the name and its chevron are the button, not the space after it.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Builder(
        builder: (button) {
          // The switcher follows the name when the dashboard changes layout.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (button.mounted) reportVehicleNamePosition(button, ref);
          });
          return Semantics(
            header: true,
            button: true,
            onTapHint: 'Switch vehicle',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showVehicleSwitcher(button, ref),
              onLongPress: onLongPress,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: dense ? 24 : kMinTouchTarget,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ExcludeSemantics(
                      child: Icon(
                        Symbols.expand_more,
                        size: (style.fontSize ?? 14) * 1.2,
                        color: style.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One energy store: its glyph filled to the level, the level in % and the
/// range, with [trailing] at the end (the speed while driving).
class LevelRow extends StatelessWidget {
  const LevelRow({
    super.key,
    required this.energy,
    required this.snapshot,
    required this.units,
    this.trailing,
  });

  final EnergyDescription energy;
  final VehicleSnapshot snapshot;
  final VehicleUnits units;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final level = energy.levelPercent(snapshot);
    final range = energy.rangeKm(snapshot);
    final rangeText = range == null ? null : formatRange(range, units.distance);
    final kind = switch (energy.kind) {
      EnergyKind.battery => 'Battery',
      EnergyKind.fuel => 'Fuel',
    };
    return Semantics(
      label: [
        kind,
        if (level != null) '$level percent' else 'unknown',
        ?rangeText,
      ].join(', '),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 8,
        children: [
          LevelGlyph(kind: energy.kind, levelPercent: level),
          Flexible(
            child: Text(
              level == null ? kNoValue : '$level%',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: AppTextStyles.level.copyWith(color: tokens.text),
            ),
          ),
          if (rangeText != null)
            Flexible(
              child: Text(
                rangeText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.range.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ),
          if (trailing case final trailing?) ...[const Spacer(), trailing],
        ],
      ),
    );
  }
}

/// A battery filled to the level, or a fuel pump for a tank. Empty when the
/// level is unknown.
class LevelGlyph extends StatelessWidget {
  const LevelGlyph({super.key, required this.kind, this.levelPercent});

  final EnergyKind kind;
  final int? levelPercent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return switch (kind) {
      EnergyKind.battery => CustomPaint(
        size: Size(30 * scale, 16 * scale),
        painter: _BatteryPainter(
          level: (levelPercent ?? 0).clamp(0, 100) / 100,
          outline: tokens.text,
          fill: tokens.accent,
        ),
      ),
      // A tank's fill isn't drawn yet; no platform has one.
      EnergyKind.fuel => Icon(
        Symbols.local_gas_station,
        size: 24 * scale,
        color: tokens.text,
      ),
    };
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter({
    required this.level,
    required this.outline,
    required this.fill,
  });

  /// From 0 to 1.
  final double level;
  final Color outline;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.height / 10;
    final nub = size.width / 12;
    final body = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - nub - stroke,
      size.height - stroke,
    );
    final radius = Radius.circular(size.height / 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, radius),
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          body.right + stroke / 2,
          size.height * 0.3,
          nub,
          size.height * 0.4,
        ),
        Radius.circular(nub / 2),
      ),
      Paint()..color = outline,
    );
    final inner = body.deflate(stroke * 1.25);
    if (level > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inner.left,
            inner.top,
            inner.width * level,
            inner.height,
          ),
          Radius.circular(size.height / 10),
        ),
        Paint()..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.level != level || old.outline != outline || old.fill != fill;
}

/// The round settings button of the header.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return IconButton(
      tooltip: 'Settings',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.text,
        shape: tokens.radiusRound.shape(
          side: BorderSide(color: tokens.outline),
        ),
        minimumSize: const Size.square(kMinTouchTarget),
      ),
      icon: const Icon(Symbols.settings, size: 20),
    );
  }
}

/// How the app reaches the vehicle: `Remote`, `Bluetooth`, or `Offline` with
/// the time of the last update. The dot spins while a command is being sent.
/// See "Connection pill" in `docs/ui.md`. Tapping it opens the connection
/// activity.
class ConnectionPill extends ConsumerStatefulWidget {
  const ConnectionPill({super.key, required this.snapshot});

  final VehicleSnapshot snapshot;

  @override
  ConsumerState<ConnectionPill> createState() => _ConnectionPillState();
}

class _ConnectionPillState extends ConsumerState<ConnectionPill> {
  /// Refreshes "Updated 12 min ago" while offline.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(ConnectionPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    final offline = !widget.snapshot.isStateLive;
    if (offline && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    } else if (!offline) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // The popover follows the pill when the dashboard changes layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reportConnectionPillPosition(context, ref);
    });
    final tokens = context.tokens;
    // The real link, whichever tier the dashboard shows.
    final link = dashboardTierFor(ref.watch(transportTypeProvider));
    final snapshot = widget.snapshot;
    final pending = ref.watch(
      pendingCommandControlsProvider.select((ids) => ids.isNotEmpty),
    );
    final live = snapshot.isStateLive;
    final label = connectionLabel(snapshot, link, DateTime.now());
    final dotColor = live ? tokens.accent : tokens.textSecondary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    const dotSize = 8.0;
    final Widget dot = pending
        ? SizedBox.square(
            dimension: dotSize + 2,
            child: reduceMotion
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: dotColor, width: 2),
                    ),
                  )
                : CircularProgressIndicator(strokeWidth: 2, color: dotColor),
          )
        : Container(
            width: dotSize,
            height: dotSize,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          );

    return Semantics(
      label: [label, if (pending) 'sending a command'].join(', '),
      button: true,
      onTap: () => showConnectionActivity(context, ref),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showConnectionActivity(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: ShapeDecoration(
                color: tokens.surface,
                shape: tokens.radiusPill.shape(
                  side: BorderSide(color: tokens.outline),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  dot,
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: tokens.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The connection pill's text: the live link, or how old [snapshot] is.
String connectionLabel(
  VehicleSnapshot snapshot,
  DashboardTier link,
  DateTime now,
) => snapshot.isStateLive
    ? switch (link) {
        DashboardTier.remote => 'Remote',
        DashboardTier.bluetooth => 'Bluetooth',
      }
    : [
        'Offline',
        if (snapshot.lastUpdated case final updated?)
          'Updated ${formatUpdatedAgo(updated, now)}',
      ].join(' · ');

/// How long ago [then] was, for the pill: "just now", "12 min ago",
/// "3 h ago", "2 d ago".
String formatUpdatedAgo(DateTime then, DateTime now) {
  final age = now.difference(then);
  if (age.inMinutes < 1) return 'just now';
  if (age.inHours < 1) return '${age.inMinutes} min ago';
  if (age.inDays < 1) return '${age.inHours} h ago';
  return '${age.inDays} d ago';
}
