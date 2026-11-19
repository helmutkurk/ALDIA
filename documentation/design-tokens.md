# Design tokens (provisional)

App and portal share these colors. Agree changes between both owners (Helmut and Isa) and edit all three places:
`app/lib/core/theme.dart`, `portal/src/styles/tokens.css` and this file.

| Token | Hex | Use |
|---|---|---|
| `primary` | `#0F766E` | main actions, header |
| `primary-dark` | `#115E59` | pressed state |
| `accent` | `#F59E0B` | highlights, pending status |
| `success` | `#16A34A` | verified |
| `danger` | `#DC2626` | rejected, errors |
| `surface` | `#FFFFFF` | cards |
| `background` | `#F1F5F9` | page background |
| `text` | `#0F172A` | main text |
| `text-muted` | `#475569` | secondary text |

Font: system font stack in the portal, platform default in the app.
