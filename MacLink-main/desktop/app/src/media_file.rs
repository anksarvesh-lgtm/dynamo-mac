// SPDX-License-Identifier: GPL-3.0-or-later
//! Play on phone for video files (docs/protocol/media.md §4): which file a
//! desktop player on this PC plays. Players don't say, but Windows keeps a
//! shortcut to every file opened lately (the Recent folder), and the
//! player's title or its window's names the file.

#![cfg_attr(not(windows), allow(dead_code))]

use std::path::{Path, PathBuf};

use crate::win::{browser, shortcut};

/// Formats a phone's own player plays.
const PLAYABLE: &[&str] = &["mp4", "m4v", "mkv", "webm", "mov", "3gp", "ts"];

/// How many of the latest Recent shortcuts to look through.
const RECENT: usize = 400;

/// Whether a phone plays a file of this name itself.
pub fn playable(name: &str) -> bool {
    Path::new(name)
        .extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| PLAYABLE.iter().any(|p| e.eq_ignore_ascii_case(p)))
}

/// Letters and digits only, lowercase: "Holiday (2024).mp4 - VLC" and
/// "holiday_2024" compare alike.
fn words(text: &str) -> String {
    text.chars().filter(|c| c.is_alphanumeric()).flat_map(char::to_lowercase).collect()
}

/// How well `title` names the file `file_name`: 2 when it is just its
/// name, 1 when one holds the other, 0 when it doesn't name it.
pub(crate) fn names(title: &str, file_name: &str) -> u8 {
    let stem = Path::new(file_name).file_stem().and_then(|s| s.to_str()).unwrap_or(file_name);
    let (title, stem) = (words(title), words(stem));
    if title.chars().count() < 4 || stem.chars().count() < 4 {
        0
    } else if title == stem {
        2
    } else if title.contains(&stem) || stem.contains(&title) {
        1
    } else {
        0
    }
}

/// The file among `recent` (file names, newest first) that `titles` name
/// best: just its name, else the longest name a title holds; the newest of
/// equals.
pub(crate) fn pick<'a>(titles: &[&str], recent: &'a [String]) -> Option<&'a String> {
    let mut best: Option<((u8, usize), &String)> = None;
    for name in recent.iter().filter(|n| playable(n)) {
        let level = titles.iter().map(|t| names(t, name)).max().unwrap_or(0);
        if level == 0 {
            continue;
        }
        let score = (level, words(name).len());
        if best.is_none_or(|(s, _)| score > s) {
            best = Some((score, name));
        }
    }
    best.map(|(_, name)| name)
}

/// The video file this PC's `player` plays (`title`, as its media session
/// says), if it is one a phone plays and Windows lists it as opened lately.
pub fn file_for(player: &str, title: &str) -> Option<PathBuf> {
    let programs = browser::programs_for(player);
    if programs.iter().any(|p| browser::is_browser(p)) {
        return None;
    }
    let windows: Vec<String> =
        browser::windows().into_iter().filter(|w| programs.contains(&w.program)).map(|w| w.title).collect();
    let mut titles: Vec<&str> = windows.iter().map(String::as_str).collect();
    titles.push(title);

    let dir = shortcut::recent_dir()?;
    let mut links: Vec<(std::time::SystemTime, PathBuf)> = std::fs::read_dir(&dir)
        .ok()?
        .filter_map(Result::ok)
        .filter(|e| e.path().extension().is_some_and(|x| x.eq_ignore_ascii_case("lnk")))
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .collect();
    links.sort_by_key(|(modified, _)| std::cmp::Reverse(*modified));
    links.truncate(RECENT);
    // "Holiday.mp4.lnk" is the shortcut to Holiday.mp4.
    let names: Vec<String> =
        links.iter().filter_map(|(_, p)| p.file_stem().and_then(|s| s.to_str()).map(str::to_owned)).collect();
    let name = pick(&titles, &names)?;
    let link = links.iter().find(|(_, p)| p.file_stem().and_then(|s| s.to_str()) == Some(name.as_str()))?;
    let target = shortcut::target(&link.1)?;
    (target.is_file() && target.file_name().and_then(|n| n.to_str()).is_some_and(playable)).then_some(target)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_formats_phones_play() {
        assert!(playable("Holiday.MP4") && playable("a.mkv") && playable("clip.webm"));
        assert!(!playable("old.avi") && !playable("song.mp3") && !playable("notes.txt") && !playable("mp4"));
    }

    #[test]
    fn a_title_names_its_file() {
        assert_eq!(names("Holiday 2024", "Holiday_2024.mp4"), 2);
        assert_eq!(names("Holiday_2024.mp4 - VLC media player", "Holiday_2024.mp4"), 1);
        assert_eq!(names("Holiday", "Holiday 2024 (director's cut).mkv"), 1);
        assert_eq!(names("Something else", "Holiday.mp4"), 0);
        assert_eq!(names("abc", "abc.mp4"), 0, "too short to tell");
    }

    #[test]
    fn the_best_named_playable_file_wins_and_newest_breaks_ties() {
        let recent: Vec<String> =
            ["Holiday 2024.mkv", "Holiday 2024 extras.mp4", "Holiday 2024.avi", "Holiday 2024.mp4"]
                .map(String::from)
                .to_vec();
        // Exactly named beats only contained; the .avi doesn't play on a phone.
        assert_eq!(pick(&["Holiday 2024"], &recent).map(String::as_str), Some("Holiday 2024.mkv"));
        assert_eq!(pick(&["Unrelated"], &recent), None);
        // The window's title counts too.
        let titles = ["", "Holiday 2024 extras.mp4 - VLC media player"];
        assert_eq!(pick(&titles, &recent).map(String::as_str), Some("Holiday 2024 extras.mp4"));
    }
}
