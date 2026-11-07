// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS elevated execution stubs.

use std::path::Path;

pub enum Error {
    #[allow(dead_code)]
    Declined,
    Other(String),
}

pub struct Process;

impl Process {
    pub fn exit_code(&self) -> Option<u32> {
        Some(0)
    }
}

pub fn start(_program: &Path, _params: &str) -> Result<Process, Error> {
    Err(Error::Other("elevated execution is not supported on macOS".into()))
}
