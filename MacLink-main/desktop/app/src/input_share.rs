// SPDX-License-Identifier: GPL-3.0-or-later
//! Which paired device the PC is controlling (a mirror window the mouse is in,
//! or a remote control session), and the clipboard following along: with
//! `flow_follow_clipboard` on, the PC's clipboard goes to the device when
//! control moves to it. Moving the cursor across a screen edge onto the phone
//! (`ScreenEdge`) is planned, not built.

use std::sync::{
    Mutex, OnceLock,
    atomic::{AtomicU64, Ordering},
};

use maclink_core::DeviceId;

use crate::{core_host, settings};

/// Screen edge where a paired phone or tablet is positioned relative to the PC monitor.
#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScreenEdge {
    Left,
    Right,
    Top,
    Bottom,
}

static ACTIVE_REMOTE: OnceLock<Mutex<Option<DeviceId>>> = OnceLock::new();
static CLIPBOARD_SYNC_COUNT: AtomicU64 = AtomicU64::new(0);

fn active_slot() -> &'static Mutex<Option<DeviceId>> {
    ACTIVE_REMOTE.get_or_init(|| Mutex::new(None))
}

/// Returns the paired device currently receiving Flow cursor/keyboard input, if any.
#[allow(dead_code)]
pub fn active_remote() -> Option<DeviceId> {
    *active_slot().lock().unwrap_or_else(|e| e.into_inner())
}

/// Returns how many times Flow edge transitions have triggered a clipboard push.
#[allow(dead_code)]
pub fn clipboard_sync_count() -> u64 {
    CLIPBOARD_SYNC_COUNT.load(Ordering::SeqCst)
}

/// Transitions Flow cursor/keyboard focus from the PC to `peer`.
/// When `flow_follow_clipboard` is enabled (default `true`), pushes the current
/// PC clipboard to `peer`. Returns `true` if clipboard sync was triggered.
pub fn enter_remote(peer: DeviceId) -> bool {
    enter_remote_with_setting(peer, settings::flow_follow_clipboard())
}

/// Transitions Flow cursor/keyboard focus to `peer` with an explicit
/// `follow_clipboard` flag. Returns `true` if clipboard sync was triggered.
pub fn enter_remote_with_setting(peer: DeviceId, follow_clipboard: bool) -> bool {
    let changed = {
        let mut guard = active_slot().lock().unwrap_or_else(|e| e.into_inner());
        let is_new = *guard != Some(peer);
        *guard = Some(peer);
        is_new
    };
    if changed && follow_clipboard {
        CLIPBOARD_SYNC_COUNT.fetch_add(1, Ordering::SeqCst);
        if core_host::node().is_some() {
            crate::mirror::sync_clipboard_for_device(peer);
        }
        true
    } else {
        false
    }
}

/// Transitions Flow cursor/keyboard focus back from the remote phone/tablet to the PC.
pub fn leave_remote() -> Option<DeviceId> {
    active_slot().lock().unwrap_or_else(|e| e.into_inner()).take()
}

/// Checks whether cursor coordinates `(x, y)` have reached the configured [`ScreenEdge`]
/// of monitor bounds `(left, top, right, bottom)`.
#[allow(dead_code)]
pub fn is_at_screen_edge(
    x: i32,
    y: i32,
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
    edge: ScreenEdge,
) -> bool {
    match edge {
        ScreenEdge::Left => x <= left,
        ScreenEdge::Right => x >= right - 1,
        ScreenEdge::Top => y <= top,
        ScreenEdge::Bottom => y >= bottom - 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn edge_transition_triggers_clipboard_sync_when_enabled() {
        let _ = leave_remote();
        assert_eq!(active_remote(), None);

        assert!(is_at_screen_edge(0, 500, 0, 0, 1920, 1080, ScreenEdge::Left));
        assert!(is_at_screen_edge(1919, 500, 0, 0, 1920, 1080, ScreenEdge::Right));
        assert!(is_at_screen_edge(500, 0, 0, 0, 1920, 1080, ScreenEdge::Top));
        assert!(is_at_screen_edge(500, 1079, 0, 0, 1920, 1080, ScreenEdge::Bottom));
        assert!(!is_at_screen_edge(500, 500, 0, 0, 1920, 1080, ScreenEdge::Right));

        let peer = DeviceId([0x42; 32]);
        let before = clipboard_sync_count();

        // Entering remote via enter_remote uses settings::flow_follow_clipboard() (default true).
        settings::set_flow_follow_clipboard(true);
        assert!(enter_remote(peer));
        assert_eq!(active_remote(), Some(peer));
        assert_eq!(clipboard_sync_count(), before + 1);

        // Re-entering the same active peer without leaving does not duplicate sync.
        assert!(!enter_remote_with_setting(peer, true));
        assert_eq!(clipboard_sync_count(), before + 1);

        // Leaving clears the active remote peer.
        assert_eq!(leave_remote(), Some(peer));
        assert_eq!(active_remote(), None);

        // Entering remote with flow_follow_clipboard = false does not trigger clipboard sync.
        assert!(!enter_remote_with_setting(peer, false));
        assert_eq!(active_remote(), Some(peer));
        assert_eq!(clipboard_sync_count(), before + 1);
        let _ = leave_remote();
    }
}
