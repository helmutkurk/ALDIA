# Design tokens (neutral, 2026-11-19)

Decision (Helmut): **simple, neutral colors; no distinctive brand colors** (not yellow, not saturated blue or teal like the
reference apps). The interface is graphite, white and warm gray; color appears only where it carries meaning (report status), and
always together with a word or icon. App and portal share these values: `app/lib/core/theme.dart`,
`portal/src/styles/tokens.css` and this file. Agree changes between both owners.

| Token | Hex | Use |
|---|---|---|
| `primary` | `#1F2937` | main actions, header bar, selected tab |
| `primary-dark` | `#111827` | pressed state, strong text on light |
| `on-primary` | `#FFFFFF` | text on primary |
| `background` | `#F5F5F4` | page background |
| `surface` | `#FFFFFF` | cards, sheets |
| `border` | `#E5E7EB` | dividers, outlines |
| `text` | `#111827` | main text |
| `text-muted` | `#4B5563` | secondary text |
| `focus` | `#111827` | focus ring (2 px, offset 2 px) |

Status colors (functional only, muted, always with text):

| Status group | Hex | Word |
|---|---|---|
| open | `#B45309` | Abierto / Nuevo / En revisión |
| in work | `#1D4ED8` is NOT used; use `#4B5563` with a hatched or outlined marker | Programado / En proceso |
| resolved | `#15803D` | Resuelto |
| closed | `#6B7280` | Cerrado / No procede / Duplicado |
| rejected or error | `#B91C1C` | Rechazado |

Rules: contrast at least 4.5:1 for text; never color alone; pins use the neutral primary with a status icon/letter and an outline,
not rainbow fills; dark mode inverts surface and text, keeps the same status words. Font: system font stack (portal), platform
default (app).
