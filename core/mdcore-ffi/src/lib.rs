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

// MARK: Markdown

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum SpanKind {
    Heading { level: u8 },
    BlockQuote,
    CodeBlock,
    MathBlock,
    Table,
    ThematicBreak,
    ListItem,
    TaskMarker { checked: bool },
    Html,
    FootnoteDefinition,
    Emphasis,
    Strong,
    Strikethrough,
    Code,
    Math,
    Link,
    Image,
    FootnoteReference,
}

impl From<mdcore::markdown::Kind> for SpanKind {
    fn from(kind: mdcore::markdown::Kind) -> Self {
        use mdcore::markdown::Kind as K;
        match kind {
            K::Heading(level) => Self::Heading { level },
            K::BlockQuote => Self::BlockQuote,
            K::CodeBlock => Self::CodeBlock,
            K::MathBlock => Self::MathBlock,
            K::Table => Self::Table,
            K::ThematicBreak => Self::ThematicBreak,
            K::ListItem => Self::ListItem,
            K::TaskMarker { checked } => Self::TaskMarker { checked },
            K::Html => Self::Html,
            K::FootnoteDefinition => Self::FootnoteDefinition,
            K::Emphasis => Self::Emphasis,
            K::Strong => Self::Strong,
            K::Strikethrough => Self::Strikethrough,
            K::Code => Self::Code,
            K::Math => Self::Math,
            K::Link => Self::Link,
            K::Image => Self::Image,
            K::FootnoteReference => Self::FootnoteReference,
        }
    }
}

/// Half-open range in UTF-16 code units (NSString offsets).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Utf16Range {
    pub start: u32,
    pub end: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct MarkdownSpan {
    pub kind: SpanKind,
    pub range: Utf16Range,
    /// Syntax characters (`**`, `# `, `](url)`, …) inside `range`.
    pub markers: Vec<Utf16Range>,
}

fn utf16_range(r: std::ops::Range<usize>) -> Utf16Range {
    Utf16Range { start: r.start as u32, end: r.end as u32 }
}

/// Styled spans of `text` in document order (parents before children).
#[uniffi::export]
pub fn parse_markdown(text: String) -> Vec<MarkdownSpan> {
    mdcore::markdown::parse(&text)
        .into_iter()
        .map(|s| MarkdownSpan {
            kind: s.kind.into(),
            range: utf16_range(s.range),
            markers: s.markers.into_iter().map(utf16_range).collect(),
        })
        .collect()
}

// MARK: Search

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FuzzyMatch {
    /// Index into the candidates passed in.
    pub index: u32,
    pub score: u32,
    /// Matched positions (UTF-16 offsets) for highlighting.
    pub positions: Vec<u32>,
}

/// Fuzzy-ranks `candidates` (relative paths) for quick open, best first.
#[uniffi::export]
pub fn fuzzy_match(candidates: Vec<String>, query: String, limit: u32) -> Vec<FuzzyMatch> {
    mdcore::search::fuzzy(&candidates, &query, limit as usize)
        .into_iter()
        .map(|m| FuzzyMatch {
            index: m.index as u32,
            score: m.score,
            positions: m.positions.into_iter().map(|p| p as u32).collect(),
        })
        .collect()
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SearchLine {
    pub line: u32,
    pub snippet: String,
    /// Matches within `snippet`.
    pub ranges: Vec<Utf16Range>,
    /// First match in the whole note.
    pub match_range: Utf16Range,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SearchHit {
    pub relative_path: String,
    pub title_match: bool,
    pub lines: Vec<SearchLine>,
}

/// Full-text index of a library. Thread-safe; search from a background thread.
#[derive(uniffi::Object)]
pub struct SearchIndex {
    inner: Mutex<mdcore::search::Index>,
}

#[uniffi::export]
impl SearchIndex {
    #[uniffi::constructor]
    pub fn new(root: String) -> Arc<Self> {
        Arc::new(Self { inner: Mutex::new(mdcore::search::Index::new(Path::new(&root))) })
    }

    /// Reloads notes changed on disk since the last refresh.
    pub fn refresh(&self) -> Result<()> {
        Ok(self.inner.lock().unwrap().refresh()?)
    }

    pub fn search(&self, query: String, limit: u32) -> Vec<SearchHit> {
        self.inner
            .lock()
            .unwrap()
            .search(&query, limit as usize)
            .into_iter()
            .map(|h| SearchHit {
                relative_path: h.relative_path,
                title_match: h.title_match,
                lines: h
                    .lines
                    .into_iter()
                    .map(|l| SearchLine {
                        line: l.line as u32,
                        snippet: l.snippet,
                        ranges: l.ranges.into_iter().map(utf16_range).collect(),
                        match_range: utf16_range(l.offset..l.offset + l.length),
                    })
                    .collect(),
            })
            .collect()
    }
}

// MARK: HTML

/// Renders Markdown to an HTML fragment.
#[uniffi::export]
pub fn markdown_to_html(markdown: String) -> String {
    mdcore::html::to_html(&markdown)
}
