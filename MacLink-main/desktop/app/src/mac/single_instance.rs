// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS single-instance lock and IPC using Unix domain sockets.

use std::{
    io::{Read, Write},
    os::unix::net::{UnixListener, UnixStream},
    path::{Path, PathBuf},
    sync::Mutex,
};

#[derive(Debug)]
pub struct PrimaryInstance {
    listener: Mutex<Option<UnixListener>>,
    sock_path: PathBuf,
}

#[derive(Debug)]
pub enum Instance {
    Primary(PrimaryInstance),
    Secondary,
}

pub fn acquire(data_dir: &Path) -> Result<Instance, String> {
    let _ = std::fs::create_dir_all(data_dir);
    let sock_path = data_dir.join("maclink.sock");

    match UnixListener::bind(&sock_path) {
        Ok(listener) => {
            Ok(Instance::Primary(PrimaryInstance { listener: Mutex::new(Some(listener)), sock_path }))
        }
        Err(_) => {
            // Check if another instance is actively responding
            if UnixStream::connect(&sock_path).is_ok() {
                return Ok(Instance::Secondary);
            }
            // Stale socket from previous crash or exit
            let _ = std::fs::remove_file(&sock_path);
            match UnixListener::bind(&sock_path) {
                Ok(listener) => {
                    Ok(Instance::Primary(PrimaryInstance { listener: Mutex::new(Some(listener)), sock_path }))
                }
                Err(e) => Err(format!("can't bind single-instance socket: {e}")),
            }
        }
    }
}

pub fn wake(data_dir: &Path) {
    let sock_path = data_dir.join("maclink.sock");
    if let Ok(mut stream) = UnixStream::connect(&sock_path) {
        let _ = stream.write_all(b"wake\n");
    }
}

impl PrimaryInstance {
    pub fn watch(&'static self, on_activate: impl Fn() + Send + 'static) {
        let listener = match self.listener.lock() {
            Ok(mut guard) => guard.take(),
            Err(_) => None,
        };
        let Some(listener) = listener else {
            return;
        };

        std::thread::Builder::new()
            .name("single-instance".into())
            .spawn(move || {
                for mut s in listener.incoming().flatten() {
                    let mut buf = [0u8; 16];
                    let _ = s.read(&mut buf);
                    on_activate();
                }
            })
            .ok();
    }
}

impl Drop for PrimaryInstance {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.sock_path);
    }
}
