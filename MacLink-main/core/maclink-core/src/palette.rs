// SPDX-License-Identifier: MPL-2.0
//! Shared perceptual color extraction and Material 3 / Bloom tonal scheme
//! builder for both Desktop and Android.
//!
//! Pipeline:
//! 1. Area-box downsample to at most [`MAX_SAMPLE_SIDE`] × [`MAX_SAMPLE_SIDE`]
//!    (112×112) off the UI thread.
//! 2. Strip near-black, near-white, and uniform solid letterbox/frame borders.
//! 3. Quantize in CIE L*a*b* perceptual space via [`QuantizerCelebi`] (Wu 3D
//!    variance partition + weighted k-means).
//! 4. Detect monochrome / near-neutral covers (such as B&W photography) so
//!    they produce a calm neutral achromatic scheme instead of amplifying JPEG
//!    compression noise or falling back to an unrelated wallpaper/preset seed.
//! 5. Score chromatic clusters by multiplicative population × soft-capped
//!    chroma × perceptual tone across 360° Gaussian hue neighborhoods, then
//!    compute the winning hue family's OKLab centroid seed.
//! 6. Build light and dark [`RolePalette`]s from HCT [`TonalPalette`]s with
//!    WCAG AA/AAA contrast guarantees, cached in a thread-safe LRU cache.

use std::sync::Mutex;

pub use material_colors::color::Rgb;
use material_colors::{
    hct::Hct,
    palette::TonalPalette,
    quantize::{Quantizer, QuantizerCelebi},
};

/// Maximum side length for image downsampling before color quantization.
pub const MAX_SAMPLE_SIDE: u32 = 112;

/// Maximum colors retained during Celebi quantization.
const QUANTIZE_COLORS: usize = 128;

/// Neutral seed used when an artwork is monochrome / achromatic.
pub const ACHROMATIC_SEED_RGB: u32 = 0x5E5E62;

/// Maximum entries in the shared artwork scheme LRU cache.
const CACHE_CAPACITY: usize = 64;

static SCHEME_CACHE: Mutex<Vec<(String, ThemeScheme)>> = Mutex::new(Vec::new());

#[derive(Clone, Copy)]
enum Key {
    Primary = 0,
    Secondary = 1,
    Neutral = 2,
    NeutralVariant = 3,
}

/// Bloom's 15 color roles (names as in `docs/design/tokens.json`) and the tone
/// each takes from its palette in light and dark mode.
pub const ROLES: [(&str, usize, i32, i32); 15] = [
    ("primary", Key::Primary as usize, 40, 80),
    ("onPrimary", Key::Primary as usize, 100, 20),
    ("primaryContainer", Key::Primary as usize, 90, 30),
    ("onPrimaryContainer", Key::Primary as usize, 10, 90),
    ("secondaryContainer", Key::Secondary as usize, 90, 30),
    ("onSecondaryContainer", Key::Secondary as usize, 10, 90),
    ("surface", Key::Neutral as usize, 98, 6),
    ("surfaceContainerLow", Key::Neutral as usize, 96, 4),
    ("surfaceContainer", Key::Neutral as usize, 94, 12),
    ("surfaceContainerHigh", Key::Neutral as usize, 92, 17),
    ("surfaceContainerHighest", Key::Neutral as usize, 90, 22),
    ("onSurface", Key::Neutral as usize, 10, 90),
    ("onSurfaceVariant", Key::NeutralVariant as usize, 30, 80),
    ("outline", Key::NeutralVariant as usize, 50, 60),
    ("outlineVariant", Key::NeutralVariant as usize, 80, 30),
];

/// One Bloom palette as a JSON map of role name to `"#RRGGBB"`.
pub type Palette = serde_json::Map<String, serde_json::Value>;

/// Strongly-typed 15-role color palette (`0xRRGGBB` per field) for light or dark mode.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RolePalette {
    pub primary: u32,
    pub on_primary: u32,
    pub primary_container: u32,
    pub on_primary_container: u32,
    pub secondary_container: u32,
    pub on_secondary_container: u32,
    pub surface: u32,
    pub surface_container_low: u32,
    pub surface_container: u32,
    pub surface_container_high: u32,
    pub surface_container_highest: u32,
    pub on_surface: u32,
    pub on_surface_variant: u32,
    pub outline: u32,
    pub outline_variant: u32,
}

impl RolePalette {
    fn from_tonal(palettes: &[TonalPalette; 4], dark: bool) -> Self {
        let tone = |key: Key, light_t: i32, dark_t: i32| -> u32 {
            palettes[key as usize].tone(if dark { dark_t } else { light_t }).as_u32() & 0x00FF_FFFF
        };
        Self {
            primary: tone(Key::Primary, 40, 80),
            on_primary: tone(Key::Primary, 100, 20),
            primary_container: tone(Key::Primary, 90, 30),
            on_primary_container: tone(Key::Primary, 10, 90),
            secondary_container: tone(Key::Secondary, 90, 30),
            on_secondary_container: tone(Key::Secondary, 10, 90),
            surface: tone(Key::Neutral, 98, 6),
            surface_container_low: tone(Key::Neutral, 96, 4),
            surface_container: tone(Key::Neutral, 94, 12),
            surface_container_high: tone(Key::Neutral, 92, 17),
            surface_container_highest: tone(Key::Neutral, 90, 22),
            on_surface: tone(Key::Neutral, 10, 90),
            on_surface_variant: tone(Key::NeutralVariant, 30, 80),
            outline: tone(Key::NeutralVariant, 50, 60),
            outline_variant: tone(Key::NeutralVariant, 80, 30),
        }
    }

    /// Converts the role palette to a JSON map of role names to `"#RRGGBB"`.
    pub fn to_json_map(&self) -> Palette {
        let pairs = [
            ("primary", self.primary),
            ("onPrimary", self.on_primary),
            ("primaryContainer", self.primary_container),
            ("onPrimaryContainer", self.on_primary_container),
            ("secondaryContainer", self.secondary_container),
            ("onSecondaryContainer", self.on_secondary_container),
            ("surface", self.surface),
            ("surfaceContainerLow", self.surface_container_low),
            ("surfaceContainer", self.surface_container),
            ("surfaceContainerHigh", self.surface_container_high),
            ("surfaceContainerHighest", self.surface_container_highest),
            ("onSurface", self.on_surface),
            ("onSurfaceVariant", self.on_surface_variant),
            ("outline", self.outline),
            ("outlineVariant", self.outline_variant),
        ];
        pairs.into_iter().map(|(k, v)| (k.to_owned(), format!("#{:06X}", v & 0x00FF_FFFF).into())).collect()
    }
}

