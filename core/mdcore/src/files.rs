//! Reading, writing, creating and renaming notes.

use std::fs::{self, OpenOptions};
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};

use pulldown_cmark::{Event, Options, Parser};
use unicode_normalization::UnicodeNormalization;

use crate::error::{Error, IoContext, Result};

const UNTITLED: &str = "Untitled";
const MAX_TITLE_CHARS: usize = 80;

/// Reads a note as UTF-8 (invalid sequences are replaced, never fatal).
pub fn read(path: &Path) -> Result<String> {
    let bytes = fs::read(path).at(path)?;
    Ok(match String::from_utf8(bytes) {
        Ok(s) => s,
        Err(e) => String::from_utf8_lossy(e.as_bytes()).into_owned(),
    })
}

/// Writes atomically: a hidden temp file in the same folder, then rename over the target.
/// Readers (and file watchers) never see a half-written note.
pub fn write_atomic(path: &Path, contents: &str) -> Result<()> {
    let dir = path.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
    let mut tmp = tempfile::Builder::new()
        .prefix(".scribe-")
        .suffix(".tmp")
        .tempfile_in(dir)
        .at(dir)?;
    tmp.write_all(contents.as_bytes()).at(tmp.path())?;
    tmp.as_file().sync_all().at(tmp.path())?;
    if let Ok(meta) = fs::metadata(path) {
        // Keep the original file's permissions.
        let _ = fs::set_permissions(tmp.path(), meta.permissions());
    }
    tmp.persist(path).map_err(|e| Error::Io { path: path.to_path_buf(), source: e.error })?;
    Ok(())
}

/// Creates an empty `Untitled.md` (or `Untitled 2.md`, …) in `dir` and returns its path.
pub fn create_untitled(dir: &Path) -> Result<PathBuf> {
    for n in 1.. {
        let path = dir.join(numbered(UNTITLED, n, "md"));
        match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(_) => return Ok(path),
            Err(e) if e.kind() == ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(Error::Io { path, source: e }),
        }
    }
    unreachable!()
}

/// Derives a file name stem from a note's first non-empty line: the text a reader
/// sees, without Markdown syntax (`# **Trip** to [Kraków](…)` → `Trip to Kraków`),
/// with characters unsafe in file names replaced.
pub fn title_from_text(text: &str) -> Option<String> {
    let line = first_line(text)?;
    sanitize_stem(&plain_text(line)).or_else(|| legacy_title(line))
}

/// How titles were derived before Markdown syntax was removed (only `#` stripped).
/// Notes named that way still count as following their first line, so they are
/// renamed to the clean title on their next save.
fn legacy_title(line: &str) -> Option<String> {
    sanitize_stem(line.trim_start_matches('#').trim())
}

fn first_line(text: &str) -> Option<&str> {
    text.lines().map(str::trim).find(|l| !l.is_empty())
}

/// The visible text of one line of Markdown: emphasis, code, link and math syntax,
/// heading, list, quote and task markers removed; link and image text kept.
fn plain_text(line: &str) -> String {
    let options = Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_TASKLISTS
        | Options::ENABLE_MATH
        | Options::ENABLE_GFM;
    let mut out = String::new();
    for event in Parser::new_ext(line, options) {
        match event {
            Event::Text(t) | Event::Code(t) | Event::InlineMath(t) | Event::DisplayMath(t) => out.push_str(&t),
            Event::SoftBreak | Event::HardBreak => out.push(' '),
            _ => {}
        }
    }
    out
}

/// Whether a note's file name should follow its first line.
///
/// Comparison ignores Unicode normalization: macOS file APIs often hand back
/// decomposed (NFD) names while typed text is composed (NFC).
///
/// Stateless, so it survives restarts and syncing: true when the stem is
/// `Untitled` / `Untitled N`, or equals the title derived from `text`
/// (optionally with a ` N` collision suffix). A note renamed by hand to something
/// else stops following automatically.
pub fn follows_first_line(stem: &str, text: &str) -> bool {
    let stem: String = stem.nfc().collect();
    let stem = stem.as_str();
    if strip_number_suffix(stem) == UNTITLED {
        return true;
    }
    let base = strip_number_suffix(stem);
    let matches = |title: Option<String>| title.is_some_and(|t| stem == t || base == t);
    let line = first_line(text);
    matches(title_from_text(text)) || matches(line.and_then(legacy_title))
}

