// SPDX-License-Identifier: GPL-3.0-or-later
//! Webcam integration stub for macOS.
//! Phone camera and webcam continuity are retired per user specification.

use crate::settings::Settings;
use maclink_core::{DeviceId, NodeEvent, WebcamSink};
use std::sync::{Arc, Mutex};

#[allow(dead_code)] // Preview stream identifier for webcam
pub const PREVIEW_STREAM: &str = "webcam";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Phase {
    Idle,
    #[allow(dead_code)] // Asking phase for webcam stream
    Asking {
        device: DeviceId,
    },
    #[allow(dead_code)] // Active streaming phase for webcam stream
    Streaming {
        device: DeviceId,
        width: u32,
        height: u32,
        fps: u32,
    },
    #[allow(dead_code)] // Ended phase for webcam stream
    Ended {
        reason: String,
    },
}

static SELECTED_PHONE: Mutex<Option<DeviceId>> = Mutex::new(None);
static CAMERA: Mutex<String> = Mutex::new(String::new());

pub fn init(_settings: &Settings) {}
pub fn shutdown() {}
pub fn release_idle_resources() {}

pub fn sink(_peer: &DeviceId) -> Option<Arc<dyn WebcamSink>> {
    None
}

pub fn phase() -> Phase {
    Phase::Idle
}

pub fn addon_registered() -> bool {
    false
}

pub fn addon_busy() -> bool {
    false
}

pub fn height() -> u32 {
    1080
}

pub fn uhd() -> bool {
    false
}

pub fn camera() -> String {
    CAMERA.lock().map(|g| g.clone()).unwrap_or_default()
}

pub fn set_camera(camera: &str) {
    if let Ok(mut g) = CAMERA.lock() {
        *g = camera.to_string();
    }
}

pub fn mirror() -> bool {
    false
}

pub fn set_mirror(_on: bool) {}

pub fn selected_phone() -> Option<DeviceId> {
    SELECTED_PHONE.lock().ok().and_then(|g| *g)
}

pub fn set_selected_phone(id: DeviceId) {
    if let Ok(mut g) = SELECTED_PHONE.lock() {
        *g = Some(id);
    }
}

pub fn set_height(_h: u32) {}
pub fn setup_addon() {}
pub fn remove_addon() {}
pub fn start(_device: Option<DeviceId>) {}
pub fn stop() {}
pub fn set_preview_active(_active: bool) {}
pub fn on_event(_event: &NodeEvent) {}
