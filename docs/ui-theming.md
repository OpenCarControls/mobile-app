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

Everything else (backgrounds, surfaces, text, outlines, frosted-glass fills) is derived from the brightness and is the same for all skins. If a platform later needs more (a different surface tint, a custom font), add it to the skin deliberately, with a contrast check.

## Colour tokens
Default skin (the mockups). `accent`, `accentContainer` and `onAccentContainer` are the skin's; the rest are shared.

| Token | Role | Light | Dark |
|---|---|---|---|
| `bg` | Page behind the hero | `#E7ECEB` | `#0C1112` |
| `surface` | Solid surfaces: pill, round buttons, side column | `#FFFFFF` | `#151C1E` |
| `text` | Primary text, glyph outlines | `#11181A` | `#E6EEEC` |
| `textSecondary` | Range, captions, labels | `#46565A` | `#9DB0B3` |
| `accent` | Level fill, active power button, charging text, dots | `#00695C` | `#4FD8C4` |
| `accentContainer` | Fill of an "on" button (80–95% opaque over the layer) | `#CBEAE4` | `#0F3F39` |
| `onAccentContainer` | Text and icons on `accentContainer` | `#00302A` | `#BDF2EA` |
| `outline` | Borders of solid controls, level track | `#C3CECC` | `#2F3D40` |
| `tileBorder` | 1 px border of frosted surfaces | 12% `text` | 14% `text` |
| `glassFill` | Frosted tiles and cards | white at 82% | `#1F2A2D` at 80% |
| `layerFill` | The scrolling controls layer | `bg` at 66% | `bg` at 66% |
| `headerFill` | The pinned header | `bg` at 82% | `bg` at 80% |

Alternate skins used in the mockups:

| Skin | Light `accent` / container / on-container | Dark `accent` / container / on-container |
|---|---|---|
| Default (teal) | `#00695C` / `#CBEAE4` / `#00302A` | `#4FD8C4` / `#0F3F39` / `#BDF2EA` |
| Boxy (steel) | `#37474F` / `#CFD8DC` / `#1C262B` | `#CFD8DC` / `#37474F` / `#ECEFF1` |
| Rounded (rose) | `#B3245A` / `#FCD6E2` / `#5B0F2C` | `#FF8FB1` / `#5E1A34` / `#FFD9E5` |

The hero's own colours (car paint, road, ground) belong to the 3D scene, not to the skin. The charge-port glow and cable use `accent`.

## Shape tokens
| Token | Used for | Default | Boxy | Rounded |
|---|---|---|---|---|
| `radiusSmall` | Small icon buttons in the climate panel | 14 | 2 | 22 |
| `radiusMedium` | Buttons, climate bar, stat cards | 16 | 2 | 28 |
| `radiusLarge` | Top corners of the controls layer | 24 | 2 | 40 |
| `radiusPill` | Connection pill, chips, section labels, temperature stepper | full (stadium) | 2 | full |
| `radiusRound` | Circular icon buttons (power, +/−, settings) | full (circle) | 2 | full |

Rules:
*   A radius is a plain number in dp, or "full" (stadium or circle). A boxy skin sets all five small; a rounded one sets them large or full.
*   Nothing else in a component hard-codes a radius.
*   Buttons are never narrower than their touch target, whatever the radius.

## Glass
The controls sit on frosted translucent surfaces over the hero: a blur plus a translucent fill and a hairline border. The mockup uses a 14 dp blur on tiles and cards, 18 dp on the controls layer and 16 dp on the header. In Flutter each `BackdropFilter` costs a render pass, so use one on the controls layer and one on the header, and make the tiles inside plain translucent fills. The look is the same and it is far cheaper than nesting blurs. Check scrolling frame times on a mid-range phone.

## Typography and icons
Both are shared across skins:

*   One typeface family at a few weights (the mockups use Manrope 400–800; the final family and its licence are still to be chosen and must be bundled as an asset).
*   Scale used by the mockups: vehicle name 20/800, level 26/800, range 15/600, button title 12/700, caption 12/400, stat value 18/800, climate target 22/800.
*   Standard icons from one set (for example Material Symbols), not the demo drawings in the mockups. A platform may override an individual icon where the standard set lacks one (for example a seat glyph).

## Contrast
Skins must pass these checks in both brightnesses, against the worst case behind translucent fills (the page colour and the hero's car colour):

| Pair | Minimum |
|---|---|
| `text` and `textSecondary` on a frosted tile | 4.5:1 |
| `onAccentContainer` on `accentContainer` | 4.5:1 |
| `accent` as text on `bg` (the charging text) | 4.5:1 |
| `accent` against a tile (active power button, level fill, icon strokes) | 3:1 |
| `surface` text on an `accent` fill (active power button) | 4.5:1 |

The default, boxy and rounded skins in both brightnesses pass all of these. The lowest value is 5.3:1, for the rounded skin's `accent` text on `bg`. Put this check in a unit test over every registered skin, so a new platform cannot ship an unreadable skin.

## Implementation notes
*   Resolve the theme once per dashboard from the vehicle's skin and the current brightness. Provide it above the dashboard (wrap what `buildDashboard()` returns in a `Theme`), so the shared widgets read tokens and never import a vehicle.
*   Keep the skin in a `ThemeExtension` next to Material's `ColorScheme`, so stock widgets (dialogs, snackbars) still look right. Derive the extension's neutral colours from the brightness.
*   Shapes: `StadiumBorder` for "full", `RoundedRectangleBorder` for numbers. A single helper builds the `ShapeBorder` from a radius token, so "full" is handled in one place.
*   Platforms register a skin next to their other metadata; the pairing wizard (before a vehicle is known) uses the default skin.
