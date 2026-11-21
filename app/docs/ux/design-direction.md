# Design direction (approved 2026-11-21)

Phase 1 UX spec, 2026-11-21. **Spec only, not code.** Approved for the app and the portal in
[`documentation/decisions/ux-2026-11-21.md`](../../../documentation/decisions/ux-2026-11-21.md): new palette, contrast
fixes (§2), coral accent and the new status colors (§5). It replaces the calm teal/graphite palette in
`documentation/design-tokens.md` when the shared tokens are implemented in Phase 3.

## 1. Brief (as given)

- **Primary:** Guatemala flag sky blue `#4997D0`; darker variant `#2F7FBF` for buttons and active states.
- **Backgrounds:** white, plus light sky `#EAF4FB` for cards.
- **Accent:** warm coral `#FF7A59` for alerts, badges and key calls to action (alternative: quetzal green `#1E8C6E`).
- **Style references:** large rounded cards with thin borders, an icon category grid, generous whitespace, pill-shaped
  filter chips, a bottom navigation bar, metric cards with a simple chart, bold large headings.

## 2. Contrast check of the brief

The repo rule (`documentation/design-tokens.md`, enforced by `test/core/theme_test.dart`) is text ≥ 4.5:1 and non-text
(dots, borders, icons that carry meaning) ≥ 3:1. Measured with the WCAG 2.x formula:

| Pair | Ratio | Result |
|---|---|---|
| White text on `#4997D0` | 3.17 | ❌ text; ✅ non-text / large text ≥ 24 px only |
| White text on `#2F7FBF` | 4.28 | ❌ normal text (button labels are 14–16 sp) |
| `#2F7FBF` text on `#EAF4FB` | 3.84 | ❌ |
| White text on `#FF7A59` | 2.57 | ❌ |
| `#1F2933` text on `#FF7A59` | 5.75 | ✅ |
| White text on `#1E8C6E` | 4.17 | ❌ |
| `#4997D0` on white (non-text, e.g. chart line, icon) | 3.17 | ✅ non-text |
| `#4997D0` on `#EAF4FB` (non-text) | 2.84 | ❌ even non-text |

**Proposal:** keep the brief's hues and add two darker steps for text and filled buttons:

- `sky-700` `#2A6FA8` — filled buttons, links, active nav icon (white on it 5.33; on `#EAF4FB` 4.78).
- `sky-800` `#235E8F` — pressed state (white on it 6.84).
- `#4997D0` stays the **brand** color: logo, illustrations, map clusters, chart series, large headings on dark images.
- `#2F7FBF` stays for large text and non-text active indicators (it passes 3:1), not for button labels.
- Coral as a fill carries **dark text** `#1F2933`; coral as text uses `coral-700` `#B4472B` (5.42 on white).
- If quetzal green is chosen instead: use `#17735A` for text and fills with white text (5.78).

## 3. Material 3 color roles (light)

| M3 role | Hex | Use | Check |
|---|---|---|---|
| `primary` | `#2A6FA8` | Filled buttons, links, selected controls | white 5.33 |
| `onPrimary` | `#FFFFFF` | Text/icons on primary | — |
| `primaryContainer` | `#D3E7F6` | Selected chip, nav indicator pill, info banners | — |
| `onPrimaryContainer` | `#0B2A40` | Text on primaryContainer | 11.65 |
| `secondary` (brand) | `#4997D0` | Brand marks, cluster bubbles, chart lines, non-text active marks | 3.17 on white (non-text) |
| `onSecondary` | `#0B2A40` | Text on brand fills (never white) | 4.66 on `#4997D0` |
| `tertiary` (accent) | `#FF7A59` | Badges, alert dots, the key CTA fill (e.g. "Reportar") | — |
| `onTertiary` | `#1F2933` | Text on coral | 5.75 |
| `tertiaryText` (custom) | `#B4472B` | Coral-colored text | 5.42 |
| `surface` | `#FFFFFF` | Page background | — |
| `surfaceContainerLow` | `#EAF4FB` | Cards, category tiles, metric cards | text `#1F2933` 13.23, muted 5.79 |
| `surfaceContainerHighest` | `#D3E7F6` | Image placeholders, pressed card | — |
| `onSurface` | `#1F2933` | Main text | 14.76 on white |
| `onSurfaceVariant` | `#52606D` | Secondary text | 6.46 on white, 5.79 on `#EAF4FB` |
| `outline` | `#9DB7CB` | Input borders (needs 3:1 → **use `#6B7280` for inputs**; 2.09 is only decorative) | ⚠️ |
| `outlineVariant` | `#C5D9E8` | Thin card borders (decorative, 1 dp) | 1.45 decorative only |
| `error` / `onError` | `#B91C1C` / `#FFFFFF` | Errors (unchanged) | 6.47 |
| focus ring | `#235E8F` 2 dp, 2 dp offset | Keyboard/switch focus | 6.84 |

## 4. Material 3 color roles (dark)

**Assumption:** dark mode stays (the app supports it today). Same hues, lighter steps:

