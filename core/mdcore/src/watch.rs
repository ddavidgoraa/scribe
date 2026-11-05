//! Recursive, debounced watching of a library folder.

use std::path::{Path, PathBuf};
use std::time::Duration;

use notify_debouncer_full::notify::{RecommendedWatcher, RecursiveMode};
use notify_debouncer_full::{new_debouncer, DebounceEventResult, Debouncer, RecommendedCache};

use crate::error::{Error, Result};
use crate::library::is_hidden_within;

const DEBOUNCE: Duration = Duration::from_millis(250);

/// Watches a folder; dropping it stops watching.
pub struct Watcher {
    _debouncer: Debouncer<RecommendedWatcher, RecommendedCache>,
}

impl Watcher {
    /// Calls `on_changes` (on a background thread) with the deduplicated, sorted
    /// absolute paths that changed. Hidden paths (e.g. `.git`, our own temp files) are ignored.
    pub fn new<F>(root: &Path, on_changes: F) -> Result<Self>
    where
        F: Fn(Vec<PathBuf>) + Send + 'static,
    {
        let root_owned = root.to_path_buf();
        let mut debouncer = new_debouncer(DEBOUNCE, None, move |result: DebounceEventResult| {
            let Ok(events) = result else { return };
            let mut paths: Vec<PathBuf> = events
                .into_iter()
                .flat_map(|e| e.event.paths)
                .filter(|p| !is_hidden_within(&root_owned, p))
                .collect();
            paths.sort();
            paths.dedup();
            if !paths.is_empty() {
                on_changes(paths);
            }
        })
        .map_err(|e| Error::Watch(e.to_string()))?;
        debouncer
            .watch(root, RecursiveMode::Recursive)
            .map_err(|e| Error::Watch(e.to_string()))?;
        Ok(Self { _debouncer: debouncer })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    #[test]
    fn reports_changes_but_not_hidden_files() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().canonicalize().unwrap();
        let (tx, rx) = mpsc::channel();
        let _w = Watcher::new(&root, move |paths| {
            let _ = tx.send(paths);
        })
        .unwrap();
        std::thread::sleep(Duration::from_millis(200));
        std::fs::write(root.join(".ignored.md"), "x").unwrap();
        std::fs::write(root.join("note.md"), "x").unwrap();

        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        let mut seen = Vec::new();
        while std::time::Instant::now() < deadline && !seen.iter().any(|p: &PathBuf| p.ends_with("note.md")) {
            if let Ok(paths) = rx.recv_timeout(Duration::from_millis(500)) {
                seen.extend(paths);
            }
        }
        assert!(seen.iter().any(|p| p.ends_with("note.md")), "saw {seen:?}");
        assert!(!seen.iter().any(|p| p.ends_with(".ignored.md")));
    }
}
