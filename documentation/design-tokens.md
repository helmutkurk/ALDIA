# Design tokens (calm SeeClickFix-style palette, 2026-11-20)

Decision (Helmut, 2026-11-20): the portal follows **FixMyStreet's structure** (map and list side by side, filters, report page,
dashboard with big numbers and charts) with **SeeClickFix's calm colors**; the app follows SeeClickFix's screens and colors.
Avoid FixMyStreet's yellow and black. Colors are approximations chosen by eye from the reference captures, not brand assets.
App and portal share these values: `app/lib/core/theme.dart`, `portal/src/styles/tokens.css` and this file.

| Token | Hex | Use |
|---|---|---|
| `bar` | `#3A3F44` | dark top bar (app map/list bar, portal header), white text |
| `primary` | `#0F7A99` | main buttons, links, selected controls (white text on it: 5.0:1) |
| `primary-dark` | `#0B6079` | pressed state, strong links |
| `accent` | `#E8731A` | tab underline, highlights, focus accents (never for text) |
| `background` | `#F3F4F6` | page background |
| `surface` | `#FFFFFF` | cards, sheets, panels |
| `border` | `#D9DEE3` | dividers, outlines |
| `text` | `#1F2933` | main text |
| `text-muted` | `#52606D` | secondary text (7.0:1 on white) |
| `focus` | `#0B6079` | focus ring, 2 px with 2 px offset |

Status colors are used for dots, pins and chart series, always **with the status word next to them in the normal text color**:

| Group | Dot/pin | Word (examples) |
|---|---|---|
| open | `#E8731A` orange | Abierto, Nuevo, En revisión |
| in work | `#3F9A47` green | Programado, En proceso, Reconocido |
| resolved | `#2D8CD0` blue | Resuelto |
| closed | `#6B7280` gray | Cerrado, No procede, Duplicado |
| rejected / error | `#B91C1C` red | Rechazado |
| pending | outlined `#52606D` | Pendiente de verificación |

Rules: text contrast at least 4.5:1 (test the pairs in code); never color alone; dark mode keeps the same hues with darker
surfaces; system font stack (portal), platform default (app); minimalist, generous spacing, no decoration without purpose.
