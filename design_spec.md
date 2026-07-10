# Office Game — Design Spec

Implementation-ready visual design system for `office_game_app`. Covers color, type, spacing, iconography, component treatments, and motion, with Flutter-specific notes throughout. Pairs with `office_game_concept_season1.md` (game rules) and `implementation_plan.md` (build phases).

## 1. Principles

- **Dark by design, not just dark mode.** The app ships dark-only in v1 — this is a deliberate choice, not a missing light theme. The whole positioning is an escape from corporate software, and a light theme immediately reads as "another SaaS tool." Revisit light mode only if real users ask for it.
- **Two accents, rationed.** Brass carries ordinary interaction. Crimson is reserved for danger and mafia-only context. No third accent color — restraint is what keeps crimson meaningful when it appears.
- **Case file, not dashboard.** Surfaces read like documents and dossiers: hairline borders instead of drop shadows, monospace for anything that's data, serif for anything that's ceremony.
- **Ceremony for the moments that matter.** Role reveal, discovering the elimination signal, and unmasking are the emotional core of the game. They get real motion design. Everything else (voting, logging an observation) should be fast and unfussy — don't make the player sit through animation on routine actions.
- **Flat.** No gradients, no drop shadows. Shadows barely read against near-black and end up looking muddy; hairline borders read as intentional.

## 2. Color

All values are fixed hex — this palette does not adapt to system light/dark mode, since the app is dark-only by design (see Principles).

### Base

| Token | Hex | Use |
|---|---|---|
| `ink` | `#15120E` | App background (Scaffold) |
| `surface` | `#1E1A14` | Cards, panels, list containers |
| `surfaceRaised` | `#241F17` | Inputs, bottom sheets, anything that sits above `surface` |
| `borderHairline` | `#3A3226` | Default 1px borders between/around surfaces |
| `borderStrong` | `#4E4530` | Emphasized dividers, focused input border |

### Text

| Token | Hex | Use |
|---|---|---|
| `textPrimary` | `#EDE6D6` | Primary content — ivory, not pure white |
| `textSecondary` | `#A69B85` | Supporting text, subtitles |
| `textMuted` | `#6B6252` | Timestamps, hints, disabled labels |

### Brass (primary accent)

| Token | Hex | Use |
|---|---|---|
| `brass` | `#C9A227` | Default accent — buttons, active states, links, vote-weight number |
| `brassStrong` | `#A9840F` | Pressed/active state |
| `brassSoft` | `#3A2F12` | Subtle background tint (e.g. selected list row) |
| `onBrass` | `#2C1D02` | Text/icon color on a solid `brass` fill |

### Crimson (danger / mafia accent)

| Token | Hex | Use |
|---|---|---|
| `crimson` | `#8B2635` | Danger actions, mafia-only chrome accents |
| `crimsonStrong` | `#6E1D29` | Pressed/active state |
| `crimsonSoft` | `#3A1216` | Banner/card background (elimination signal, mafia thread) |
| `crimsonText` | `#E0949C` | Crimson-toned label text on `crimsonSoft` |
| `onCrimson` | `#F5E4E6` | Text/icon color on a solid `crimson` fill |

**Rule:** there is no dedicated success/green color. Confirmations (method accepted, observation logged) reuse `brass` — a third accent isn't worth the loss of restraint.

**Contrast:** `brass` on `ink` and `crimsonText` on `crimsonSoft` both read comfortably at the sizes specified in section 3, but run them through a contrast checker once implemented — don't take the hex values on faith for body-text-sized UI.

## 3. Typography

Three families, each with one job. Use `google_fonts` (`flutter pub add google_fonts`) rather than bundling font files, unless offline-first reliability becomes a real requirement later.

| Family | Package call | Job |
|---|---|---|
| Playfair Display | `GoogleFonts.playfairDisplay()` | Ceremony: role reveal, unmask, elimination-discovery headlines |
| JetBrains Mono | `GoogleFonts.jetBrainsMono()` | Data: vote weight, case numbers, timestamps, IDs |
| Inter | `GoogleFonts.inter()` | Everything else: body copy, buttons, list items, inputs |

### Type scale

| Style | Family | Weight | Size | Line height | Use |
|---|---|---|---|---|---|
| `displayLarge` | Playfair | 700 | 30 | 1.2 | Role reveal headline ("You are the informant") |
| `displayMedium` | Playfair | 600 | 22 | 1.25 | Other ceremony headers ("Unmasked", "Elimination logged") |
| `heading` | Inter | 500 | 18 | 1.3 | Screen titles, card headers |
| `body` | Inter | 400 | 16 | 1.5 | Standard UI copy |
| `bodySmall` | Inter | 400 | 14 | 1.5 | Secondary/help text |
| `data` | JetBrains Mono | 500 | 15 | 1.4 | Vote weight, stats |
| `dataSmall` | JetBrains Mono | 400 | 13 | 1.4 | Case-file labels, timestamps — this is the floor, don't go smaller |
| `button` | Inter | 500 | 16 | 1.2 | Button labels |

