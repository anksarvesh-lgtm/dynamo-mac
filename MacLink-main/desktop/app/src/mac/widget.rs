// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS widget stubs.

use std::{path::Path, process::ExitCode};

pub const ARG: &str = "--widget-provider";

pub fn write_state_snapshot(_dir: &Path) {}

pub fn run_provider(_data_dir: &Path) -> ExitCode {
    ExitCode::SUCCESS
}
