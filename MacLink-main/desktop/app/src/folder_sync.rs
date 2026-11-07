// SPDX-License-Identifier: GPL-3.0-or-later
//! Folder Sync (§3.6 P2): one-way (Phone → PC) and two-way folder
//! synchronization over the MacLink storage service (`storage.list`,
//! `storage.read`, `storage.write`), with conflict-safe renaming so neither
//! side's edits are ever lost.

use crate::i18n::tr;
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Mutex, OnceLock},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use maclink_core::{DeviceId, Node};
use serde::{Deserialize, Serialize};

use crate::{core_host, settings};

/// User-configured folder synchronization rule persisted in `settings.json`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FolderSyncRule {
    pub id: String,
    pub phone_id: String,
    /// Relative path on the phone (e.g. `"DCIM/Camera"` or `"Download"`).
    pub phone_folder: String,
    /// Absolute path on this PC (e.g. `"C:\\Users\\Alice\\Pictures\\Phone"`).
    pub pc_folder: String,
    /// `"one_way_phone_to_pc"` or `"two_way"`.
    pub mode: String,
    pub enabled: bool,
}

/// Metadata for a single file compared during folder synchronization.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncEntry {
    pub rel_path: String,
    pub size: u64,
    pub modified_ms: i64,
}

/// Reconciliation action produced by [`plan_two_way_sync`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SyncAction {
    PullToPc { rel_path: String },
    PushToPhone { rel_path: String },
    ConflictRenamePcAndPull { rel_path: String, conflict_rel_path: String },
}

type RuleBaselineMap = HashMap<String, HashMap<String, (u64, i64)>>;

static LAST_SYNCED: OnceLock<Mutex<RuleBaselineMap>> = OnceLock::new();

fn baselines() -> &'static Mutex<RuleBaselineMap> {
    LAST_SYNCED.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Formats a conflict-safe relative path by inserting
/// ` (conflict-<date_yyyymmdd>-<hostname>)` before the file extension.
pub fn conflict_file_name(rel_path: &str, date_yyyymmdd: &str, hostname: &str) -> String {
    let clean_host: String =
        hostname.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_').take(32).collect();
    let host = if clean_host.is_empty() { "PC" } else { &clean_host };
    let suffix = format!(" (conflict-{date_yyyymmdd}-{host})");

    let (dir_prefix, file_name) = match rel_path.rfind('/') {
        Some(idx) => (&rel_path[..=idx], &rel_path[idx + 1..]),
        None => ("", rel_path),
    };

    match file_name.rfind('.') {
        Some(dot) if dot > 0 => {
            let stem = &file_name[..dot];
            let ext = &file_name[dot..];
            format!("{dir_prefix}{stem}{suffix}{ext}")
        }
        _ => format!("{dir_prefix}{file_name}{suffix}"),
    }
}

fn current_date_yyyymmdd() -> String {
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    // Civil date from Unix days (Howard Hinnant's algorithm).
    let z = secs.div_euclid(86_400) + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };
    format!("{year:04}{m:02}{d:02}")
}

fn matches_state(entry: &SyncEntry, state: (u64, i64)) -> bool {
    entry.size == state.0 && (entry.modified_ms - state.1).abs() <= 2_000
}

/// Pure reconciliation planner for one-way (`"one_way_phone_to_pc"`) and
/// two-way (`"two_way"`) folder synchronization.
pub fn plan_two_way_sync(
    phone_files: &[SyncEntry],
    pc_files: &[SyncEntry],
    last_synced: &HashMap<String, (u64, i64)>,
    mode: &str,
    pc_hostname: &str,
) -> Vec<SyncAction> {
    plan_two_way_sync_with_date(
        phone_files,
        pc_files,
        last_synced,
        mode,
        pc_hostname,
        &current_date_yyyymmdd(),
    )
}

