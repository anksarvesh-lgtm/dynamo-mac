// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS share target stubs.

use std::path::{Path, PathBuf};

pub const ARG: &str = "--share";

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SharedPayload {
    pub files: Vec<PathBuf>,
    pub url: Option<String>,
    pub text: Option<String>,
}

impl SharedPayload {
    pub fn is_empty(&self) -> bool {
        self.files.is_empty() && self.url.is_none() && self.text.is_none()
    }
}

fn is_share_url(s: &str) -> bool {
    let s = s.trim();
    if s.is_empty() || s.len() > 4096 || s.chars().any(char::is_whitespace) {
        return false;
    }
    let lower: String = s.chars().take(8).collect::<String>().to_ascii_lowercase();
    lower.starts_with("http://")
        || lower.starts_with("https://")
        || (lower.starts_with("geo:") && s.len() > 4)
}

fn looks_like_path(s: &str) -> bool {
    let bytes = s.as_bytes();
    Path::new(s).exists()
        || s.contains('\\')
        || s.contains('/')
        || (bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':')
}

/// Classifies `--share <target…>` CLI arguments into files, a link, or text.
pub fn parse_targets(targets: &[String]) -> SharedPayload {
    let mut payload = SharedPayload::default();
    let mut text_parts = Vec::new();
    for raw in targets {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        if payload.url.is_none() && is_share_url(trimmed) {
            payload.url = Some(trimmed.to_owned());
        } else if looks_like_path(trimmed) {
            payload.files.push(PathBuf::from(trimmed));
        } else {
            text_parts.push(trimmed.to_owned());
        }
    }
    if !text_parts.is_empty() {
        payload.text = Some(text_parts.join(" "));
    }
    payload
}

pub fn take_activated_share(_data_dir: &Path) -> Option<SharedPayload> {
    None
}
