// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS desktop shortcut and send-to stubs.

use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Shortcut {
    pub target: PathBuf,
    pub arguments: String,
    pub description: String,
}

pub fn send_to_dir() -> Option<PathBuf> {
    None
}

pub fn recent_dir() -> Option<PathBuf> {
    None
}

pub fn arguments(path: &Path) -> Option<String> {
    let content = std::fs::read_to_string(path).ok()?;
    let mut lines = content.lines();
    let _target = lines.next()?;
    let arguments = lines.next()?;
    Some(arguments.to_string())
}

pub fn target(path: &Path) -> Option<PathBuf> {
    let content = std::fs::read_to_string(path).ok()?;
    let mut lines = content.lines();
    let target = lines.next()?;
    Some(PathBuf::from(target))
}

pub fn write(path: &Path, shortcut: &Shortcut) -> std::io::Result<()> {
    std::fs::write(
        path,
        format!("{}\n{}\n{}\n", shortcut.target.display(), shortcut.arguments, shortcut.description),
    )
}