/// `"Ideas 2"` → `"Ideas"`; numbers below 2 and non-numeric suffixes are kept.
fn strip_number_suffix(stem: &str) -> &str {
    match stem.rsplit_once(' ') {
        Some((base, n)) if n.parse::<u32>().is_ok_and(|n| n >= 2) && !n.starts_with('0') => base,
        _ => stem,
    }
}

/// Renames a note to `new_stem` + its current extension, in the same folder.
/// Appends ` 2`, ` 3`, … if the name is taken. Returns the new path.
pub fn rename(path: &Path, new_stem: &str) -> Result<PathBuf> {
    let stem = sanitize_stem(new_stem).ok_or_else(|| Error::InvalidName(new_stem.to_string()))?;
    let dir = path.parent().unwrap_or(Path::new("."));
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("md");
    for n in 1.. {
        let target = dir.join(numbered(&stem, n, ext));
        if target == path {
            return Ok(target);
        }
        if target.exists() && !same_file(&target, path) {
            continue;
        }
        // Same file differing only in case (case-insensitive FS) or a free name.
        fs::rename(path, &target).at(path)?;
        return Ok(target);
    }
    unreachable!()
}

// MARK: Assets (pasted / dropped images)

const ASSETS_DIR: &str = "assets";

/// Saves image `bytes` as `assets/<note>-<timestamp>.<ext>` next to `note`.
/// `timestamp` is supplied by the caller (local time, e.g. `20261109-143005`).
pub fn save_asset(note: &Path, bytes: &[u8], extension: &str, timestamp: &str) -> Result<PathBuf> {
    let (path, mut file) = create_asset_file(note, extension, timestamp)?;
    file.write_all(bytes).at(&path)?;
    Ok(path)
}

/// Copies the file at `source` into the note's `assets/` folder (same naming as `save_asset`).
pub fn import_asset(note: &Path, source: &Path, timestamp: &str) -> Result<PathBuf> {
    let extension = source
        .extension()
        .and_then(|e| e.to_str())
        .map(str::to_lowercase)
        .unwrap_or_else(|| "png".into());
    let (path, file) = create_asset_file(note, &extension, timestamp)?;
    drop(file);
    fs::copy(source, &path).at(source)?;
    Ok(path)
}

/// Reserves a fresh, unique file in `<note dir>/assets/`.
fn create_asset_file(note: &Path, extension: &str, timestamp: &str) -> Result<(PathBuf, fs::File)> {
    let dir = note.parent().unwrap_or(Path::new(".")).join(ASSETS_DIR);
    fs::create_dir_all(&dir).at(&dir)?;
    let stem = note.file_stem().and_then(|s| s.to_str()).unwrap_or("");
    let base = format!("{}-{}", slug(stem), slug(timestamp));
    let ext = extension.trim_start_matches('.').to_lowercase();
    for n in 1.. {
        let name = if n == 1 { format!("{base}.{ext}") } else { format!("{base}-{n}.{ext}") };
        let path = dir.join(name);
        match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(file) => return Ok((path, file)),
            Err(e) if e.kind() == ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(Error::Io { path, source: e }),
        }
    }
    unreachable!()
}

/// File-name-friendly form: letters, digits, `-`, `_`; whitespace becomes `-`.
fn slug(raw: &str) -> String {
    let mut out = String::new();
    for c in raw.nfc() {
        if c.is_alphanumeric() || c == '_' {
            out.push(c);
        } else if (c.is_whitespace() || c == '-' || c == '.') && !out.ends_with('-') && !out.is_empty() {
            out.push('-');
        }
    }
    let trimmed = out.trim_end_matches('-').to_string();
    if trimmed.is_empty() { "image".into() } else { trimmed }
}

/// Markdown link target from `from_dir` to `target`: relative, `/`-separated,
/// with characters that would break the link (spaces, parentheses, `<>`) escaped.
pub fn relative_link(from_dir: &Path, target: &Path) -> String {
    let from: Vec<_> = from_dir.components().collect();
    let to: Vec<_> = target.components().collect();
    let common = from.iter().zip(&to).take_while(|(a, b)| a == b).count();
    let mut parts: Vec<String> = std::iter::repeat_n("..".to_string(), from.len() - common).collect();
    parts.extend(to[common..].iter().map(|c| c.as_os_str().to_string_lossy().into_owned()));
    let mut link = String::new();
    for c in parts.join("/").chars() {
        match c {
            ' ' => link.push_str("%20"),
            '(' => link.push_str("%28"),
            ')' => link.push_str("%29"),
            '<' => link.push_str("%3C"),
            '>' => link.push_str("%3E"),
            c => link.push(c),
        }
    }
    link
}

