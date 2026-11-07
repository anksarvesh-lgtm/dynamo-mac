// SPDX-License-Identifier: GPL-3.0-or-later
//! `strings`: the text the Windows app builds in Rust, for Qt's translation
//! tools. Every `tr!("Context", "Text", ...)` in `desktop/app/src` goes into
//! `desktop/app/i18n/rust_strings.h` as a `QT_TRANSLATE_NOOP`, which `lupdate`
//! reads along with the QML. `--check` fails when the file is out of date.

use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};

const SOURCES: &str = "desktop/app/src";
const OUT: &str = "desktop/app/i18n/rust_strings.h";

pub fn run(check: bool) -> Result<()> {
    let root = crate::repo_root();
    let mut files = Vec::new();
    collect(&root.join(SOURCES), &mut files)?;
    files.sort();
    // (context, text) -> the file it first appears in (no line: a line
    // moving would make the file stale).
    let mut strings: BTreeMap<(String, String), String> = BTreeMap::new();
    for file in &files {
        let source = fs::read_to_string(file).with_context(|| format!("reading {}", file.display()))?;
        let shown = file.strip_prefix(&root).unwrap_or(file).to_string_lossy().replace('\\', "/");
        for (_, context, text) in find(&source).with_context(|| format!("in {shown}"))? {
            // The unit tests' own strings aren't the app's.
            if context != "Tests" {
                strings.entry((context, text)).or_insert_with(|| shown.clone());
            }
        }
    }
    let content = render(&strings);
    let out = root.join(OUT);
    if check {
        if fs::read_to_string(&out).unwrap_or_default() != content {
            bail!("out of date: {OUT}; run `cargo xtask strings`");
        }
        println!("{OUT} is up to date ({} strings)", strings.len());
    } else {
        fs::write(&out, content).with_context(|| format!("writing {OUT}"))?;
        println!("wrote {OUT} ({} strings)", strings.len());
    }
    Ok(())
}

fn collect(dir: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
    for entry in fs::read_dir(dir).with_context(|| format!("reading {}", dir.display()))? {
        let path = entry?.path();
        if path.is_dir() {
            collect(&path, files)?;
        } else if path.extension().is_some_and(|e| e == "rs") {
            files.push(path);
        }
    }
    Ok(())
}

/// Every `tr!("Context", "Text"` in `source`: its line, context and text.
fn find(source: &str) -> Result<Vec<(usize, String, String)>> {
    let mut found = Vec::new();
    let mut rest = source;
    let mut offset = 0;
    while let Some(at) = rest.find("tr!(") {
        // Not a longer name ending in "tr" (e.g. `str!(`).
        let before = source[..offset + at].chars().next_back();
        let start = offset + at + "tr!(".len();
        offset = start;
        rest = &source[start..];
        if before.is_some_and(|c| c.is_alphanumeric() || c == '_') {
            continue;
        }
        // Not in a comment (a doc example).
        let line_start = source[..start].rfind('\n').map_or(0, |i| i + 1);
        if source[line_start..start].contains("//") {
            continue;
        }
        let line = source[..start].matches('\n').count() + 1;
        let (context, after) =
            literal(rest).with_context(|| format!("line {line}: tr! needs a context literal"))?;
        let after = after.trim_start().strip_prefix(',').context("tr! needs a text")?;
        let (text, _) = literal(after).with_context(|| format!("line {line}: tr! needs a text literal"))?;
        found.push((line, context, text));
    }
    Ok(found)
}

/// A Rust string literal at the start of `s` (after whitespace), unescaped,
/// and what follows it.
fn literal(s: &str) -> Result<(String, &str)> {
    let s = s.trim_start();
    let body = s.strip_prefix('"').context("not a string literal")?;
    let mut out = String::new();
    let mut chars = body.char_indices();
    while let Some((i, c)) = chars.next() {
        match c {
            '"' => return Ok((out, &body[i + 1..])),
            '\\' => match chars.next().map(|(_, e)| e) {
                Some('n') => out.push('\n'),
                Some('t') => out.push('\t'),
                Some('"') => out.push('"'),
                Some('\'') => out.push('\''),
                Some('\\') => out.push('\\'),
                Some('\n') => {
                    // A line continuation: skip the next line's indentation.
                    while chars.clone().next().is_some_and(|(_, c)| c.is_whitespace()) {
                        chars.next();
                    }
                }
                other => bail!("unsupported escape {other:?}"),
            },
            c => out.push(c),
        }
    }
    bail!("unterminated string literal")
}

fn c_string(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn render(strings: &BTreeMap<(String, String), String>) -> String {
    let mut out = String::from(
        "// SPDX-License-Identifier: GPL-3.0-or-later\n\
         // Generated by `cargo xtask strings` from the tr! calls in desktop/app/src. Do not edit.\n\
         // Never compiled: lupdate reads it with the QML, so the text the app builds\n\
         // in Rust is translated like the rest (see desktop/app/src/i18n.rs).\n\
         \n\
         static const char *const maclink_rust_strings[] = {\n",
    );
    for ((context, text), at) in strings {
        out.push_str(&format!("    QT_TRANSLATE_NOOP({}, {}), // {at}\n", c_string(context), c_string(text)));
    }
    out.push_str("};\n");
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_tr_calls_with_their_text() {
        let source = r#"
            show_message(tr!("Media", "That player can't do that."));
            let x = tr!("Links", "Sent to %1", name);
            let s = my_str!("not this");
            /// An example: tr!("Docs", "not this either")
            tr!(
                "Mic",
                "Plays into \"%1\"",
                device
            );
        "#;
        let found = find(source).unwrap();
        assert_eq!(
            found,
            vec![
                (2, "Media".into(), "That player can't do that.".into()),
                (3, "Links".into(), "Sent to %1".into()),
                (6, "Mic".into(), "Plays into \"%1\"".into()),
            ]
        );
    }

    #[test]
    fn the_header_escapes_for_c() {
        let mut strings = BTreeMap::new();
        strings.insert(("Ctx".to_owned(), "Say \"hi\"\\".to_owned()), "a.rs".to_owned());
        assert!(render(&strings).contains(r#"QT_TRANSLATE_NOOP("Ctx", "Say \"hi\"\\"), // a.rs"#));
    }
}
