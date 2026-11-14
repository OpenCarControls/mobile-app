import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/cars/egmp/hero/egmp_motion.dart';
import 'package:open_car_app/cars/egmp/hero/egmp_scene.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/hero/glb_index.dart';
import 'package:open_car_app/widgets/hero/thermion_frame_rate.dart';

EgmpScene _scene(BasicState basic) => EgmpScene.fromSnapshot(
  VehicleSnapshot(basicState: basic, advancedState: AdvancedState()),
);

void main() {
  group('the shipped model', () {
    final index = GlbIndex.parse(
      File('assets/cars/egmp/2022_kia_ev6.glb').readAsBytesSync(),
    );

    test('has every material the hero drives', () {
      for (final material in [...kEgmpLightMaterials, 'Mat_PowerFlow']) {
        expect(index.materials[material], isNotEmpty, reason: material);
      }
    });

    test('has the cables, as meshes under the named nodes', () {
      expect(index.nodeMeshes['Charger_L2'], isNotEmpty);
      expect(index.nodeMeshes['Charger_DC'], isNotEmpty);
    });

    test('has an animation for every part the scene sets', () {
      final json = _glbJson('assets/cars/egmp/2022_kia_ev6.glb');
      final animations = {
        for (final a in json['animations'] as List) (a as Map)['name'],
      };
      expect(animations, containsAll(_scene(BasicState()).parts.keys));
    });
  });

  group('EgmpScene', () {
    test('a closed, parked car is all zeros from the front', () {
      final scene = _scene(BasicState());
      expect(scene.rearView, isFalse);
      expect(scene.parts.values, everyElement(0));
      expect(scene.cable, EgmpCable.none);
      expect(scene.powerFlow, isFalse);
    });

    test('an open port turns to the rear and opens the flap', () {
      final scene = _scene(
        BasicState(
          chargePortState: BasicState_ChargePortState.CHARGE_PORT_STATE_OPEN,
        ),
      );
      expect(scene.rearView, isTrue);
      expect(scene.part('Anim_ChargePort'), 1);
      expect(scene.cable, EgmpCable.none);
    });

    test('AC charging shows the L2 cable and DC the DC one', () {
      final ac = _scene(
        BasicState(
          chargePortState:
              BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING,
          powerFlowWatt: 7200,
        ),
      );
      expect(ac.cable, EgmpCable.l2);
      expect(ac.part('Anim_Connect_L2'), 1);
      expect(ac.part('Anim_Connect_DC'), 0);
      expect(ac.powerFlow, isTrue);

      final dc = _scene(
        BasicState(
          chargePortState:
              BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING,
        ),
      );
      expect(dc.cable, EgmpCable.dc);
      expect(dc.part('Anim_Connect_DC'), 1);
    });

    test('windows open to their step', () {
      final scene = _scene(
        BasicState(
          driverWindowPosition:
              BasicState_WindowPosition.WINDOW_POSITION_SLIGHTLY_OPEN,
          passengerWindowPosition:
              BasicState_WindowPosition.WINDOW_POSITION_FULLY_OPEN,
        ),
      );
      expect(scene.part('Anim_Window_FL'), 0.2);
      expect(scene.part('Anim_Window_FR'), 1);
    });

    test('equal states make equal scenes', () {
      expect(
        _scene(BasicState(isDriverDoorOpen: true)),
        _scene(BasicState(isDriverDoorOpen: true)),
      );
      expect(
        _scene(BasicState(isDriverDoorOpen: true)),
        isNot(_scene(BasicState())),
      );
    });

    test('hazards turn the side lights amber on the on half only', () {
      final scene = _scene(BasicState(areHazardLightsOn: true));
      expect(egmpLooks(scene, blinkOn: true)['TopDRLs']!.emissive, 0xffc400);
      expect(egmpLooks(scene, blinkOn: false)['TopDRLs']!.emissive, 0);
    });
  });

  group('EgmpMotion', () {
    EgmpMotion motion() =>
        EgmpMotion(durations: {'Anim_Door_FL': 1.0, 'Anim_Hood': 2.0});

    test('jumps to the target on the first frame', () {
      final m = motion();
      final frame = m.step(
        const EgmpScene(rearView: true, parts: {'Anim_Door_FL': 1}),
        0,
        instant: true,
      );
      expect(m.theta, kEgmpRearTheta);
      expect(m.part('Anim_Door_FL'), 1);
      expect(frame.cameraMoved, isTrue);
      expect(frame.moving, isFalse);
    });

    test('parts play at their own speed', () {
      final m = motion();
      const scene = EgmpScene(parts: {'Anim_Door_FL': 1, 'Anim_Hood': 1});
      final frame = m.step(scene, 0.5);
      expect(m.part('Anim_Door_FL'), 0.5);
      expect(m.part('Anim_Hood'), 0.25);
      expect(frame.parts.keys, unorderedEquals(['Anim_Door_FL', 'Anim_Hood']));
      expect(frame.moving, isTrue);
    });

    test('settles once everything reached the target', () {
      final m = motion();
      const scene = EgmpScene(parts: {'Anim_Door_FL': 1});
      m.step(scene, 1);
      final frame = m.step(scene, 0.1);
      expect(frame.parts, isEmpty);
      expect(frame.moving, isFalse);
      expect(frame.ambient, isFalse);
    });

    test('the camera glides, or snaps with reduced motion', () {
      final glide = motion();
      glide.step(const EgmpScene(rearView: true), 1 / 60);
      expect(glide.theta, greaterThan(kEgmpFrontTheta));
      expect(glide.theta, lessThan(kEgmpRearTheta));

      final snap = motion();
      final frame = snap.step(
        const EgmpScene(rearView: true),
        1 / 60,
        reducedMotion: true,
      );
      expect(snap.theta, kEgmpRearTheta);
      expect(frame.moving, isFalse);
    });

    test('the glow fades in, then scrolls at the ambient rate', () {
      final m = motion();
      const scene = EgmpScene(powerFlow: true);
      var frame = m.step(scene, 0.25);
      expect(m.flowStrength, inExclusiveRange(0, 1));
      expect(frame.moving, isTrue);
      frame = m.step(scene, 0.25);
      expect(m.flowStrength, 1);
      expect(frame.moving, isFalse);
      expect(frame.ambient, isTrue);
      final scroll = m.scrollU;
      frame = m.step(scene, 0.1);
      expect(m.scrollU, isNot(scroll));
      expect(frame.flowChanged, isTrue);
    });

    test('with reduced motion the glow is on without fade or scroll', () {
      final m = motion();
      const scene = EgmpScene(powerFlow: true);
      final frame = m.step(scene, 0.1, reducedMotion: true);
      expect(m.flowStrength, 1);
      expect(m.scrollU, 0);
      expect(frame.ambient, isFalse);
      expect(m.step(scene, 0.1, reducedMotion: true).flowChanged, isFalse);
    });

    test('hazards blink every half second, starting on', () {
      final m = motion();
      const scene = EgmpScene(hazards: true);
      expect(m.step(scene, 0).ambient, isTrue);
      expect(m.blinkOn, isTrue);
      m.step(scene, 0.4);
      expect(m.blinkOn, isTrue);
      m.step(scene, 0.2);
      expect(m.blinkOn, isFalse);
      m.step(scene, 0.5);
      expect(m.blinkOn, isTrue);
      m.step(const EgmpScene(), 0.1);
      expect(m.blinkOn, isFalse);
    });
  });

  group('ThermionFrameRate', () {
    test('runs at the highest request, idle rate without one', () {
      final applied = <int>[];
      final rate = ThermionFrameRate(applied.add);
      final a = Object(), b = Object();
      rate.request(a, 120);
      rate.request(b, 30);
      expect(rate.applied, 120);
      rate.release(a);
      expect(rate.applied, 30);
      rate.release(b);
      expect(rate.applied, kThermionIdleFps);
      expect(applied, [120, 30, kThermionIdleFps]);
    });
  });
}

Map<String, dynamic> _glbJson(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final length = data.getUint32(12, Endian.little);
  return jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
      as Map<String, dynamic>;
}
