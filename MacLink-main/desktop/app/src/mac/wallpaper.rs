// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS wallpaper color accent seed and artwork palette extraction.

use material_colors::color::Rgb;
use std::path::Path;

pub fn seed() -> Option<Rgb> {
    Some(Rgb::new(245, 166, 35))
}

pub fn artwork_scheme_from_path(_path: &Path) -> Option<String> {
    None
}
