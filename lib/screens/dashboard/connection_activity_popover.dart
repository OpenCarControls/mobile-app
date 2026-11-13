import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/models/connection_activity.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/connection_activity_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/dashboard/dashboard_header.dart'
    show formatUpdatedAgo;
import 'package:open_car_app/screens/dashboard/dashboard_screen.dart'
    show dashboardTierFor;
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/popover_arrow.dart';
import 'package:open_car_app/widgets/tiles/command_control.dart'
    show kMinTouchTarget;

const _gutter = 12.0;
const _maxWidth = 420.0;
const _arrowWidth = 20.0;
const _arrowHeight = 10.0;

/// The empty space below the pill inside its touch target.
const _pillSlack = 6.0;

/// Shares text through the system share sheet. Replaced in tests.
final shareTextProvider = Provider<Future<void> Function(String text)>(
  (_) => (text) async {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'Open Car connection activity'),
    );
  },
);

/// Where the connection pill is on the screen. The pill keeps this current,
/// because it moves when the dashboard changes layout with the popover open.
class _PillPosition extends Notifier<Rect?> {
  @override
  Rect? build() => null;

  void set(Rect position) {
    if (position != state) state = position;
  }
}

final _pillPositionProvider = NotifierProvider<_PillPosition, Rect?>(
  _PillPosition.new,
);

/// Records where the pill whose context is [pill] is. Call after layout.
void reportConnectionPillPosition(BuildContext pill, WidgetRef ref) {
  final box = pill.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return;
  // The pill is centred in a box that can be taller than its touch target.
  ref
      .read(_pillPositionProvider.notifier)
      .set(
        Rect.fromCenter(
          center: box.localToGlobal(box.size.center(Offset.zero)),
          width: box.size.width,
          height: kMinTouchTarget,
        ),
      );
}

/// Opens the connection activity, anchored to the connection pill whose
/// context is [pill]. See "Connection activity" in `docs/ui-screens.md`.
Future<void> showConnectionActivity(BuildContext pill, WidgetRef ref) {
  reportConnectionPillPosition(pill, ref);
  return showGeneralDialog<void>(
    context: pill,
    barrierDismissible: true,
    barrierLabel: 'Close connection activity',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, _, _) => const _Popover(),
  );
}

/// The heading of a day of the log.
String connectionActivityDayHeading(
  DateTime day,
  DateTime now,
  MaterialLocalizations localizations,
) {
  final today = DateUtils.dateOnly(now);
  final difference = today.difference(DateUtils.dateOnly(day)).inHours;
  // In hours and rounded, because a day with a clock change isn't 24 h.
  final days = (difference / 24).round();
  return switch (days) {
    0 => 'TODAY',
    1 => 'YESTERDAY',
    _ => localizations.formatMediumDate(day).toUpperCase(),
  };
}

