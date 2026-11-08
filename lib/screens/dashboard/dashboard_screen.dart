import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/models/dashboard_layout.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/dashboard_layout_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_history_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/dashboard/dashboard_banner.dart';
import 'package:open_car_app/screens/dashboard/dashboard_header.dart';
import 'package:open_car_app/screens/settings_screen.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/tiles/catalog_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_context.dart';
import 'package:open_car_app/widgets/tiles/tile_editing.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

/// From this width the dashboard uses its wide layouts.
const double kWideLayoutMinWidth = 800;

/// The remote tier's hero box never gets shorter than this; below it, the
/// tiles scroll over the hero.
const double kHeroMinHeight = 160;

/// The width of the remote tier's tile column on wide screens.
const double _sideColumnWidth = 400;

/// The blur of the remote tier's frosted tile layer.
const double _layerBlur = 18;

/// The cross-fade when the link switches between Remote and Bluetooth.
const _tierSwitchDuration = Duration(milliseconds: 300);

/// The grid item of the edit controls; no catalog tile has this id.
const _editControlId = '__edit__';

/// The grid item of the edit mode hint.
const _editHintId = '__edit_hint__';

/// The tier for a transport: remote over MQTT, Bluetooth otherwise (stub and
/// HTTP behave like BLE).
DashboardTier dashboardTierFor(TransportType transport) => switch (transport) {
  TransportType.mqtt => DashboardTier.remote,
  TransportType.ble ||
  TransportType.stub ||
  TransportType.http => DashboardTier.bluetooth,
};

/// The shared dashboard: the current vehicle's tiles in its default layout
/// for the tier the transport gives. See `docs/ui.md`.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// The grid being edited, if any.
  DashboardGrid? _editing;

  void _setEditing(DashboardGrid? grid) => setState(() => _editing = grid);

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(selectedVehicleProvider);
    // Briefly null while unpairing, before the router shows the wizard.
    if (vehicle == null) return const SizedBox.shrink();
    final snapshot = ref.watch(vehicleStateProvider);
    final tier = dashboardTierFor(ref.watch(transportTypeProvider));
    // A link change swaps the grid: don't come back to it still in edit mode.
    ref.listen(transportTypeProvider, (previous, next) {
      if (previous == null) return;
      if (dashboardTierFor(previous) != dashboardTierFor(next)) {
        _setEditing(null);
      }
    });
    final grid = DashboardGrid.of(tier);
    final editing = _editing == grid;
    final data = TileContext(
      vehicle: vehicle,
      snapshot: snapshot,
      history: ref.watch(vehicleHistoryProvider),
    );
    final debugDrawer = kDebugMode ? vehicle.buildDebugDrawer() : null;
    // A tile whose command the car doesn't have is left out, and the tiles
    // after it close the gap.
    final layout = [
      for (final entry in ref.watch(dashboardLayoutProvider(tier)))
        if (!_commandHidden(vehicle.tileById(entry.tileId))) entry,
    ];

    final dashboard = _Dashboard(
      key: ValueKey(tier),
      tier: tier,
      data: data,
      items: _gridItems(grid, tier, layout, data),
      onRefresh: () => ref.read(bleConnectionProvider.notifier).pullToRefresh(),
      onSettings: () => SettingsScreen.open(context),
      onNameLongPress: debugDrawer == null
          ? null
          : () => _scaffoldKey.currentState?.openEndDrawer(),
    );

    return PopScope(
      canPop: !editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setEditing(null);
      },
      child: Scaffold(
        key: _scaffoldKey,
        endDrawer: debugDrawer,
        body: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : _tierSwitchDuration,
          child: dashboard,
        ),
      ),
    );
  }

  /// [layout]'s tiles for [grid], with the editing controls the grid allows.
  List<TileGridItem> _gridItems(
    DashboardGrid grid,
    DashboardTier tier,
    List<TileLayoutEntry> layout,
    TileContext data,
  ) {
    final items = catalogGridItems(layout, data, tiers: tier.tileTiers);
    if (grid.editing == TileGridEditing.none) return items;
    if (_editing != grid) {
      return [
        for (final item in items)
          TileGridItem(
            id: item.id,
            span: item.span,
            // Holding a tile starts editing, and the same hold can drag it.
            drag: TileDragHandlers(
              onStart: () => _setEditing(grid),
              onMoveTo: (index) => ref
                  .read(savedLayoutsProvider.notifier)
                  .save(grid, _moved(layout, item.id, index)),
            ),
            child: item.child,
          ),
        if (grid.editing == TileGridEditing.explicit)
          TileGridItem(
            id: _editControlId,
            span: const TileSpan(1, 1),
            child: EditLayoutTile(onPressed: () => _setEditing(grid)),
          ),
      ];
    }

    void save(List<TileLayoutEntry> edited) =>
        ref.read(savedLayoutsProvider.notifier).save(grid, edited);
    final vehicle = data.vehicle;
    final addable = [
      for (final tile in tilesNotInLayout(layout, vehicle, tier))
        (tile: tile, supported: !_commandHidden(tile)),
    ];
    // Removing the last tile of an implicit grid would leave nothing to hold
    // to edit it again.
    final removable =
        grid.editing == TileGridEditing.explicit || items.length > 1;
    return [
      for (final (index, item) in items.indexed)
        () {
          final tile = vehicle.tileById(item.id)!;
          return TileGridItem(
            id: item.id,
            span: item.span,
            drag: TileDragHandlers(
              onStart: () {},
              onMoveTo: (index) => save(_moved(layout, tile.id, index)),
            ),
            child: EditingTile(
              tile: tile,
              span: item.span,
              onRemove: removable
                  ? () => save(layout.withoutTile(tile.id))
                  : null,
              onNextSize: tile.sizes.length > 1
                  ? () => save(layout.withNextSize(tile))
                  : null,
              onMoveEarlier: index > 0
                  ? () => save(layout.withTileMoved(tile.id, -1))
                  : null,
              onMoveLater: index < items.length - 1
                  ? () => save(layout.withTileMoved(tile.id, 1))
                  : null,
              child: item.child,
            ),
          );
        }(),
      TileGridItem(
        id: _editControlId,
        span: kEditActionsSpan,
        child: EditActionsTile(
          onAdd: addable.isEmpty
              ? null
              : () async {
                  final tile = await showAddTileSheet(context, addable);
                  if (tile != null) save(layout.withTile(tile));
                },
          onDone: () => _setEditing(null),
          onReset: () => _reset(grid, layout),
        ),
      ),
      TileGridItem(
        id: _editHintId,
        span: const TileSpan(kTileColumnsPhone, 1),
        child: Center(
          child: Text(
            'Hold a tile and drag to move it. Tap its size to resize it.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: context.tokens.textSecondary,
            ),
          ),
        ),
      ),
    ];
  }

  /// [layout] with the tile [tileId] at [index].
  List<TileLayoutEntry> _moved(
    List<TileLayoutEntry> layout,
    String tileId,
    int index,
  ) => layout.withTileMoved(
    tileId,
    index - layout.indexWhere((entry) => entry.tileId == tileId),
  );

  void _reset(DashboardGrid grid, List<TileLayoutEntry> previous) {
    final layouts = ref.read(savedLayoutsProvider.notifier);
    layouts.reset(grid);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Layout reset'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => layouts.save(grid, previous),
          ),
        ),
      );
  }

  bool _commandHidden(TileDefinition? tile) {
    final key = switch (tile) {
      CommandTileDefinition(:final command) => command.key,
      ClimateTileDefinition(:final climate) => climate.command,
      _ => null,
    };
    return key != null &&
        ref.watch(commandUiStateProvider(key)) == CommandUiState.hidden;
  }
}

