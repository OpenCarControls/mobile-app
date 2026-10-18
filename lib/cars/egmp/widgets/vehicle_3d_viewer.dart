import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

/// The bundled Three.js viewer (`web_3d/`, built into `assets/web/`), served
/// straight from the APK by Android's WebViewAssetLoader — no local server.
final _viewerUrl = WebUri(
  'https://${WebViewAssetLoader.DEFAULT_DOMAIN}'
  '/assets/flutter_assets/assets/web/index.html',
);

/// SharedPreferences keys used by older builds to store snapshots. Removed on
/// load: large values there are read into memory on every app start.
const _legacySnapshotPrefsKeys = [
  'vehicle_3d_last_frame',
  'vehicle_3d_last_frame_light',
  'vehicle_3d_last_frame_dark',
];

/// Snapshots older than this are shown grayed out.
const _kRecentThreshold = Duration(seconds: 30);

/// States drawn with the small L2 cable. `CONNECTED` (cable in, charger type not known
/// yet) uses it too until the 3D model gets a generic cable.
const _kL2CableStates = {
  BasicState_ChargePortState.CHARGE_PORT_STATE_CONNECTED,
  BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CONNECTED,
  BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING,
};

const _kDcConnectedStates = {
  BasicState_ChargePortState.CHARGE_PORT_STATE_DC_NEGOTIATING,
  BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CONNECTED,
  BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING,
};

bool _isRecent(VehicleSnapshot s) {
  if (s.isStateLive) return true;
  final lastUpdated = s.lastUpdated;
  if (lastUpdated == null) return false;
  return DateTime.now().difference(lastUpdated) < _kRecentThreshold;
}

class Vehicle3DViewer extends ConsumerStatefulWidget {
  const Vehicle3DViewer({super.key});

  @override
  ConsumerState<Vehicle3DViewer> createState() => _Vehicle3DViewerState();
}