| Role | Hex | Check |
|---|---|---|
| `surface` | `#12181D` | — |
| `surfaceContainerLow` (cards) | `#1B2329` | text `#F3F4F6` 14.47 |
| `surfaceContainerHigh` | `#22303A` | text 12.3, muted `#C5CDD5` 8.42 |
| `primary` | `#7DB8E6` | on card 7.48 |
| `onPrimary` | `#0B2A40` | 6.95 |
| `tertiary` (coral) | `#FF9A80` | on card 7.72; text on it `#1F2933` 7.16 |
| `onSurface` / `onSurfaceVariant` | `#F3F4F6` / `#C5CDD5` | 14.47 / 9.91 |

## 5. Status colors (needs a decision)

Today: open orange `#E8731A`, in work green `#3F9A47`, resolved blue `#2D8CD0`, closed gray `#6B7280`, rejected red
`#B91C1C`, pending outlined. With the new brand, **resolved blue looks like the primary** and **open orange looks like the
coral accent** (`#E8731A` vs `#FF7A59` luminance ratio 1.19). Proposal (open-decisions #22), each ≥ 3:1 on white and on
`#EAF4FB`, always with the state word beside it:

| Group | Proposed | On white | Reason |
|---|---|---|---|
| open | amber `#B26A00` | 4.24 | warm "needs attention", distinct from coral |
| in work | violet `#7E57C2` | 5.21 | not blue, not green |
| resolved | quetzal green `#17735A` | 5.78 | "done", national color |
| closed | gray `#6B7280` | 4.83 | unchanged |
| rejected | red `#B91C1C` | 6.47 | unchanged |
| pending | outlined `#52606D` | 6.46 | unchanged |

This also changes portal pins and chart series, so Isa must agree.

## 6. Typography (M3 type scale)

Platform default font (Roboto on Android, San Francisco on iOS), as today; no new font dependency. Bold, large headings:

| M3 style | Size / line | Weight | Use |
|---|---|---|---|
| `displaySmall` | 36 / 44 | 800 | Big counters (Inicio, metric cards), tabular figures |
| `headlineLarge` | 32 / 40 | 700 | Screen titles on Inicio |
| `headlineMedium` | 28 / 36 | 700 | Main screen headings |
| `headlineSmall` | 24 / 32 | 700 | Wizard step titles, detail heading |
| `titleLarge` | 22 / 28 | 600 | Section headings ("Historial") |
| `titleMedium` | 16 / 24 | 600 | Card titles, group headers |
| `bodyLarge` | 16 / 24 | 400 | Body text, inputs |
| `bodyMedium` | 14 / 20 | 400 | Secondary text in cards |
| `labelLarge` | 14 / 20 | 600 | Buttons |
| `labelMedium` | 12 / 16 | 600 | Chips, badges, nav labels |

All sizes scale with system text size; layouts must still work at 200 % (existing rule).

## 7. Shape, spacing, elevation

| Token | Value | Use |
|---|---|---|
| `shape.card` | 20 dp radius, 1 dp `outlineVariant` border, no shadow | Report cards, metric cards |
| `shape.tile` | 16 dp | Category grid tiles |
| `shape.button` | full pill (`StadiumBorder`), min height 52 dp | Filled/outlined buttons |
| `shape.chip` | full pill, 36 dp visual height, 48 dp touch target | Filter chips |
| `shape.sheet` | 28 dp top corners | Bottom sheets, wizard sheet |
| spacing | 4 / 8 / 12 / 16 / 24 / 32 / 48 (existing `AldiaSpace` + 48) | Screen gutter 20 dp, card padding 16–20 dp, section gap 32 dp |
| elevation | 0 for cards (borders instead); 3 for bottom sheet; 2 for nav bar | Flat, calm look |

## 8. Component notes (for Phase 2 wireframes)

- **Bottom navigation:** M3 `NavigationBar`, five destinations as today; indicator pill `primaryContainer`, active icon
  `primary`, labels always visible. **Assumption:** the center "Reportar" becomes a coral pill CTA inside the bar.
- **Category grid:** 3 columns on phones (2 at 200 % text), tile = `surfaceContainerLow`, 48 dp icon circle in white
  with a `primary` icon, label below (max 2 lines, never truncated). Use in the wizard category step and, if decided,
  on Inicio as shortcuts.
- **Filter chips:** horizontal scroll row of pills (Estado, Categoría, Cerca de mí); selected = `primaryContainer` +
  check icon + `onPrimaryContainer` text; unselected = white with `outline` border.
- **Report card:** photo on top (16:9, rounded top 20 dp), then state dot + word, category title (`titleMedium`), place,
  note (2 lines), date and short reference; heart and share as separate 48 dp targets.
- **Metric card:** label (`labelLarge`, muted), big number (`displaySmall`), period text ("últimos 90 días"), sparkline
  in brand `#4997D0` 2 dp with a `primary` end dot; optional coral badge for a change. Always with a text equivalent.
  **Assumption:** mainly a Dashboard component; on the app only if decision #25 says so.
- **Headings:** bold, left-aligned, one per screen; generous top spacing (32 dp).
- **Alerts/badges:** coral dot or pill with dark text; never coral alone for a meaning — always a word or a count.

## 9. What does not change

Spanish UI text, 48 dp targets, semantics, reduced motion, never color alone, the 11 citizen states, live-photo rule,
privacy notices. These are product rules, not style.
