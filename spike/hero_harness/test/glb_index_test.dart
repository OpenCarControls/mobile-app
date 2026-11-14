import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hero_harness/hero_harness.dart';

void main() {
  for (final file in ['ev6_meshopt.glb', 'ev6_raw.glb']) {
    test('indexes $file', () {
      final index = GlbIndex.parse(
        File('assets/models/$file').readAsBytesSync(),
      );
      for (final material in [
        'CarPaint',
        'Headlights',
        'TopDRLs',
        'BottomDRLs',
        'BrakeLight_Bar_Main',
        'BrakeLight_Side_Main',
        'BrakeLight_Side_Base1',
        'MirrorTurnSignals',
        'Mat_PowerFlow',
      ]) {
        expect(index.materials[material], isNotEmpty, reason: material);
      }
      expect(index.nodeMeshes['Charger_L2'], isNotEmpty);
      expect(index.nodeMeshes['Charger_DC'], isNotEmpty);
      // ignore: avoid_print
      print('$file: ${index.extensionsUsed}\n'
          '  Headlights ${index.materials['Headlights']}\n'
          '  Mat_PowerFlow ${index.materials['Mat_PowerFlow']}\n'
          '  Charger_L2 ${index.nodeMeshes['Charger_L2']}');
    });
  }
}
