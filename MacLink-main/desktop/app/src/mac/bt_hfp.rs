// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS Bluetooth HFP integration via MacLinkTelephony native Swift framework.
#![allow(unsafe_code, dead_code)]

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct HfpStatus {
    pub available: bool,
    pub connected: bool,
    pub device_name: String,
    pub detail: String,
}

unsafe extern "C" {
    fn maclink_calls_hfp_publish_sdp(rfcomm_channel: u8) -> bool;
    fn maclink_calls_hfp_unpublish_sdp();
    fn maclink_calls_hfp_connect(device_address: *const std::ffi::c_char) -> bool;
    fn maclink_calls_hfp_disconnect();
    fn maclink_calls_hfp_is_connected() -> bool;
    fn maclink_calls_hfp_is_sco_active() -> bool;
    fn maclink_calls_hfp_route_audio(to_mac: bool);
    fn maclink_calls_hfp_accept();
    fn maclink_calls_hfp_end();
    fn maclink_calls_hfp_dial(number: *const std::ffi::c_char) -> bool;
}

pub fn probe_status(phone_name: Option<&str>) -> HfpStatus {
    let connected = unsafe { maclink_calls_hfp_is_connected() };
    let sco_active = unsafe { maclink_calls_hfp_is_sco_active() };
    HfpStatus {
        available: true,
        connected,
        device_name: phone_name.unwrap_or("Phone").to_string(),
        detail: if sco_active {
            "Call audio routed to Mac".to_string()
        } else if connected {
            "Connected (Hands-Free)".to_string()
        } else {
            "Bluetooth ready".to_string()
        },
    }
}

pub fn connect_audio(phone_name: Option<&str>) -> Result<HfpStatus, String> {
    unsafe {
        maclink_calls_hfp_publish_sdp(6);
        maclink_calls_hfp_route_audio(true);
    }
    Ok(probe_status(phone_name))
}

pub fn disconnect_audio() {
    unsafe {
        maclink_calls_hfp_route_audio(false);
    }
}

pub fn open_bluetooth_settings() {
    let _ = std::process::Command::new("open")
        .arg("x-apple.systempreferences:com.apple.BluetoothSettings")
        .spawn();
}
