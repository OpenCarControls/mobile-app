import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_car_app/cars/egmp/egmp_definition.dart';
import 'package:open_car_app/cars/virtual_car/virtual_car_definition.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/config/theme_mode_config.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/theme_provider.dart';
import 'package:open_car_app/screens/theme_gallery_screen.dart';
import 'package:open_car_app/screens/tile_gallery_section.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/theme/radius_token.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);

/// The lowest opacity of an "on" tile's `accentContainer` fill.
const _minContainerOpacity = 0.80;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Every check from `docs/ui-theming.md#contrast` that [tokens] fails.
///
/// Translucent fills are measured over what can be behind them. The car's
/// paint isn't fixed, so black and white stand in for its extremes. On the
/// remote tier tiles sit on the frosted layer, so they never meet the hero
/// directly. The header is checked directly over it as a worst case.
List<String> _contrastFailures(AppTokens tokens) {
  final failures = <String>[];
  void check(String pair, Color a, Color b, double minimum) {
    final ratio = _contrast(a, b);
    if (ratio < minimum) {
      failures.add('$pair: ${ratio.toStringAsFixed(2)} < $minimum');
    }
  }

  final layerBackdrops = {
    'page': tokens.bg,
    'side column': tokens.surface,
    'black car under the layer': Color.alphaBlend(tokens.layerFill, _black),
    'white car under the layer': Color.alphaBlend(tokens.layerFill, _white),
  };
  for (final MapEntry(key: name, value: backdrop) in layerBackdrops.entries) {
    final tile = Color.alphaBlend(tokens.glassFill, backdrop);
    check('text on a tile ($name)', tokens.text, tile, 4.5);
    check('textSecondary on a tile ($name)', tokens.textSecondary, tile, 4.5);
    check('accent on a tile ($name)', tokens.accent, tile, 3);
    check('danger on a tile ($name)', tokens.danger, tile, 4.5);
    check(
      'onAccentContainer on a translucent accentContainer ($name)',
      tokens.onAccentContainer,
      Color.alphaBlend(
        tokens.accentContainer.withValues(alpha: _minContainerOpacity),
        backdrop,
      ),
      4.5,
    );
  }

  final headerBackdrops = {
    'page': tokens.bg,
    'black car': _black,
    'white car': _white,
  };
  for (final MapEntry(key: name, value: backdrop) in headerBackdrops.entries) {
    final header = Color.alphaBlend(tokens.headerFill, backdrop);
    check('text on the header ($name)', tokens.text, header, 4.5);
    check(
      'textSecondary on the header ($name)',
      tokens.textSecondary,
      header,
      4.5,
    );
  }

  check(
    'onAccentContainer on accentContainer',
    tokens.onAccentContainer,
    tokens.accentContainer,
    4.5,
  );
  check('accent as text on bg', tokens.accent, tokens.bg, 4.5);
  check('surface on an accent fill', tokens.surface, tokens.accent, 4.5);
  check('danger on bg', tokens.danger, tokens.bg, 4.5);
  check('onDanger on danger', tokens.onDanger, tokens.danger, 4.5);
  return failures;
}

/// All the skins the app can show.
Set<VehicleSkin> _registeredSkins() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return {
    defaultSkin,
    for (final vehicle in container.read(availableVehiclesProvider))
      vehicle.skin,
  };
}

