# Theming & skins

How colours, shapes and other visual tokens work in the [shared dashboard](ui.md), and what a vehicle platform may customise. Mockups: [`ui/mockups`](ui/mockups/README.md).

## Model
The resolved look is **brightness × skin**:

*   **Brightness:** light or dark. Follows the system setting unless the user overrides it. The app owns this, never the platform.
*   **Skin:** chosen by the vehicle platform. It customises *shape* and *accent colours* only. A Cybertruck-like platform ships a boxy skin; a Fiat 500-like one ships a very rounded, colourful skin. Layout, spacing, type scale, icon set and motion are not part of a skin, so every platform feels like the same app.

A skin is small on purpose:

| Part | What the platform supplies |
|---|---|
| Accent colours, per brightness | `accent`, `accentContainer`, `onAccentContainer` |
| Shape set | five radii (below) |

Everything else (backgrounds, surfaces, text, outlines, frosted-glass fills) is derived from the brightness and is the same for all skins. These neutrals are greys with a tiny blue tint: red 2 below and blue 3 above the green value (white stays white). If a platform later needs more (a different surface tint, a custom font), add it to the skin deliberately, with a contrast check.

## Colour tokens
Default skin (the mockups). `accent`, `accentContainer` and `onAccentContainer` are the skin's; the rest are shared.