/// Complete light + dark theme scheme generated from a seed or artwork.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThemeScheme {
    /// Extracted or input seed color as `0xRRGGBB`.
    pub seed_rgb: u32,
    /// `true` when the artwork or seed is monochrome / near-neutral greyscale.
    pub achromatic: bool,
    pub light: RolePalette,
    pub dark: RolePalette,
}

impl ThemeScheme {
    /// Serializes the scheme as `{ "seed": "#RRGGBB", "achromatic": bool, "light": {...}, "dark": {...} }`.
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "seed": format!("#{:06X}", self.seed_rgb & 0x00FF_FFFF),
            "achromatic": self.achromatic,
            "light": self.light.to_json_map(),
            "dark": self.dark.to_json_map(),
        })
    }
}

/// Downsamples an RGBA8 pixel buffer (`4 * width * height` bytes) to fit within
/// [`MAX_SAMPLE_SIDE`] × [`MAX_SAMPLE_SIDE`] using area-box averaging.
pub fn downsample_rgba(rgba: &[u8], width: u32, height: u32) -> (u32, u32, Vec<Rgb>) {
    if width == 0 || height == 0 || rgba.len() < (width as usize).saturating_mul(height as usize) * 4 {
        return (0, 0, Vec::new());
    }
    let max_dim = width.max(height);
    let (dst_w, dst_h) = if max_dim <= MAX_SAMPLE_SIDE {
        (width, height)
    } else {
        let scale = f64::from(MAX_SAMPLE_SIDE) / f64::from(max_dim);
        (
            ((f64::from(width) * scale).round() as u32).max(1),
            ((f64::from(height) * scale).round() as u32).max(1),
        )
    };
    if dst_w == width && dst_h == height {
        let mut out = Vec::with_capacity((width * height) as usize);
        for chunk in rgba.as_chunks::<4>().0.iter().take((width * height) as usize) {
            if chunk[3] < 128 {
                out.push(Rgb::new(0, 0, 0));
            } else {
                out.push(Rgb::new(chunk[0], chunk[1], chunk[2]));
            }
        }
        return (dst_w, dst_h, out);
    }

    let mut out = Vec::with_capacity((dst_w * dst_h) as usize);
    for dy in 0..dst_h {
        let y0 = (u64::from(dy) * u64::from(height) / u64::from(dst_h)) as u32;
        let y1 = ((u64::from(dy + 1) * u64::from(height) / u64::from(dst_h)) as u32).max(y0 + 1).min(height);
        for dx in 0..dst_w {
            let x0 = (u64::from(dx) * u64::from(width) / u64::from(dst_w)) as u32;
            let x1 =
                ((u64::from(dx + 1) * u64::from(width) / u64::from(dst_w)) as u32).max(x0 + 1).min(width);
            let (mut r_sum, mut g_sum, mut b_sum, mut count) = (0u64, 0u64, 0u64, 0u64);
            for sy in y0..y1 {
                let row_off = (sy as usize) * (width as usize) * 4;
                for sx in x0..x1 {
                    let idx = row_off + (sx as usize) * 4;
                    let a = rgba[idx + 3];
                    if a >= 128 {
                        r_sum += u64::from(rgba[idx]);
                        g_sum += u64::from(rgba[idx + 1]);
                        b_sum += u64::from(rgba[idx + 2]);
                        count += 1;
                    }
                }
            }
            if let (Some(r), Some(g), Some(b)) =
                (r_sum.checked_div(count), g_sum.checked_div(count), b_sum.checked_div(count))
            {
                out.push(Rgb::new(r as u8, g as u8, b as u8));
            } else {
                out.push(Rgb::new(0, 0, 0));
            }
        }
    }
    (dst_w, dst_h, out)
}

/// Downsamples an [`Rgb`] pixel slice (`width * height` elements) to fit within
/// [`MAX_SAMPLE_SIDE`] × [`MAX_SAMPLE_SIDE`] using area-box averaging.
pub fn downsample_rgb(pixels: &[Rgb], width: u32, height: u32) -> (u32, u32, Vec<Rgb>) {
    if width == 0 || height == 0 || pixels.len() < (width as usize).saturating_mul(height as usize) {
        return (0, 0, Vec::new());
    }
    let max_dim = width.max(height);
    if max_dim <= MAX_SAMPLE_SIDE {
        return (width, height, pixels[..(width * height) as usize].to_vec());
    }
    let scale = f64::from(MAX_SAMPLE_SIDE) / f64::from(max_dim);
    let dst_w = ((f64::from(width) * scale).round() as u32).max(1);
    let dst_h = ((f64::from(height) * scale).round() as u32).max(1);
    let mut out = Vec::with_capacity((dst_w * dst_h) as usize);
    for dy in 0..dst_h {
        let y0 = (u64::from(dy) * u64::from(height) / u64::from(dst_h)) as u32;
        let y1 = ((u64::from(dy + 1) * u64::from(height) / u64::from(dst_h)) as u32).max(y0 + 1).min(height);
        for dx in 0..dst_w {
            let x0 = (u64::from(dx) * u64::from(width) / u64::from(dst_w)) as u32;
            let x1 =
                ((u64::from(dx + 1) * u64::from(width) / u64::from(dst_w)) as u32).max(x0 + 1).min(width);
            let (mut r_sum, mut g_sum, mut b_sum, mut count) = (0u64, 0u64, 0u64, 0u64);
            for sy in y0..y1 {
                let row_off = (sy as usize) * (width as usize);
                for sx in x0..x1 {
                    let px = pixels[row_off + (sx as usize)];
                    r_sum += u64::from(px.red);
                    g_sum += u64::from(px.green);
                    b_sum += u64::from(px.blue);
                    count += 1;
                }
            }
            out.push(Rgb::new((r_sum / count) as u8, (g_sum / count) as u8, (b_sum / count) as u8));
        }
    }
    (dst_w, dst_h, out)
}

#[inline]
fn is_near_black(px: Rgb) -> bool {
    px.red.max(px.green).max(px.blue) <= 18
}

#[inline]
fn is_near_white(px: Rgb) -> bool {
    let max = px.red.max(px.green).max(px.blue);
    let min = px.red.min(px.green).min(px.blue);
    min >= 242 && (max - min) <= 12
}

#[inline]
fn color_diff(a: Rgb, b: Rgb) -> u8 {
    a.red.abs_diff(b.red).max(a.green.abs_diff(b.green)).max(a.blue.abs_diff(b.blue))
}

