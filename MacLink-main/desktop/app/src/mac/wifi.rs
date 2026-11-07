// SPDX-License-Identifier: GPL-3.0-or-later
//! Wi-Fi stubs on macOS.

/// Whether a Wi-Fi network is in range.
#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reach {
    NotInRange,
    InRange,
    Connected,
}

/// Saved Wi-Fi networks known to the OS.
pub fn saved_networks() -> Vec<String> {
    Vec::new()
}

/// Requests a background Wi-Fi scan.
pub fn scan() {}

/// Checks whether `profile` is in range or connected.
pub fn reach(_profile: &str) -> Reach {
    Reach::NotInRange
}

/// Connects to a saved Wi-Fi profile.
pub fn connect(_profile: &str) -> Result<(), String> {
    Err("Wi-Fi network connection is not supported on macOS".into())
}