fn numbered(stem: &str, n: u32, ext: &str) -> String {
    if n == 1 { format!("{stem}.{ext}") } else { format!("{stem} {n}.{ext}") }
}

fn same_file(a: &Path, b: &Path) -> bool {
    match (fs::canonicalize(a), fs::canonicalize(b)) {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    }
}

fn sanitize_stem(raw: &str) -> Option<String> {
    let cleaned: String = raw
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' => '-',
            c if c.is_control() => ' ',
            c => c,
        })
        .collect();
    let cleaned: String = cleaned.nfc().collect();
    let collapsed = cleaned.split_whitespace().collect::<Vec<_>>().join(" ");
    let trimmed = collapsed.trim_start_matches('.').trim();
    let truncated: String = trimmed.chars().take(MAX_TITLE_CHARS).collect();
    let result = truncated.trim_end().to_string();
    (!result.is_empty()).then_some(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn write_then_read_roundtrip_leaves_no_temp_files() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("note.md");
        write_atomic(&path, "# Zażółć\n").unwrap();
        write_atomic(&path, "# Gęślą jaźń\n").unwrap();
        assert_eq!(read(&path).unwrap(), "# Gęślą jaźń\n");
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
    }

    #[test]
    fn read_tolerates_invalid_utf8() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("bad.md");
        fs::write(&path, b"ok \xff end").unwrap();
        assert_eq!(read(&path).unwrap(), "ok \u{fffd} end");
    }

    #[test]
    fn create_untitled_numbers_files() {
        let dir = tempfile::tempdir().unwrap();
        let a = create_untitled(dir.path()).unwrap();
        let b = create_untitled(dir.path()).unwrap();
        assert_eq!(a.file_name().unwrap(), "Untitled.md");
        assert_eq!(b.file_name().unwrap(), "Untitled 2.md");
    }

    #[test]
    fn title_drops_markdown_syntax() {
        let cases = [
            ("Pierwsza **Notatka**", "Pierwsza Notatka"),
            ("# Trip to *Kraków*", "Trip to Kraków"),
            ("## __Bold__ and _italic_ and ~~gone~~", "Bold and italic and gone"),
            ("Call `run()` now", "Call run() now"),
            ("See [the plan](https://example.com/plan) today", "See the plan today"),
            ("![Sunset](assets/sun.png) photo", "Sunset photo"),
            ("Einstein: $E = mc^2$", "Einstein- E = mc^2"),
            ("- [ ] Buy tickets", "Buy tickets"),
            ("1. Morning train", "Morning train"),
            ("> Quoted idea", "Quoted idea"),
            ("<b>Hello</b> world", "Hello world"),
        ];
        for (line, title) in cases {
            assert_eq!(title_from_text(line).as_deref(), Some(title), "{line}");
        }
    }

    #[test]
    fn notes_named_before_syntax_removal_keep_following() {
        // Named by the old rule: they still follow, so the next save renames them.
        assert!(follows_first_line("Pierwsza **Notatka**", "Pierwsza **Notatka**\n\ntext"));
        assert!(follows_first_line("Pierwsza Notatka", "Pierwsza **Notatka**\n"));
        assert!(follows_first_line("Pierwsza Notatka 2", "Pierwsza **Notatka**\n"));
        assert!(!follows_first_line("Renamed by hand", "Pierwsza **Notatka**\n"));
    }

    #[test]
    fn title_from_first_nonempty_line() {
        assert_eq!(title_from_text("\n\n## Plan: Q1/Q2  \nbody").as_deref(), Some("Plan- Q1-Q2"));
        assert_eq!(title_from_text("...secret").as_deref(), Some("secret"));
        assert_eq!(title_from_text("   \n#  \n"), None);
        assert_eq!(title_from_text(&"x".repeat(200)).unwrap().chars().count(), MAX_TITLE_CHARS);
    }

    #[test]
    fn untitled_notes_follow_first_line() {
        assert!(follows_first_line("Untitled", ""));
        assert!(follows_first_line("Untitled 3", "# Anything"));
        assert!(!follows_first_line("Untitled 1", "# Anything"));
        assert!(!follows_first_line("Untitled draft", "# Anything"));
    }

    #[test]
    fn notes_named_after_first_line_keep_following() {
        assert!(follows_first_line("Shopping list", "# Shopping list\n- milk"));
        assert!(follows_first_line("Ideas 2", "Ideas"));
        assert!(follows_first_line("Plan- Q1-Q2", "## Plan: Q1/Q2"));
        assert!(!follows_first_line("Groceries", "# Shopping list"));
        assert!(!follows_first_line("Notes", ""));
    }

    #[test]
    fn follow_check_ignores_unicode_normalization() {
        let nfd_stem: String = "Trip to Kraków".nfd().collect();
        assert_ne!(nfd_stem, "Trip to Kraków");
        assert!(follows_first_line(&nfd_stem, "# Trip to Kraków"));
        let nfd_text: String = "# Zażółć".nfd().collect();
        assert_eq!(title_from_text(&nfd_text).as_deref(), Some("Zażółć"));
    }

    #[test]
    fn save_asset_names_after_note_and_avoids_collisions() {
        let dir = tempfile::tempdir().unwrap();
        let note = dir.path().join("Trip to Kraków.md");
        let a = save_asset(&note, b"png-bytes", "PNG", "20261109-143005").unwrap();
        let b = save_asset(&note, b"other", "png", "20261109-143005").unwrap();
        assert_eq!(a, dir.path().join("assets/Trip-to-Kraków-20261109-143005.png"));
        assert_eq!(b.file_name().unwrap(), "Trip-to-Kraków-20261109-143005-2.png");
        assert_eq!(fs::read(&a).unwrap(), b"png-bytes");
    }

    #[test]
    fn import_asset_copies_and_keeps_extension() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("Photo.JPEG");
        fs::write(&source, b"jpeg").unwrap();
        let note = dir.path().join("notes/Untitled.md");
        let copied = import_asset(&note, &source, "t1").unwrap();
        assert_eq!(copied, dir.path().join("notes/assets/Untitled-t1.jpeg"));
        assert_eq!(fs::read(&copied).unwrap(), b"jpeg");
        assert!(source.exists(), "original untouched");
    }

    #[test]
    fn slug_handles_odd_names() {
        assert_eq!(slug("  My note: (draft) v2 "), "My-note-draft-v2");
        assert_eq!(slug("..."), "image");
        assert_eq!(slug("Zażółć gęślą"), "Zażółć-gęślą");
    }

    #[test]
    fn relative_links() {
        let root = Path::new("/lib");
        assert_eq!(relative_link(&root.join("notes"), &root.join("notes/assets/a b.png")), "assets/a%20b.png");
        assert_eq!(relative_link(&root.join("notes/deep"), &root.join("img/x (1).png")), "../../img/x%20%281%29.png");
        assert_eq!(relative_link(root, &root.join("x.png")), "x.png");
    }

    #[test]
    fn rename_avoids_collisions_and_keeps_extension() {
        let dir = tempfile::tempdir().unwrap();
        let taken = dir.path().join("Ideas.markdown");
        fs::write(&taken, "").unwrap();
        let src = dir.path().join("Untitled.markdown");
        fs::write(&src, "x").unwrap();
        let new = rename(&src, "Ideas").unwrap();
        assert_eq!(new.file_name().unwrap(), "Ideas 2.markdown");
        assert_eq!(read(&new).unwrap(), "x");
        assert!(!src.exists());
    }

    #[test]
    fn rename_to_same_name_is_noop_and_case_change_works() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("notes.md");
        fs::write(&src, "").unwrap();
        assert_eq!(rename(&src, "notes").unwrap(), src);
        let new = rename(&src, "Notes").unwrap();
        assert_eq!(new.file_name().unwrap(), "Notes.md");
        let names: Vec<_> = fs::read_dir(dir.path()).unwrap().map(|e| e.unwrap().file_name()).collect();
        assert_eq!(names, vec!["Notes.md"]);
    }

    #[test]
    fn rename_rejects_empty_names() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("a.md");
        fs::write(&src, "").unwrap();
        assert!(matches!(rename(&src, " .. "), Err(Error::InvalidName(_))));
    }
}
