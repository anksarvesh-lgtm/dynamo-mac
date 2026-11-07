// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS network change notification stubs.

pub fn watch(_callback: impl Fn() + Send + Sync + 'static) {}
pub fn stop() {}