class _Popover extends ConsumerWidget {
  const _Popover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(_pillPositionProvider);
    if (anchor == null) return const SizedBox.shrink();
    final tokens = context.tokens;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width - 2 * _gutter, _maxWidth);
    final left = (anchor.right - width).clamp(
      _gutter,
      size.width - width - _gutter,
    );
    final top = anchor.bottom - _pillSlack + _arrowHeight;
    final maxHeight =
        size.height - top - MediaQuery.paddingOf(context).bottom - _gutter;
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Material(
              color: tokens.surface,
              clipBehavior: Clip.antiAlias,
              shape: tokens.radiusLarge.shape(
                side: BorderSide(color: tokens.outline),
              ),
              child: const _Content(),
            ),
          ),
        ),
        Positioned(
          left: anchor.center.dx - _arrowWidth / 2,
          // One pixel into the card, to cover its border.
          top: top - _arrowHeight + 1,
          child: ExcludeSemantics(
            child: CustomPaint(
              size: const Size(_arrowWidth, _arrowHeight),
              painter: PopoverArrowPainter(
                fill: tokens.surface,
                border: tokens.outline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Content extends ConsumerStatefulWidget {
  const _Content();

  @override
  ConsumerState<_Content> createState() => _ContentState();
}

class _ContentState extends ConsumerState<_Content> {
  /// Refreshes "For 12 min" and "last update just now".
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _share() async {
    final entries = ref.read(connectionActivityProvider);
    final platformName = ref.read(selectedVehicleProvider)?.platformName ?? '';
    final share = ref.read(shareTextProvider);
    final version = (await PackageInfo.fromPlatform()).version;
    await share(
      formatConnectionActivityForSharing(
        entries,
        appVersion: version,
        platformName: platformName,
      ),
    );
  }

  /// "For 12 min · last update just now", as far as it is known.
  String? _statusDetail(
    VehicleSnapshot snapshot,
    List<ConnectionActivityEntry> entries,
    DateTime now,
  ) {
    final since = snapshot.isStateLive ? connectedSince(entries) : null;
    final updated = snapshot.lastUpdated;
    final minutes = since == null ? null : now.difference(since).inMinutes;
    final parts = [
      if (minutes != null)
        minutes < 1
            ? 'for less than a minute'
            : 'for ${formatMinutes(minutes)}',
      if (updated != null) 'last update ${formatUpdatedAgo(updated, now)}',
    ];
    if (parts.isEmpty) return null;
    final text = parts.join(' · ');
    return text[0].toUpperCase() + text.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final snapshot = ref.watch(vehicleStateProvider);
    final entries = ref.watch(connectionActivityProvider);
    final link = dashboardTierFor(ref.watch(transportTypeProvider));
    final live = snapshot.isStateLive;
    final now = DateTime.now();
    final status = live
        ? switch (link) {
            DashboardTier.remote => 'Connected remotely',
            DashboardTier.bluetooth => 'Connected over Bluetooth',
          }
        : 'Offline';
    final detail = _statusDetail(snapshot, entries, now);
    final secondary = TextStyle(color: tokens.textSecondary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connection', style: AppTextStyles.statValue),
                    const SizedBox(height: 2),
                    Row(
                      spacing: 8,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: live ? tokens.accent : tokens.textSecondary,
                          ),
                        ),
                        Flexible(child: Text(status)),
                      ],
                    ),
                    if (detail != null) Text(detail, style: secondary),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: 'Close',
                icon: const Icon(Symbols.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                // Nothing to reconnect while the link is up.
                onPressed: ref.watch(bleConnectionProvider) is BleReady
                    ? null
                    : () => unawaited(
                        ref
                            .read(bleConnectionProvider.notifier)
                            .pullToRefresh(),
                      ),
                child: const Text('Reconnect Bluetooth'),
              ),
              OutlinedButton(
                onPressed: entries.isEmpty ? null : () => unawaited(_share()),
                child: const Text('Share log'),
              ),
            ],
          ),
        ),
        Flexible(
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Nothing to show yet.', style: secondary),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _rows(context, entries, now),
                ),
        ),
        Divider(height: 1, color: tokens.outline),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Text(
            'Shows connection changes and the commands sent from this phone. '
            'Routine updates are not listed.',
            style: AppTextStyles.caption.copyWith(color: tokens.textSecondary),
          ),
        ),
      ],
    );
  }

  List<Widget> _rows(
    BuildContext context,
    List<ConnectionActivityEntry> entries,
    DateTime now,
  ) {
    final tokens = context.tokens;
    final localizations = MaterialLocalizations.of(context);
    final rows = <Widget>[];
    DateTime? day;
    for (final entry in entries) {
      final entryDay = DateUtils.dateOnly(entry.time);
      if (entryDay != day) {
        day = entryDay;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              connectionActivityDayHeading(entryDay, now, localizations),
              style: AppTextStyles.caption.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      } else {
        rows.add(Divider(height: 1, color: tokens.outline));
      }
      rows.add(_EntryRow(entry: entry));
    }
    return rows;
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final ConnectionActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final entry = this.entry;
    final failure = entry.isFailure;
    final lost =
        entry is ConnectionChangeEntry &&
        entry.change == ConnectionChange.bluetoothLost;
    final icon = switch (entry) {
      ConnectionChangeEntry() => lost ? Symbols.link_off : Symbols.link,
      CommandEntry() => failure ? Symbols.priority_high : Symbols.check,
    };
    final iconColor = failure
        ? tokens.danger
        : lost
        ? tokens.textSecondary
        : tokens.onAccentContainer;
    final circle = failure || lost ? tokens.outline : tokens.accentContainer;
    final detail = entry.detail;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(shape: BoxShape.circle, color: circle),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: AppTextStyles.buttonTitle),
                if (detail != null)
                  Text(
                    detail,
                    style: TextStyle(
                      color: failure ? tokens.danger : tokens.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            TimeOfDay.fromDateTime(entry.time).format(context),
            style: AppTextStyles.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
