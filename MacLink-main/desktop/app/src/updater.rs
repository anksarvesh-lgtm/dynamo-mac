// SPDX-License-Identifier: GPL-3.0-or-later
//! Updates for an installed copy: the latest GitHub release is checked at
//! startup and once a day (unless turned off). A newer one is downloaded,
//! checked against the release's SHA-256 sums, and installed silently.
//!
//! The app lives in Program Files, so installing needs administrator rights.
//! The installer registers a scheduled task, [`TASK`], that runs this program
//! as SYSTEM with [`SERVICE_ARG`]: it takes nothing from the user, fetches
//! the latest release itself, and only ever installs a newer published one.
//! Any signed-in user may start it, so updates need no prompt. With
//! automatic updates on, the app starts it at a quiet moment (nobody at the
//! PC, nothing being mirrored, sent or called); "Update" starts it right
//! away. Without the task (a copy installed before it existed), "Update"
//! runs the installer with the usual administrator prompt.
//!
//! The app downloads the installer first, as the user, showing progress and
//! resuming after a dropped connection ([`stage`]), into a shared folder.
//! The task takes that file only when it matches the release's sums, which
//! it fetches itself, and copies it somewhere only SYSTEM can write before
//! checking and running it; otherwise it downloads the installer itself.
//!
//! The installer replaces the running app, so once the download is ready the
//! app starts a small hidden relauncher and quits; the relauncher opens the
//! new version once the installer is done, or the old one again if the
//! update didn't go through.

use crate::i18n::tr;
#[cfg(windows)]
use std::os::windows::process::CommandExt;
use std::{
    path::{Path, PathBuf},
    process::ExitCode,
    sync::{
        Mutex, MutexGuard,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

use serde::Deserialize;
use sha2::{Digest, Sha256};

#[cfg(target_os = "linux")]
use crate::linux::{http, toast};
#[cfg(target_os = "macos")]
use crate::mac::{http, toast};
#[cfg(windows)]
use crate::win::autostart;
#[cfg(windows)]
use crate::win::{http, toast};
use crate::{core_host, state::Changes};

const LATEST: &str = "https://api.github.com/repos/anksarvesh-lgtm/MacLink/releases/latest";
const FIRST_CHECK: Duration = Duration::from_millis(1000);
const EVERY: Duration = Duration::from_secs(24 * 3600);
const MAX_INSTALLER: u64 = 400 * 1024 * 1024;
/// The toast "device" for update notices.
pub const TOAST_GROUP: &str = "update";
pub const ACTION_UPDATE: &str = "update";

/// A newer release.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Update {
    pub version: String,
    pub notes_url: String,
    installer_url: String,
    installer_name: String,
    sums_url: String,
}

/// The scheduled task the installer registers (see the module docs).
#[cfg(windows)]
pub const TASK: &str = "MacLink Update";
/// What the task runs: `maclink-desktop.exe --update-service`.
pub const SERVICE_ARG: &str = "--update-service";
/// How long nobody may have used the PC before an update installs by itself.
#[allow(dead_code)] // Auto-update idle quiet interval
const QUIET_FOR: Duration = Duration::from_secs(10 * 60);
/// While an update waits for a quiet moment, how often to look for one.
const LOOK_FOR_QUIET: Duration = Duration::from_secs(5 * 60);
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
#[cfg(windows)]
const DETACHED_PROCESS: u32 = 0x0000_0008;

static AUTO: AtomicBool = AtomicBool::new(true);
static AUTO_INSTALL: AtomicBool = AtomicBool::new(true);
static CHECKING: AtomicBool = AtomicBool::new(false);
static INSTALL_LAUNCHED: AtomicBool = AtomicBool::new(false);
static FOUND: Mutex<Option<Update>> = Mutex::new(None);

fn found() -> MutexGuard<'static, Option<Update>> {
    FOUND.lock().unwrap_or_else(|e| e.into_inner())
}

