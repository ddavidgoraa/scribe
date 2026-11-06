//! UniFFI bindings exposing `mdcore` to Swift.

use std::path::Path;
use std::sync::{Arc, Mutex};

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("{message}")]
    Io { message: String },
    #[error("{message}")]
    InvalidName { message: String },
    #[error("{message}")]
    Watch { message: String },
}

impl From<mdcore::Error> for CoreError {
    fn from(e: mdcore::Error) -> Self {
        let message = e.to_string();
        match e {
            mdcore::Error::Io { .. } => Self::Io { message },
            mdcore::Error::InvalidName(_) => Self::InvalidName { message },
            mdcore::Error::Watch(_) => Self::Watch { message },
        }
    }
}

type Result<T> = std::result::Result<T, CoreError>;

#[uniffi::export]
pub fn core_version() -> String {
    mdcore::version().to_string()
}

#[uniffi::export]
pub fn greet(name: String) -> String {
    mdcore::greet(&name)
}

// MARK: Library

#[derive(uniffi::Record)]
pub struct LibraryEntry {
    /// `/`-separated path relative to the library root.
    pub relative_path: String,
    pub is_dir: bool,
    pub modified_ms: i64,
}

/// Lists non-hidden folders and Markdown notes under `root`, sorted by path.
#[uniffi::export]
pub fn scan_library(root: String) -> Result<Vec<LibraryEntry>> {
    Ok(mdcore::library::scan(Path::new(&root))?
        .into_iter()
        .map(|e| LibraryEntry { relative_path: e.relative_path, is_dir: e.is_dir, modified_ms: e.modified_ms })
        .collect())
}

// MARK: Files

#[uniffi::export]
pub fn read_note(path: String) -> Result<String> {
    Ok(mdcore::files::read(Path::new(&path))?)
}

/// Atomic write (temp file + rename).
#[uniffi::export]
pub fn write_note(path: String, contents: String) -> Result<()> {
    Ok(mdcore::files::write_atomic(Path::new(&path), &contents)?)
}

/// Creates `Untitled.md` / `Untitled N.md` in `dir`; returns its path.
#[uniffi::export]
pub fn create_untitled_note(dir: String) -> Result<String> {
    Ok(path_string(mdcore::files::create_untitled(Path::new(&dir))?))
}

/// Renames to `new_name` (stem, extension kept), avoiding collisions; returns the new path.
#[uniffi::export]
pub fn rename_note(path: String, new_name: String) -> Result<String> {
    Ok(path_string(mdcore::files::rename(Path::new(&path), &new_name)?))
}

/// File name stem derived from the first non-empty line, if any.
#[uniffi::export]
pub fn title_from_text(text: String) -> Option<String> {
    mdcore::files::title_from_text(&text)
}

/// Whether a note named `file_stem` (no extension) with contents `text` should be
/// auto-renamed when its first line changes.
#[uniffi::export]
pub fn follows_first_line(file_stem: String, text: String) -> bool {
    mdcore::files::follows_first_line(&file_stem, &text)
}

fn path_string(p: std::path::PathBuf) -> String {
    p.to_string_lossy().into_owned()
}

// MARK: Watching

/// Implemented in Swift; called on a background thread.
#[uniffi::export(with_foreign)]
pub trait LibraryListener: Send + Sync {
    fn on_changes(&self, paths: Vec<String>);
}

#[derive(uniffi::Object)]
pub struct LibraryWatcher {
    inner: Mutex<Option<mdcore::watch::Watcher>>,
}

#[uniffi::export]
impl LibraryWatcher {
    #[uniffi::constructor]
    pub fn new(root: String, listener: Arc<dyn LibraryListener>) -> Result<Arc<Self>> {
        let watcher = mdcore::watch::Watcher::new(Path::new(&root), move |paths| {
            listener.on_changes(paths.into_iter().map(path_string).collect());
        })?;
        Ok(Arc::new(Self { inner: Mutex::new(Some(watcher)) }))
    }

    /// Stops watching. Also happens when the object is released.
    pub fn stop(&self) {
        self.inner.lock().unwrap().take();
    }
}
