//! Reading, writing, creating and renaming notes.

use std::fs::{self, OpenOptions};
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};

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

/// Derives a file name stem from a note's first non-empty line
/// (heading markers stripped, characters unsafe in file names replaced).
pub fn title_from_text(text: &str) -> Option<String> {
    let line = text.lines().map(str::trim).find(|l| !l.is_empty())?;
    let line = line.trim_start_matches('#').trim();
    sanitize_stem(line)
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
    fn title_from_first_nonempty_line() {
        assert_eq!(title_from_text("\n\n## Plan: Q1/Q2  \nbody").as_deref(), Some("Plan- Q1-Q2"));
        assert_eq!(title_from_text("...secret").as_deref(), Some("secret"));
        assert_eq!(title_from_text("   \n#  \n"), None);
        assert_eq!(title_from_text(&"x".repeat(200)).unwrap().chars().count(), MAX_TITLE_CHARS);
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
