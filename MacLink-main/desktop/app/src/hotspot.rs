// SPDX-License-Identifier: GPL-3.0-or-later
//! Instant Hotspot, the PC's half: after the phone turns its hotspot on (Home's
//! Instant Hotspot, through Elevated), the PC joins it, using the Wi-Fi network
//! the user picked for that phone in Settings. That's a network Windows has
//! saved from when the user joined the hotspot themselves once, so MacLink
//! never handles its password.

use crate::i18n::tr;
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::Mutex,
    time::{Duration, Instant},
};

use maclink_core::DeviceId;

use crate::{bridge::app::show_message, core_host, state::Changes, win::wifi::Reach};

/// How long the phone's hotspot has to show up.
const APPEAR_WITHIN: Duration = Duration::from_secs(45);
/// How long Windows has to finish joining it.
const JOIN_WITHIN: Duration = Duration::from_secs(20);
const LOOK_EVERY: Duration = Duration::from_secs(2);

static NETWORKS: Mutex<Option<HashMap<DeviceId, String>>> = Mutex::new(None);
/// Phones whose hotspot the PC is joining right now.
static JOINING: Mutex<Vec<DeviceId>> = Mutex::new(Vec::new());

fn file() -> PathBuf {
    core_host::host().data_dir.join("hotspot.json")
}

fn load(path: &Path) -> HashMap<DeviceId, String> {
    std::fs::read(path)
        .ok()
        .and_then(|b| serde_json::from_slice::<HashMap<String, String>>(&b).ok())
        .map(|m| m.into_iter().filter_map(|(k, v)| Some((k.parse().ok()?, v))).collect())
        .unwrap_or_default()
}

fn save(path: &Path, networks: &HashMap<DeviceId, String>) -> std::io::Result<()> {
    let plain: HashMap<String, &String> = networks.iter().map(|(k, v)| (k.to_string(), v)).collect();
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_vec(&plain).map_err(std::io::Error::other)?)?;
    std::fs::rename(&tmp, path)
}

fn with_networks<T>(f: impl FnOnce(&mut HashMap<DeviceId, String>) -> T) -> T {
    let mut guard = NETWORKS.lock().unwrap_or_else(|e| e.into_inner());
    let networks = guard.get_or_insert_with(|| load(&file()));
    f(networks)
}

/// The Wi-Fi network the PC joins when `device` turns its hotspot on, if one is set.
pub fn network_for(device: DeviceId) -> Option<String> {
    with_networks(|n| n.get(&device).cloned())
}

/// Sets (or, with `None`, clears) the network for `device`'s hotspot.
pub fn set_network(device: DeviceId, network: Option<String>) {
    let snapshot = with_networks(|n| {
        match network.filter(|s| !s.trim().is_empty()) {
            Some(name) => n.insert(device, name),
            None => n.remove(&device),
        };
        n.clone()
    });
    if let Err(e) = save(&file(), &snapshot) {
        tracing::warn!(error = %e, "can't save the hotspot networks");
    }
    core_host::host().hub.changed(Changes::DEVICES);
}

/// What the PC needs from Wi-Fi, so joining can be tested without changing networks.
pub(crate) trait Wifi {
    fn scan(&self);
    fn reach(&self, profile: &str) -> Reach;
    fn connect(&self, profile: &str) -> Result<(), String>;
    fn wait(&self, d: Duration);
}

struct Windows;

