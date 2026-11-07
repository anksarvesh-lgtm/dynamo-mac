// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS status bar / tray integration using native NSStatusItem.
#![allow(unsafe_code)]

use std::{
    ffi::CString,
    sync::{Mutex, OnceLock},
};

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrayEvent {
    Open,
    CommandPalette,
    Shelf,
    TakePhoto,
    ScanDocument,
    FindPhone,
    OpenLinkOnPhone,
    Quit,
    Resumed,
    AppearanceChanged,
}

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct MenuLabels {
    pub open: String,
    pub command_palette: String,
    pub shelf: String,
    pub take_photo: String,
    pub scan_document: String,
    pub find_phone: String,
    pub open_link: String,
    pub quit: String,
}

unsafe extern "C" {
    fn mac_lifecycle_init(on_activate: extern "C" fn(), on_quit: extern "C" fn(), on_wake: extern "C" fn());
    fn mac_lifecycle_cleanup();
    fn mac_was_launched_as_login_item() -> bool;
    fn mac_status_item_init(
        on_open: extern "C" fn(),
        on_shelf: extern "C" fn(),
        on_find_phone: extern "C" fn(),
        on_toggle_login: extern "C" fn(),
        on_quit: extern "C" fn(),
    );
    fn mac_status_item_update(
        status_line: *const std::os::raw::c_char,
        phone_connected: bool,
        shelf_available: bool,
        find_phone_available: bool,
    );
    fn mac_set_phone_activity(connected: bool);
}

extern "C" fn on_mac_activate() {
    crate::bridge::app::request_activation();
}

extern "C" fn on_mac_quit() {
    crate::bridge::app::request_quit();
}

extern "C" fn on_mac_wake() {
    tracing::info!("system wake notification; reconnecting");
    if let Some(node) = crate::core_host::node() {
        crate::core_host::spawn(async move { node.network_changed().await });
    }
}

pub fn init_lifecycle() {
    unsafe {
        mac_lifecycle_init(on_mac_activate, on_mac_quit, on_mac_wake);
    }
}

pub fn cleanup_lifecycle() {
    unsafe {
        mac_lifecycle_cleanup();
    }
}

pub fn was_launched_as_login_item() -> bool {
    unsafe { mac_was_launched_as_login_item() }
}

type TrayHandler = Box<dyn Fn(TrayEvent) + Send + Sync + 'static>;
static TRAY_HANDLER: OnceLock<Mutex<Option<TrayHandler>>> = OnceLock::new();
static FIND_PHONE_ENABLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

extern "C" fn tray_cb_open() {
    if let Some(guard) = TRAY_HANDLER.get().and_then(|m| m.lock().ok())
        && let Some(ref cb) = *guard
    {
        cb(TrayEvent::Open);
    }
}

extern "C" fn tray_cb_shelf() {
    if let Some(guard) = TRAY_HANDLER.get().and_then(|m| m.lock().ok())
        && let Some(ref cb) = *guard
    {
        cb(TrayEvent::Shelf);
    }
}

extern "C" fn tray_cb_find_phone() {
    if let Some(guard) = TRAY_HANDLER.get().and_then(|m| m.lock().ok())
        && let Some(ref cb) = *guard
    {
        cb(TrayEvent::FindPhone);
    }
}

extern "C" fn tray_cb_toggle_login() {
    let current_status = crate::mac::autostart::status();
    if current_status == crate::mac::autostart::STATUS_ENABLED {
        let _ = crate::mac::autostart::set_enabled(false);
    } else if current_status == crate::mac::autostart::STATUS_REQUIRES_APPROVAL {
        crate::mac::autostart::open_settings();
    } else {
        let _ = crate::mac::autostart::set_enabled(true);
    }
}

extern "C" fn tray_cb_quit() {
    if let Some(guard) = TRAY_HANDLER.get().and_then(|m| m.lock().ok())
        && let Some(ref cb) = *guard
    {
        cb(TrayEvent::Quit);
    }
}

pub struct Tray;

impl Tray {
    pub fn create(
        _tooltip: &str,
        _labels: MenuLabels,
        handler: impl Fn(TrayEvent) + Send + Sync + 'static,
    ) -> Result<Tray, String> {
        let _ = TRAY_HANDLER.set(Mutex::new(Some(Box::new(handler))));
        unsafe {
            mac_status_item_init(
                tray_cb_open,
                tray_cb_shelf,
                tray_cb_find_phone,
                tray_cb_toggle_login,
                tray_cb_quit,
            );
        }
        Ok(Tray)
    }

    pub fn set_tooltip(&self, text: &str) {
        let connected = text.contains("connected");
        let line = if connected { text.replace("MacLink · ", "") } else { "No phone connected".to_string() };
        let c_line = CString::new(line).unwrap_or_default();
        let find_phone = FIND_PHONE_ENABLED.load(std::sync::atomic::Ordering::Relaxed) && connected;
        unsafe {
            mac_status_item_update(c_line.as_ptr(), connected, true, find_phone);
            mac_set_phone_activity(connected);
        }
    }

    pub fn set_find_phone_enabled(&self, enabled: bool) {
        FIND_PHONE_ENABLED.store(enabled, std::sync::atomic::Ordering::Relaxed);
    }
}

pub fn update_hotkeys(_photo_spec: &str, _scan_spec: &str, _palette_spec: &str, _shelf_spec: &str) {}

#[allow(dead_code)]
pub fn record_foreground_window() {}

pub fn apply_no_activate_style_by_title(title: &str) {
    crate::mac::shelf_edge::style_shelf_window(title);
}

#[allow(dead_code)] // Multiplatform tray window focus
pub fn focus_window(_hwnd: isize) -> bool {
    true
}

#[allow(dead_code)] // Multiplatform tray window state
pub fn is_window_alive_and_visible(_hwnd: isize) -> bool {
    false
}

#[allow(dead_code)] // Multiplatform target window query
pub fn snapshot_target_window() -> Option<(isize, String)> {
    None
}

#[allow(dead_code)] // Multiplatform clipboard paste target
pub fn send_paste_fallback_if_not_foreground(_hwnd: isize) {}

#[allow(dead_code)]
pub fn parse_hotkey(_spec: &str) -> Option<(u32, u32)> {
    None
}