pub fn plan_two_way_sync_with_date(
    phone_files: &[SyncEntry],
    pc_files: &[SyncEntry],
    last_synced: &HashMap<String, (u64, i64)>,
    mode: &str,
    pc_hostname: &str,
    date_yyyymmdd: &str,
) -> Vec<SyncAction> {
    let phone_map: HashMap<&str, &SyncEntry> = phone_files.iter().map(|e| (e.rel_path.as_str(), e)).collect();
    let pc_map: HashMap<&str, &SyncEntry> = pc_files.iter().map(|e| (e.rel_path.as_str(), e)).collect();

    let mut actions = Vec::new();

    if mode == "one_way_phone_to_pc" {
        for ph in phone_files {
            match pc_map.get(ph.rel_path.as_str()) {
                None => actions.push(SyncAction::PullToPc { rel_path: ph.rel_path.clone() }),
                Some(pc) => {
                    let same = ph.size == pc.size && (ph.modified_ms - pc.modified_ms).abs() <= 2_000;
                    if !same && (ph.size != pc.size || ph.modified_ms > pc.modified_ms + 2_000) {
                        actions.push(SyncAction::PullToPc { rel_path: ph.rel_path.clone() });
                    }
                }
            }
        }
        return actions;
    }

    // Two-way mode:
    for ph in phone_files {
        match pc_map.get(ph.rel_path.as_str()) {
            None => {
                actions.push(SyncAction::PullToPc { rel_path: ph.rel_path.clone() });
            }
            Some(pc) => {
                if ph.size == pc.size && (ph.modified_ms - pc.modified_ms).abs() <= 2_000 {
                    continue;
                }
                match last_synced.get(&ph.rel_path).copied() {
                    Some(base) => {
                        let phone_changed = !matches_state(ph, base);
                        let pc_changed = !matches_state(pc, base);
                        match (phone_changed, pc_changed) {
                            (true, false) => {
                                actions.push(SyncAction::PullToPc { rel_path: ph.rel_path.clone() });
                            }
                            (false, true) => {
                                actions.push(SyncAction::PushToPhone { rel_path: ph.rel_path.clone() });
                            }
                            (true, true) => {
                                let conflict_rel_path =
                                    conflict_file_name(&ph.rel_path, date_yyyymmdd, pc_hostname);
                                actions.push(SyncAction::ConflictRenamePcAndPull {
                                    rel_path: ph.rel_path.clone(),
                                    conflict_rel_path,
                                });
                            }
                            (false, false) => {}
                        }
                    }
                    None => {
                        if ph.size != pc.size {
                            let conflict_rel_path =
                                conflict_file_name(&ph.rel_path, date_yyyymmdd, pc_hostname);
                            actions.push(SyncAction::ConflictRenamePcAndPull {
                                rel_path: ph.rel_path.clone(),
                                conflict_rel_path,
                            });
                        } else if ph.modified_ms > pc.modified_ms + 2_000 {
                            actions.push(SyncAction::PullToPc { rel_path: ph.rel_path.clone() });
                        } else if pc.modified_ms > ph.modified_ms + 2_000 {
                            actions.push(SyncAction::PushToPhone { rel_path: ph.rel_path.clone() });
                        }
                    }
                }
            }
        }
    }

    for pc in pc_files {
        if !phone_map.contains_key(pc.rel_path.as_str()) {
            actions.push(SyncAction::PushToPhone { rel_path: pc.rel_path.clone() });
        }
    }

    actions
}

/// Maximum subfolder nesting depth traversed during folder synchronization.
pub const MAX_SUBFOLDER_DEPTH: usize = 3;

const STREAM_CHUNK_SIZE: usize = 64 * 1024;

fn read_pc_entries(dir: &Path) -> Vec<SyncEntry> {
    let mut out = Vec::new();
    read_pc_entries_inner(dir, "", 0, &mut out);
    out.sort_by(|a, b| a.rel_path.cmp(&b.rel_path));
    out
}

