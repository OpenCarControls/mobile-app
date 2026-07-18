import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

class Vehicle3DViewer extends ConsumerStatefulWidget {
  const Vehicle3DViewer({super.key});

  @override
  ConsumerState<Vehicle3DViewer> createState() => _Vehicle3DViewerState();
}

class _Vehicle3DViewerState extends ConsumerState<Vehicle3DViewer> {
  final InAppLocalhostServer _localhostServer = InAppLocalhostServer();
  InAppWebViewController? _webViewController;
  bool _isServerRunning = false;
  bool _isModelLoaded = false;
  
  Timer? _hazardTimer;
  bool _hazardFlashState = false;

  @override
  void initState() {
    super.initState();
    _startServer();
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
    // Note: Do not close the localhost server here if you have multiple viewers or navigating back/forth
    // InAppLocalhostServer is typically kept alive or managed globally, but we'll close it safely
    if (_localhostServer.isRunning()) {
      _localhostServer.close();
    }
    _hazardTimer?.cancel();
    super.dispose();
  }

  void _pushStateToWebView() {
    if (_webViewController == null || !_isModelLoaded) return;
    
    final state = ref.read(vehicleStateProvider);
    final basicState = state.basicState as BasicState;

    final chargePort = basicState.chargePortState;
    final isPortOpen = chargePort != BasicState_ChargePortState.CHARGE_PORT_STATE_CLOSED && chargePort != BasicState_ChargePortState.CHARGE_PORT_STATE_UNSPECIFIED;
    final isAcConnected = chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CONNECTED || chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING;
    final isDcConnected = chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CONNECTED || chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING || chargePort == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_NEGOTIATING;

    final isLightsOn = basicState.areLightsOn;
    final isHazardsOn = basicState.areHazardLightsOn;
    final isBraking = isLightsOn; // Simple logic for now

    final stateJson = jsonEncode({
      'camera': {
        'targetTheta': isPortOpen ? (225 * pi / 180) : (45 * pi / 180),
      },
      'meshVisibility': {
        'Charger_L2': true,
        'Charger_DC': true,
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
        }
      ]
    });

    _webViewController?.evaluateJavascript(source: "window.setVehicleState('$stateJson');");
  }

  @override
  Widget build(BuildContext context) {
    if (!_isServerRunning) {
      return const Center(child: CircularProgressIndicator());
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

      _pushStateToWebView();
    });

    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri('http://localhost:8080/assets/web/index.html'),
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
                'ambientLight': { 'color': 0xffffff, 'intensity': 1.2 },
                'directionalLight': { 'color': 0xffffff, 'intensity': 3.0, 'position': { 'x': 10.0, 'y': 20.0, 'z': 10.0 } }
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
            _pushStateToWebView(); // Push initial state
          },
        );
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint('Three.js: ${consoleMessage.message}');
      },
    );
  }
}