| Token | Role | Light | Dark |
|---|---|---|---|
| `bg` | Page behind the hero | `#E9EBEE` | `#0E1013` |
| `surface` | Solid surfaces: pill, round buttons, side column | `#FFFFFF` | `#191B1E` |
| `text` | Primary text, glyph outlines | `#15171A` | `#EAECEF` |
| `textSecondary` | Range, captions, labels | `#515356` | `#AAACAF` |
| `accent` | Level fill, active power button, charging text, dots | `#1C68C5` | `#91B8EB` |
| `accentContainer` | Fill of an "on" button (80–95% opaque over the layer) | `#D5E4F8` | `#163B66` |
| `onAccentContainer` | Text and icons on `accentContainer` | `#0B2A52` | `#D5E6FF` |
| `outline` | Borders of solid controls, level track | `#CACCCF` | `#393B3E` |
| `tileBorder` | 1 px border of frosted surfaces | 12% `text` | 14% `text` |
| `glassFill` | Frosted tiles and cards | white at 82% | `#26282B` at 80% |
| `layerFill` | The frosted layer behind the tiles on the remote tier | `bg` at 66% | `bg` at 66% |
| `headerFill` | The pinned header | `bg` at 85% | `bg` at 80% |
| `danger` | Destructive actions and failures (Unpair, a failed command's detail, the pairing error) | `#B3261E` | `#FFB4AB` |
| `onDanger` | Text on a `danger` fill (the confirm button of a destructive dialog) | `#FFFFFF` | `#3B0A07` |
| `editScrim` | Overlay that dims a tile in edit mode | `bg` at 60% | `bg` at 60% |
| `modalScrim` | Dims the screen behind a popover or dialog | black at 40% | black at 60% |

`danger` and `onDanger` are shared by all skins; a skin does not change them.

Alternate skins used in the mockups:

| Skin | Light `accent` / container / on-container | Dark `accent` / container / on-container |
|---|---|---|
| Default (blue) | `#1C68C5` / `#D5E4F8` / `#0B2A52` | `#91B8EB` / `#163B66` / `#D5E6FF` |
| Boxy (steel) | `#37474F` / `#CFD8DC` / `#1C262B` | `#CFD8DC` / `#37474F` / `#ECEFF1` |
| Rounded (rose) | `#B3245A` / `#FCD6E2` / `#5B0F2C` | `#FF8FB1` / `#5E1A34` / `#FFD9E5` |

Each paired vehicle has its own skin. The vehicle switcher and the Vehicles screen draw each vehicle's avatar with its `accentContainer` and `onAccentContainer`, so the cars are easy to tell apart (see [Vehicles](ui-screens.md#vehicles)).

The hero's own colours (car paint, road, ground) belong to the 3D scene, not to the skin. The charge-port glow and cable use `accent`.

## Shape tokens
| Token | Used for | Default | Boxy | Rounded |
|---|---|---|---|---|
| `radiusSmall` | Small icon buttons in the climate panel, segmented controls | 14 | 2 | 22 |
| `radiusMedium` | Tiles, the climate bar, cards, wizard buttons, dialog buttons | 16 | 2 | 28 |
| `radiusLarge` | Popovers and dialogs, and the top corners of the remote tier's frosted layer | 24 | 2 | 40 |
| `radiusPill` | Connection pill, chips, switches, the temperature stepper | full (stadium) | 2 | full |
| `radiusRound` | Circular icon buttons (power, +/−, settings, back), vehicle avatars | full (circle) | 2 | full |

Rules:
*   A radius is a plain number in dp, or "full" (stadium or circle). A boxy skin sets all five small; a rounded one sets them large or full.
*   Nothing else in a component hard-codes a radius.
*   Buttons are never narrower than their touch target, whatever the radius.

## Glass
The tiles sit on frosted translucent surfaces: a blur plus a translucent fill and a hairline border. On the remote tier they float over the hero on a frosted layer; on the Bluetooth tier, with no hero, they sit on the page colour and only the header is blurred. The mockup uses a 14 dp blur on tiles and cards, 18 dp on the remote tier's layer and 16 dp on the header. In Flutter each `BackdropFilter` costs a render pass, so use one on the layer (remote) and one on the header, and make the tiles inside plain translucent fills. The look is the same and it is far cheaper than nesting blurs. Check scrolling frame times on a mid-range phone.

## Typography and icons
Both are shared across skins:

*   One typeface family at a few weights: Manrope 400–800, bundled in `assets/fonts` under the SIL Open Font License. It is a variable font and `FontWeight` drives its weight axis, so one file covers every weight.
*   Scale used by the mockups: vehicle name 20/800, level 26/800, range 15/600, button title 12/700, caption 12/400, stat value 18/800, climate target 22/800.
*   Standard icons from Material Symbols, outlined style (the `material_symbols_icons` package), not the demo drawings in the mockups. Its fill axis can show on and off from one glyph (`Icon(Symbols.lock, fill: 1)`), but line-only glyphs like defrost and seat heating barely change, so those rely on the tile's fill and colour. A platform may override an individual icon where the standard set lacks one.

## Contrast
Skins must pass these checks in both brightnesses, against the worst case behind translucent fills. The car's paint isn't fixed, so black and white stand in for its extremes:

*   A frosted tile is measured over the page, the solid side column, and a black or white car under `layerFill`. Tiles are never directly over the hero.
*   The header is measured over the page and directly over a black or white car, the worst case for anything that scrolls or draws under it.
*   An "on" tile is measured at the lowest opacity of its fill, 80%.

| Pair | Minimum |
|---|---|
| `text` and `textSecondary` on a frosted tile | 4.5:1 |
| `text` and `textSecondary` on the header | 4.5:1 |
| `onAccentContainer` on `accentContainer` | 4.5:1 |
| `accent` as text on `bg` (the charging text) | 4.5:1 |
| `accent` against a tile (active power button, level fill, icon strokes) | 3:1 |
| `surface` text on an `accent` fill (active power button) | 4.5:1 |
| `danger` as text on `bg` and on a frosted tile | 4.5:1 |
| `onDanger` on a `danger` fill | 4.5:1 |

`danger` is the same for every skin. `test/theme_test.dart` runs these checks over every registered skin, and over the Material colour roles derived from the tokens, so a new platform cannot ship an unreadable skin. The rounded skin isn't registered yet, so it isn't covered.

## Implementation notes
*   `buildAppTheme(skin, brightness)` builds a `ThemeData`. Resolve it at `MaterialApp.theme` and `darkTheme` from the current vehicle's skin (`currentSkinProvider`), so pushed routes, dialogs and sheets get it too. A `Theme` around the dashboard would not reach routes pushed on the root navigator. The shared widgets read tokens with `context.tokens` and never import a vehicle.
*   Today only the debug gallery uses the new theme. The app switches over in the shared dashboard work, so the existing screens keep their look until then.
*   Keep the skin in a `ThemeExtension` next to Material's `ColorScheme`, so stock widgets (dialogs, snackbars) still look right. Derive the extension's neutral colours from the brightness.
*   Shapes: `StadiumBorder` for "full", `RoundedRectangleBorder` for numbers. A single helper builds the `ShapeBorder` from a radius token, so "full" is handled in one place.
*   Platforms return a skin from `VehicleDefinition.skin`; the pairing wizard (before a vehicle is known) uses the default skin. Because the current vehicle can change, the theme is resolved from the current vehicle, and screens that list several vehicles (the switcher, the Vehicles screen) read each vehicle's skin for its avatar.
*   Theme mode (system, light, dark) is a user setting saved in `SharedPreferences` and loaded before `runApp`, so the first frame has the right brightness.
*   The debug-only theme gallery shows the tokens and components in every skin and brightness, for checking the design on a phone. Its tile sandbox has fake tiles of every type, with fake commands. Open it from the pairing wizard or the dashboard's menu in a debug build.
