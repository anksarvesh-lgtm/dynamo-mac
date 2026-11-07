// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS task argument stubs.

use std::path::Path;

pub const ARG: &str = "--task";

pub fn register(_data_dir: Option<&Path>) {}

pub fn unregister() {}
