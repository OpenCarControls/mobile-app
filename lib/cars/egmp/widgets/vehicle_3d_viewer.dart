import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

class Vehicle3DViewer extends ConsumerStatefulWidget {
  const Vehicle3DViewer({super.key});

  @override
  ConsumerState<Vehicle3DViewer> createState() => _Vehicle3DViewerState();
}

class _Vehicle3DViewerState extends ConsumerState<Vehicle3DViewer> with TickerProviderStateMixin, WidgetsBindingObserver {
  final InAppLocalhostServer _localhostServer = InAppLocalhostServer(documentRoot: 'assets');
  InAppWebViewController? _webViewController;
  bool _isServerRunning = false;
  bool _isModelLoaded = false;
  bool _showOverlay = true;
  bool _isImageLoaded = false;
  
  Uint8List? _lastFrameBytes;
  Timer? _screenshotTimer;
  
  Timer? _hazardTimer;
  bool _hazardFlashState = false;

  late final AnimationController _acAnimController;
  late final AnimationController _dcAnimController;
  late final AnimationController _powerFlowAnimController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _acAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _dcAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _powerFlowAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    
    _acAnimController.addListener(_pushStateToWebView);
    _dcAnimController.addListener(_pushStateToWebView);
    _powerFlowAnimController.addListener(_pushStateToWebView);
    
