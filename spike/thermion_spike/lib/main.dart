import 'package:hero_harness/hero_harness.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import 'thermion_hero.dart';

void main() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    debugPrint('[thermion] ${r.level.name} ${r.loggerName}: ${r.message}');
  });
  runApp(
    SpikeApp(
      name: 'Thermion',
      tuning: kThermionTuning,
      builder: (context, config) => ThermionHero(config: config),
    ),
  );
}
