//! Scanning a library folder into a flat list of entries.

use std::path::Path;
use std::time::UNIX_EPOCH;

use walkdir::{DirEntry, WalkDir};

use crate::error::{Error, IoContext, Result};

/// A folder or Markdown note inside the library, relative to its root.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    /// `/`-separated path relative to the library root.
    pub relative_path: String,
    pub is_dir: bool,
    /// Last modification time, milliseconds since the Unix epoch.
    pub modified_ms: i64,
}

/// Whether a path names a Markdown note (by extension, case-insensitive).
pub fn is_markdown(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| e.eq_ignore_ascii_case("md") || e.eq_ignore_ascii_case("markdown"))
}

/// Whether any component of `path` (relative to `root`) is hidden (starts with `.`).
pub fn is_hidden_within(root: &Path, path: &Path) -> bool {
    path.strip_prefix(root)
        .unwrap_or(path)
        .components()
        .any(|c| c.as_os_str().to_string_lossy().starts_with('.'))
}

fn is_hidden(entry: &DirEntry) -> bool {
    entry.depth() > 0 && entry.file_name().to_string_lossy().starts_with('.')
}

/// Lists all non-hidden folders and Markdown notes under `root`, sorted by path.
/// Symlinks are not followed.
pub fn scan(root: &Path) -> Result<Vec<Entry>> {
    if !root.is_dir() {
        return Err(Error::Io {
            path: root.to_path_buf(),
            source: std::io::Error::new(std::io::ErrorKind::NotFound, "not a directory"),
        });
    }
    let mut entries = Vec::new();
    for item in WalkDir::new(root).min_depth(1).into_iter().filter_entry(|e| !is_hidden(e)) {
        let item = match item {
            Ok(item) => item,
            // Unreadable subfolders shouldn't make the whole library fail.
            Err(_) => continue,
        };
        let file_type = item.file_type();
        let is_dir = file_type.is_dir();
        if !is_dir && !(file_type.is_file() && is_markdown(item.path())) {
            continue;
        }
        let meta = item.metadata().map_err(std::io::Error::from).at(item.path())?;
        let modified_ms = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map_or(0, |d| d.as_millis() as i64);
        let rel = item.path().strip_prefix(root).expect("walkdir yields paths under root");
        let relative_path = rel
            .components()
            .map(|c| c.as_os_str().to_string_lossy())
            .collect::<Vec<_>>()
            .join("/");
        entries.push(Entry { relative_path, is_dir, modified_ms });
    }
    entries.sort_by(|a, b| a.relative_path.cmp(&b.relative_path));
    Ok(entries)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn scan_lists_folders_and_markdown_only() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        fs::create_dir_all(root.join("Projects/Empty")).unwrap();
        fs::create_dir_all(root.join(".git")).unwrap();
        fs::write(root.join(".git/HEAD.md"), "").unwrap();
        fs::write(root.join(".hidden.md"), "").unwrap();
        fs::write(root.join("Inbox.md"), "# hi").unwrap();
        fs::write(root.join("photo.png"), "").unwrap();
        fs::write(root.join("Projects/Plan.MARKDOWN"), "").unwrap();

        let paths: Vec<_> = scan(root)
            .unwrap()
            .into_iter()
            .map(|e| (e.relative_path, e.is_dir))
            .collect();
        assert_eq!(
            paths,
            vec![
                ("Inbox.md".into(), false),
                ("Projects".into(), true),
                ("Projects/Empty".into(), true),
                ("Projects/Plan.MARKDOWN".into(), false),
            ]
        );
    }

    #[test]
    fn scan_reports_modification_time() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("a.md"), "").unwrap();
        let entries = scan(dir.path()).unwrap();
        assert!(entries[0].modified_ms > 1_600_000_000_000);
    }

    #[test]
    fn scan_fails_for_missing_root() {
        assert!(scan(Path::new("/definitely/not/here")).is_err());
    }
}
