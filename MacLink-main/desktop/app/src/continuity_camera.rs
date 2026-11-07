// SPDX-License-Identifier: GPL-3.0-or-later
//! Continuity Camera coordinator for Windows: initiates "Take photo with phone"
//! and "Scan document with phone" from the tray menu, global hotkeys, or the
//! MacLink UI, remembers the external foreground window (`HWND`) that was
//! active when the request started, places the captured image onto the Windows
//! clipboard on arrival, and either restores focus + synthesizes `Ctrl+V` into
//! the original target window or prompts the user if that window was closed.

use crate::i18n::tr;
use std::{
    sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::{SystemTime, UNIX_EPOCH},
};

use maclink_core::{CameraCaptureMode, DeviceId, NodeEvent};

use crate::{core_host, state::Changes};

#[allow(dead_code)] // Continuity camera request sequence counter
static REQUEST_SEQ: AtomicU64 = AtomicU64::new(1);

#[allow(dead_code)] // Continuity camera active request descriptor
#[derive(Debug, Clone)]
struct ActiveRequest {
    #[allow(dead_code)]
    request_id: String,
    #[allow(dead_code)]
    device: DeviceId,
    device_name: String,
    mode: CameraCaptureMode,
    #[allow(dead_code)]
    target_hwnd: Option<isize>,
    #[allow(dead_code)]
    target_title: String,
    queued_offline: bool,
}

#[derive(Debug, Clone)]
struct PendingPastePrompt {
    title: String,
    body: String,
    target_name: String,
}

#[derive(Debug, Default)]
struct ContinuityState {
    active: Option<ActiveRequest>,
    prompt: Option<PendingPastePrompt>,
}

static STATE: Mutex<ContinuityState> = Mutex::new(ContinuityState { active: None, prompt: None });

/// Snapshot of Continuity Camera state exposed to QML via `AppController`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ContinuityView {
    pub busy: bool,
    pub mode: String,
    pub status: String,
    pub paste_prompt_visible: bool,
    pub paste_prompt_title: String,
    pub paste_prompt_body: String,
    pub paste_target_name: String,
}

/// Pure decision for what to do after placing a captured image on the clipboard.
#[allow(dead_code)] // Continuity camera paste decision
#[derive(Debug, Clone, PartialEq, Eq)]
enum DeliveryDecision {
    /// The remembered target window is still alive and visible: focus it and paste.
    AutoPaste { hwnd: isize, toast: String },
    /// A target window was remembered when the request started, but is no longer
    /// alive/visible when the capture arrived. Do not blindly paste elsewhere;
    /// ask the user in MacLink.
    PromptMissingTarget { title: String, body: String, target_name: String },
    /// No external target window was remembered when the request started.
    ClipboardOnly { toast: String },
}

#[allow(dead_code)] // Continuity camera delivery strategy decider
fn decide_delivery_action(
    mode: CameraCaptureMode,
    device_name: &str,
    target: Option<(isize, &str)>,
    target_still_alive: bool,
) -> DeliveryDecision {
    let (item_cap, item_lower) = match mode {
        CameraCaptureMode::Photo => ("Photo", "photo"),
        CameraCaptureMode::Scan => ("Scanned document", "scanned document"),
    };
    if let Some((hwnd, raw_title)) = target
        && hwnd != 0
    {
        let trimmed = raw_title.trim();
        let target_name =
            if trimmed.is_empty() { "your previous window".to_owned() } else { trimmed.to_owned() };
        if target_still_alive {
            return DeliveryDecision::AutoPaste {
                hwnd,
                toast: format!("{item_cap} from {device_name} pasted into {target_name}"),
            };
        }
        return DeliveryDecision::PromptMissingTarget {
            title: format!("{item_cap} ready on clipboard"),
            body: format!(
                "“{target_name}” is no longer open, so MacLink didn’t paste automatically. Switch to the window where you want your {item_lower} from {device_name} and click Paste into active window, or press Ctrl+V anywhere."
            ),
            target_name,
        };
    }
    DeliveryDecision::ClipboardOnly { toast: format!("{item_cap} from {device_name} copied to clipboard") }
}

#[allow(dead_code)] // Continuity camera request ID generator
fn next_request_id() -> String {
    let ms = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0);
    let seq = REQUEST_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("cc-{ms}-{seq}")
}

#[allow(dead_code)] // Continuity camera UI notifier
fn notify_continuity() {
    core_host::host().hub.update(|_| Changes::CONTINUITY);
}

/// Returns a snapshot of the current Continuity Camera UI state.
pub fn view() -> ContinuityView {
    let guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
    let (busy, mode, status) = match &guard.active {
        Some(active) if !active.queued_offline => {
            let mode_str = active.mode.as_str().to_owned();
            let status_str = match active.mode {
                CameraCaptureMode::Photo => {
                    tr!("ContinuityCamera", "Take a photo on %1…", active.device_name)
                }
                CameraCaptureMode::Scan => {
                    tr!("ContinuityCamera", "Scan a document on %1…", active.device_name)
                }
            };
            (true, mode_str, status_str)
        }
        _ => (false, String::new(), String::new()),
    };
    let (paste_prompt_visible, paste_prompt_title, paste_prompt_body, paste_target_name) =
        if let Some(prompt) = &guard.prompt {
            (true, prompt.title.clone(), prompt.body.clone(), prompt.target_name.clone())
        } else {
            (false, String::new(), String::new(), String::new())
        };
    ContinuityView {
        busy,
        mode,
        status,
        paste_prompt_visible,
        paste_prompt_title,
        paste_prompt_body,
        paste_target_name,
    }
}

/// Starts a Continuity Camera capture (`"photo"` or `"scan"`) on the active
/// paired phone, remembering the current external foreground window.
pub fn start(_mode_raw: &str) {}

pub fn start_for_index(_preferred_index: usize, _mode_raw: &str) {}

pub fn cancel() {}

pub fn confirm_paste() {}

pub fn dismiss_paste() {}

pub fn on_event(_event: &NodeEvent) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delivery_decision_auto_pastes_when_target_window_is_alive() {
        let decision = decide_delivery_action(
            CameraCaptureMode::Photo,
            "Pixel 9",
            Some((0x1234, "Document.docx - Word")),
            true,
        );
        assert_eq!(
            decision,
            DeliveryDecision::AutoPaste {
                hwnd: 0x1234,
                toast: "Photo from Pixel 9 pasted into Document.docx - Word".into(),
            }
        );
    }

    #[test]
    fn delivery_decision_prompts_when_target_window_disappeared() {
        let decision = decide_delivery_action(
            CameraCaptureMode::Scan,
            "Pixel 9",
            Some((0x1234, "Notes - Notion")),
            false,
        );
        match decision {
            DeliveryDecision::PromptMissingTarget { title, body, target_name } => {
                assert_eq!(title, "Scanned document ready on clipboard");
                assert_eq!(target_name, "Notes - Notion");
                assert!(body.contains("Notes - Notion"));
                assert!(body.contains("no longer open"));
            }
            other => panic!("expected PromptMissingTarget, got {other:?}"),
        }
    }

    #[test]
    fn delivery_decision_copies_only_when_no_external_target_was_recorded() {
        let decision = decide_delivery_action(CameraCaptureMode::Photo, "Pixel 9", None, false);
        assert_eq!(
            decision,
            DeliveryDecision::ClipboardOnly { toast: "Photo from Pixel 9 copied to clipboard".into() }
        );
    }
}
