// SPDX-License-Identifier: GPL-3.0-or-later
//! Native macOS Shelf edge trigger and cursor glow monitor.
#![allow(unsafe_code)]

use std::ffi::CString;

unsafe extern "C" {
    fn shelf_edge_init(callback: extern "C" fn());
    fn shelf_edge_set_close_callback(callback: extern "C" fn());
    fn shelf_edge_set_enabled(enabled: bool);
    fn shelf_edge_set_ratio(ratio: f32);
    fn shelf_edge_set_shelf_open(is_open: bool);
    fn shelf_edge_style_shelf_window(title: *const std::os::raw::c_char);
    #[allow(dead_code)]
    fn shelf_edge_cleanup();
}

extern "C" fn on_shelf_edge_trigger() {
    crate::bridge::app::open_shelf_from_edge();
}

extern "C" fn on_shelf_edge_close() {
    crate::bridge::app::close_shelf_from_edge();
}

/// Initializes the native mouse monitor and glow window with current settings.
pub fn init() {
    unsafe {
        shelf_edge_init(on_shelf_edge_trigger);
        shelf_edge_set_close_callback(on_shelf_edge_close);
    }
    set_enabled(crate::settings::shelf_edge_trigger());
    set_size(&crate::settings::shelf_edge_size());
}

/// Toggles whether the edge trigger and cursor monitor are active.
pub fn set_enabled(enabled: bool) {
    unsafe {
        shelf_edge_set_enabled(enabled);
    }
}

/// Sets the edge trigger area size ratio based on configuration ("small", "medium", "large").
pub fn set_size(size: &str) {
    let ratio = match size.trim().to_lowercase().as_str() {
        "small" => 0.25f32,
        "large" => 0.60f32,
        _ => 0.40f32, // Medium default
    };
    unsafe {
        shelf_edge_set_ratio(ratio);
    }
}

/// Informs the edge monitor whether the Shelf window is currently open.
pub fn set_shelf_open(is_open: bool) {
    unsafe {
        shelf_edge_set_shelf_open(is_open);
    }
}

/// Applies native NSWindow collection behaviors and floating window level to the Shelf window.
pub fn style_shelf_window(title: &str) {
    if let Ok(c_str) = CString::new(title) {
        unsafe {
            shelf_edge_style_shelf_window(c_str.as_ptr());
        }
    }
}

/// Cleans up global/local monitors and destroys the glow window.
#[allow(dead_code)]
pub fn cleanup() {
    unsafe {
        shelf_edge_cleanup();
    }
}
