// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS media session integration stubs.

use maclink_core::{MediaAction, MediaError, MediaPlayer};

pub fn start(_on_change: impl Fn(Vec<MediaPlayer>) + Send + Sync + 'static) {}

pub fn command(_player: &str, _action: MediaAction, _pos: Option<u64>) -> Result<(), MediaError> {
    Ok(())
}

pub fn pause_for_call() {}

pub fn resume_after_call() {}

#[allow(dead_code)]
pub fn says_video(_id: &str) -> bool {
    false
}
