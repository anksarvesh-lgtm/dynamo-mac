// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS system media transport controls stubs.

use crate::state::PlayerView;
use maclink_core::{DeviceId, MediaAction};

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct Shown {
    pub device: DeviceId,
    pub device_name: String,
    pub view: PlayerView,
}

pub fn start(_on_command: impl Fn(DeviceId, String, MediaAction, Option<u64>) + Send + Sync + 'static) {}
pub fn show(_shown: Option<Shown>) {}
#[allow(dead_code)]
pub fn clear() {}