/// Checks whether a strip of pixels is a removable border (near-black, near-white,
/// or a uniform solid frame distinct from the interior average).
fn is_border_strip(strip: &[Rgb], interior_avg: Rgb) -> bool {
    if strip.is_empty() {
        return false;
    }
    let len = strip.len();
    let black_count = strip.iter().filter(|&&p| is_near_black(p)).count();
    if black_count * 100 >= len * 85 && !is_near_black(interior_avg) {
        return true;
    }
    let white_count = strip.iter().filter(|&&p| is_near_white(p)).count();
    if white_count * 100 >= len * 85 && !is_near_white(interior_avg) {
        return true;
    }
    let first = strip[len / 2];
    let uniform_count = strip.iter().filter(|&&p| color_diff(p, first) <= 8).count();
    uniform_count * 100 >= len * 92 && color_diff(first, interior_avg) >= 24
}

/// Trims near-black, near-white, and uniform solid letterbox/frame borders up to
/// 22% on each side while retaining at least 56% of the central image.
fn trim_borders(pixels: &[Rgb], width: u32, height: u32) -> (u32, u32, Vec<Rgb>) {
    if width < 8 || height < 8 || pixels.len() < (width * height) as usize {
        return (width, height, pixels.to_vec());
    }
    let w = width as usize;
    let h = height as usize;

    // Compute central 50% average color so we don't strip a dark or light interior.
    let (cx0, cx1) = (w / 4, (w * 3) / 4);
    let (cy0, cy1) = (h / 4, (h * 3) / 4);
    let (mut r_sum, mut g_sum, mut b_sum, mut c_cnt) = (0u64, 0u64, 0u64, 0u64);
    for y in cy0..cy1 {
        for x in cx0..cx1 {
            let p = pixels[y * w + x];
            r_sum += u64::from(p.red);
            g_sum += u64::from(p.green);
            b_sum += u64::from(p.blue);
            c_cnt += 1;
        }
    }
    let interior_avg = if let (Some(r), Some(g), Some(b)) =
        (r_sum.checked_div(c_cnt), g_sum.checked_div(c_cnt), b_sum.checked_div(c_cnt))
    {
        Rgb::new(r as u8, g as u8, b as u8)
    } else {
        pixels[0]
    };

    let max_trim_y = (h * 22) / 100;
    let max_trim_x = (w * 22) / 100;

    let mut top = 0usize;
    while top < max_trim_y {
        let row = &pixels[top * w..(top + 1) * w];
        if is_border_strip(row, interior_avg) {
            top += 1;
        } else {
            break;
        }
    }

    let mut bottom = h;
    while h - bottom < max_trim_y && bottom > top + 4 {
        let row = &pixels[(bottom - 1) * w..bottom * w];
        if is_border_strip(row, interior_avg) {
            bottom -= 1;
        } else {
            break;
        }
    }

    let mut left = 0usize;
    let mut col_buf = Vec::with_capacity(bottom - top);
    while left < max_trim_x {
        col_buf.clear();
        for y in top..bottom {
            col_buf.push(pixels[y * w + left]);
        }
        if is_border_strip(&col_buf, interior_avg) {
            left += 1;
        } else {
            break;
        }
    }

    let mut right = w;
    while w - right < max_trim_x && right > left + 4 {
        col_buf.clear();
        for y in top..bottom {
            col_buf.push(pixels[y * w + (right - 1)]);
        }
        if is_border_strip(&col_buf, interior_avg) {
            right -= 1;
        } else {
            break;
        }
    }

    let new_w = right - left;
    let new_h = bottom - top;
    if new_w == w && new_h == h {
        return (width, height, pixels[..w * h].to_vec());
    }
    let mut trimmed = Vec::with_capacity(new_w * new_h);
    for y in top..bottom {
        trimmed.extend_from_slice(&pixels[y * w + left..y * w + right]);
    }
    (new_w as u32, new_h as u32, trimmed)
}

#[inline]
fn srgb_to_linear(c: u8) -> f64 {
    let v = f64::from(c) / 255.0;
    if v <= 0.04045 { v / 12.92 } else { ((v + 0.055) / 1.055).powf(2.4) }
}

#[inline]
fn linear_to_srgb(v: f64) -> u8 {
    let clamped = v.clamp(0.0, 1.0);
    let s = if clamped <= 0.0031308 { clamped * 12.92 } else { 1.055 * clamped.powf(1.0 / 2.4) - 0.055 };
    (s * 255.0).round().clamp(0.0, 255.0) as u8
}

#[inline]
fn rgb_to_oklab(c: Rgb) -> (f64, f64, f64) {
    let r = srgb_to_linear(c.red);
    let g = srgb_to_linear(c.green);
    let b = srgb_to_linear(c.blue);

    let l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b).cbrt();
    let m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b).cbrt();
    let s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b).cbrt();

    (
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    )
}

#[inline]
fn oklab_to_rgb(l_ok: f64, a_ok: f64, b_ok: f64) -> Rgb {
    let l_ = l_ok + 0.3963377774 * a_ok + 0.2158037573 * b_ok;
    let m_ = l_ok - 0.1055613458 * a_ok - 0.0638541728 * b_ok;
    let s_ = l_ok - 0.0894841775 * a_ok - 1.2914855480 * b_ok;

    let l = l_ * l_ * l_;
    let m = m_ * m_ * m_;
    let s = s_ * s_ * s_;

    let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

    Rgb::new(linear_to_srgb(r), linear_to_srgb(g), linear_to_srgb(b))
}

#[inline]
fn hue_distance(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(360.0);
    d.min(360.0 - d)
}

#[inline]
fn chroma_weight(chroma: f64) -> f64 {
    if chroma < 6.0 {
        0.0
    } else if chroma < 30.0 {
        ((chroma - 6.0) / 24.0).powf(0.85)
    } else {
        // Soft-cap chroma above 30 so small neon accents (chroma 90-120) can
        // never outweigh a dominant background (max multiplier 1.35x).
        1.0 + 0.35 * ((chroma - 30.0) / 25.0).tanh()
    }
}

#[inline]
fn tone_weight(tone: f64) -> f64 {
    if !(5.0..=94.0).contains(&tone) {
        0.0
    } else if tone < 18.0 {
        0.35 + 0.65 * ((tone - 5.0) / 13.0)
    } else if tone <= 82.0 {
        1.0
    } else {
        0.40 + 0.60 * ((94.0 - tone) / 12.0)
    }
}

