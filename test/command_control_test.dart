import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/pending_command_controls_provider.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/tiles/command_control.dart';
import 'package:open_car_app/widgets/tiles/command_tile.dart';

const _command = (set: CommandSet.basic, id: 1);

class _Harness {
  final sends = <Completer<void>>[];

  Future<void> send() {
    final completer = Completer<void>();
    sends.add(completer);
    return completer.future;
  }
}

final tile = find.byType(InkWell);

void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());

  Future<ProviderContainer> pumpTile(
    WidgetTester tester, {
    CommandUiState availability = CommandUiState.enabled,
    bool disableAnimations = false,
    String reason = 'Fake reason',
  }) async {
    final container = ProviderContainer(
      overrides: [
        commandUiStateProvider.overrideWith((ref, key) => availability),
        commandUnavailableReasonProvider.overrideWith((ref, key) => reason),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(defaultSkin, Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 100,
                  height: 64,
                  child: CommandTile(
                    id: 'tile',
                    command: _command,
                    send: harness.send,
                    activityName: 'Lock doors',
                    semanticLabel: 'Doors, locked',
                    child: const Text('Doors'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  double shakeOf(WidgetTester tester) => tester
      .widget<Transform>(
        find
            .descendant(
              of: find.byType(CommandControl),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform
      .getTranslation()
      .x;

  double opacityOf(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(CommandControl),
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;

  bool hasDangerOverlay(WidgetTester tester) {
    return tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .any(
          (box) => switch (box.decoration) {
            ShapeDecoration(:final color?) => color.r > color.b && color.a < 1,
            _ => false,
          },
        );
  }

  testWidgets('sends on tap and is pending until the answer', (tester) async {
    final container = await pumpTile(tester);

    await tester.tap(tile);
    await tester.pump();

    expect(harness.sends, hasLength(1));
    expect(container.read(pendingCommandControlsProvider), {'tile'});

    harness.sends.single.complete();
    await tester.pump();

    expect(container.read(pendingCommandControlsProvider), isEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('ignores taps while pending', (tester) async {
    await pumpTile(tester);

    await tester.tap(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();

    expect(harness.sends, hasLength(1));
    harness.sends.single.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('pulses while pending and stops after', (tester) async {
    await pumpTile(tester);

    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacityOf(tester), lessThan(1));

    harness.sends.single.complete();
    await tester.pump();
    await tester.pump();
    expect(opacityOf(tester), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('does not pulse with reduced motion', (tester) async {
    await pumpTile(tester, disableAnimations: true);

    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacityOf(tester), 1);

    harness.sends.single.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a failure flashes, shakes and shows the snackbar', (
    tester,
  ) async {
    final container = await pumpTile(tester);

    await tester.tap(tile);
    await tester.pump();
    harness.sends.single.completeError(StateError('Refused'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(container.read(pendingCommandControlsProvider), isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(hasDangerOverlay(tester), isTrue);
    expect(shakeOf(tester), isNot(0));

    await tester.pump(const Duration(seconds: 1));
    expect(hasDangerOverlay(tester), isFalse);
    expect(shakeOf(tester), 0);
  });

  testWidgets('a failure holds still with reduced motion', (tester) async {
    await pumpTile(tester, disableAnimations: true);

    await tester.tap(tile);
    await tester.pump();
    harness.sends.single.completeError(StateError('Refused'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(hasDangerOverlay(tester), isTrue);
    expect(shakeOf(tester), 0);

    await tester.pump(const Duration(seconds: 2));
    expect(hasDangerOverlay(tester), isFalse);
  });

  testWidgets('a greyed-out tile does not send and says why', (tester) async {
    await pumpTile(tester, availability: CommandUiState.disabled);

    await tester.tap(tile);
    await tester.pump();

    expect(harness.sends, isEmpty);
    expect(find.text('Fake reason'), findsOneWidget);
  });

  testWidgets('a hidden command shows nothing', (tester) async {
    await pumpTile(tester, availability: CommandUiState.hidden);

    expect(find.text('Doors'), findsNothing);
  });

  testWidgets('the label includes the state', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTile(tester);
    expect(find.bySemanticsLabel('Doors, locked'), findsOneWidget);

    await tester.tap(tile);
    await tester.pump();
    expect(find.bySemanticsLabel('Doors, locked, sending'), findsOneWidget);
    harness.sends.single.complete();
    await tester.pumpAndSettle();

    await pumpTile(tester, availability: CommandUiState.disabled);
    await tester.pump();
    expect(
      find.bySemanticsLabel('Doors, locked, not available'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('the target is at least 44 dp', (tester) async {
    await pumpTile(tester);

    final size = tester.getSize(find.byType(CommandControl));
    expect(size.width, greaterThanOrEqualTo(kMinTouchTarget));
    expect(size.height, greaterThanOrEqualTo(kMinTouchTarget));
  });

  testWidgets('only the pressed control is pending when two share a command', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Widget control(String id) => CommandControl(
      activityName: 'Test',
      id: id,
      command: _command,
      send: harness.send,
      semanticLabel: id,
      shape: const StadiumBorder(),
      child: Text(id),
    );
    container.read(pendingCommandControlsProvider.notifier).begin('a');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(defaultSkin, Brightness.light),
          home: Scaffold(
            body: Column(
              children: [
                FractionallySizedBox(widthFactor: 0.5, child: control('a')),
                FractionallySizedBox(widthFactor: 0.5, child: control('b')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('a, sending'), findsOneWidget);
    expect(find.bySemanticsLabel('b, sending'), findsNothing);
    container.read(pendingCommandControlsProvider.notifier).end('a');
    await tester.pump();
  });

  group('commandUnavailableReason', () {
    String reason({
      TransportType transport = TransportType.ble,
      CommandSet set = CommandSet.basic,
      CanAccessState? canAccess,
      PhoneAccessState? phoneAccess,
    }) => commandUnavailableReason(
      transport: transport,
      set: set,
      canAccess: canAccess,
      phoneAccess: phoneAccess,
    );

    final notApproved = CanAccessState(
      carIdentityConfirmed: true,
      approval: CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_NOT_APPROVED,
    );
    final bonded = PhoneAccessState(
      trust: PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED,
    );

    test('advanced commands need Bluetooth', () {
      expect(
        reason(transport: TransportType.mqtt, set: CommandSet.advanced),
        contains('Bluetooth'),
      );
    });

    test('approval comes before validation, like the banners', () {
      expect(
        reason(canAccess: notApproved, phoneAccess: bonded),
        contains('approved'),
      );
    });

    test('an unvalidated phone', () {
      expect(reason(phoneAccess: bonded), contains('validated'));
    });

    test('says nothing specific when the app does not know', () {
      expect(reason(), 'Not available right now.');
    });
  });
}