impl Wifi for Windows {
    fn scan(&self) {
        crate::win::wifi::scan();
    }
    fn reach(&self, profile: &str) -> Reach {
        crate::win::wifi::reach(profile)
    }
    fn connect(&self, profile: &str) -> Result<(), String> {
        crate::win::wifi::connect(profile)
    }
    fn wait(&self, d: Duration) {
        std::thread::sleep(d);
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum JoinOutcome {
    Already,
    Joined,
    /// The hotspot never showed up in time.
    NotFound,
    Failed(String),
}

/// Waits for `profile` to come into range, joins it, and waits for Windows to finish.
pub(crate) fn join(
    wifi: &impl Wifi,
    profile: &str,
    appear_within: Duration,
    join_within: Duration,
) -> JoinOutcome {
    if wifi.reach(profile) == Reach::Connected {
        return JoinOutcome::Already;
    }
    let started = Instant::now();
    let mut waited = Duration::ZERO;
    loop {
        wifi.scan();
        wifi.wait(LOOK_EVERY);
        waited += LOOK_EVERY;
        match wifi.reach(profile) {
            Reach::Connected => return JoinOutcome::Joined,
            Reach::InRange => break,
            Reach::NotInRange if waited >= appear_within || started.elapsed() > appear_within * 2 => {
                return JoinOutcome::NotFound;
            }
            Reach::NotInRange => {}
        }
    }
    if let Err(e) = wifi.connect(profile) {
        return JoinOutcome::Failed(e);
    }
    let mut joining = Duration::ZERO;
    while joining < join_within {
        wifi.wait(LOOK_EVERY);
        joining += LOOK_EVERY;
        if wifi.reach(profile) == Reach::Connected {
            return JoinOutcome::Joined;
        }
    }
    JoinOutcome::Failed("Windows didn't finish joining".into())
}

/// The phone just turned its hotspot on: join it, if a network is set for it.
pub fn hotspot_turned_on(device: DeviceId) {
    let Some(profile) = network_for(device) else { return };
    {
        let mut joining = JOINING.lock().unwrap_or_else(|e| e.into_inner());
        if joining.contains(&device) {
            return;
        }
        joining.push(device);
    }
    let name = core_host::host().hub.read(|s| s.name_of(&device)).unwrap_or_else(|| "your phone".into());
    std::thread::Builder::new()
        .name("hotspot-join".into())
        .spawn(move || {
            let outcome = join(&Windows, &profile, APPEAR_WITHIN, JOIN_WITHIN);
            JOINING.lock().unwrap_or_else(|e| e.into_inner()).retain(|d| *d != device);
            match outcome {
                JoinOutcome::Already => {}
                JoinOutcome::Joined => show_message(tr!("Hotspot", "Connected to %1's hotspot.", name)),
                JoinOutcome::NotFound => show_message(tr!(
                    "Hotspot",
                    "%1's hotspot didn't show up. Check that it's on, then pick %2 in Windows' Wi-Fi list.",
                    name,
                    profile
                )),
                JoinOutcome::Failed(e) => {
                    tracing::warn!(error = e, "couldn't join the phone's hotspot");
                    show_message(tr!(
                        "Hotspot",
                        "Couldn't join %1's hotspot. Pick %2 in Windows' Wi-Fi list.",
                        name,
                        profile
                    ));
                }
            }
        })
        .ok();
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::{Cell, RefCell};

    /// Wi-Fi that shows the hotspot after `appears` looks and joins it on connect.
    struct Fake {
        appears_after: u32,
        looks: Cell<u32>,
        connected: Cell<bool>,
        connect_works: bool,
        log: RefCell<Vec<&'static str>>,
    }

    impl Fake {
        fn new(appears_after: u32, connect_works: bool) -> Fake {
            Fake {
                appears_after,
                looks: Cell::new(0),
                connected: Cell::new(false),
                connect_works,
                log: RefCell::new(Vec::new()),
            }
        }
    }

    impl Wifi for Fake {
        fn scan(&self) {
            self.looks.set(self.looks.get() + 1);
        }
        fn reach(&self, _profile: &str) -> Reach {
            if self.connected.get() {
                Reach::Connected
            } else if self.looks.get() >= self.appears_after {
                Reach::InRange
            } else {
                Reach::NotInRange
            }
        }
        fn connect(&self, _profile: &str) -> Result<(), String> {
            self.log.borrow_mut().push("connect");
            if self.connect_works {
                self.connected.set(true);
                Ok(())
            } else {
                Err("refused".into())
            }
        }
        fn wait(&self, _d: Duration) {}
    }

    const APPEAR: Duration = Duration::from_secs(10);
    const JOIN: Duration = Duration::from_secs(6);

    #[test]
    fn joins_once_the_hotspot_shows_up() {
        let wifi = Fake::new(3, true);
        assert_eq!(join(&wifi, "Pixel", APPEAR, JOIN), JoinOutcome::Joined);
        assert_eq!(*wifi.log.borrow(), ["connect"], "connects exactly once");
        assert_eq!(wifi.looks.get(), 3);
    }

    #[test]
    fn already_on_it_does_nothing() {
        let wifi = Fake::new(0, true);
        wifi.connected.set(true);
        assert_eq!(join(&wifi, "Pixel", APPEAR, JOIN), JoinOutcome::Already);
        assert!(wifi.log.borrow().is_empty());
    }

    #[test]
    fn gives_up_when_it_never_shows_up_without_connecting() {
        let wifi = Fake::new(u32::MAX, true);
        assert_eq!(join(&wifi, "Pixel", APPEAR, JOIN), JoinOutcome::NotFound);
        assert!(wifi.log.borrow().is_empty(), "never connects to a network that isn't there");
        assert_eq!(wifi.looks.get(), 5, "looked for 10 s, every 2 s");
    }

    #[test]
    fn says_so_when_windows_refuses() {
        assert!(matches!(join(&Fake::new(1, false), "Pixel", APPEAR, JOIN), JoinOutcome::Failed(_)));
    }

    #[test]
    fn networks_round_trip_by_phone() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("hotspot.json");
        let mut networks = HashMap::new();
        networks.insert(DeviceId([3; 32]), "Pixel 9 hotspot".to_owned());
        save(&path, &networks).unwrap();
        assert_eq!(load(&path), networks);
        assert!(load(&dir.path().join("missing.json")).is_empty());
    }
}