/// One tier of the dashboard, narrow or wide.
class _Dashboard extends StatelessWidget {
  const _Dashboard({
    super.key,
    required this.tier,
    required this.data,
    required this.items,
    required this.onRefresh,
    required this.onSettings,
    this.onNameLongPress,
  });

  final DashboardTier tier;
  final TileContext data;

  /// The tiles to show, in order.
  final List<TileGridItem> items;
  final Future<void> Function() onRefresh;
  final VoidCallback onSettings;
  final VoidCallback? onNameLongPress;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kWideLayoutMinWidth;
    Widget header({bool blur = true}) => DashboardHeader(
      vehicle: data.vehicle,
      snapshot: data.snapshot,
      tier: tier,
      onSettings: onSettings,
      onNameLongPress: onNameLongPress,
      blur: blur,
    );
    Widget hero() => data.vehicle.buildHero(context, data.snapshot);

    return ColoredBox(
      color: context.tokens.bg,
      child: switch ((tier, wide)) {
        (DashboardTier.remote, false) => RemoteDashboardLayout(
          header: header(),
          hero: hero(),
          items: items,
          onRefresh: onRefresh,
        ),
        (DashboardTier.remote, true) => _WideRemoteLayout(
          header: header(blur: false),
          hero: hero(),
          items: items,
          onRefresh: onRefresh,
        ),
        (DashboardTier.bluetooth, _) => _BluetoothLayout(
          header: header(),
          items: items,
          columns: wide ? kTileColumnsWide : kTileColumnsPhone,
          onRefresh: onRefresh,
        ),
      },
    );
  }
}

