// SPDX-License-Identifier: GPL-3.0-or-later
//! MacLink Apple Liquid Glass application icon renderer.
//! Provides pre-rendered, high-fidelity liquid glass icon RGBA pixels
//! for window icons, system tray, and platform resources.

#[allow(dead_code)]
const RAW_16: &[u8] = include_bytes!("icons_raw/icon_16.raw");
#[allow(dead_code)]
const RAW_20: &[u8] = include_bytes!("icons_raw/icon_20.raw");
#[allow(dead_code)]
const RAW_24: &[u8] = include_bytes!("icons_raw/icon_24.raw");
#[allow(dead_code)]
const RAW_32: &[u8] = include_bytes!("icons_raw/icon_32.raw");
#[allow(dead_code)]
const RAW_40: &[u8] = include_bytes!("icons_raw/icon_40.raw");
#[allow(dead_code)]
const RAW_48: &[u8] = include_bytes!("icons_raw/icon_48.raw");
#[allow(dead_code)]
const RAW_64: &[u8] = include_bytes!("icons_raw/icon_64.raw");
#[allow(dead_code)]
const RAW_128: &[u8] = include_bytes!("icons_raw/icon_128.raw");
#[allow(dead_code)]
const RAW_256: &[u8] = include_bytes!("icons_raw/icon_256.raw");

/// Renders the MacLink liquid glass icon as straight-alpha RGBA, `size`×`size`.
#[allow(dead_code)]
pub fn render(size: usize) -> Vec<u8> {
    match size {
        16 => RAW_16.to_vec(),
        20 => RAW_20.to_vec(),
        24 => RAW_24.to_vec(),
        32 => RAW_32.to_vec(),
        40 => RAW_40.to_vec(),
        48 => RAW_48.to_vec(),
        64 => RAW_64.to_vec(),
        128 => RAW_128.to_vec(),
        256 => RAW_256.to_vec(),
        _ => {
            // Nearest neighbor resample from the 256px icon for non-standard sizes
            let src = RAW_256;
            let src_size = 256;
            let mut out = vec![0u8; size * size * 4];
            for y in 0..size {
                let sy = y * src_size / size;
                for x in 0..size {
                    let sx = x * src_size / size;
                    let src_idx = (sy * src_size + sx) * 4;
                    let dst_idx = (y * size + x) * 4;
                    out[dst_idx..dst_idx + 4].copy_from_slice(&src[src_idx..src_idx + 4]);
                }
            }
            out
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_every_tray_size() {
        for size in [16, 20, 24, 32, 48, 64, 256] {
            let img = render(size);
            assert_eq!(img.len(), size * size * 4);
            assert!(img.chunks(4).any(|p| p[3] > 0), "{size}px has visible pixels");
        }
    }
}
