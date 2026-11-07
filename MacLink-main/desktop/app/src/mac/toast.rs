// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS native notifications via NSUserNotificationCenter & AppKit.
#![allow(unsafe_code)]

use std::{
    ffi::{CStr, CString},
    path::PathBuf,
    sync::{Mutex, OnceLock},
};

#[allow(dead_code)] // Application User Model ID for system notifications
pub const AUMID: &str = "in.maclink.srv";
pub const CALL_ANSWER: &str = "answer";
pub const CALL_DECLINE: &str = "decline";
pub const CALL_END: &str = "end";

#[allow(dead_code)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ToastEvent {
    Opened { device: String, key: String },
    Action { device: String, key: String, action: String },
    Reply { device: String, key: String, action: String, text: String },
    Dismissed { device: String, key: String },
}

#[allow(dead_code)]
#[derive(Clone)]
pub struct Toast {
    pub device: String,
    pub key: String,
    pub title: String,
    pub body: String,
    pub attribution: String,
    pub icon: Option<PathBuf>,
    pub image: Option<PathBuf>,
    pub actions: Vec<(String, String)>,
    pub reply: Option<(String, String)>,
    pub silent: bool,
    pub progress: Option<Progress>,
    pub call: bool,
}

impl std::fmt::Debug for Toast {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Toast").field("device", &self.device).finish_non_exhaustive()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Progress {
    pub status: String,
    pub value: Option<f64>,
    pub label: String,
}

type OnEvent = Box<dyn Fn(ToastEvent) + Send + Sync>;
static ON_EVENT: OnceLock<Mutex<Option<OnEvent>>> = OnceLock::new();

unsafe extern "C" {
    fn mac_notification_start(
        app_icon_path: *const std::os::raw::c_char,
        callback: extern "C" fn(
            *const std::os::raw::c_char,
            *const std::os::raw::c_char,
            *const std::os::raw::c_char,
            *const std::os::raw::c_char,
            *const std::os::raw::c_char,
        ),
    );
    fn mac_notification_show(
        device: *const std::os::raw::c_char,
        key: *const std::os::raw::c_char,
        title: *const std::os::raw::c_char,
        subtitle: *const std::os::raw::c_char,
        body: *const std::os::raw::c_char,
        icon_path: *const std::os::raw::c_char,
        image_path: *const std::os::raw::c_char,
        silent: bool,
        has_reply: bool,
        reply_id: *const std::os::raw::c_char,
        reply_title: *const std::os::raw::c_char,
        action_count: std::os::raw::c_int,
        action_ids: *const *const std::os::raw::c_char,
        action_titles: *const *const std::os::raw::c_char,
    );
    fn mac_notification_update_progress(
        device: *const std::os::raw::c_char,
        key: *const std::os::raw::c_char,
        value: f64,
        status: *const std::os::raw::c_char,
    );
    fn mac_notification_remove(device: *const std::os::raw::c_char, key: *const std::os::raw::c_char);
    fn mac_notification_remove_device(device: *const std::os::raw::c_char);
    fn mac_notification_unregister();
}

extern "C" fn notification_callback(
    event_type: *const std::os::raw::c_char,
    device: *const std::os::raw::c_char,
    key: *const std::os::raw::c_char,
    action: *const std::os::raw::c_char,
    text: *const std::os::raw::c_char,
) {
    if event_type.is_null() || device.is_null() || key.is_null() {
        return;
    }
    let ev_str = unsafe { CStr::from_ptr(event_type).to_string_lossy() };
    let dev_str = unsafe { CStr::from_ptr(device).to_string_lossy().into_owned() };
    let key_str = unsafe { CStr::from_ptr(key).to_string_lossy().into_owned() };
    let act_str = if !action.is_null() {
        unsafe { CStr::from_ptr(action).to_string_lossy().into_owned() }
    } else {
        String::new()
    };
    let txt_str = if !text.is_null() {
        unsafe { CStr::from_ptr(text).to_string_lossy().into_owned() }
    } else {
        String::new()
    };

    let event = match ev_str.as_ref() {
        "opened" => ToastEvent::Opened { device: dev_str, key: key_str },
        "action" => ToastEvent::Action { device: dev_str, key: key_str, action: act_str },
        "reply" => ToastEvent::Reply { device: dev_str, key: key_str, action: act_str, text: txt_str },
        "dismissed" => ToastEvent::Dismissed { device: dev_str, key: key_str },
        _ => return,
    };

    if let Some(guard) = ON_EVENT.get().and_then(|m| m.lock().ok())
        && let Some(ref cb) = *guard
    {
        cb(event);
    }
}