void main() {
  group('contrast', () {
    test('every registered skin passes in both brightnesses', () {
      for (final skin in _registeredSkins()) {
        for (final brightness in Brightness.values) {
          expect(
            _contrastFailures(AppTokens.resolve(skin, brightness)),
            isEmpty,
            reason: '${skin.name}, ${brightness.name}',
          );
        }
      }
    });

    test('an unreadable skin is caught', () {
      const unreadable = SkinAccents(
        accent: Color(0xFFD0D8D6),
        accentContainer: Color(0xFFCCCCCC),
        onAccentContainer: Color(0xFFBBBBBB),
      );
      const skin = VehicleSkin(
        name: 'Unreadable',
        light: unreadable,
        dark: unreadable,
        shapes: SkinShapes.all(RadiusToken(2)),
      );

      final failures = _contrastFailures(
        AppTokens.resolve(skin, Brightness.light),
      );

      expect(
        failures,
        containsAll([
          contains('onAccentContainer on accentContainer'),
          contains('accent as text on bg'),
          contains('accent on a tile'),
          contains('surface on an accent fill'),
        ]),
      );
    });

    test('the Material roles stock widgets pair stay readable', () {
      for (final skin in _registeredSkins()) {
        for (final brightness in Brightness.values) {
          final scheme = buildAppTheme(skin, brightness).colorScheme;
          final pairs = {
            'dialog': (scheme.onSurface, scheme.surfaceContainerHigh),
            'dialog body': (
              scheme.onSurfaceVariant,
              scheme.surfaceContainerHigh,
            ),
            'snackbar': (scheme.onInverseSurface, scheme.inverseSurface),
            'button': (scheme.onPrimary, scheme.primary),
            'tonal button': (
              scheme.onSecondaryContainer,
              scheme.secondaryContainer,
            ),
            'error container': (scheme.onErrorContainer, scheme.errorContainer),
          };
          for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
            expect(
              _contrast(fg, bg),
              greaterThanOrEqualTo(4.5),
              reason: '$name, ${skin.name}, ${brightness.name}',
            );
          }
        }
      }
    });
  });

  group('skins', () {
    test('the virtual car has a different skin from E-GMP', () {
      expect(
        const VirtualCarDefinition().skin,
        isNot(same(const EgmpDefinition().skin)),
      );
    });

    test('the theme carries the tokens and the matching Material roles', () {
      final theme = buildAppTheme(defaultSkin, Brightness.dark);
      final tokens = theme.extension<AppTokens>()!;

      expect(theme.brightness, Brightness.dark);
      expect(tokens.accent, defaultSkin.dark.accent);
      expect(theme.colorScheme.primary, tokens.accent);
      expect(theme.colorScheme.error, tokens.danger);
      expect(theme.scaffoldBackgroundColor, tokens.bg);
    });

    test('danger and the neutrals do not depend on the skin', () {
      for (final brightness in Brightness.values) {
        final a = AppTokens.resolve(defaultSkin, brightness);
        final b = AppTokens.resolve(
          const VirtualCarDefinition().skin,
          brightness,
        );
        expect(b.bg, a.bg);
        expect(b.text, a.text);
        expect(b.glassFill, a.glassFill);
        expect(b.danger, a.danger);
        expect(b.onDanger, a.onDanger);
      }
    });
  });

  group('RadiusToken', () {
    test('a number is a rounded rectangle, "full" a stadium', () {
      expect(
        const RadiusToken(14).shape(),
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
      expect(RadiusToken.full.shape(), isA<StadiumBorder>());
    });

    test('lerp interpolates numbers and switches to or from "full"', () {
      expect(
        RadiusToken.lerp(const RadiusToken(2), const RadiusToken(16), 0.5),
        const RadiusToken(9),
      );
      expect(
        RadiusToken.lerp(const RadiusToken(2), RadiusToken.full, 0.4),
        const RadiusToken(2),
      );
      expect(
        RadiusToken.lerp(const RadiusToken(2), RadiusToken.full, 0.6),
        RadiusToken.full,
      );
    });

    test('tokens lerp across skins without losing "full"', () {
      final a = AppTokens.resolve(defaultSkin, Brightness.light);
      final b = AppTokens.resolve(
        const VirtualCarDefinition().skin,
        Brightness.dark,
      );

      expect(a.lerp(b, 0).radiusPill, RadiusToken.full);
      expect(a.lerp(b, 1).radiusPill, b.radiusPill);
      expect(a.lerp(b, 1).bg, b.bg);
      expect(a.lerp(null, 0.5), same(a));
    });
  });

  group('current skin', () {
    ProviderContainer containerFor(PairedVehicleConfig? config) {
      final container = ProviderContainer(
        overrides: [
          initialPairedVehicleConfigProvider.overrideWithValue(config),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is the default one with no vehicle', () {
      expect(containerFor(null).read(currentSkinProvider), same(defaultSkin));
    });

    test('follows the paired vehicle', () {
      final definition = const VirtualCarDefinition();
      final container = containerFor(
        PairedVehicleConfig(
          vehicleId: definition.platformName,
          bleRemoteId: '00:11:22:33:44:55',
          transportPreference: TransportPreference.http,
        ),
      );

      expect(container.read(currentSkinProvider), same(definition.skin));
    });
  });

  group('theme mode', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('follows the system by default', () async {
      expect(await loadThemeMode(), ThemeMode.system);
    });

    test('survives a restart', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).set(ThemeMode.dark);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(await loadThemeMode(), ThemeMode.dark);
    });

    test('ignores an unknown saved value', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'sepia'});

      expect(await loadThemeMode(), ThemeMode.system);
    });
  });

  group('gallery', () {
    Future<void> pumpGallery(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ThemeGalleryScreen())),
      );
    }

    testWidgets('lists every skin and switches between them', (tester) async {
      await pumpGallery(tester);

      BuildContext scaffold() => tester.element(find.byType(Scaffold));
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Boxy'), findsOneWidget);
      expect(scaffold().tokens.radiusPill, RadiusToken.full);

      await tester.tap(find.text('Boxy'));
      await tester.pump();

      expect(scaffold().tokens.radiusPill, const RadiusToken(2));
    });

    testWidgets('shows fake tiles that send nothing to the vehicle', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3000);
      addTearDown(tester.view.reset);
      await pumpGallery(tester);

      // The vehicle layouts section below has real tiles of the same names.
      Finder inSandbox(Finder finder) => find.descendant(
        of: find.byType(TileGallerySection),
        matching: finder,
      );
      expect(inSandbox(find.text('Doors')), findsOneWidget);
      expect(inSandbox(find.text('Climate')), findsOneWidget);
      expect(inSandbox(find.text('Odometer')), findsOneWidget);

      await tester.tap(inSandbox(find.bySemanticsLabel('Climate, off')));
      await tester.pump();
      await tester.pump(fakeCommandDelay);
      await tester.pumpAndSettle();

      expect(inSandbox(find.text('21°C')), findsOneWidget);
    });

    testWidgets('previews both brightnesses', (tester) async {
      await pumpGallery(tester);

      await tester.tap(find.text('Dark').first);
      await tester.pump();

      final context = tester.element(find.byType(Scaffold));
      expect(Theme.of(context).brightness, Brightness.dark);
    });
  });
}
