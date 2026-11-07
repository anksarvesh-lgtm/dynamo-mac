// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS Wake-on-LAN integration stubs.

use maclink_core::PcWakeInfo;

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WakeSupport {
    Enabled,
    Disabled,
    Unknown,
}

impl WakeSupport {
    pub fn as_str(self) -> &'static str {
        match self {
            WakeSupport::Enabled => "enabled",
            WakeSupport::Disabled => "disabled",
            WakeSupport::Unknown => "unknown",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WakeAdapter {
    pub label: String,
    pub wired: bool,
    pub mac: String,
    pub broadcasts: Vec<String>,
    pub support: WakeSupport,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct WakeStatus {
    pub info: PcWakeInfo,
    pub adapters: Vec<WakeAdapter>,
}

impl WakeStatus {
    pub fn primary(&self) -> Option<&WakeAdapter> {
        self.adapters.first()
    }

    pub fn state_str(&self) -> &'static str {
        match self.primary() {
            Some(a) => a.support.as_str(),
            None => "none",
        }
    }
}

pub fn query_wake_status() -> WakeStatus {
    WakeStatus::default()
}

#[allow(dead_code)]
pub fn wake(_mac: &[u8]) -> Result<(), String> {
    Err("wake-on-lan is not supported on macOS".into())
}
