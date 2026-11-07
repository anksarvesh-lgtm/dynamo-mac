// SPDX-License-Identifier: GPL-3.0-or-later
//! Shared perceptual color extraction and Bloom tonal scheme builder,
//! re-exported from [`maclink_core::palette`].

#[allow(unused_imports)]
pub use maclink_core::palette::{
    ACHROMATIC_SEED_RGB, MAX_SAMPLE_SIDE, Palette, ROLES, Rgb, RolePalette, ThemeScheme, achromatic_scheme,
    downsample_rgb, downsample_rgba, extract_artwork_scheme_rgb, extract_artwork_scheme_rgba,
    scheme_from_seed_rgb, scheme_json, seed_from_grid, seed_from_pixels,
};
