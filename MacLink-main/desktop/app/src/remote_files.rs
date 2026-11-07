// SPDX-License-Identifier: GPL-3.0-or-later
//! Remote file manager backend for browsing and transferring files between Mac and paired Android phones.

use std::{
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use maclink_core::{DeviceId, Node, StorageEntry};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteFileUiItem {
    pub name: String,
    pub folder: String,
    pub size: String,
    pub bytes: u64,
    pub date: String,
    pub modified: i64,
    #[serde(rename = "isDir")]
    pub is_dir: bool,
    pub icon: String,
    #[serde(rename = "type")]
    pub kind: String,
}

/// Normalizes a remote path to match the MacLink storage protocol specification:
/// relative to the shared storage root, no leading or trailing slashes,
/// and strips any legacy `/sdcard/` or `/storage/emulated/0/` prefixes.
pub fn normalize_remote_path(path: &str) -> String {
    let p = path.trim().replace('\\', "/");
    let mut clean = p.as_str();

    // Strip common Android absolute root aliases if passed by the UI
    if let Some(rest) = clean.strip_prefix("/storage/emulated/0/") {
        clean = rest;
    } else if let Some(rest) = clean.strip_prefix("storage/emulated/0/") {
        clean = rest;
    } else if let Some(rest) = clean.strip_prefix("/storage/emulated/0") {
        clean = rest;
    } else if let Some(rest) = clean.strip_prefix("/sdcard/") {
        clean = rest;
    } else if let Some(rest) = clean.strip_prefix("sdcard/") {
        clean = rest;
    } else if let Some(rest) = clean.strip_prefix("/sdcard") {
        clean = rest;
    } else if clean == "sdcard" || clean == "storage" {
        clean = "";
    }

    clean.trim_matches('/').to_string()
}

/// Formats byte sizes into human-readable strings (e.g. "38.4 MB", "840 KB").
pub fn format_bytes(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = 1024 * KB;
    const GB: u64 = 1024 * MB;

    if bytes >= GB {
        format!("{:.1} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.1} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.0} KB", bytes as f64 / KB as f64)
    } else {
        format!("{bytes} B")
    }
}

/// Formats Unix millisecond timestamps into human-friendly relative or calendar dates.
pub fn format_timestamp(unix_ms: i64) -> String {
    if unix_ms <= 0 {
        return "Unknown".to_string();
    }
    let secs = (unix_ms / 1000) as u64;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let diff = now.saturating_sub(secs);

    if diff < 60 {
        "Just now".to_string()
    } else if diff < 3600 {
        format!("{}m ago", diff / 60)
    } else if diff < 86400 {
        format!("{}h ago", diff / 3600)
    } else if diff < 86400 * 2 {
        "Yesterday".to_string()
    } else if diff < 86400 * 30 {
        format!("{}d ago", diff / 86400)
    } else {
        // Fallback to formatted epoch date
        format!("{} days ago", diff / 86400)
    }
}

/// Classifies an entry into UI type and icon category (mapping to QML `Icons.*`).
pub fn classify_file_type(name: &str, is_dir: bool) -> (String, String) {
    if is_dir {
        return ("dir".to_string(), "folder".to_string());
    }
    let ext = Path::new(name).extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();

    match ext.as_str() {
        "jpg" | "jpeg" | "png" | "gif" | "webp" | "heic" | "heif" | "bmp" | "svg" => {
            ("image".to_string(), "photo".to_string())
        }
        "mp4" | "mkv" | "mov" | "avi" | "webm" | "m4v" => ("video".to_string(), "video".to_string()),
        "mp3" | "m4a" | "wav" | "flac" | "aac" | "ogg" | "opus" => ("audio".to_string(), "sound".to_string()),
        "pdf" | "doc" | "docx" | "txt" | "rtf" | "md" | "odt" | "xlsx" | "xls" | "csv" | "pptx" | "ppt" => {
            ("doc".to_string(), "text".to_string())
        }
        "apk" => ("apk".to_string(), "sparkle".to_string()),
        "zip" | "tar" | "gz" | "7z" | "rar" | "bz2" | "xz" => ("archive".to_string(), "folder".to_string()),
        _ => ("file".to_string(), "text".to_string()),
    }
}

/// Converts core `StorageEntry` items into a JSON array consumable by QML's `fileListView`.
pub fn entries_to_ui_json(folder: &str, entries: &[StorageEntry]) -> String {
    let items: Vec<RemoteFileUiItem> = entries
        .iter()
        .map(|entry| {
            let (kind, icon) = classify_file_type(&entry.name, entry.is_dir);
            let size = if entry.is_dir { "Folder".to_string() } else { format_bytes(entry.size) };
            RemoteFileUiItem {
                name: entry.name.clone(),
                folder: folder.to_string(),
                size,
                bytes: entry.size,
                date: format_timestamp(entry.modified),
                modified: entry.modified,
                is_dir: entry.is_dir,
                icon,
                kind,
            }
        })
        .collect();

    serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string())
}

