import 'package:hero_harness/hero_harness.dart';
import 'package:material_ui/material_ui.dart';

import 'webview_hero.dart';

void main() {
  runApp(
    SpikeApp(
      name: 'WebView',
      builder: (context, config) => WebViewHero(config: config),
    ),
  );
}