    _loadLastFrame();
    _startServer();
  }

  Future<void> _loadLastFrame() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base64String = prefs.getString('vehicle_3d_last_frame');
      if (base64String != null && mounted) {
        setState(() {
          _lastFrameBytes = base64Decode(base64String);
          _isImageLoaded = false;
        });
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isImageLoaded = true;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load last frame: $e');
    }
  }

  Future<void> _saveLastFrame() async {
    if (_webViewController == null || !_isModelLoaded) return;
    try {
      final result = await _webViewController!.evaluateJavascript(source: "window.getSnapshot();");
      
      if (result != null && result is String && result.startsWith('data:image/png;base64,')) {
        final base64String = result.substring(22);
        
        // If it's too small, it's likely just an empty transparent PNG
        if (base64String.length > 1000) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('vehicle_3d_last_frame', base64String);
        } else {
          debugPrint('Frame was too small (empty transparent image).');
        }
      }
    } catch (e) {
      debugPrint('Failed to save 3D frame: $e');
    }
  }

  Future<void> _startServer() async {
    if (!_localhostServer.isRunning()) {
        await _localhostServer.start();
    }
    if (mounted) {
      setState(() {
        _isServerRunning = true;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Note: Do not close the localhost server here if you have multiple viewers or navigating back/forth
    // InAppLocalhostServer is typically kept alive or managed globally, but we'll close it safely
    if (_localhostServer.isRunning()) {
      _localhostServer.close();
    }
    _screenshotTimer?.cancel();
    _hazardTimer?.cancel();
    _acAnimController.dispose();
    _dcAnimController.dispose();
    _powerFlowAnimController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _webViewController?.evaluateJavascript(source: "window.dispatchEvent(new Event('resize'));");
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _saveLastFrame();
    }
  }

  String _buildStateJson(VehicleSnapshot state) {
    final basicState = state.basicState as BasicState;

    final chargePort = basicState.chargePortState;
    final isPortOpen = chargePort != BasicState_ChargePortState.CHARGE_PORT_STATE_CLOSED && chargePort != BasicState_ChargePortState.CHARGE_PORT_STATE_UNSPECIFIED;
    final isAcConnected = chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CONNECTED || chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING;
    final isDcConnected = chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CONNECTED || chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING || chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_NEGOTIATING;

    final isLightsOn = basicState.areLightsOn;
    final isHazardsOn = basicState.areHazardLightsOn;
    final isBraking = isLightsOn; // Simple logic for now

    return jsonEncode({
      'camera': {
        'targetTheta': isPortOpen ? (225 * pi / 180) : (45 * pi / 180),
      },
      'meshOpacity': {
        'Charger_L2': _acAnimController.value,
        'Charger_DC': _dcAnimController.value,
      },
      'animations': {
        'Anim_ChargePort': isPortOpen,
        'Anim_Connect_L2': isAcConnected,
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
          'emissive': isLightsOn ? 0xffffff : 0x000000,
          'intensity': isLightsOn ? 50 : 0,
        },
        {
          'name': 'TopDRLs',
          'color': (_hazardFlashState && isHazardsOn) ? 0xffc400 : 0xffffff,
          'emissive': (_hazardFlashState && isHazardsOn) ? 0xffc400 : (isLightsOn ? 0xffffff : 0x000000),
          'intensity': (_hazardFlashState && isHazardsOn) ? 50 : (isLightsOn ? 50 : 0),
        },
        {
          'name': 'BottomDRLs',
          'emissive': isLightsOn ? 0xffffff : 0x000000,
          'intensity': isLightsOn ? 50 : 0,
        },
        {
          'name': 'MirrorTurnSignals',
          'color': (_hazardFlashState && isHazardsOn) ? 0xffc400 : 0xe7e7e7,
          'emissive': (_hazardFlashState && isHazardsOn) ? 0xffc400 : 0x000000,
          'intensity': (_hazardFlashState && isHazardsOn) ? 50 : 0,
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
        {
          'name': 'BrakeLight_Side_Base1',
          'emissive': 0x970000,
          'intensity': (_hazardFlashState && isHazardsOn) ? 20 : 0,
        },
        {
          'name': 'Mat_PowerFlow',
          'emissive': 0xffffff,
          'intensity': Curves.easeInOut.transform(_powerFlowAnimController.value) * 5.0,
          'scrollX': _powerFlowAnimController.value > 0.0 ? 0.18 : 0.0,
          'resetScroll': _powerFlowAnimController.value == 0.0,
        }
      ]
    });
  }

  void _pushStateToWebView() {
    if (_webViewController == null || !_isModelLoaded) return;
    
    final state = ref.read(vehicleStateProvider);
    final stateJson = _buildStateJson(state);
    
    _webViewController?.evaluateJavascript(source: "window.setVehicleState('$stateJson');");
    
    _screenshotTimer?.cancel();
    _screenshotTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _saveLastFrame();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vehicleStateProvider);
    final basicState = state.basicState as BasicState;
    final chargePort = basicState.chargePortState;
    
    final isAcConnected = chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CONNECTED || chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING;
    if (isAcConnected && _acAnimController.status != AnimationStatus.forward && _acAnimController.status != AnimationStatus.completed) {
      _acAnimController.forward();
    } else if (!isAcConnected && _acAnimController.status != AnimationStatus.reverse && _acAnimController.status != AnimationStatus.dismissed) {
      _acAnimController.reverse();
    }

    final isDcConnected = chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CONNECTED || chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING || chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_NEGOTIATING;
    if (isDcConnected && _dcAnimController.status != AnimationStatus.forward && _dcAnimController.status != AnimationStatus.completed) {
      _dcAnimController.forward();
    } else if (!isDcConnected && _dcAnimController.status != AnimationStatus.reverse && _dcAnimController.status != AnimationStatus.dismissed) {
      _dcAnimController.reverse();
    }

    final isCharging = basicState.powerFlowWatt != 0;
    if (isCharging && _powerFlowAnimController.status != AnimationStatus.forward && _powerFlowAnimController.status != AnimationStatus.completed) {
      _powerFlowAnimController.forward();
    } else if (!isCharging && _powerFlowAnimController.status != AnimationStatus.reverse && _powerFlowAnimController.status != AnimationStatus.dismissed) {
      _powerFlowAnimController.reverse();
    }

    // Listen to vehicle state and push changes to the WebView
    ref.listen(vehicleStateProvider, (previous, next) {
      final wasHazardsOn = (previous?.basicState as BasicState?)?.areHazardLightsOn ?? false;
      final isHazardsOn = (next.basicState as BasicState).areHazardLightsOn;

      if (isHazardsOn && !wasHazardsOn) {
        _hazardFlashState = true;
        _hazardTimer?.cancel();
        _hazardTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
          if (mounted) {
            setState(() {
              _hazardFlashState = !_hazardFlashState;
            });
            _pushStateToWebView();
          }
        });
      } else if (!isHazardsOn && wasHazardsOn) {
        _hazardTimer?.cancel();
        _hazardTimer = null;
        _hazardFlashState = false;
      }

      // Fade out the snapshot overlay when live, fade it back in when stale
      if (previous != null && previous.isStateLive != next.isStateLive && _isModelLoaded) {
        if (next.isStateLive) {
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) {
              setState(() {
                _showOverlay = false;
              });
            }
          });
        } else {
          if (mounted) {
            setState(() {
              _showOverlay = true;
            });
          }
        }
      }

      _pushStateToWebView();
    });

    Widget webView = _isServerRunning ? IgnorePointer(
      child: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri('http://localhost:8080/web/index.html'),
        ),
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          disableHorizontalScroll: true,
          disableVerticalScroll: true,
          supportZoom: false,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;
          
          // Add JS handler to know when the generic renderer script is loaded
          controller.addJavaScriptHandler(
            handlerName: 'onRendererReady',
            callback: (args) {
              final configJson = jsonEncode({
                'camera': {
                  'frustumSize': 6.0,
                  'position': { 'radius': 10.0, 'phi': 60.0 * pi / 180.0, 'theta': 45.0 * pi / 180.0 }
                },
                'lighting': {
                  'ambientLight': { 'color': 0xffffff, 'intensity': Theme.of(context).brightness == Brightness.dark ? 1.2 : 3.5 },
                  'directionalLight': { 'color': 0xffffff, 'intensity': Theme.of(context).brightness == Brightness.dark ? 3.0 : 6.0, 'position': { 'x': 10.0, 'y': 20.0, 'z': 10.0 } }
                },
                'model': {
                  'path': '../cars/egmp/2022_kia_ev6.glb'
                },
                'shader': {
                  'fadeStart': 4.0,
                  'fadeEnd': 4.25
                }
              });
              controller.evaluateJavascript(source: "window.initRenderer('$configJson');");
            },
          );
          
          // Add JS handler to know when model is loaded
          controller.addJavaScriptHandler(
            handlerName: 'onModelLoaded',
            callback: (args) {
              _isModelLoaded = true;
              _pushStateToWebView(); // First push instantly snaps to the cached state from VehicleStateProvider

              final isLive = ref.read(vehicleStateProvider).isStateLive;
              if (isLive) {
                Future.delayed(const Duration(milliseconds: 150), () {
                  if (mounted) {
                    setState(() {
                      _showOverlay = false;
                    });
                  }
                });
              }
            },
          );

          // Listen for when all animations and camera moves have completely finished
          controller.addJavaScriptHandler(
            handlerName: 'onStateSettled',
            callback: (args) {
              if (mounted) {
                _screenshotTimer?.cancel();
                _saveLastFrame();
              }
            },
          );
        },
        onConsoleMessage: (controller, consoleMessage) {
          debugPrint('Three.js: ${consoleMessage.message}');
        },
      ),
    ) : const SizedBox.shrink();

    return Stack(
      children: [
        webView,
        if (!_isServerRunning && _lastFrameBytes == null)
          const Center(child: CircularProgressIndicator()),
        if (_lastFrameBytes != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: (_showOverlay && _isImageLoaded) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    0.33, 0.59, 0.11, 0, 0,
                    0.33, 0.59, 0.11, 0, 0,
                    0.33, 0.59, 0.11, 0, 0,
                    0,    0,    0,    1, 0,
                  ]),
                  child: Image.memory(
                    _lastFrameBytes!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