fn read_pc_entries_inner(dir: &Path, prefix: &str, depth: usize, out: &mut Vec<SyncEntry>) {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return;
    };
    for item in rd.flatten() {
        let Ok(name) = item.file_name().into_string() else {
            continue;
        };
        if name.starts_with('.') || name.ends_with(".maclink.part") || name.contains(" (conflict-") {
            continue;
        }
        let Ok(ft) = item.file_type() else {
            continue;
        };
        if ft.is_symlink() {
            continue;
        }
        let rel_path = if prefix.is_empty() { name.clone() } else { format!("{prefix}/{name}") };
        if ft.is_dir() {
            if depth < MAX_SUBFOLDER_DEPTH {
                read_pc_entries_inner(&item.path(), &rel_path, depth + 1, out);
            }
            continue;
        }
        if !ft.is_file() {
            continue;
        }
        let Ok(meta) = item.metadata() else {
            continue;
        };
        let modified_ms = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .and_then(|d| i64::try_from(d.as_millis()).ok())
            .unwrap_or(0);
        out.push(SyncEntry { rel_path, size: meta.len(), modified_ms });
    }
}

fn join_phone_path(folder: &str, rel_path: &str) -> String {
    let trimmed = folder.trim_matches('/');
    if trimmed.is_empty() {
        rel_path.to_owned()
    } else if rel_path.is_empty() {
        trimmed.to_owned()
    } else {
        format!("{trimmed}/{rel_path}")
    }
}

async fn list_phone_entries(node: &Node, peer: DeviceId, base_folder: &str) -> Option<Vec<SyncEntry>> {
    let mut out = Vec::new();
    let mut queue = std::collections::VecDeque::new();
    queue.push_back((String::new(), 0usize));

    while let Some((rel_dir, depth)) = queue.pop_front() {
        let remote_dir = join_phone_path(base_folder, &rel_dir);
        let entries = match node.storage_list(peer, &remote_dir).await {
            Ok(list) => list,
            Err(_) if rel_dir.is_empty() => return None,
            Err(_) => continue,
        };
        for entry in entries {
            if entry.name.starts_with('.')
                || entry.name.ends_with(".maclink.part")
                || entry.name.contains(" (conflict-")
            {
                continue;
            }
            let rel_path =
                if rel_dir.is_empty() { entry.name.clone() } else { format!("{rel_dir}/{}", entry.name) };
            if entry.is_dir {
                if depth < MAX_SUBFOLDER_DEPTH {
                    queue.push_back((rel_path, depth + 1));
                }
            } else {
                out.push(SyncEntry { rel_path, size: entry.size, modified_ms: entry.modified });
            }
        }
    }

    out.sort_by(|a, b| a.rel_path.cmp(&b.rel_path));
    Some(out)
}

fn temp_part_path(dest: &Path) -> Option<PathBuf> {
    let file_name = dest.file_name()?.to_string_lossy();
    Some(dest.with_file_name(format!(".{file_name}.maclink.part")))
}

/// Streams a chunked reader to a `.maclink.part` temporary file, verifies
/// that the byte count and BLAKE3 digest match the written file on disk, and
/// atomically renames the temporary file to `dest`.
#[cfg(test)]
pub async fn write_verified_part_file<R>(
    mut reader: R,
    expected_len: u64,
    dest: &Path,
) -> std::io::Result<blake3::Hash>
where
    R: tokio::io::AsyncRead + Unpin,
{
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let part_path = temp_part_path(dest)
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidInput, "missing file name"))?;
    if let Some(parent) = dest.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }

    let mut file = tokio::fs::File::create(&part_path).await?;
    let mut stream_hasher = blake3::Hasher::new();
    let mut written = 0u64;
    let mut buf = vec![0u8; STREAM_CHUNK_SIZE];

    let write_res: std::io::Result<()> = async {
        loop {
            let n = reader.read(&mut buf).await?;
            if n == 0 {
                break;
            }
            written = written.saturating_add(n as u64);
            if written > expected_len {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    "stream exceeded expected length",
                ));
            }
            stream_hasher.update(&buf[..n]);
            file.write_all(&buf[..n]).await?;
        }
        if written != expected_len {
            return Err(std::io::Error::new(
                std::io::ErrorKind::UnexpectedEof,
                "stream ended before expected length",
            ));
        }
        file.flush().await?;
        file.sync_all().await?;
        Ok(())
    }
    .await;

    drop(file);
    if let Err(err) = write_res {
        let _ = tokio::fs::remove_file(&part_path).await;
        return Err(err);
    }

    let streamed_hash = stream_hasher.finalize();
    let part_clone = part_path.clone();
    let verified = tokio::task::spawn_blocking(move || -> std::io::Result<(u64, blake3::Hash)> {
        let mut f = std::fs::File::open(&part_clone)?;
        let len = f.metadata()?.len();
        let mut disk_hasher = blake3::Hasher::new();
        std::io::copy(&mut f, &mut disk_hasher)?;
        Ok((len, disk_hasher.finalize()))
    })
    .await
    .map_err(std::io::Error::other)??;

    if verified.0 != expected_len || verified.1 != streamed_hash {
        let _ = tokio::fs::remove_file(&part_path).await;
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "staged file size or BLAKE3 hash mismatch",
        ));
    }

    if let Err(err) = tokio::fs::rename(&part_path, dest).await {
        let _ = tokio::fs::remove_file(&part_path).await;
        return Err(err);
    }

    Ok(streamed_hash)
}