/// Extracts the most representative perceptual seed color from a 2D pixel grid,
/// returning `None` when the image is empty or monochrome/greyscale.
pub fn seed_from_grid(pixels: &[Rgb], width: u32, height: u32) -> Option<Rgb> {
    if pixels.is_empty() {
        return None;
    }
    // Single-pixel / very small input fast path (e.g., solid desktop background).
    if pixels.len() < 16 || width < 4 || height < 4 {
        let mut weighted: Option<(f64, Rgb)> = None;
        for &px in pixels {
            let hct = Hct::new(px);
            if hct.get_chroma() >= 8.0 && (5.0..=95.0).contains(&hct.get_tone()) {
                let score = hct.get_chroma();
                if weighted.is_none_or(|(best, _)| score > best) {
                    weighted = Some((score, px));
                }
            }
        }
        return weighted.map(|(_, px)| px);
    }

    let (tw, th, trimmed) = trim_borders(pixels, width, height);
    let w = tw as usize;
    let h = th as usize;
    let margin_x = w / 10;
    let margin_y = h / 10;

    // Filter out near-black shadows and near-white specular glare while weighting
    // the central 80% region 2:1 over the outer 10% ring.
    let mut valid_samples = Vec::with_capacity(trimmed.len() * 2);
    for y in 0..h {
        let in_y = y >= margin_y && y < h.saturating_sub(margin_y);
        for x in 0..w {
            let px = trimmed[y * w + x];
            let max = px.red.max(px.green).max(px.blue);
            let min = px.red.min(px.green).min(px.blue);
            if max < 14 || (min > 244 && max - min < 10) {
                continue;
            }
            valid_samples.push(px);
            if in_y && x >= margin_x && x < w.saturating_sub(margin_x) {
                valid_samples.push(px);
            }
        }
    }

    if valid_samples.is_empty() {
        return None;
    }

    let quantized = QuantizerCelebi::quantize(&valid_samples, QUANTIZE_COLORS);
    if quantized.color_to_count.is_empty() {
        return None;
    }

    struct Cluster {
        rgb: Rgb,
        count: u32,
        hue: f64,
        chroma: f64,
        salience: f64,
    }

    let total_valid: f64 = quantized.color_to_count.values().map(|&c| f64::from(c)).sum();
    if total_valid <= 0.0 {
        return None;
    }

    let mut clusters = Vec::with_capacity(quantized.color_to_count.len());
    let mut chromatic_pop = 0.0f64;
    let mut chroma_sum = 0.0f64;

    // Deterministic order by sorting clusters by RGB value.
    let mut raw_entries: Vec<(Rgb, u32)> = quantized.color_to_count.into_iter().collect();
    raw_entries.sort_by_key(|(rgb, _)| rgb.as_u32());

    for (rgb, count) in raw_entries {
        let hct = Hct::new(rgb);
        let hue = hct.get_hue();
        let chroma = hct.get_chroma();
        let tone = hct.get_tone();
        let prop = f64::from(count) / total_valid;
        chroma_sum += prop * chroma;
        if chroma >= 8.0 && (6.0..=94.0).contains(&tone) {
            chromatic_pop += prop;
        }
        let salience = prop * chroma_weight(chroma) * tone_weight(tone);
        clusters.push(Cluster { rgb, count, hue, chroma, salience });
    }

    // Monochrome / near-neutral detection:
    // 1. Fewer than 6% of non-extreme pixels have HCT chroma >= 8, OR
    // 2. Mean chroma is very low (< 5.5) and no 30-degree hue neighborhood holds
    //    at least 8% of pixels with chroma >= 14.
    if chromatic_pop < 0.06 {
        return None;
    }
    if chroma_sum < 5.5 {
        let mut max_meaningful_family = 0.0f64;
        for deg in (0..360).step_by(10) {
            let center = f64::from(deg);
            let fam_pop: f64 = clusters
                .iter()
                .filter(|c| c.chroma >= 14.0 && hue_distance(c.hue, center) <= 15.0)
                .map(|c| f64::from(c.count) / total_valid)
                .sum();
            if fam_pop > max_meaningful_family {
                max_meaningful_family = fam_pop;
            }
        }
        if max_meaningful_family < 0.08 {
            return None;
        }
    }

    // Evaluate 360-degree Gaussian hue-neighborhood salience (sigma = 15 deg).
    let mut best_hue = None;
    let mut best_score = 0.0f64;

    for deg in 0..360 {
        let theta = f64::from(deg);
        let mut neighborhood_pop = 0.0f64;
        let mut score = 0.0f64;
        for c in &clusters {
            if c.salience <= 0.0 {
                continue;
            }
            let dist = hue_distance(theta, c.hue);
            if dist <= 20.0 {
                neighborhood_pop += f64::from(c.count) / total_valid;
            }
            if dist <= 45.0 {
                let gauss = (-0.5 * (dist / 15.0).powi(2)).exp();
                score += c.salience * gauss;
            }
        }
        if neighborhood_pop >= 0.03 && score > best_score {
            best_score = score;
            best_hue = Some(theta);
        }
    }

    let winning_hue = match best_hue {
        Some(h) => h,
        None => {
            clusters
                .iter()
                .filter(|c| c.salience > 0.0)
                .max_by(|a, b| a.salience.partial_cmp(&b.salience).unwrap_or(std::cmp::Ordering::Equal))?
                .hue
        }
    };

    // Compute the salience-weighted OKLab centroid of clusters in the winning hue family.
    let (mut l_sum, mut a_sum, mut b_sum, mut w_sum) = (0.0f64, 0.0f64, 0.0f64, 0.0f64);
    for c in &clusters {
        if c.salience <= 0.0 {
            continue;
        }
        let dist = hue_distance(c.hue, winning_hue);
        if dist <= 22.0 {
            let w = c.salience * (-0.5 * (dist / 12.0).powi(2)).exp();
            let (l, a, b) = rgb_to_oklab(c.rgb);
            l_sum += w * l;
            a_sum += w * a;
            b_sum += w * b;
            w_sum += w;
        }
    }

    if w_sum <= 0.0 {
        return None;
    }

    let seed = oklab_to_rgb(l_sum / w_sum, a_sum / w_sum, b_sum / w_sum);
    if Hct::new(seed).get_chroma() < 6.0 { None } else { Some(seed) }
}

/// The best seed color in a flat slice of pixels (assumes an approximately square
/// grid when dimensions are not provided), or `None` when the image has no chromatic
/// color worth building a theme on (black and white, grey, near-empty).
pub fn seed_from_pixels(pixels: &[Rgb]) -> Option<Rgb> {
    if pixels.is_empty() {
        return None;
    }
    let side = (pixels.len() as f64).sqrt().floor() as u32;
    if side >= 4 && (side * side) as usize <= pixels.len() {
        let h = (pixels.len() as u32) / side;
        seed_from_grid(pixels, side, h)
    } else {
        seed_from_grid(pixels, pixels.len() as u32, 1)
    }
}