pub fn enabled() -> bool {
    true
}

pub fn set_process_id() {}

pub fn unregister() {
    unsafe { mac_notification_unregister() };
}

pub fn start(icon: PathBuf, on_event: impl Fn(ToastEvent) + Send + Sync + 'static) {
    let _ = ON_EVENT.set(Mutex::new(Some(Box::new(on_event))));
    let icon_c = icon.to_str().and_then(|s| CString::new(s).ok());
    unsafe {
        mac_notification_start(
            icon_c.as_ref().map_or(std::ptr::null(), |s| s.as_ptr()),
            notification_callback,
        );
    }
}

pub fn show(toast: Toast) {
    let dev_c = CString::new(toast.device).unwrap_or_default();
    let key_c = CString::new(toast.key).unwrap_or_default();
    let title_c = CString::new(toast.title).unwrap_or_default();
    let sub_c = CString::new(toast.attribution).unwrap_or_default();
    let body_c = CString::new(toast.body).unwrap_or_default();
    let icon_c = toast.icon.and_then(|p| p.to_str().and_then(|s| CString::new(s).ok()));
    let img_c = toast.image.and_then(|p| p.to_str().and_then(|s| CString::new(s).ok()));

    let (has_reply, reply_id_c, reply_title_c) = match toast.reply {
        Some((id, title)) => {
            (true, CString::new(id).unwrap_or_default(), CString::new(title).unwrap_or_default())
        }
        None => (false, CString::default(), CString::default()),
    };

    let mut act_id_c: Vec<CString> = Vec::new();
    let mut act_title_c: Vec<CString> = Vec::new();
    for (id, title) in &toast.actions {
        if let (Ok(i), Ok(t)) = (CString::new(id.as_str()), CString::new(title.as_str())) {
            act_id_c.push(i);
            act_title_c.push(t);
        }
    }
    let act_id_ptrs: Vec<*const std::os::raw::c_char> = act_id_c.iter().map(|s| s.as_ptr()).collect();
    let act_title_ptrs: Vec<*const std::os::raw::c_char> = act_title_c.iter().map(|s| s.as_ptr()).collect();

    unsafe {
        mac_notification_show(
            dev_c.as_ptr(),
            key_c.as_ptr(),
            title_c.as_ptr(),
            sub_c.as_ptr(),
            body_c.as_ptr(),
            icon_c.as_ref().map_or(std::ptr::null(), |s| s.as_ptr()),
            img_c.as_ref().map_or(std::ptr::null(), |s| s.as_ptr()),
            toast.silent,
            has_reply,
            reply_id_c.as_ptr(),
            reply_title_c.as_ptr(),
            act_id_ptrs.len() as std::os::raw::c_int,
            act_id_ptrs.as_ptr(),
            act_title_ptrs.as_ptr(),
        );
    }
}

pub fn update_progress(device: &str, key: &str, progress: Progress) {
    if let (Ok(dev_c), Ok(key_c), Ok(status_c)) =
        (CString::new(device), CString::new(key), CString::new(progress.status))
    {
        unsafe {
            mac_notification_update_progress(
                dev_c.as_ptr(),
                key_c.as_ptr(),
                progress.value.unwrap_or(0.0),
                status_c.as_ptr(),
            );
        }
    }
}

pub fn remove(device: &str, key: &str) {
    if let (Ok(dev_c), Ok(key_c)) = (CString::new(device), CString::new(key)) {
        unsafe { mac_notification_remove(dev_c.as_ptr(), key_c.as_ptr()) };
    }
}

pub fn remove_device(device: &str) {
    if let Ok(dev_c) = CString::new(device) {
        unsafe { mac_notification_remove_device(dev_c.as_ptr()) };
    }
}