async fn pull_phone_file_streaming(
    node: &Node,
    peer: DeviceId,
    remote: String,
    dest: &Path,
) -> Option<(u64, i64)> {
    use tokio::io::AsyncWriteExt;

    let (meta, mut recv) = node.storage_read_stream(peer, remote, 0, None).await.ok()?;
    if meta.length != meta.size {
        return None;
    }
    let part_path = temp_part_path(dest)?;
    if let Some(parent) = dest.parent() {
        tokio::fs::create_dir_all(parent).await.ok()?;
    }

    let mut file = tokio::fs::File::create(&part_path).await.ok()?;
    let mut stream_hasher = blake3::Hasher::new();
    let mut written = 0u64;

    let ok = async {
        while let Some(chunk) = recv.read_chunk(STREAM_CHUNK_SIZE).await.ok()? {
            if chunk.is_empty() {
                break;
            }
            written = written.saturating_add(chunk.len() as u64);
            if written > meta.length {
                return None;
            }
            stream_hasher.update(&chunk);
            file.write_all(&chunk).await.ok()?;
        }
        if written != meta.length {
            return None;
        }
        file.flush().await.ok()?;
        file.sync_all().await.ok()?;
        Some(())
    }
    .await;

    drop(file);
    if ok.is_none() {
        let _ = tokio::fs::remove_file(&part_path).await;
        return None;
    }

    let streamed_hash = stream_hasher.finalize();
    let part_clone = part_path.clone();
    let verified = tokio::task::spawn_blocking(move || -> Option<(u64, blake3::Hash)> {
        let mut f = std::fs::File::open(&part_clone).ok()?;
        let len = f.metadata().ok()?.len();
        let mut disk_hasher = blake3::Hasher::new();
        std::io::copy(&mut f, &mut disk_hasher).ok()?;
        Some((len, disk_hasher.finalize()))
    })
    .await
    .ok()
    .flatten();

    let Some((disk_len, disk_hash)) = verified else {
        let _ = tokio::fs::remove_file(&part_path).await;
        return None;
    };
    if disk_len != meta.length || disk_hash != streamed_hash {
        let _ = tokio::fs::remove_file(&part_path).await;
        return None;
    }

    if tokio::fs::rename(&part_path, dest).await.is_err() {
        let _ = tokio::fs::remove_file(&part_path).await;
        return None;
    }

    Some((meta.size, meta.modified))
}