Bumped +2px across the board from the original scale (28/20/16/14/12/13/11/14) after real-device testing showed the original sizes were hard to read comfortably.

**Rule:** if a piece of text represents a *number the player needs to trust* (vote weight, a round count, a timestamp), it's monospace. If it's *prose*, it's Inter. Playfair is reserved for the three or four ceremony moments — using it anywhere else dilutes it.

## 4. Spacing and radius

4px base grid.

| Token | Value |
|---|---|
| `spaceXs` | 4 |
| `spaceSm` | 8 |
| `spaceMd` | 12 |
| `spaceLg` | 16 |
| `spaceXl` | 24 |
| `spaceXxl` | 32 |

| Token | Value | Use |
|---|---|---|
| `radiusSm` | 8 | Buttons, inputs, small chips |
| `radiusMd` | 12 | Cards, banners |
| `radiusLg` | 20 | Bottom sheets, modals |
| `radiusPill` | 999 | Badges, the vote-weight pill |

No elevation/shadow tokens — see Principles. Separate surfaces with `borderHairline`, not `BoxShadow`.

## 5. Iconography

Recommend `phosphor_flutter` (`flutter pub add phosphor_flutter`), using the **light** (thin outline) weight throughout — it's the closest match to a detective/occult mood without going full skull-and-crossbones. Avoid Material's filled/rounded default icon set; it reads as generic productivity-app chrome.

| Concept | Icon | Where |
|---|---|---|
| Observation / watching | `PhosphorIconsLight.eye` | Villager observation log |
| Role reveal / seal | Bespoke — `assets/graphics/villager_seal.svg` / `mafia_seal.svg` (`AppGraphics`) | Role badge, role reveal screen |
| Mafia / concealment | Bespoke — `assets/graphics/mask_bespoke.svg` | Mafia thread header ("The Wire"), mafia-only chrome |
| Investigation | `PhosphorIconsLight.magnifyingGlass` | Vote/deduction screens |
| Secret message | `PhosphorIconsLight.envelopeSimple` | Elimination-method proposal, dead-drop-style content |
| Access / trust | `PhosphorIconsLight.key` | Recruitment flow |
| Identity | Bespoke — `assets/graphics/fingerprint_dossier_mark.svg` | Game-list tile, player profile / dossier header |
| Vote weight | Bespoke — `assets/graphics/vote_pip_filled.svg` / `vote_pip_hollow.svg` | Vote-weight pill |
| Unmask ceremony | Bespoke — `assets/graphics/unmask_stamp_burst.svg` | Unmask ceremony stamp |
| Elimination signal (pre-reveal) | Bespoke — `assets/graphics/redaction_bar.svg` | Elimination signal banner wipe-reveal cover |
| Brand mark | Bespoke — `assets/graphics/app_mark_seal_eye.svg` | Entry screen header, future app icon |

Bespoke assets are single-color line art using `currentColor`, loaded via `flutter_svg`'s `SvgPicture.asset` with a `ColorFilter` (`BlendMode.srcIn`) so each can be tinted per role/state (brass vs. crimson) without separate files, mirroring how the Phosphor icons above are already tinted. Asset path constants live in `lib/design/graphics.dart` (`AppGraphics`). The app mark (`app_mark_seal_eye.svg`) is the exception — it's a fixed multi-tone brand mark, not meant to be recolored.

Icon sizing: 20px inline (next to text), 24px standalone/decorative, 44–52px inside the role-badge circle. Icons take `textSecondary` by default, `brass` or `crimson` only when they're load-bearing for meaning (e.g. the crimson mask on the mafia thread).

## 6. Components

Written against the screens that already exist in `lib/ui/` — `role_switcher_screen.dart` and `game_screen.dart`.

### App bar
`ink` background, no elevation, `borderHairline` as a 1px bottom border instead of a shadow. Title in `heading` style, `textPrimary`.

### Primary button
Fill `brass`, label `onBrass` in `button` style, `radiusSm`, no elevation. Used for the single most important action per screen (e.g. "Accept the role", "Start game"). At most one primary button visible at a time — everything else is secondary.

### Secondary / ghost button
Transparent fill, 1px `borderHairline`, label `textPrimary`. Used for "Accept current elimination method", "Add & join", and similar non-primary actions.

### Danger button
Fill `crimson`, label `onCrimson`. Reserve for actions with real narrative weight — not general use. Most mafia-side actions should still be secondary-styled; the fill is for the proposal/commit action specifically.

### Card / dossier panel
`surface` background, 1px `borderHairline`, `radiusMd`, padding `spaceLg`. Wraps sections like "mafia coordination" and "observations" in `game_screen.dart`.

### Elimination signal banner
`crimsonSoft` background, 1px `crimson` border, `radiusMd`. Label ("today's signal") in `dataSmall`/`crimsonText`, body in `body`/`textPrimary`. This is the one banner in the whole app that should visually interrupt — everything else stays quiet.

### List row (player list, mafia thread entries)
No card wrapper — 1px `borderHairline` bottom border between rows, `spaceMd` vertical padding. Name in `body`/`textPrimary`, trailing action (e.g. "vote") as a text-style button in `brass`.

