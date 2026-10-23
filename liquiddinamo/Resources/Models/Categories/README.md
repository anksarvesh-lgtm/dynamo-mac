# Category 3D Models Directory

Drop your USDZ category models here to replace the procedural primitive stand-ins.

## Supported Filenames

Place any of the following `.usdz` files directly into this directory:

| Device Category | Recommended Filename | Alternative Filenames |
| :--- | :--- | :--- |
| **Earbuds** | `earbuds.usdz` | `Earbuds.usdz` |
| **Headphones** | `headphones.usdz` | `Headphones.usdz` |
| **Speaker** | `speaker.usdz` | `Speaker.usdz` |
| **SSD / External Drive** | `ssd_drive.usdz` | `ssdDrive.usdz`, `drive.usdz`, `ssd.usdz` |
| **USB Flash Drive** | `usb_stick.usdz` | `usbStick.usdz`, `usbstick.usdz` |
| **Mouse** | `mouse.usdz` | `Mouse.usdz` |
| **Keyboard** | `keyboard.usdz` | `Keyboard.usdz` |
| **Phone** | `phone.usdz` | `Phone.usdz` |
| **Generic** | `generic.usdz` | `generic_device.usdz`, `Generic.usdz` |

## Asset Guidelines for Best Performance

1. **Format**: Standard Apple `.usdz` format (can be exported from Blender, Reality Composer, Cinema4D, or converted using `xcrun usdz_converter`).
2. **Polygon Count**: Ideal target is **8,000 – 16,000 triangles** (max 35,000 triangles) to maintain instant load times and 60 FPS turntable rotation.
3. **Materials**: PBR materials with `diffuseColor` (or BaseColor map max 1024x1024), `roughness`, and `metalness`.
4. **Dimensions & Orientation**:
   - The renderer automatically centers any model and scales it to fit a 1x1x1 unit box.
   - For natural turntable spin, orient the front of the device facing towards the positive Z-axis and the top pointing up along the positive Y-axis.