/// Runs all enabled [`FolderSyncRule`]s once against `node`, returning the
/// number of file operations performed.
pub async fn sync_now(node: &Node) -> usize {
    let rules = settings::folder_sync_rules();
    if rules.is_empty() {
        return 0;
    }
    let pc_hostname = hostname::get().ok().and_then(|h| h.into_string().ok()).unwrap_or_else(|| "PC".into());
    let mut executed = 0usize;

    for rule in rules.into_iter().filter(|r| r.enabled) {
        let Ok(peer) = rule.phone_id.parse::<DeviceId>() else {
            continue;
        };
        let pc_dir = PathBuf::from(&rule.pc_folder);
        if std::fs::create_dir_all(&pc_dir).is_err() {
            continue;
        }
        let Some(phone_files) = list_phone_entries(node, peer, rule.phone_folder.trim_matches('/')).await
        else {
            continue;
        };
        let pc_files = tokio::task::spawn_blocking({
            let pc_dir = pc_dir.clone();
            move || read_pc_entries(&pc_dir)
        })
        .await
        .unwrap_or_default();

        let last_synced =
            baselines().lock().unwrap_or_else(|e| e.into_inner()).get(&rule.id).cloned().unwrap_or_default();

        let actions = plan_two_way_sync(&phone_files, &pc_files, &last_synced, &rule.mode, &pc_hostname);
        let mut updated_baseline = last_synced;
        for ph in &phone_files {
            if pc_files.iter().any(|pc| {
                pc.rel_path == ph.rel_path
                    && pc.size == ph.size
                    && (pc.modified_ms - ph.modified_ms).abs() <= 2_000
            }) {
                updated_baseline.insert(ph.rel_path.clone(), (ph.size, ph.modified_ms));
            }
        }

        for action in actions {
            match action {
                SyncAction::PullToPc { rel_path } => {
                    let remote = join_phone_path(&rule.phone_folder, &rel_path);
                    let dest = pc_dir.join(&rel_path);
                    if let Some((size, modified)) = pull_phone_file_streaming(node, peer, remote, &dest).await
                    {
                        updated_baseline.insert(rel_path, (size, modified));
                        executed += 1;
                    }
                }
                SyncAction::PushToPhone { rel_path } => {
                    if let Some((parent_rel, _)) = rel_path.rsplit_once('/') {
                        let remote_parent = join_phone_path(&rule.phone_folder, parent_rel);
                        let _ = node.storage_mkdir(peer, remote_parent).await;
                    }
                    let remote = join_phone_path(&rule.phone_folder, &rel_path);
                    let src = pc_dir.join(&rel_path);
                    if let Ok(done) = node.storage_write(peer, remote, &src).await {
                        updated_baseline.insert(rel_path, (done.size, done.modified));
                        executed += 1;
                    }
                }
                SyncAction::ConflictRenamePcAndPull { rel_path, conflict_rel_path } => {
                    let src = pc_dir.join(&rel_path);
                    let conflict_dst = pc_dir.join(&conflict_rel_path);
                    if let Some(parent) = conflict_dst.parent() {
                        let _ = tokio::fs::create_dir_all(parent).await;
                    }
                    let _ = tokio::fs::rename(&src, &conflict_dst).await;
                    let remote = join_phone_path(&rule.phone_folder, &rel_path);
                    if let Some((size, modified)) = pull_phone_file_streaming(node, peer, remote, &src).await
                    {
                        updated_baseline.insert(rel_path, (size, modified));
                        executed += 1;
                    }
                }
            }
        }

        baselines().lock().unwrap_or_else(|e| e.into_inner()).insert(rule.id, updated_baseline);
    }

    executed
}

/// Triggers an immediate folder sync pass on the core runtime.
pub fn trigger_sync_now() {
    core_host::spawn(async {
        if let Some(node) = core_host::node() {
            let count = sync_now(&node).await;
            if count > 0 {
                crate::bridge::app::show_message(tr!("FolderSync", "Synced %1 file(s).", count));
            } else {
                crate::bridge::app::show_message(tr!("FolderSync", "Folders are up to date."));
            }
        }
    });
}