### Text input
`surfaceRaised` background, 1px `borderHairline` (→ `borderStrong` on focus), `radiusSm`, input text in `body`, placeholder in `textMuted`.

### Role badge
Circle, 1px `brass` (or `crimson` for mafia) border, transparent fill, icon centered at 24–28px. Appears at the top of the role-reveal screen and can double as a small persistent identity marker elsewhere.

### Vote-weight indicator
Pill (`radiusPill`), `borderHairline` border, transparent/`surface` fill, value in `data` style. Optional enhancement worth prototyping: three small circular pips instead of (or alongside) the number, filled for remaining weight and hollow for lost weight — makes the erosion mechanic legible at a glance without reading a digit, and echoes a wax-seal-dripping motif that fits the theme.

## 7. Motion — the ceremony moments

Two duration bands: fast, everyday interaction stays under 300ms; the three ceremony moments get 500–900ms because they're meant to be felt, not just registered.

| Token | Duration | Curve | Use |
|---|---|---|---|
| `durFast` | 150ms | `Curves.easeOut` | Button press, toggle |
| `durBase` | 300ms | `Curves.easeOutCubic` | List updates, ordinary state transitions |
| `durCeremony` | 600–900ms | see below | Role reveal, elimination discovery, unmasking |

**Role reveal.** Seal/badge icon scales in from 0.85 → 1.0 over 500ms with `Curves.easeOutBack` (a slight overshoot — it should feel like it "lands"), then the `displayLarge` headline fades and slides up over 400ms, starting ~150ms after the seal settles. Pair with `HapticFeedback.mediumImpact()` when the seal lands.

**Elimination signal discovery.** The signal text starts hidden behind a solid `crimsonSoft` bar (like a redaction) and reveals via a 500ms left-to-right wipe (`ClipRect` with an animated width, or a `Stack` crossfade if a wipe proves fiddly) rather than a plain fade — the redaction-lifting motion is what sells the "you just found this" feeling.

**Unmask / vote resolution.** A brief "stamp impact": scale 1.15 → 1.0 with a tiny rotation snap (-3° → 0°) over 250ms, `Curves.easeOutBack`, plus `HapticFeedback.mediumImpact()`. This is the shortest of the three ceremony moments — it's a punctuation mark, not a scene.

**Implementation note:** hand-rolling three separate `AnimationController`s is more ceremony (pun intended) than a solo, less-advanced dev needs to take on. Consider `flutter pub add flutter_animate` — it lets you chain these effects declaratively (`.scale().then().fadeIn()` style) without manually managing controllers, which fits the "move fast" constraint from the implementation plan.

**Respect reduce-motion.** Check `MediaQuery.of(context).disableAnimations` and fall back to an instant state change (no wipe, no scale-bounce) for players who have that system setting on. The three ceremony moments are the only place this matters — routine UI has no motion to reduce.

## 8. Flutter implementation notes

Suggested structure, additive to what's already in `office_game_app/lib/`:

```
lib/
  design/
    colors.dart       // the hex tokens from section 2, as Color constants
    typography.dart   // TextStyle constants from section 3, built on GoogleFonts
    spacing.dart       // spaceXs..spaceXxl, radiusSm..radiusPill as double constants
    theme.dart         // assembles a ThemeData from the above
```

`theme.dart` gets consumed once, in `main.dart`:

```dart
MaterialApp(
  theme: buildOfficeGameTheme(), // from lib/design/theme.dart
  home: const RoleSwitcherScreen(),
)
```

Sketch of what `buildOfficeGameTheme()` maps to — adjust field names to taste, but keep the mapping this direct so a future contributor can find "where does `crimsonSoft` come from" in one place:

```dart
ThemeData buildOfficeGameTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.ink,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.brass,
      onPrimary: AppColors.onBrass,
      error: AppColors.crimson,
      onError: AppColors.onCrimson,
    ),
    textTheme: AppTypography.textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brass,
        foregroundColor: AppColors.onBrass,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
      ),
    ),
  );
}
```

Package additions to `pubspec.yaml` beyond what's already there (`provider`):

```yaml
dependencies:
  google_fonts: ^6.2.1
  phosphor_flutter: ^2.0.1
  flutter_animate: ^4.5.0
```

## 9. Accessibility

- Minimum tap target 44×44 logical pixels — applies to list-row trailing actions and icon buttons, which are the easiest things to accidentally under-size.
- Respect system text scaling: avoid fixed-height containers around text (the player list rows, the elimination banner) so they grow instead of clipping when someone increases their text size.
- Verify `brass`-on-`ink` and `crimsonText`-on-`crimsonSoft` against WCAG AA (4.5:1 for body text, 3:1 for large/`displayLarge` text) once the theme is wired up — the hex values above were chosen by eye against this bar, not measured.
- Ceremony animations respect `MediaQuery.disableAnimations` (section 7) — this is the one place motion is load-bearing enough to need an explicit fallback.
