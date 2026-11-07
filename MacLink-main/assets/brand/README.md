# The MacLink mark

The Waggle Dance: two loops, the phone and the PC, around a glowing drop,
tilted like the run of a honeybee's waggle dance, which is how devices connect seamlessly.

| File | What it is |
|---|---|
| `icon.svg` | The full-color app icon: espresso tile, warm glow, honey rim |
| `icon-flat.svg` | The same without the glow and highlights, for flat contexts |
| `icon-mono.svg` | The mark alone in white, for one-color uses (notifications, themed icons) |
| `icon-512.png` | `icon.svg` at 512 × 512 |

The apps draw the mark themselves from the same geometry:
`desktop/app/src/mark.rs` (the Windows icon, tray and notifications at every
size) and `android/app/src/main/res/drawable/ic_launcher_*.xml` and
`ic_notification.xml`.

Colors (Honey palette, `docs/design/tokens.json`): tile `#2C1600`, glow
`#693C00`, phone loop `#FFF8F3`, PC loop `#FFDDB8`, center and rim `#FFB95F`.

The name and the mark are covered by the [trademark policy](../../TRADEMARKS.md).