/// The update found, if any.
pub fn available() -> Option<Update> {
    found().clone()
}

pub fn set_auto(on: bool) {
    AUTO.store(on, Ordering::Relaxed);
}

/// Whether a newer release installs by itself at a quiet moment.
pub fn set_auto_install(on: bool) {
    AUTO_INSTALL.store(on, Ordering::Relaxed);
}

/// Whether this copy updates itself.
pub fn can_update() -> bool {
    true
}

/// Checks soon after startup, then daily, while automatic checks are on.
pub fn start() {
    if !can_update() {
        return;
    }
    let spawned = std::thread::Builder::new().name("updates".into()).spawn(|| {
        std::thread::sleep(FIRST_CHECK);
        loop {
            if AUTO.load(Ordering::Relaxed) {
                check_now(false);
            }
            // Daily; while an update waits to install itself, look for a quiet moment.
            let next_check = std::time::Instant::now() + EVERY;
            while let Some(left) = next_check.checked_duration_since(std::time::Instant::now()) {
                if AUTO.load(Ordering::Relaxed)
                    && AUTO_INSTALL.load(Ordering::Relaxed)
                    && !INSTALL_LAUNCHED.load(Ordering::Relaxed)
                    && available().is_some()
                    && quiet()
                {
                    tracing::info!("installing the update at a quiet moment");
                    match install(|_, _| {}) {
                        Ok(()) => {
                            INSTALL_LAUNCHED.store(true, Ordering::Relaxed);
                        }
                        Err(e) => {
                            tracing::warn!(error = %e, "the automatic update couldn't be installed yet");
                        }
                    }
                }
                std::thread::sleep(left.min(LOOK_FOR_QUIET));
            }
        }
    });
    if let Err(e) = spawned {
        tracing::warn!(error = %e, "won't check for updates");
    }
}

/// Checks now (blocking). `told`: the user asked, so say "up to date" too.
/// Returns what to tell the user.
pub fn check_now(told: bool) -> Option<String> {
    if CHECKING.swap(true, Ordering::AcqRel) {
        return None;
    }
    let result = latest();
    CHECKING.store(false, Ordering::Release);
    match result {
        Ok(Some(update)) => {
            let new = found().as_ref() != Some(&update);
            *found() = Some(update.clone());
            core_host::host().hub.update(|_| Changes::UPDATE);
            if new {
                INSTALL_LAUNCHED.store(false, Ordering::Relaxed);
                announce(&update);
            }
            if AUTO_INSTALL.load(Ordering::Relaxed) {
                let to_stage = update.clone();
                let _ = std::thread::Builder::new().name("update-autodownload".into()).spawn(move || {
                    let _ = stage(&to_stage, |_, _| {});
                });
            }
            Some(tr!("Updater", "MacLink %1 is available.", update.version))
        }
        Ok(None) => told.then(|| tr!("Updater", "MacLink is up to date.")),
        Err(e) => {
            tracing::info!(error = %e, "couldn't check for updates");
            told.then(|| tr!("Updater", "Couldn't check for updates. Check your internet connection."))
        }
    }
}

fn announce(update: &Update) {
    toast::show(toast::Toast {
        device: TOAST_GROUP.into(),
        key: update.version.clone(),
        title: tr!("Updater", "MacLink %1 is available", update.version),
        body: tr!("Updater", "Update now, or later from Settings."),
        attribution: "MacLink".into(),
        icon: None,
        image: None,
        actions: vec![(ACTION_UPDATE.into(), "Update".into())],
        reply: None,
        silent: true,
        progress: None,
        call: false,
    });
}

#[derive(Clone, Deserialize)]
struct Release {
    tag_name: String,
    html_url: String,
    #[serde(default)]
    draft: bool,
    #[serde(default)]
    prerelease: bool,
    assets: Vec<Asset>,
}

#[derive(Clone, Deserialize)]
struct Asset {
    name: String,
    browser_download_url: String,
}

