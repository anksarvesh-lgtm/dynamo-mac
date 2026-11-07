// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS login item / autostart via ServiceManagement (SMAppService).
#![allow(unsafe_code)]

use std::path::Path;

unsafe extern "C" {
    fn mac_login_item_get_status() -> i32;
    fn mac_login_item_set_enabled(
        enabled: bool,
        err_buf: *mut std::os::raw::c_char,
        err_buf_len: std::os::raw::c_int,
    ) -> bool;
    fn mac_login_item_open_settings();
}

#[allow(dead_code)]
pub const STATUS_NOT_REGISTERED: i32 = 0;
pub const STATUS_ENABLED: i32 = 1;
pub const STATUS_REQUIRES_APPROVAL: i32 = 2;
#[allow(dead_code)]
pub const STATUS_NOT_FOUND: i32 = 3;

pub fn status() -> i32 {
    unsafe { mac_login_item_get_status() }
}

pub fn is_enabled() -> bool {
    status() == STATUS_ENABLED
}

pub fn is_installed(_exe: &Path) -> bool {
    is_enabled()
}

pub fn set_enabled(enabled: bool) -> Result<(), String> {
    let mut err_buf = [0i8; 256];
    let ok = unsafe { mac_login_item_set_enabled(enabled, err_buf.as_mut_ptr(), 256) };
    if ok {
        Ok(())
    } else {
        let err_str = unsafe { std::ffi::CStr::from_ptr(err_buf.as_ptr()).to_string_lossy().into_owned() };
        if err_str.is_empty() {
            Err("failed to update login item registration".to_string())
        } else {
            Err(err_str)
        }
    }
}

pub fn set(enabled: bool, _exe: &Path) -> Result<(), String> {
    set_enabled(enabled)
}

pub fn open_settings() {
    unsafe {
        mac_login_item_open_settings();
    }
}
