import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:hero_harness/hero_harness.dart';
import 'package:material_ui/material_ui.dart';

/// The bundled Three.js viewer, the same files the app ships (`assets/web`).
final _viewerUrl = WebUri(
  'https://${WebViewAssetLoader.DEFAULT_DOMAIN}'
  '/assets/flutter_assets/assets/web/index.html',
);

/// The current Three.js WebView, as a baseline. It is
/// `vehicle_3d_viewer.dart` without the snapshot cache: the same viewer
/// bundle, settings and state payload, driven by the harness state.
class WebViewHero extends StatefulWidget {
  const WebViewHero({super.key, required this.config});

  final HeroRendererConfig config;

  @override
  State<WebViewHero> createState() => _WebViewHeroState();
}

class _WebViewHeroState extends State<WebViewHero> {
  InAppWebViewController? _controller;
  var _modelLoaded = false;
  String? _lastPushed;
  final _startup = Stopwatch()..start();

  HeroRendererConfig get _config => widget.config;

  void _log(String message) {
    if (!_config.compact || message.startsWith('!')) {
      _config.log('webview${_config.compact ? '(tile)' : ''}: $message');
    }
  }

  @override
  void didUpdateWidget(WebViewHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.state != _config.state) _push();
  }

  void _onRendererReady(List<dynamic> _) {
    _log('renderer ready at ${_startup.elapsedMilliseconds} ms');
    final isDark = _config.isDark;
    // From index.html in flutter_assets/assets/web/ to the harness's model.
    final modelPath = '../../${_config.model.assetKey}';
    final config = jsonEncode({
      'camera': {
        'frustumSize': 6.0,
        'position': {
          'radius': 10.0,
          'phi': 60.0 * math.pi / 180.0,
          'theta': 45.0 * math.pi / 180.0,
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
      'model': {'path': modelPath},
    });
    _controller?.evaluateJavascript(
      source: 'window.initRenderer(${jsonEncode(config)});',
    );
  }

  void _onModelLoaded(List<dynamic> _) {
    _log('model loaded, ready at ${_startup.elapsedMilliseconds} ms');
    _modelLoaded = true;
    _lastPushed = null;
    _push();
  }

  void _push() {
    final controller = _controller;
    if (controller == null || !_modelLoaded) return;
    final json = jsonEncode(_payload(_config.state));
    if (json == _lastPushed) return;
    _lastPushed = json;
    controller.evaluateJavascript(source: 'window.setVehicleState($json);');
  }

  /// The payload vehicle_3d_viewer.dart builds, from the harness state.
  static Map<String, Object> _payload(HeroSceneState s) {
    final lights = s.lightsOn ? 0xffffff : 0x000000;
    final lightsIntensity = s.lightsOn ? 50 : 0;
    return {
      'camera': {'targetTheta': (s.rearView ? 225 : 45) * math.pi / 180},
      'meshOpacity': {
        'Charger_L2': s.cable == Cable.l2 ? 1.0 : 0.0,
        'Charger_DC': s.cable == Cable.dc ? 1.0 : 0.0,
      },
      'animations': {
        for (final name in kPartAnimations) name: s.part(name),
        'Anim_Connect_L2': s.cable == Cable.l2,
        'Anim_Connect_DC': s.cable == Cable.dc,
      },
      'materials': [
        {'name': 'CarPaint', 'color': s.paint.toARGB32() & 0xffffff},
        {
          'name': 'Headlights',
          'emissive': lights,
          'intensity': lightsIntensity,
        },
        {
          'name': 'BottomDRLs',
          'emissive': lights,
          'intensity': lightsIntensity,
        },
        {
          'name': 'BrakeLight_Bar_Main',
          'emissive': 0xff0000,
          'intensity': s.lightsOn ? 20 : 0,
        },
        {
          'name': 'BrakeLight_Side_Main',
          'emissive': 0xff0000,
          'intensity': s.lightsOn ? 20 : 0,
        },
      ],
      'materialPulses': {
        'Mat_PowerFlow': {
          'active': s.powerFlow,
          'maxIntensity': 5.0,
          'scrollX': 0.18,
          'durationMs': 500,
        },
      },
      'blink': {
        'active': s.hazards,
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
            'emissive': lights,
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
    };
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
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
          _controller = controller;
          _log('webview created at ${_startup.elapsedMilliseconds} ms');
          controller.addJavaScriptHandler(
            handlerName: 'onRendererReady',
            callback: _onRendererReady,
          );
          controller.addJavaScriptHandler(
            handlerName: 'onModelLoaded',
            callback: _onModelLoaded,
          );
          controller.addJavaScriptHandler(
            handlerName: 'onStateSettled',
            callback: (_) {},
          );
        },
        onConsoleMessage: (controller, message) {
          _log('js: ${message.message}');
        },
      ),
    );
  }
}