/// Starts a periodic background task that runs enabled folder sync rules.
pub fn start_poller() {
    core_host::spawn(async {
        let mut interval = tokio::time::interval(Duration::from_secs(60));
        loop {
            interval.tick().await;
            if let Some(node) = core_host::node() {
                let _ = sync_now(&node).await;
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn conflict_file_name_inserts_suffix_before_extension() {
        assert_eq!(
            conflict_file_name("notes/todo.txt", "20260420", "DESKTOP-1"),
            "notes/todo (conflict-20260420-DESKTOP-1).txt"
        );
        assert_eq!(conflict_file_name("README", "20260420", "MYPC"), "README (conflict-20260420-MYPC)");
    }

    #[test]
    fn one_way_phone_to_pc_pulls_new_and_updated_files() {
        let phone = vec![
            SyncEntry { rel_path: "IMG_001.jpg".into(), size: 1200, modified_ms: 10_000 },
            SyncEntry { rel_path: "IMG_002.jpg".into(), size: 2500, modified_ms: 20_000 },
        ];
        let pc = vec![
            SyncEntry { rel_path: "IMG_001.jpg".into(), size: 1200, modified_ms: 10_000 },
            SyncEntry { rel_path: "PC_ONLY.png".into(), size: 900, modified_ms: 30_000 },
        ];
        let actions = plan_two_way_sync_with_date(
            &phone,
            &pc,
            &HashMap::new(),
            "one_way_phone_to_pc",
            "MYPC",
            "20260420",
        );
        assert_eq!(actions, vec![SyncAction::PullToPc { rel_path: "IMG_002.jpg".into() }]);
    }

    #[test]
    fn two_way_sync_pushes_pc_only_and_pulls_phone_only() {
        let phone = vec![SyncEntry { rel_path: "from_phone.txt".into(), size: 100, modified_ms: 5_000 }];
        let pc = vec![SyncEntry { rel_path: "from_pc.txt".into(), size: 200, modified_ms: 6_000 }];
        let actions =
            plan_two_way_sync_with_date(&phone, &pc, &HashMap::new(), "two_way", "MYPC", "20260420");
        assert_eq!(
            actions,
            vec![
                SyncAction::PullToPc { rel_path: "from_phone.txt".into() },
                SyncAction::PushToPhone { rel_path: "from_pc.txt".into() },
            ]
        );
    }

    #[test]
    fn two_way_sync_resolves_simultaneous_edits_with_conflict_copy() {
        let mut baseline = HashMap::new();
        baseline.insert("shared.txt".to_owned(), (100u64, 1_000i64));

        let phone = vec![SyncEntry { rel_path: "shared.txt".into(), size: 150, modified_ms: 8_000 }];
        let pc = vec![SyncEntry { rel_path: "shared.txt".into(), size: 180, modified_ms: 9_000 }];

        let actions = plan_two_way_sync_with_date(&phone, &pc, &baseline, "two_way", "OFFICEPC", "20260420");
        assert_eq!(
            actions,
            vec![SyncAction::ConflictRenamePcAndPull {
                rel_path: "shared.txt".into(),
                conflict_rel_path: "shared (conflict-20260420-OFFICEPC).txt".into(),
            }]
        );
    }

    #[test]
    fn read_pc_entries_scans_subfolders_and_skips_part_files() {
        let dir = tempfile::tempdir().unwrap();
        let sub = dir.path().join("albums").join("2026");
        std::fs::create_dir_all(&sub).unwrap();
        std::fs::write(dir.path().join("root.txt"), b"root").unwrap();
        std::fs::write(sub.join("photo.jpg"), b"123456").unwrap();
        std::fs::write(sub.join(".photo.jpg.maclink.part"), b"partial").unwrap();

        let entries = read_pc_entries(dir.path());
        let paths: Vec<&str> = entries.iter().map(|e| e.rel_path.as_str()).collect();
        assert_eq!(paths, vec!["albums/2026/photo.jpg", "root.txt"]);
    }

    #[tokio::test]
    async fn streaming_part_file_verifies_size_and_blake3_and_cleans_up_on_truncation() {
        let dir = tempfile::tempdir().unwrap();
        let payload = vec![0x5Au8; 150_000];
        let expected_hash = blake3::hash(&payload);
        let dest = dir.path().join("nested").join("video.mp4");

        let hash = write_verified_part_file(&payload[..], payload.len() as u64, &dest).await.unwrap();
        assert_eq!(hash, expected_hash);
        assert_eq!(std::fs::read(&dest).unwrap(), payload);
        assert!(!temp_part_path(&dest).unwrap().exists());

        // Truncated stream must fail and remove the `.maclink.part` file.
        let bad_dest = dir.path().join("nested").join("truncated.mp4");
        let res = write_verified_part_file(&payload[..1024], payload.len() as u64, &bad_dest).await;
        assert!(res.is_err());
        assert!(!bad_dest.exists());
        assert!(!temp_part_path(&bad_dest).unwrap().exists());
    }
}
