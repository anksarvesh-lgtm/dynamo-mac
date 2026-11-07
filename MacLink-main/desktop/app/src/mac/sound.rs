// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS sound ringing ("find my PC" from phone).

use std::{
    sync::atomic::{AtomicU32, AtomicU64, Ordering},
    time::Duration,
};

const MAX_RING: Duration = Duration::from_secs(60);
static GENERATION: AtomicU64 = AtomicU64::new(0);
static CURRENT_PID: AtomicU32 = AtomicU32::new(0);

pub fn start_ringing() {
    let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    let _ = std::thread::Builder::new().name("mac-ring".into()).spawn(move || {
        let start = std::time::Instant::now();
        while start.elapsed() < MAX_RING && GENERATION.load(Ordering::SeqCst) == generation {
            if let Ok(mut child) =
                std::process::Command::new("afplay").arg("/System/Library/Sounds/Ping.aiff").spawn()
            {
                CURRENT_PID.store(child.id(), Ordering::SeqCst);
                let _ = child.wait();
                CURRENT_PID.store(0, Ordering::SeqCst);
            }
            std::thread::sleep(Duration::from_millis(600));
        }
    });
}

pub fn stop_ringing() {
    GENERATION.fetch_add(1, Ordering::SeqCst);
    let pid = CURRENT_PID.swap(0, Ordering::SeqCst);
    if pid != 0 {
        let _ = std::process::Command::new("kill").arg("-9").arg(pid.to_string()).output();
    }
}
