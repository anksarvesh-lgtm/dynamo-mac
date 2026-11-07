# AirPods product renders (optional)

Island shows the best artwork it can find for the connected model:

1. **A render in this folder.** Use a transparent PNG/HEIC, at least 1024 px, with the product centred and no shadow.
2. **The model-specific device artwork that macOS provides.** Island doesn't ship this; it reads it at runtime through the public `UTType` and `NSWorkspace` APIs.
3. **Nothing.** If neither exists, the card shows no picture rather than a fake one.

## File names (most specific match wins)

| Model | File |
|---|---|
| AirPods Pro 2 (USB-C) | `airPodsPro2USBC.png` → falls back to `airPodsPro2.png` → `airPodsPro.png` |
| AirPods Pro 2 (Lightning) | `airPodsPro2.png` → `airPodsPro.png` |
| AirPods Pro 3 | `airPodsPro3.png` → `airPodsPro2.png` → `airPodsPro.png` |
| AirPods Pro (1st gen) | `airPodsPro.png` |
| AirPods 4 / 4 ANC | `airPods4.png` (`airPods4ANC.png` takes precedence for the ANC model) |
| AirPods 3 / 2 / 1 | `airPods3.png`, `airPods2.png`, `airPods1.png` |
| AirPods Max (USB-C) | `airPodsMaxUSBC.png` → `airPodsMax.png` |
| AirPods Max | `airPodsMax.png` |

**Licensing:** only add images you have the right to redistribute, such as a render you own or a properly licensed 3D render. Apple's product photography and the artwork extracted from iOS or macOS are not redistributable.