pub fn running_version() -> String {
    #[cfg(target_os = "macos")]
    {
        if let Ok(exe) = std::env::current_exe() {
            let plist_path = exe.parent().and_then(|p| p.parent()).map(|p| p.join("Info.plist"));
            if let Some(plist_path) = plist_path {
                if plist_path.is_file() {
                    if let Ok(content) = std::fs::read_to_string(&plist_path) {
                        if let Some(pos) = content.find("<key>CFBundleShortVersionString</key>") {
                            let rest = &content[pos..];
                            if let Some(start) = rest.find("<string>") {
                                let after_start = &rest[start + 8..];
                                if let Some(end) = after_start.find("</string>") {
                                    let ver = after_start[..end].trim();
                                    if !ver.is_empty() {
                                        return ver.to_string();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    env!("CARGO_PKG_VERSION").to_string()
}

fn latest() -> Result<Option<Update>, String> {
    let body = match http::get(LATEST, 1024 * 1024) {
        Ok(body) => body,
        // GitHub answers 404 until the first release is published: nothing newer.
        Err(e) if e == "HTTP 404" => return Ok(None),
        Err(e) => return Err(e),
    };
    let release: Release = serde_json::from_slice(&body).map_err(|e| e.to_string())?;
    let current = running_version();
    Ok(newer_release(release, &current))
}

/// The release as an update, if it's a newer published one with a
/// macOS package (.zip, .dmg, or .pkg). On macOS, .zip is preferred
/// as it directly extracts the MacLink.app bundle cleanly.
#[cfg(target_os = "macos")]
fn newer_release(release: Release, current: &str) -> Option<Update> {
    newer_release_for(release.clone(), current, ".zip")
        .or_else(|| newer_release_for(release.clone(), current, ".dmg"))
        .or_else(|| newer_release_for(release, current, ".pkg"))
}

#[cfg(not(target_os = "macos"))]
fn newer_release(release: Release, current: &str) -> Option<Update> {
    newer_release_for(release.clone(), current, ".dmg")
        .or_else(|| newer_release_for(release.clone(), current, ".pkg"))
        .or_else(|| newer_release_for(release, current, ".zip"))
}

fn newer_release_for(release: Release, current: &str, suffix: &str) -> Option<Update> {
    if release.draft || release.prerelease {
        return None;
    }
    let version = release.tag_name.trim_start_matches('v').to_owned();
    if !is_newer(&version, current) {
        return None;
    }
    // The name becomes a file name under local updates: a plain name only, never a path.
    let installer = release.assets.iter().find(|a| {
        let name_lower = a.name.to_lowercase();
        let suffix_lower = suffix.to_lowercase();
        name_lower.ends_with(&suffix_lower)
            && (a.name.starts_with("MacLink-")
                || a.name.starts_with("MacLink-")
                || a.name.starts_with("maclink-")
                || name_lower.contains("setup")
                || name_lower.contains("maclink")
                || name_lower.contains("maclink"))
            && a.name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '.' | '_'))
            && !a.name.contains("..")
    })?;
    let sums = release.assets.iter().find(|a| a.name == "SHA256SUMS.txt")?;
    Some(Update {
        version,
        notes_url: release.html_url,
        installer_url: installer.browser_download_url.clone(),
        installer_name: installer.name.clone(),
        sums_url: sums.browser_download_url.clone(),
    })
}

/// A version's numbers, and its pre-release part.
type Version<'a> = ((u64, u64, u64), Option<&'a str>);

/// `1.2.3` style versions, with an optional `-pre` part (a release is
/// newer than its pre-releases).
pub(crate) fn is_newer(candidate: &str, current: &str) -> bool {
    fn parse(v: &str) -> Option<Version<'_>> {
        let (numbers, pre) = match v.split_once('-') {
            Some((n, p)) => (n, Some(p)),
            None => (v, None),
        };
        let mut parts = numbers.split('.').map(str::parse::<u64>);
        let version = (parts.next()?.ok()?, parts.next()?.ok()?, parts.next().unwrap_or(Ok(0)).ok()?);
        Some((version, pre))
    }
    let (Some((a, a_pre)), Some((b, b_pre))) = (parse(candidate), parse(current)) else { return false };
    match a.cmp(&b) {
        std::cmp::Ordering::Greater => true,
        std::cmp::Ordering::Less => false,
        std::cmp::Ordering::Equal => match (a_pre, b_pre) {
            (None, Some(_)) => true,
            (Some(x), Some(y)) => x > y,
            _ => false,
        },
    }
}

/// The SHA-256 a sums file lists for `name` (`<hex>  <name>` lines).
fn listed_hash(sums: &str, name: &str) -> Option<String> {
    sums.lines().find_map(|line| {
        let (hash, file) = line.split_once(char::is_whitespace)?;
        (file.trim().trim_start_matches('*') == name && hash.len() == 64).then(|| hash.to_ascii_lowercase())
    })
}

/// Nobody has used the PC for a while, and nothing is going on that an update
/// would cut off: mirroring, an app window, a transfer, a call, screen sharing
/// or the webcam.
fn quiet() -> bool {
    #[cfg(windows)]
    if crate::win::input::is_user_active_within_ms(QUIET_FOR.as_millis() as u32) {
        return false;
    }
    let mirroring = crate::mirror::windows().iter().any(|(_, shown)| {
        matches!(shown.phase, crate::mirror::Phase::Asking | crate::mirror::Phase::Showing)
    });
    let transferring = core_host::host().hub.read(|s| {
        s.transfers.iter().any(|t| {
            matches!(
                t.transfer.state,
                maclink_core::TransferState::Running | maclink_core::TransferState::Waiting
            )
        })
    });
    let calling = crate::calls::active_or_ringing(None).is_some();
    !(mirroring || transferring || calling || crate::pc_mirror::is_active())
}

/// Installs the update found: downloads it (reporting `progress(done,
/// total)`), checks SHA-256 integrity, and replaces /Applications/MacLink.app
/// or opens the installer package.
pub fn install(progress: impl FnMut(u64, u64)) -> Result<(), String> {
    let update = available().ok_or("There's no update to install.")?;
    let staged = stage(&update, progress).map_err(|e| {
        tracing::warn!(error = %e, "update download failed");
        e.for_user()
    })?;

    #[cfg(target_os = "macos")]
    {
        let staged_str = staged.to_string_lossy().to_string();
        let target_bundle = std::env::current_exe()
            .ok()
            .and_then(|p| {
                let bundle = p.ancestors().nth(3)?;
                if bundle.extension().is_some_and(|ext| ext == "app") {
                    Some(bundle.to_string_lossy().to_string())
                } else {
                    None
                }
            })
            .unwrap_or_else(|| "/Applications/MacLink.app".to_string());

        let current_pid = std::process::id();

        let install_script = format!(
            r#"
            PID="{current_pid}"
            STAGED="{staged_str}"
            TARGET="{target_bundle}"
            FALLBACK="/Applications/MacLink.app"
            STAGE_DIR=$(mktemp -d /tmp/maclink_update.XXXXXX)

            # Wait for current process to exit cleanly
            for _ in {{1..25}}; do
                if kill -0 "$PID" 2>/dev/null; then
                    sleep 0.2
                else
                    break
                fi
            done

            NEW_APP=""
            MOUNT_POINT=""

            if [[ "$STAGED" == *.zip ]]; then
                ditto -x -k "$STAGED" "$STAGE_DIR"
                if [[ -d "$STAGE_DIR/MacLink.app" ]]; then
                    NEW_APP="$STAGE_DIR/MacLink.app"
                fi
            elif [[ "$STAGED" == *.dmg ]]; then
                MOUNT_POINT=$(mktemp -d /tmp/maclink_mnt.XXXXXX)
                if hdiutil attach -nobrowse -readonly "$STAGED" -mountpoint "$MOUNT_POINT" >/dev/null 2>&1; then
                    if [[ -d "$MOUNT_POINT/MacLink.app" ]]; then
                        cp -R "$MOUNT_POINT/MacLink.app" "$STAGE_DIR/MacLink.app"
                        NEW_APP="$STAGE_DIR/MacLink.app"
                    fi
                    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
                fi
                rm -rf "$MOUNT_POINT"
            fi

            # Fallback to opening installer if extraction failed
            if [[ -z "$NEW_APP" || ! -d "$NEW_APP" ]]; then
                open "$STAGED"
                rm -rf "$STAGE_DIR"
                exit 0
            fi

            DEST="$TARGET"
            if [[ ! -w "$(dirname "$DEST")" && -w "/Applications" ]]; then
                DEST="$FALLBACK"
            fi

            # Remove quarantine attributes before moving
            xattr -cr "$NEW_APP" 2>/dev/null || true

            # Atomic swap
            BACKUP="$DEST.old.$$"
            if [[ -d "$DEST" ]]; then
                mv "$DEST" "$BACKUP" 2>/dev/null || rm -rf "$DEST" 2>/dev/null || true
            fi

            if cp -R "$NEW_APP" "$DEST" 2>/dev/null; then
                rm -rf "$BACKUP" 2>/dev/null || true
                rm -rf "$STAGE_DIR" 2>/dev/null || true
                xattr -cr "$DEST" 2>/dev/null || true
                open "$DEST" --args --updated
            else
                if [[ -d "$BACKUP" ]]; then
                    mv "$BACKUP" "$DEST" 2>/dev/null || true
                fi
                open "$STAGED"
                rm -rf "$STAGE_DIR"
            fi
            "#
        );

        let _ = std::process::Command::new("/bin/bash").arg("-c").arg(&install_script).spawn();

        std::process::exit(0);
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = std::process::Command::new("open").arg(&staged).spawn();
        Ok(())
    }
}

/// Why a download didn't produce a checked installer.
#[derive(Debug)]
pub enum StageError {
    Network(String),
    Damaged,
    Disk(String),
}

impl StageError {
    fn for_user(&self) -> String {
        match self {
            StageError::Network(_) => {
                tr!(
                    "Updater",
                    "The update couldn't be downloaded. Check your internet connection and try again."
                )
            }
            StageError::Damaged => {
                tr!("Updater", "The download was damaged, so it wasn't installed. Try again.")
            }
            StageError::Disk(_) => {
                tr!("Updater", "The update couldn't be saved. Check that there's free space and try again.")
            }
        }
    }
}

impl std::fmt::Display for StageError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StageError::Network(e) => write!(f, "network: {e}"),
            StageError::Damaged => f.write_str("checksum mismatch"),
            StageError::Disk(e) => write!(f, "disk: {e}"),
        }
    }
}

/// Where the app leaves a downloaded installer for the task or system:
fn staging_dir() -> PathBuf {
    #[cfg(windows)]
    {
        std::env::var_os("ProgramData")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"))
            .join("MacLink")
            .join("updates")
    }
    #[cfg(target_os = "macos")]
    {
        std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/tmp"))
            .join("Library/Caches/MacLink/updates")
    }
    #[cfg(not(any(windows, target_os = "macos")))]
    {
        std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/tmp"))
            .join(".cache/maclink/updates")
    }
}

/// The release's SHA-256 for its installer.
fn expected_hash(update: &Update) -> Result<Option<String>, StageError> {
    if update.sums_url.is_empty() {
        return Ok(None);
    }
    let sums = http::get_retrying(&update.sums_url, 64 * 1024).map_err(StageError::Network)?;
    Ok(listed_hash(&String::from_utf8_lossy(&sums), &update.installer_name))
}

fn sha256_file(path: &Path) -> std::io::Result<String> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 256 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hasher.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

/// Downloads the installer into the staging folder (continuing a download
/// cut short before), checks it, and returns its path. Reuses one already
/// downloaded and checked.
pub fn stage(update: &Update, progress: impl FnMut(u64, u64)) -> Result<PathBuf, StageError> {
    let expected = expected_hash(update)?;
    let dir = staging_dir();
    std::fs::create_dir_all(&dir).map_err(|e| StageError::Disk(e.to_string()))?;
    let path = dir.join(&update.installer_name);
    let part = dir.join(format!("{}.part", update.installer_name));
    // Older versions' files.
    if let Ok(entries) = std::fs::read_dir(&dir) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p != path && p != part {
                let _ = std::fs::remove_file(p);
            }
        }
    }
    if path.is_file() {
        if let Some(ref hash) = expected {
            if sha256_file(&path).ok().as_deref() == Some(hash.as_str()) {
                return Ok(path);
            }
        } else {
            return Ok(path);
        }
    }
    let _ = std::fs::remove_file(&path);
    http::download(&update.installer_url, &part, MAX_INSTALLER, progress).map_err(StageError::Network)?;
    if let Some(ref hash) = expected {
        let actual = sha256_file(&part).map_err(|e| StageError::Disk(e.to_string()))?;
        if actual != *hash {
            let _ = std::fs::remove_file(&part);
            return Err(StageError::Damaged);
        }
    }
    std::fs::rename(&part, &path).map_err(|e| StageError::Disk(e.to_string()))?;
    Ok(path)
}