class _Vehicle3DViewerState extends ConsumerState<Vehicle3DViewer>
    with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  bool _isModelLoaded = false;
  bool _showOverlay = true;
  bool _isImageLoaded = false;

  /// Last payload sent to the WebView, to skip redundant pushes.
  String? _lastPushedStateJson;

  Uint8List? _lastFrameLightBytes;
  Uint8List? _lastFrameDarkBytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLastFrames();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _webViewController?.evaluateJavascript(
        source: "window.dispatchEvent(new Event('resize'));",
      );
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _saveLastFrame();
    }
  }

  // ── Snapshot cache ─────────────────────────────────────────────────────────
  // The last rendered frame is shown while the WebView boots and grayed out
  // when the state is stale. Stored as PNG files, one per theme.

  Future<File> _snapshotFile({required bool isDark}) async {
    final dir = await getApplicationSupportDirectory();
    final name = isDark ? 'last_frame_dark.png' : 'last_frame_light.png';
    return File('${dir.path}/vehicle_3d/$name');
  }

  Future<Uint8List?> _readSnapshot({required bool isDark}) async {
    final file = await _snapshotFile(isDark: isDark);
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> _loadLastFrames() async {
    try {
      final light = await _readSnapshot(isDark: false);
      final dark = await _readSnapshot(isDark: true);
      if (!mounted) return;
      setState(() {
        _lastFrameLightBytes = light;
        _lastFrameDarkBytes = dark;
        _isImageLoaded = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isImageLoaded = true);
      });

      final prefs = await SharedPreferences.getInstance();
      for (final key in _legacySnapshotPrefsKeys) {
        await prefs.remove(key);
      }
    } catch (e) {
      dev.log('Failed to load last frame: $e', name: 'Vehicle3DViewer');
    }
  }

  Future<void> _saveLastFrame() async {
    final controller = _webViewController;
    if (controller == null || !_isModelLoaded) return;
    // Read the theme before any await: the context may be gone afterwards.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    try {
      final result = await controller.evaluateJavascript(
        source: 'window.getSnapshot();',
      );
      const prefix = 'data:image/png;base64,';
      if (result is! String || !result.startsWith(prefix)) return;
      final base64String = result.substring(prefix.length);

      // If it's too small, it's likely just an empty transparent PNG.
      if (base64String.length <= 1000) {
        dev.log('Frame was too small (empty image)', name: 'Vehicle3DViewer');
        return;
      }

      final bytes = base64Decode(base64String);
      final file = await _snapshotFile(isDark: isDark);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);

      if (mounted) {
        setState(() {
          if (isDark) {
            _lastFrameDarkBytes = bytes;
          } else {
            _lastFrameLightBytes = bytes;
          }
        });
      }
    } catch (e) {
      dev.log('Failed to save 3D frame: $e', name: 'Vehicle3DViewer');
    }
  }

  // ── State → WebView ────────────────────────────────────────────────────────
  // Flutter only sends target values; fades, the power-flow pulse and hazard
  // blinking are animated by the render loop in web_3d/src/app.js.

  String _buildStateJson(VehicleSnapshot state) {
    final basicState = state.basicState as BasicState;

    final chargePort = basicState.chargePortState;
    final isPortOpen =
        chargePort != BasicState_ChargePortState.CHARGE_PORT_STATE_CLOSED &&
        chargePort != BasicState_ChargePortState.CHARGE_PORT_STATE_UNSPECIFIED;
    final isL2CableShown = _kL2CableStates.contains(chargePort);
    final isDcConnected = _kDcConnectedStates.contains(chargePort);

    final isLightsOn = basicState.areLightsOn;
    final isBraking = isLightsOn; // Simple logic for now
    final lightsEmissive = isLightsOn ? 0xffffff : 0x000000;
    final lightsIntensity = isLightsOn ? 50 : 0;

    return jsonEncode({
      'camera': {
        'targetTheta': isPortOpen ? (225 * pi / 180) : (45 * pi / 180),
      },
      'meshOpacity': {
        'Charger_L2': isL2CableShown ? 1.0 : 0.0,
        'Charger_DC': isDcConnected ? 1.0 : 0.0,
      },
      'animations': {
        'Anim_ChargePort': isPortOpen,
        'Anim_Connect_L2': isL2CableShown,
        'Anim_Connect_DC': isDcConnected,
        'Anim_Door_FL': basicState.isDriverDoorOpen,
        'Anim_Door_FR': basicState.isPassengerDoorOpen,
        'Anim_Door_RL': basicState.isRearLeftDoorOpen,
        'Anim_Door_RR': basicState.isRearRightDoorOpen,
        'Anim_Hood': basicState.isFrunkOpen,
        'Anim_Trunk': basicState.isTrunkOpen,
        'Anim_Window_FL': basicState.isDriverWindowOpen,
        'Anim_Window_FR': basicState.isPassengerWindowOpen,
        'Anim_Window_RL': basicState.isRearLeftWindowOpen,
        'Anim_Window_RR': basicState.isRearRightWindowOpen,
      },
      'materials': [
        {
          'name': 'Headlights',
          'emissive': lightsEmissive,
          'intensity': lightsIntensity,
        },
        {
          'name': 'BottomDRLs',
          'emissive': lightsEmissive,
          'intensity': lightsIntensity,
        },
        {
          'name': 'BrakeLight_Bar_Main',
          'emissive': 0xff0000,
          'intensity': isBraking ? 20 : 0,
        },
        {
          'name': 'BrakeLight_Side_Main',
          'emissive': 0xff0000,
          'intensity': isBraking ? 20 : 0,
        },
      ],
      'materialPulses': {
        'Mat_PowerFlow': {
          'active': basicState.powerFlowWatt != 0,
          'maxIntensity': 5.0,
          'scrollX': 0.18,
          'durationMs': 500,
        },
      },
      'blink': {
        'active': basicState.areHazardLightsOn,
        'periodMs': 500,
        'on': [
          {
            'name': 'TopDRLs',
            'color': 0xffc400,
            'emissive': 0xffc400,
            'intensity': 50,
          },
          {
            'name': 'MirrorTurnSignals',
            'color': 0xffc400,
            'emissive': 0xffc400,
            'intensity': 50,
          },
          {
            'name': 'BrakeLight_Side_Base1',
            'emissive': 0x970000,
            'intensity': 20,
          },
        ],
        'off': [
          {
            'name': 'TopDRLs',
            'color': 0xffffff,
            'emissive': lightsEmissive,
            'intensity': lightsIntensity,
          },
          {
            'name': 'MirrorTurnSignals',
            'color': 0xe7e7e7,
            'emissive': 0x000000,
            'intensity': 0,
          },
          {
            'name': 'BrakeLight_Side_Base1',
            'emissive': 0x970000,
            'intensity': 0,
          },
        ],
      },
    });
  }

  void _pushStateToWebView(VehicleSnapshot state) {
    final controller = _webViewController;
    if (controller == null || !_isModelLoaded) return;

    final stateJson = _buildStateJson(state);
    if (stateJson == _lastPushedStateJson) return;
    _lastPushedStateJson = stateJson;

    // JSON is a valid JS expression, so pass it as an object literal.
    controller.evaluateJavascript(
      source: 'window.setVehicleState($stateJson);',
    );
  }

  void _setOverlayVisible(bool visible) {
    if (visible) {
      if (mounted) setState(() => _showOverlay = true);
      return;
    }
    // Let the WebView render the live state before fading the snapshot out.
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  void _onRendererReady(List<dynamic> _) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final configJson = jsonEncode({
      'camera': {
        'frustumSize': 6.0,
        'position': {
          'radius': 10.0,
          'phi': 60.0 * pi / 180.0,
          'theta': 45.0 * pi / 180.0,
        },
      },
      'lighting': {
        'ambientLight': {'color': 0xffffff, 'intensity': isDark ? 1.2 : 3.5},
        'directionalLight': {
          'color': 0xffffff,
          'intensity': isDark ? 3.0 : 6.0,
          'position': {'x': 10.0, 'y': 20.0, 'z': 10.0},
        },
      },
      'model': {'path': '../cars/egmp/2022_kia_ev6.glb'},
      'shader': {'fadeStart': 4.0, 'fadeEnd': 4.25},
    });
    // initRenderer expects a JSON string; jsonEncode makes it a JS literal.
    _webViewController?.evaluateJavascript(
      source: 'window.initRenderer(${jsonEncode(configJson)});',
    );
  }

  void _onModelLoaded(List<dynamic> _) {
    if (!mounted) return;
    setState(() => _isModelLoaded = true);
    _lastPushedStateJson = null;
    // The first push snaps instantly to the cached state.
    final state = ref.read(vehicleStateProvider);
    _pushStateToWebView(state);
    if (_isRecent(state)) _setOverlayVisible(false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vehicleStateProvider);

    ref.listen(vehicleStateProvider, (previous, next) {
      // Fade out the snapshot overlay when live, fade it back in when stale.
      if (previous != null &&
          _isModelLoaded &&
          _isRecent(previous) != _isRecent(next)) {
        _setOverlayVisible(!_isRecent(next));
      }
      _pushStateToWebView(next);
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lastFrameBytes = isDark ? _lastFrameDarkBytes : _lastFrameLightBytes;
    final applyGrayFilter = !_isRecent(state);

    final snapshot = lastFrameBytes == null
        ? null
        : Image.memory(lastFrameBytes, fit: BoxFit.fitHeight);

    return Stack(
      children: [
        IgnorePointer(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: _viewerUrl),
            initialSettings: InAppWebViewSettings(
              transparentBackground: true,
              disableHorizontalScroll: true,
              disableVerticalScroll: true,
              supportZoom: false,
              webViewAssetLoader: WebViewAssetLoader(
                pathHandlers: [AssetsPathHandler(path: '/assets/')],
              ),
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
              controller.addJavaScriptHandler(
                handlerName: 'onRendererReady',
                callback: _onRendererReady,
              );
              controller.addJavaScriptHandler(
                handlerName: 'onModelLoaded',
                callback: _onModelLoaded,
              );
              // All animations and camera moves have finished.
              controller.addJavaScriptHandler(
                handlerName: 'onStateSettled',
                callback: (_) {
                  if (mounted) _saveLastFrame();
                },
              );
            },
            onConsoleMessage: (controller, consoleMessage) {
              dev.log(consoleMessage.message, name: 'Three.js');
            },
          ),
        ),
        if (snapshot == null && !_isModelLoaded)
          const Center(child: CircularProgressIndicator()),
        if (snapshot != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: (_showOverlay && _isImageLoaded) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: applyGrayFilter
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.matrix([
                          0.33, 0.59, 0.11, 0, 0, //
                          0.33, 0.59, 0.11, 0, 0, //
                          0.33, 0.59, 0.11, 0, 0, //
                          0, 0, 0, 1, 0, //
                        ]),
                        child: snapshot,
                      )
                    : snapshot,
              ),
            ),
          ),
      ],
    );
  }
}