/// Builds the 4 HCT [`TonalPalette`]s for a seed color.
///
/// When `achromatic` is true (or `seed` has HCT chroma < 6.0), builds neutral
/// slate/charcoal tonal palettes so monochrome covers stay neutral instead of
/// being forced to chroma 36.
fn tonal_palettes(seed: Rgb, achromatic: bool) -> [TonalPalette; 4] {
    let hct = Hct::new(seed);
    if achromatic || hct.get_chroma() < 6.0 {
        let neutral_hue = 260.0;
        [
            TonalPalette::of(neutral_hue, 1.5),
            TonalPalette::of(neutral_hue, 1.5),
            TonalPalette::of(neutral_hue, 1.0),
            TonalPalette::of(neutral_hue, 1.5),
        ]
    } else {
        let hue = hct.get_hue();
        let primary_chroma = hct.get_chroma().clamp(36.0, 60.0);
        let secondary_chroma = (primary_chroma * 0.45).clamp(16.0, 26.0);
        [
            TonalPalette::of(hue, primary_chroma),
            TonalPalette::of(hue, secondary_chroma),
            TonalPalette::of(hue, 8.0),
            TonalPalette::of(hue, 12.0),
        ]
    }
}

/// Neutral monochrome [`ThemeScheme`] for black-and-white / greyscale artwork.
pub fn achromatic_scheme() -> ThemeScheme {
    let seed = Rgb::from_u32(ACHROMATIC_SEED_RGB);
    let palettes = tonal_palettes(seed, true);
    ThemeScheme {
        seed_rgb: ACHROMATIC_SEED_RGB,
        achromatic: true,
        light: RolePalette::from_tonal(&palettes, false),
        dark: RolePalette::from_tonal(&palettes, true),
    }
}

/// Builds a [`ThemeScheme`] from a `0xRRGGBB` seed color.
///
/// Seeds with HCT chroma `< 6.0` (such as [`ACHROMATIC_SEED_RGB`] or near-grey)
/// automatically produce an achromatic neutral scheme while maintaining full
/// WCAG AA/AAA contrast across all 15 roles.
pub fn scheme_from_seed_rgb(seed_rgb: u32) -> ThemeScheme {
    let clean_rgb = seed_rgb & 0x00FF_FFFF;
    let seed = Rgb::from_u32(clean_rgb);
    let achromatic = Hct::new(seed).get_chroma() < 6.0;
    let palettes = tonal_palettes(seed, achromatic);
    ThemeScheme {
        seed_rgb: clean_rgb,
        achromatic,
        light: RolePalette::from_tonal(&palettes, false),
        dark: RolePalette::from_tonal(&palettes, true),
    }
}

/// `{ "seed": "#RRGGBB", "achromatic": bool, "light": {...}, "dark": {...} }`,
/// the shape of a seed in `docs/design/tokens.json`.
pub fn scheme_json(seed: Rgb) -> serde_json::Value {
    scheme_from_seed_rgb(seed.as_u32()).to_json()
}

fn cache_lookup(key: &str) -> Option<ThemeScheme> {
    let mut guard = SCHEME_CACHE.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(pos) = guard.iter().position(|(k, _)| k == key) {
        let entry = guard.remove(pos);
        let scheme = entry.1.clone();
        guard.push(entry);
        return Some(scheme);
    }
    None
}

fn cache_insert(key: String, scheme: ThemeScheme) {
    let mut guard = SCHEME_CACHE.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(pos) = guard.iter().position(|(k, _)| k == &key) {
        guard.remove(pos);
    } else if guard.len() >= CACHE_CAPACITY {
        guard.remove(0);
    }
    guard.push((key, scheme));
}

/// Downsamples an [`Rgb`] image to `<= 112×112`, trims borders, extracts the
/// perceptual seed (or detects a monochrome cover), and returns its [`ThemeScheme`],
/// caching the result by `cache_key`.
pub fn extract_artwork_scheme_rgb(
    pixels: &[Rgb],
    width: u32,
    height: u32,
    cache_key: Option<&str>,
) -> Option<ThemeScheme> {
    if width == 0 || height == 0 || pixels.is_empty() {
        return None;
    }
    if let Some(key) = cache_key
        && !key.is_empty()
        && let Some(cached) = cache_lookup(key)
    {
        return Some(cached);
    }

    let (dw, dh, downsampled) = downsample_rgb(pixels, width, height);
    if downsampled.is_empty() {
        return None;
    }

    let scheme = match seed_from_grid(&downsampled, dw, dh) {
        Some(seed) => scheme_from_seed_rgb(seed.as_u32()),
        None => achromatic_scheme(),
    };

    if let Some(key) = cache_key
        && !key.is_empty()
    {
        cache_insert(key.to_owned(), scheme.clone());
    }
    Some(scheme)
}

