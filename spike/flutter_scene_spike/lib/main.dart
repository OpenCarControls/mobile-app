import 'package:hero_harness/hero_harness.dart';
import 'package:material_ui/material_ui.dart';

import 'flutter_scene_hero.dart';

void main() {
  runApp(
    SpikeApp(
      name: 'flutter_scene',
      tuning: kFlutterSceneTuning,
      builder: (context, config) => FlutterSceneHero(config: config),
    ),
  );
}