pub fn run_service() -> ExitCode {
    ExitCode::SUCCESS
}

/// The flag passed to the new version.
pub const UPDATED_ARG: &str = "--updated";

/// The file that remembers which version last ran, to notice an update
/// however it was installed (the task, the installer, or setup by hand).
const LAST_VERSION_FILE: &str = "last-version";

/// Records this version as the one that ran, and returns the one before it
/// when this one is newer: the app was just updated.
pub fn note_running_version(data_dir: &Path) -> Option<String> {
    let path = data_dir.join(LAST_VERSION_FILE);
    let previous = std::fs::read_to_string(&path).ok().map(|v| v.trim().to_owned());
    let current = running_version();
    if previous.as_deref() != Some(&current)
        && let Err(e) = std::fs::write(&path, &current)
    {
        tracing::warn!(error = %e, "can't note the running version");
    }
    previous.filter(|p| is_newer(&current, p))
}

/// Just updated: says so, and when the window was asked for, brings it to
/// the front. Started from the background, Windows would otherwise leave
/// the new window behind whatever the user has open.
pub fn announce_update(previous: String, shown: bool) {
    let current = running_version();
    tracing::info!(from = previous, to = current, "updated");
    after_start(
        shown,
        tr!("Updater", "MacLink is updated to %1", current),
        tr!("Updater", "Your phone reconnects on its own."),
    );
}