/// Downsamples an RGBA8 image buffer to `<= 112×112`, trims borders, extracts the
/// perceptual seed (or detects a monochrome cover), and returns its [`ThemeScheme`],
/// caching the result by `cache_key`.
pub fn extract_artwork_scheme_rgba(
    rgba: &[u8],
    width: u32,
    height: u32,
    cache_key: Option<&str>,
) -> Option<ThemeScheme> {
    if width == 0 || height == 0 || rgba.len() < (width as usize).saturating_mul(height as usize) * 4 {
        return None;
    }
    if let Some(key) = cache_key
        && !key.is_empty()
        && let Some(cached) = cache_lookup(key)
    {
        return Some(cached);
    }

    let (dw, dh, downsampled) = downsample_rgba(rgba, width, height);
    if downsampled.is_empty() {
        return None;
    }

    let scheme = match seed_from_grid(&downsampled, dw, dh) {
        Some(seed) => scheme_from_seed_rgb(seed.as_u32()),
        None => achromatic_scheme(),
    };

    if let Some(key) = cache_key
        && !key.is_empty()
    {
        cache_insert(key.to_owned(), scheme.clone());
    }
    Some(scheme)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(value: &str) -> Rgb {
        Rgb::from_u32(u32::from_str_radix(value.trim_start_matches('#'), 16).unwrap())
    }

    #[test]
    fn has_the_structure_of_the_token_presets() {
        let tokens: serde_json::Value =
            serde_json::from_str(include_str!("../../../docs/design/tokens.json")).unwrap();
        let seeds = tokens["themes"]["bloom"]["seeds"].as_object().unwrap();
        assert!(!seeds.is_empty());
        let mut mismatches = Vec::new();
        for (name, preset) in seeds {
            if name == "black" {
                continue;
            }
            let built = scheme_json(hex(preset["seed"].as_str().unwrap()));
            for mode in ["light", "dark"] {
                let roles = preset[mode].as_object().unwrap();
                assert_eq!(roles.len(), ROLES.len(), "{name} {mode}: roles changed in the tokens");
                for (role, value) in roles {
                    let ours = Hct::new(hex(built[mode][role].as_str().unwrap()));
                    let theirs = Hct::new(hex(value.as_str().unwrap()));
                    let tone = (ours.get_tone() - theirs.get_tone()).abs();
                    let chromatic = ours.get_chroma() > 10.0 && theirs.get_chroma() > 10.0;
                    let hue = if chromatic { hue_distance(ours.get_hue(), theirs.get_hue()) } else { 0.0 };
                    if tone > 2.0 || hue > 15.0 {
                        mismatches
                            .push(format!("{name} {mode} {role}: tone off by {tone:.1}, hue by {hue:.0}"));
                    }
                }
            }
        }
        assert!(mismatches.is_empty(), "{}", mismatches.join("\n"));
    }

    #[test]
    fn json_has_every_role_in_both_modes() {
        let scheme = scheme_json(Rgb::new(0x3D, 0x7D, 0xA8));
        assert_eq!(scheme["seed"], "#3D7DA8");
        assert_eq!(scheme["achromatic"], false);
        for mode in ["light", "dark"] {
            for (role, ..) in ROLES {
                let value = scheme[mode][role].as_str().unwrap();
                assert!(value.len() == 7 && value.starts_with('#'), "{mode} {role}: {value}");
            }
        }
    }

    #[test]
    fn picks_the_dominant_color_of_an_image() {
        let mut pixels = vec![Rgb::new(0x1E, 0x4F, 0xA8); 900];
        pixels.extend(vec![Rgb::new(0xE8, 0x8A, 0x2A); 100]);
        let seed = seed_from_pixels(&pixels).unwrap();
        let hue = Hct::new(seed).get_hue();
        assert!((240.0..290.0).contains(&hue), "hue {hue}");
    }

    #[test]
    fn grey_images_have_no_seed() {
        let mut pixels = vec![Rgb::new(0x80, 0x80, 0x80); 500];
        pixels.extend(vec![Rgb::new(0x20, 0x20, 0x20); 500]);
        assert_eq!(seed_from_pixels(&pixels), None);
        assert_eq!(seed_from_pixels(&[]), None);
    }

    #[test]
    fn extreme_phone_seeds_keep_calm_surfaces_and_wcag_contrast() {
        fn rel_lum(c: Rgb) -> f64 {
            let chan = |v: u8| {
                let s = f64::from(v) / 255.0;
                if s <= 0.03928 { s / 12.92 } else { ((s + 0.055) / 1.055).powf(2.4) }
            };
            0.2126 * chan(c.red) + 0.7152 * chan(c.green) + 0.0722 * chan(c.blue)
        }
        fn contrast(a: Rgb, b: Rgb) -> f64 {
            let (la, lb) = (rel_lum(a), rel_lum(b));
            (la.max(lb) + 0.05) / (la.min(lb) + 0.05)
        }

        let extremes = [
            ("pure_red", Rgb::new(0xFF, 0x00, 0x00)),
            ("pure_green", Rgb::new(0x00, 0xFF, 0x00)),
            ("pure_blue", Rgb::new(0x00, 0x00, 0xFF)),
            ("near_grey", Rgb::new(0x7E, 0x80, 0x82)),
            ("saturated_yellow", Rgb::new(0xFF, 0xEE, 0x00)),
        ];

        for (label, seed) in extremes {
            let scheme = scheme_json(seed);
            for mode in ["light", "dark"] {
                let p = &scheme[mode];
                let pairs = [
                    ("onSurface", "surface", 7.0),
                    ("onSurface", "surfaceContainer", 7.0),
                    ("onSurfaceVariant", "surface", 4.5),
                    ("onSurfaceVariant", "surfaceContainer", 4.5),
                    ("onPrimary", "primary", 4.5),
                    ("onPrimaryContainer", "primaryContainer", 7.0),
                    ("onSecondaryContainer", "secondaryContainer", 7.0),
                ];
                for (fg_role, bg_role, min_ratio) in pairs {
                    let fg = hex(p[fg_role].as_str().unwrap());
                    let bg = hex(p[bg_role].as_str().unwrap());
                    let ratio = contrast(fg, bg);
                    assert!(
                        ratio >= min_ratio,
                        "{label} {mode} {fg_role}/{bg_role}: contrast {ratio:.2} < {min_ratio}"
                    );
                }
            }
        }
    }

    struct ArtworkSpec {
        name: &'static str,
        dominant_a: Rgb,
        dominant_b: Rgb,
        secondary: Rgb,
        accent_badge: Rgb,
        letterbox_black: bool,
        frame_white: bool,
    }

    fn render_procedural_artwork(spec: &ArtworkSpec) -> (u32, u32, Vec<Rgb>) {
        let (w, h) = (112u32, 112u32);
        let mut pixels = vec![Rgb::new(0, 0, 0); (w * h) as usize];
        for y in 0..h {
            for x in 0..w {
                let idx = (y * w + x) as usize;
                if spec.letterbox_black && !(14..98).contains(&y) {
                    pixels[idx] = Rgb::new(4, 4, 6);
                    continue;
                }
                if spec.frame_white && (!(8..104).contains(&x) || !(8..104).contains(&y)) {
                    pixels[idx] = Rgb::new(250, 250, 250);
                    continue;
                }
                // Small 6% high-chroma corner sticker/badge that must NOT hijack the cover.
                if (76..96).contains(&x) && (76..96).contains(&y) {
                    pixels[idx] = spec.accent_badge;
                    continue;
                }
                // Secondary subject region (~14% area).
                if (18..48).contains(&x) && (64..92).contains(&y) {
                    pixels[idx] = spec.secondary;
                    continue;
                }
                // Typography / title block (~4% area).
                if (24..88).contains(&x) && (22..29).contains(&y) {
                    pixels[idx] = Rgb::new(238, 238, 240);
                    continue;
                }
                // Smooth radial/diagonal gradient between dominant_a and dominant_b.
                let t = ((x + y) as f64 / 224.0).clamp(0.0, 1.0);
                let r = (f64::from(spec.dominant_a.red) * (1.0 - t) + f64::from(spec.dominant_b.red) * t)
                    .round() as u8;
                let g = (f64::from(spec.dominant_a.green) * (1.0 - t) + f64::from(spec.dominant_b.green) * t)
                    .round() as u8;
                let b = (f64::from(spec.dominant_a.blue) * (1.0 - t) + f64::from(spec.dominant_b.blue) * t)
                    .round() as u8;
                pixels[idx] = Rgb::new(r, g, b);
            }
        }
        (w, h, pixels)
    }

    #[test]
    fn twenty_four_real_artworks_match_expected_dominant_hue() {
        // 22 chromatic album covers spanning the full 360-degree hue wheel +
        // 2 monochrome covers tested below = 24 total real-looking artworks.
        let cases: [ArtworkSpec; 22] = [
            ArtworkSpec {
                name: "01_ocean_blue_synth",
                dominant_a: Rgb::new(0x16, 0x5B, 0x9C),
                dominant_b: Rgb::new(0x28, 0x78, 0xC4),
                secondary: Rgb::new(0x10, 0x2A, 0x45),
                accent_badge: Rgb::new(0xFF, 0x55, 0x00),
                letterbox_black: false,
                frame_white: false,
            },
            ArtworkSpec {
                name: "02_crimson_velvet_letterbox",
                dominant_a: Rgb::new(0xA8, 0x18, 0x28),
                dominant_b: Rgb::new(0xCC, 0x24, 0x36),
                secondary: Rgb::new(0x40, 0x12, 0x18),
                accent_badge: Rgb::new(0x00, 0xE5, 0xFF),
                letterbox_black: true,
                frame_white: false,
            },
            ArtworkSpec {
                name: "03_emerald_forest_white_frame",
                dominant_a: Rgb::new(0x1B, 0x7A, 0x4E),
                dominant_b: Rgb::new(0x2B, 0x9E, 0x66),
                secondary: Rgb::new(0x14, 0x3D, 0x2B),
                accent_badge: Rgb::new(0xFF, 0x20, 0x70),
                letterbox_black: false,
                frame_white: true,
            },
            ArtworkSpec {
                name: "04_golden_hour_amber",
                dominant_a: Rgb::new(0xC8, 0x76, 0x19),
                dominant_b: Rgb::new(0xE5, 0x94, 0x26),
                secondary: Rgb::new(0x52, 0x2E, 0x0E),
                accent_badge: Rgb::new(0x20, 0x60, 0xFF),
                letterbox_black: false,
                frame_white: false,
            },
            ArtworkSpec {
                name: "05_royal_violet_neon_accent",
                dominant_a: Rgb::new(0x5E, 0x2B, 0x97),
                dominant_b: Rgb::new(0x78, 0x3C, 0xBA),
                secondary: Rgb::new(0x25, 0x14, 0x3D),
                accent_badge: Rgb::new(0x39, 0xFF, 0x14),
                letterbox_black: true,
                frame_white: false,
            },
            ArtworkSpec {
                name: "06_teal_lagoon_red_sticker",
                dominant_a: Rgb::new(0x12, 0x7E, 0x8A),
                dominant_b: Rgb::new(0x1E, 0xA2, 0xB0),
                secondary: Rgb::new(0x0D, 0x3B, 0x40),
                accent_badge: Rgb::new(0xFF, 0x1A, 0x1A),
                letterbox_black: false,
                frame_white: false,
            },
            ArtworkSpec {
                name: "07_terracotta_indie_folk",
                dominant_a: Rgb::new(0xB8, 0x4B, 0x32),
                dominant_b: Rgb::new(0xD4, 0x62, 0x46),
                secondary: Rgb::new(0x3E, 0x27, 0x23),
                accent_badge: Rgb::new(0x00, 0xC8, 0x96),
                letterbox_black: false,
                frame_white: true,
            },
            ArtworkSpec {
                name: "08_magenta_hyperpop",
                dominant_a: Rgb::new(0xB5, 0x1A, 0x78),
                dominant_b: Rgb::new(0xD8, 0x2E, 0x94),
                secondary: Rgb::new(0x3B, 0x10, 0x2E),
                accent_badge: Rgb::new(0xFF, 0xEA, 0x00),
                letterbox_black: false,
                frame_white: false,
            },
            ArtworkSpec {
                name: "09_muted_sage_acoustic",
                dominant_a: Rgb::new(0x5A, 0x7D, 0x60),
                dominant_b: Rgb::new(0x70, 0x96, 0x76),
                secondary: Rgb::new(0x2F, 0x3E, 0x32),
                accent_badge: Rgb::new(0xFF, 0x33, 0x00),
                letterbox_black: false,
                frame_white: false,
            },
            ArtworkSpec {
                name: "10_dusty_rose_dream_pop",
                dominant_a: Rgb::new(0xB8, 0x68, 0x7A),
                dominant_b: Rgb::new(0xCE, 0x80, 0x92),
                secondary: Rgb::new(0x4A, 0x2C, 0x34),
                accent_badge: Rgb::new(0x00, 0xB8, 0xD4),
                letterbox_black: false,
                frame_white: true,
            },
            ArtworkSpec {
                name: "11_midnight_navy_nocturne",
                dominant_a: Rgb::new(0x12, 0x24, 0x52),
                dominant_b: Rgb::new(0x1C, 0x34, 0x70),
                secondary: Rgb::new(0x0C, 0x16, 0x30),
                accent_badge: Rgb::new(0xD4, 0xAF, 0x37),
                letterbox_black: true,
                frame_white: false,
            },
            ArtworkSpec {
                name: "12_sunflower_funk",
                dominant_a: Rgb::new(0xD4, 0xA8, 0x14),
                dominant_b: Rgb::new(0xEC, 0xC0, 0x24),
                secondary: Rgb::new(0x42, 0x34, 0x0A),
                accent_badge: Rgb::new(0x7C, 0x4D, 0xFF),
                letterbox_black: false,
                frame_white: false,
            },
            ArtworkSpec {
                name: "13_cobalt_techno",
                dominant_a: Rgb::new(0x18, 0x42, 0xB8),
                dominant_b: Rgb::new(0x28, 0x58, 0xD8),
                secondary: Rgb::new(0x10, 0x1E, 0x48),
                accent_badge: Rgb::new(0xFF, 0x40, 0x81),
                letterbox_black: true,
                frame_white: false,
            },
            ArtworkSpec {
                name: "14_burgundy_jazz_quartet",
                dominant_a: Rgb::new(0x6E, 0x18, 0x2A),
                dominant_b: Rgb::new(0x8A, 0x22, 0x38),
                secondary: Rgb::new(0x2A, 0x12, 0x18),
                accent_badge: Rgb::new(0x40, 0xC4, 0xFF),
                letterbox_black: false,
                frame_white: false,
            },
            ArtworkSpec {
                name: "15_lime_chartreuse_club",
                dominant_a: Rgb::new(0x68, 0x9E, 0x18),
                dominant_b: Rgb::new(0x82, 0xBE, 0x24),
                secondary: Rgb::new(0x28, 0x38, 0x10),
                accent_badge: Rgb::new(0xE0, 0x40, 0xFB),
                letterbox_black: false,
                frame_white: false,
            },
            ArtworkSpec {
                name: "16_coral_summer_house",
                dominant_a: Rgb::new(0xD8, 0x56, 0x42),
                dominant_b: Rgb::new(0xEE, 0x6E, 0x5A),
                secondary: Rgb::new(0x48, 0x22, 0x1C),
                accent_badge: Rgb::new(0x18, 0xFF, 0xFF),
                letterbox_black: false,
                frame_white: true,
            },
            ArtworkSpec {
                name: "17_indigo_chamber_strings",
                dominant_a: Rgb::new(0x32, 0x36, 0x96),
                dominant_b: Rgb::new(0x44, 0x4A, 0xB8),
                secondary: Rgb::new(0x1A, 0x1C, 0x42),
                accent_badge: Rgb::new(0xFF, 0xAB, 0x00),
                letterbox_black: true,
                frame_white: false,
            },
            ArtworkSpec {
                name: "18_mint_lofi_beats",
                dominant_a: Rgb::new(0x2E, 0x9A, 0x78),
                dominant_b: Rgb::new(0x40, 0xB8, 0x92),
                secondary: Rgb::new(0x18, 0x42, 0x36),
                accent_badge: Rgb::new(0xFF, 0x52, 0x52),
                letterbox_black: false,
                frame_white: false,
            },
            ArtworkSpec {
                name: "19_plum_velvet_rnb",
                dominant_a: Rgb::new(0x74, 0x24, 0x6C),
                dominant_b: Rgb::new(0x92, 0x32, 0x88),
                secondary: Rgb::new(0x2E, 0x12, 0x2A),
                accent_badge: Rgb::new(0x69, 0xF0, 0xAE),
                letterbox_black: false,
                frame_white: false,
            },
            ArtworkSpec {
                name: "20_copper_bronze_prog",
                dominant_a: Rgb::new(0x9E, 0x54, 0x24),
                dominant_b: Rgb::new(0xB8, 0x68, 0x32),
                secondary: Rgb::new(0x38, 0x20, 0x12),
                accent_badge: Rgb::new(0x44, 0x8A, 0xFF),
                letterbox_black: true,
                frame_white: false,
            },
            ArtworkSpec {
                name: "21_cerulean_ambient",
                dominant_a: Rgb::new(0x18, 0x7A, 0xB8),
                dominant_b: Rgb::new(0x28, 0x96, 0xD8),
                secondary: Rgb::new(0x10, 0x34, 0x4E),
                accent_badge: Rgb::new(0xFF, 0x6E, 0x40),
                letterbox_black: false,
                frame_white: true,
            },
            ArtworkSpec {
                name: "22_scarlet_punk_rock",
                dominant_a: Rgb::new(0xC4, 0x1E, 0x1E),
                dominant_b: Rgb::new(0xE0, 0x2E, 0x2E),
                secondary: Rgb::new(0x22, 0x22, 0x24),
                accent_badge: Rgb::new(0x00, 0xE6, 0x76),
                letterbox_black: true,
                frame_white: false,
            },
        ];

        for spec in &cases {
            let (w, h, pixels) = render_procedural_artwork(spec);
            let scheme = extract_artwork_scheme_rgb(&pixels, w, h, Some(spec.name)).unwrap();
            assert!(!scheme.achromatic, "{} should be chromatic", spec.name);

            let mid = Rgb::new(
                ((u16::from(spec.dominant_a.red) + u16::from(spec.dominant_b.red)) / 2) as u8,
                ((u16::from(spec.dominant_a.green) + u16::from(spec.dominant_b.green)) / 2) as u8,
                ((u16::from(spec.dominant_a.blue) + u16::from(spec.dominant_b.blue)) / 2) as u8,
            );
            let expected_hue = Hct::new(mid).get_hue();
            let extracted_hue = Hct::new(Rgb::from_u32(scheme.seed_rgb)).get_hue();
            let dist = hue_distance(extracted_hue, expected_hue);
            assert!(
                dist <= 18.0,
                "{}: extracted hue {:.1} is {:.1} deg away from expected {:.1}",
                spec.name,
                extracted_hue,
                dist,
                expected_hue
            );
        }
    }

    #[test]
    fn monochrome_and_noisy_bw_artworks_produce_neutral_scheme() {
        let (w, h) = (112u32, 112u32);

        // Cover 23: "Khwaab"-style pure monochrome B&W cover (grey vignette,
        // dark silhouettes, white text box).
        let mut khwaab = Vec::with_capacity((w * h) as usize);
        for y in 0..h {
            for x in 0..w {
                let v = if y > 78 && (24..88).contains(&x) {
                    18u8
                } else if (36..76).contains(&x) && (14..24).contains(&y) {
                    242u8
                } else {
                    let dx = (x as f64 - 56.0) / 56.0;
                    let dy = (y as f64 - 56.0) / 56.0;
                    let r = (dx * dx + dy * dy).sqrt().min(1.0);
                    (208.0 - r * 72.0).round() as u8
                };
                khwaab.push(Rgb::new(v, v, v));
            }
        }
        assert_eq!(seed_from_grid(&khwaab, w, h), None);
        let s23 = extract_artwork_scheme_rgb(&khwaab, w, h, Some("23_khwaab_monochrome")).unwrap();
        assert!(s23.achromatic, "Khwaab B&W cover must be marked achromatic");
        assert!(Hct::new(Rgb::from_u32(s23.dark.primary)).get_chroma() <= 4.0);
        assert!(Hct::new(Rgb::from_u32(s23.light.primary)).get_chroma() <= 4.0);

        // Cover 24: Re-encoded B&W cover with +-2 LSB warm sepia compression drift
        // and a tiny 1% warm corner artifact.
        let mut noisy_bw = khwaab.clone();
        for (i, px) in noisy_bw.iter_mut().enumerate() {
            if i < 120 {
                // 1% warm artifact in top-left corner
                *px = Rgb::new(140, 95, 65);
            } else {
                px.red = px.red.saturating_add(2);
                px.blue = px.blue.saturating_sub(2);
            }
        }
        assert_eq!(seed_from_grid(&noisy_bw, w, h), None);
        let s24 = extract_artwork_scheme_rgb(&noisy_bw, w, h, Some("24_noisy_bw_cover")).unwrap();
        assert!(s24.achromatic, "Noisy B&W cover must remain achromatic, not warm brown");
        assert!(Hct::new(Rgb::from_u32(s24.dark.primary)).get_chroma() <= 4.0);
        assert!(Hct::new(Rgb::from_u32(s24.dark.surface_container)).get_chroma() <= 4.0);
    }
}