/// Downloads a file from the connected device and saves it into the local Downloads directory.
pub async fn download_file(
    node: &Node,
    peer: DeviceId,
    remote_path: &str,
    save_dir: &Path,
) -> Result<PathBuf, String> {
    let clean_path = normalize_remote_path(remote_path);
    if clean_path.is_empty() {
        return Err("invalid empty file path".to_string());
    }
    let file_name = clean_path.split('/').next_back().unwrap_or("file");

    std::fs::create_dir_all(save_dir).map_err(|e| format!("cannot create directory: {e}"))?;
    let target_file = save_dir.join(file_name);

    let (_meta, bytes) = node
        .storage_read(peer, &clean_path, 0, None)
        .await
        .map_err(|e| format!("failed to read file from phone: {e}"))?;

    std::fs::write(&target_file, &bytes).map_err(|e| format!("failed to save downloaded file: {e}"))?;

    Ok(target_file)
}

/// Uploads a local file into the specified remote directory on the connected device.
pub async fn upload_file(
    node: &Node,
    peer: DeviceId,
    remote_dir: &str,
    local_path: &Path,
) -> Result<String, String> {
    if !local_path.is_file() {
        return Err(format!("local file does not exist: {}", local_path.display()));
    }
    let file_name = local_path
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or_else(|| "invalid local file name".to_string())?;

    let clean_dir = normalize_remote_path(remote_dir);
    let remote_dest =
        if clean_dir.is_empty() { file_name.to_string() } else { format!("{clean_dir}/{file_name}") };

    node.storage_write(peer, &remote_dest, local_path)
        .await
        .map_err(|e| format!("failed to upload to phone: {e}"))?;

    Ok(file_name.to_string())
}

/// Creates a new directory on the connected device.
pub async fn create_folder(
    node: &Node,
    peer: DeviceId,
    parent_dir: &str,
    folder_name: &str,
) -> Result<String, String> {
    let clean_parent = normalize_remote_path(parent_dir);
    let clean_name = folder_name.trim().trim_matches('/');
    if clean_name.is_empty() {
        return Err("folder name cannot be empty".to_string());
    }
    let target_path =
        if clean_parent.is_empty() { clean_name.to_string() } else { format!("{clean_parent}/{clean_name}") };

    node.storage_mkdir(peer, &target_path)
        .await
        .map_err(|e| format!("failed to create folder on phone: {e}"))?;

    Ok(target_path)
}

/// Deletes a file or directory on the connected device.
pub async fn delete_item(node: &Node, peer: DeviceId, path: &str) -> Result<(), String> {
    let clean_path = normalize_remote_path(path);
    if clean_path.is_empty() {
        return Err("cannot delete root folder".to_string());
    }
    node.storage_delete(peer, &clean_path, true)
        .await
        .map_err(|e| format!("failed to delete item on phone: {e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_remote_path() {
        assert_eq!(normalize_remote_path("/sdcard/Download"), "Download");
        assert_eq!(normalize_remote_path("sdcard/Download/Sub"), "Download/Sub");
        assert_eq!(normalize_remote_path("/storage/emulated/0/DCIM/Camera"), "DCIM/Camera");
        assert_eq!(normalize_remote_path("/sdcard"), "");
        assert_eq!(normalize_remote_path(""), "");
        assert_eq!(normalize_remote_path("Documents"), "Documents");
    }

    #[test]
    fn test_format_bytes() {
        assert_eq!(format_bytes(500), "500 B");
        assert_eq!(format_bytes(1024), "1 KB");
        assert_eq!(format_bytes(1024 * 1024 * 38), "38.0 MB");
        assert_eq!(format_bytes(1024 * 1024 * 1024 * 2), "2.0 GB");
    }

    #[test]
    fn test_classify_file_type() {
        let (kind, icon) = classify_file_type("foo.jpg", false);
        assert_eq!(kind, "image");
        assert_eq!(icon, "photo");

        let (kind, icon) = classify_file_type("app.apk", false);
        assert_eq!(kind, "apk");
        assert_eq!(icon, "sparkle");

        let (kind, icon) = classify_file_type("Folder", true);
        assert_eq!(kind, "dir");
        assert_eq!(icon, "folder");
    }
}
