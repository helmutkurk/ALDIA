# Design tokens (Guatemala sky-blue palette, 2026-11-21)

Decision: [`decisions/ux-2026-11-21.md`](decisions/ux-2026-11-21.md) (items 5–8): one palette for the app **and** the
portal, based on the Guatemala flag sky blue, with a coral accent and status colors that are neither blue nor coral.
Rationale, contrast measurements and Material 3 roles: [`app/docs/ux/design-direction.md`](../app/docs/ux/design-direction.md).

**Status:** the app implements these values in `app/lib/core/theme.dart` (tested in `app/test/core/theme_test.dart`).
The portal (`portal/src/styles/tokens.css`) still uses the previous calm teal palette until it adopts this file
(portal owner: Isa). Until then the two products do not match.

| Token | Light | Dark | Use |
|---|---|---|---|
| `primary` | `#2A6FA8` | `#7DB8E6` | filled buttons, selected controls (white text 5.3:1; dark text `#0B2A40` 7.0:1 in dark) |
| `primary-dark` | `#235E8F` | — | pressed state, text links, focus ring (6.8:1 on white) |
| `brand` | `#4997D0` | — | logo, map clusters, chart lines; **non-text only** (3.2:1) |
| `accent` | `#FF7A59` | `#FF9A80` | badges, alerts, key call to action; text on it is `#1F2933`; never used as text |
| `bar` | `#235E8F` | `#0B2A40` | top bar of the shell until those screens move to light surfaces |
| `background` / `surface` | `#FFFFFF` | `#12181D` / `#1B2329` | page, sheets |
| `card` | `#EAF4FB` | `#1B2329` | cards, tiles, metric cards |
| `primary-container` | `#D3E7F6` | — | selected chip, navigation indicator, info banners (text `#0B2A40`) |
| `border` | `#C5D9E8` | `#313C45` | thin decorative borders and dividers |
| `outline` | `#6B7280` | `#C5CDD5` | input and control outlines (3:1 non-text) |
| `text` | `#1F2933` | `#F3F4F6` | main text |
| `text-muted` | `#52606D` | `#C5CDD5` | secondary text (5.8:1 on `card`) |
| `danger` | `#B91C1C` | `#F2A5A5` | errors, rejected |

Status colors paint dots, pins and chart series only, **always with the status word next to them in the normal
text color**:

| Group | Light | Dark | Word (examples) |
|---|---|---|---|
| open | `#B26A00` amber | `#E0A13A` | Recibido, En revisión |
| in work | `#7E57C2` violet | `#B39DDB` | Programado, En proceso |
| resolved | `#17735A` quetzal green | `#4DB38A` | Resuelto |
| closed | `#6B7280` gray | `#9CA3AF` | Cerrado, Ya estaba reportado |
| rejected / error | `#B91C1C` red | `#F2A5A5` | Falta ajustar la foto |
| pending | outlined `#52606D` | outlined `#C5CDD5` | En verificación |

Shapes: buttons and chips are pills (52 dp buttons, 48 dp minimum touch target), cards 20 dp radius with a 1 dp
`border`, tiles 16 dp, inputs 12 dp, sheets and dialogs 28 dp. Type: platform font, Material 3 scale with bold
headings (`displaySmall` 800, headlines 700, titles and labels 600).

Rules: text contrast at least 4.5:1 and non-text at least 3:1, tested in code; never color alone; dark mode keeps the
hues with lighter steps on dark surfaces; minimalist, generous spacing, no decoration without purpose.