/// The remote tier on phones: the hero in a box between the header and the
/// tiles, and the tiles on a frosted layer that rests at the bottom and
/// scrolls over the hero once the box is at its minimum height. The whole
/// page scrolls, so pull-to-refresh works anywhere on it.
class RemoteDashboardLayout extends StatefulWidget {
  const RemoteDashboardLayout({
    super.key,
    required this.header,
    required this.hero,
    required this.items,
    required this.onRefresh,
  });

  final Widget header;
  final Widget hero;
  final List<TileGridItem> items;
  final Future<void> Function() onRefresh;

  @override
  State<RemoteDashboardLayout> createState() => _RemoteDashboardLayoutState();
}

class _RemoteDashboardLayoutState extends State<RemoteDashboardLayout> {
  double _headerHeight = 0;
  double _layerHeight = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight - _headerHeight;
        // The box takes what the tiles leave, down to its minimum. It follows
        // the tile layer's height frame by frame, so it moves with the grid's
        // own resize animation.
        final heroHeight = math.max(
          math.min(kHeroMinHeight, available),
          available - _layerHeight,
        );
        return Stack(
          children: [
            Positioned(
              key: const Key('dashboard-hero-box'),
              top: _headerHeight,
              left: kDashboardGutter,
              right: kDashboardGutter,
              height: heroHeight,
              child: widget.hero,
            ),
            RefreshIndicator(
              onRefresh: widget.onRefresh,
              edgeOffset: _headerHeight,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(height: _headerHeight + heroHeight),
                  ),
                  SliverToBoxAdapter(
                    child: MeasureSize(
                      onChange: (size) =>
                          setState(() => _layerHeight = size.height),
                      child: ClipRRect(
                        borderRadius: tokens.radiusLarge.borderRadius.copyWith(
                          bottomLeft: Radius.zero,
                          bottomRight: Radius.zero,
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: _layerBlur,
                            sigmaY: _layerBlur,
                          ),
                          child: ColoredBox(
                            color: tokens.layerFill,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                kDashboardGutter,
                                kDashboardGutter,
                                kDashboardGutter,
                                kDashboardGutter + bottomInset,
                              ),
                              child: _TileArea(items: widget.items),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: MeasureSize(
                onChange: (size) => setState(() => _headerHeight = size.height),
                child: widget.header,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The remote tier on wide screens: the header over the hero on the left,
/// and the tiles in a solid side column that scrolls on its own.
class _WideRemoteLayout extends StatelessWidget {
  const _WideRemoteLayout({
    required this.header,
    required this.hero,
    required this.items,
    required this.onRefresh,
  });

  final Widget header;
  final Widget hero;
  final List<TileGridItem> items;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final padding = MediaQuery.paddingOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    kDashboardGutter,
                    0,
                    kDashboardGutter,
                    kDashboardGutter + padding.bottom,
                  ),
                  child: hero,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: _sideColumnWidth,
          child: ColoredBox(
            color: tokens.surface,
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  kDashboardGutter,
                  kDashboardGutter + padding.top,
                  kDashboardGutter,
                  kDashboardGutter + padding.bottom,
                ),
                children: [_TileArea(items: items)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The Bluetooth tier: a slim pinned header over a full-screen tile grid.
class _BluetoothLayout extends StatefulWidget {
  const _BluetoothLayout({
    required this.header,
    required this.items,
    required this.columns,
    required this.onRefresh,
  });

  final Widget header;
  final List<TileGridItem> items;
  final int columns;
  final Future<void> Function() onRefresh;

  @override
  State<_BluetoothLayout> createState() => _BluetoothLayoutState();
}

class _BluetoothLayoutState extends State<_BluetoothLayout> {
  double _headerHeight = 0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: widget.onRefresh,
          edgeOffset: _headerHeight,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              kDashboardGutter,
              _headerHeight + 8,
              kDashboardGutter,
              kDashboardGutter + bottomInset,
            ),
            children: [_TileArea(items: widget.items, columns: widget.columns)],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: MeasureSize(
            onChange: (size) => setState(() => _headerHeight = size.height),
            child: widget.header,
          ),
        ),
      ],
    );
  }
}

/// The banner slot over the tile grid.
class _TileArea extends StatelessWidget {
  const _TileArea({required this.items, this.columns = kTileColumnsPhone});

  final List<TileGridItem> items;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DashboardBannerSlot(),
        TileGrid(columns: columns, items: items),
      ],
    );
  }
}

/// Reports its child's size after layout whenever it changes.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onChange, super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class RenderMeasureSize extends RenderProxyBox {
  RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final size = this.size;
    if (size == _reported) return;
    _reported = size;
    // Layout can't mark widgets dirty; report once this frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onChange(size);
    });
  }
}