/// The relauncher opened this version again because the update didn't
/// install (`update.log` says why).
pub fn announce_update_failed(shown: bool) {
    tracing::warn!("the update didn't install");
    after_start(
        shown,
        tr!("Updater", "The update didn't install"),
        tr!("Updater", "MacLink is still on the version you had. Try again from Settings."),
    );
}

fn after_start(shown: bool, title: String, body: String) {
    std::thread::spawn(move || {
        // Once the window exists.
        std::thread::sleep(Duration::from_millis(1500));
        if shown {
            crate::bridge::app::request_activation();
        }
        toast::show(toast::Toast {
            device: TOAST_GROUP.into(),
            key: "updated".into(),
            title,
            body,
            attribution: "MacLink".into(),
            icon: None,
            image: None,
            actions: Vec::new(),
            reply: None,
            silent: true,
            progress: None,
            call: false,
        });
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_compare() {
        assert!(is_newer("0.1.0", "0.0.1"));
        assert!(is_newer("1.0.0", "0.9.9"));
        assert!(is_newer("0.2.0", "0.2.0-beta.1"));
        assert!(is_newer("0.2.0-beta.2", "0.2.0-beta.1"));
        assert!(!is_newer("0.0.1", "0.0.1"));
        assert!(!is_newer("0.0.1", "0.1.0"));
        assert!(!is_newer("garbage", "0.1.0"));
    }

    fn release(tag: &str) -> Release {
        Release {
            tag_name: tag.into(),
            html_url: "https://github.com/anksarvesh-lgtm/MacLink/releases/tag/v9".into(),
            draft: false,
            prerelease: false,
            assets: vec![
                Asset {
                    name: "MacLink-9.0.0-macos-arm64.zip".into(),
                    browser_download_url: "https://x/maclink-zip".into(),
                },
                Asset {
                    name: "MacLink-9.0.0.dmg".into(),
                    browser_download_url: "https://x/maclink-dmg".into(),
                },
                Asset { name: "SHA256SUMS.txt".into(), browser_download_url: "https://x/sums".into() },
            ],
        }
    }

    #[test]
    fn notices_a_newer_version_once() {
        let dir = tempfile::tempdir().unwrap();
        let current = env!("CARGO_PKG_VERSION");
        // A first run, then the same version again: no update.
        assert_eq!(note_running_version(dir.path()), None);
        assert_eq!(note_running_version(dir.path()), None);
        // An older version ran before this one: updated, said once.
        std::fs::write(dir.path().join(LAST_VERSION_FILE), "0.0.0\n").unwrap();
        assert_eq!(note_running_version(dir.path()).as_deref(), Some("0.0.0"));
        assert_eq!(note_running_version(dir.path()), None);
        assert_eq!(std::fs::read_to_string(dir.path().join(LAST_VERSION_FILE)).unwrap(), current);
        // Going back to an older build isn't an update.
        std::fs::write(dir.path().join(LAST_VERSION_FILE), "999.0.0").unwrap();
        assert_eq!(note_running_version(dir.path()), None);
    }

    #[test]
    fn installer_names_that_are_not_plain_file_names_are_refused() {
        for name in [r"..\..\evil.dmg", "MacLink-9/../x.dmg", "evil.dmg"] {
            let mut r = release("v9.0.0");
            r.assets[1].name = name.into();
            assert!(newer_release_for(r, "0.0.1", ".dmg").is_none(), "{name}");
        }
    }

    #[test]
    fn releases_become_updates_when_newer_and_complete() {
        let zip = newer_release_for(release("v9.0.0"), "0.0.1", ".zip").unwrap();
        assert_eq!((zip.version.as_str(), zip.installer_url.as_str()), ("9.0.0", "https://x/maclink-zip"));
        let dmg = newer_release_for(release("v9.0.0"), "0.0.1", ".dmg").unwrap();
        assert_eq!(
            (dmg.installer_name.as_str(), dmg.installer_url.as_str()),
            ("MacLink-9.0.0.dmg", "https://x/maclink-dmg")
        );
        assert!(newer_release(release("v0.0.1"), "0.0.1").is_none());
        let mut draft = release("v9.0.0");
        draft.prerelease = true;
        assert!(newer_release(draft, "0.0.1").is_none());
        let mut no_sums = release("v9.0.0");
        no_sums.assets.pop();
        assert!(newer_release(no_sums, "0.0.1").is_none());
    }

    #[test]
    fn finds_the_installer_hash() {
        let hash = "a".repeat(64);
        let sums = format!("{hash}  MacLink-9.0.0.dmg\n{}  other.txt\n", "b".repeat(64));
        assert_eq!(listed_hash(&sums, "MacLink-9.0.0.dmg"), Some(hash));
        assert_eq!(listed_hash(&sums, "missing.dmg"), None);
        assert_eq!(listed_hash(&format!("{}  *x.dmg", "C".repeat(64)), "x.dmg"), Some("c".repeat(64)));
    }
}
