//! Quick open (fuzzy file names) and full-text search over a library.

use std::collections::HashMap;
use std::ops::Range;
use std::path::{Path, PathBuf};

use nucleo_matcher::pattern::{CaseMatching, Normalization, Pattern};
use nucleo_matcher::{Config, Matcher, Utf32Str};
use unicode_normalization::UnicodeNormalization;
use unicode_segmentation::UnicodeSegmentation;

use crate::error::Result;
use crate::{files, library};

// MARK: Quick open

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FuzzyMatch {
    /// Index into the candidates passed in.
    pub index: usize,
    pub score: u32,
    /// Matched positions in the candidate, UTF-16 offsets, ascending.
    pub positions: Vec<usize>,
}

/// Ranks `candidates` (e.g. relative paths) against `query`, best first.
/// An empty query returns the first `limit` candidates in order.
pub fn fuzzy(candidates: &[String], query: &str, limit: usize) -> Vec<FuzzyMatch> {
    let query = query.trim();
    if query.is_empty() {
        return (0..candidates.len().min(limit))
            .map(|index| FuzzyMatch { index, score: 0, positions: vec![] })
            .collect();
    }
    let mut matcher = Matcher::new(Config::DEFAULT.match_paths());
    let pattern = Pattern::parse(query, CaseMatching::Ignore, Normalization::Smart);
    let mut buf = Vec::new();
    let mut indices = Vec::new();
    let mut matches: Vec<FuzzyMatch> = candidates
        .iter()
        .enumerate()
        .filter_map(|(index, candidate)| {
            indices.clear();
            let haystack = Utf32Str::new(candidate, &mut buf);
            let ascii = matches!(haystack, Utf32Str::Ascii(_));
            let score = pattern.indices(haystack, &mut matcher, &mut indices)?;
            indices.sort_unstable();
            indices.dedup();
            let positions = matcher_positions_to_utf16(candidate, &indices, ascii);
            Some(FuzzyMatch { index, score, positions })
        })
        .collect();
    // Higher score first; shorter paths win ties.
    matches.sort_by(|a, b| b.score.cmp(&a.score).then(candidates[a.index].len().cmp(&candidates[b.index].len())));
    matches.truncate(limit);
    matches
}

/// Nucleo indexes ASCII haystacks by byte and others by grapheme cluster.
fn matcher_positions_to_utf16(text: &str, indices: &[u32], ascii: bool) -> Vec<usize> {
    let starts: Vec<usize> = if ascii {
        text.char_indices().map(|(b, _)| b).collect::<Vec<_>>()
    } else {
        text.grapheme_indices(true).map(|(b, _)| b).collect()
    };
    let utf16_at = |byte: usize| text[..byte].encode_utf16().count();
    indices
        .iter()
        .filter_map(|&i| {
            if ascii {
                // Byte index; only valid on char boundaries.
                let i = i as usize;
                text.is_char_boundary(i).then(|| utf16_at(i))
            } else {
                starts.get(i as usize).map(|&b| utf16_at(b))
            }
        })
        .collect()
}

// MARK: Full-text search

/// Case- and diacritic-insensitive form used for matching (`Żółć` → `zolc`).
/// Returns the folded text and, for every folded byte, the UTF-16 offset of the
/// original character it came from (plus one entry for the end).
fn fold(text: &str) -> (String, Vec<usize>) {
    let mut folded = String::with_capacity(text.len());
    let mut map = Vec::with_capacity(text.len() + 1);
    let mut utf16 = 0;
    for c in text.chars() {
        for f in fold_char(c) {
            let before = folded.len();
            folded.push(f);
            map.extend(std::iter::repeat_n(utf16, folded.len() - before));
        }
        utf16 += c.len_utf16();
    }
    map.push(utf16);
    (folded, map)
}

fn fold_char(c: char) -> impl Iterator<Item = char> {
    let special = match c {
        'ł' | 'Ł' => Some('l'),
        'ß' => Some('s'),
        'đ' | 'Đ' => Some('d'),
        'ø' | 'Ø' => Some('o'),
        _ => None,
    };
    let chars: Vec<char> = match special {
        Some(s) => vec![s],
        None => c
            .to_lowercase()
            .flat_map(|l| l.nfd())
            .filter(|d| !unicode_normalization::char::is_combining_mark(*d))
            .collect(),
    };
    chars.into_iter()
}

fn fold_only(text: &str) -> String {
    text.chars().flat_map(fold_char).collect()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LineMatch {
    /// 0-based line number.
    pub line: usize,
    /// The line (trimmed to a window around the first match).
    pub snippet: String,
    /// Matches within `snippet`, UTF-16 offsets.
    pub ranges: Vec<Range<usize>>,
    /// UTF-16 offset of the first match in the whole note (to jump to it).
    pub offset: usize,
    /// Length of the first match, UTF-16 units.
    pub length: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hit {
    pub relative_path: String,
    pub title_match: bool,
    pub lines: Vec<LineMatch>,
}

struct Doc {
    modified_ms: i64,
    text: String,
    folded: String,
}

/// In-memory index of a library's notes. `refresh` reloads only changed files.
pub struct Index {
    root: PathBuf,
    docs: HashMap<String, Doc>,
}

const SNIPPET_CHARS: usize = 120;
const MAX_LINES_PER_FILE: usize = 5;

impl Index {
    pub fn new(root: &Path) -> Self {
        Self { root: root.to_path_buf(), docs: HashMap::new() }
    }

    /// Rescans the library, (re)reading notes whose modification time changed.
    pub fn refresh(&mut self) -> Result<()> {
        let entries = library::scan(&self.root)?;
        let mut seen = std::collections::HashSet::new();
        for entry in entries.into_iter().filter(|e| !e.is_dir) {
            seen.insert(entry.relative_path.clone());
            if self.docs.get(&entry.relative_path).is_some_and(|d| d.modified_ms == entry.modified_ms) {
                continue;
            }
            let Ok(text) = files::read(&self.root.join(&entry.relative_path)) else { continue };
            let folded = fold_only(&text);
            self.docs.insert(entry.relative_path, Doc { modified_ms: entry.modified_ms, text, folded });
        }
        self.docs.retain(|path, _| seen.contains(path));
        Ok(())
    }

    pub fn len(&self) -> usize {
        self.docs.len()
    }

    pub fn is_empty(&self) -> bool {
        self.docs.is_empty()
    }

    /// Notes containing every word of `query` (in their text or path), best first:
    /// path matches, then by number of matching lines.
    pub fn search(&self, query: &str, limit: usize) -> Vec<Hit> {
        let terms: Vec<String> = query.split_whitespace().map(fold_only).filter(|t| !t.is_empty()).collect();
        if terms.is_empty() {
            return vec![];
        }
        let mut hits: Vec<(usize, Hit)> = Vec::new();
        for (path, doc) in &self.docs {
            let folded_path = fold_only(path);
            if !terms.iter().all(|t| doc.folded.contains(t.as_str()) || folded_path.contains(t.as_str())) {
                continue;
            }
            let title_match = terms.iter().any(|t| folded_path.contains(t.as_str()));
            let (lines, total) = line_matches(&doc.text, &terms);
            let rank = if title_match { 1_000_000 } else { 0 } + total;
            hits.push((rank, Hit { relative_path: path.clone(), title_match, lines }));
        }
        hits.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.relative_path.cmp(&b.1.relative_path)));
        hits.into_iter().take(limit).map(|(_, h)| h).collect()
    }
}

/// Lines containing any term (first few), and the total number of matching lines.
fn line_matches(text: &str, terms: &[String]) -> (Vec<LineMatch>, usize) {
    let mut out = Vec::new();
    let mut total = 0;
    let mut line_start_utf16 = 0;
    for (number, line) in text.split('\n').enumerate() {
        let line_utf16 = line.encode_utf16().count();
        let (folded, map) = fold(line);
        let mut ranges: Vec<Range<usize>> = terms
            .iter()
            .flat_map(|t| folded.match_indices(t.as_str()).map(|(i, m)| map[i]..map[i + m.len()]))
            .collect();
        if !ranges.is_empty() {
            total += 1;
            if out.len() < MAX_LINES_PER_FILE {
                ranges.sort_by_key(|r| r.start);
                let first = ranges[0].clone();
                let (snippet, shift) = window(line, first.start);
                let snippet_len = snippet.encode_utf16().count();
                let shifted = ranges
                    .iter()
                    .filter(|r| r.start >= shift && r.end <= shift + snippet_len)
                    .map(|r| r.start - shift..r.end - shift)
                    .collect();
                out.push(LineMatch {
                    line: number,
                    snippet,
                    ranges: shifted,
                    offset: line_start_utf16 + first.start,
                    length: first.end - first.start,
                });
            }
        }
        line_start_utf16 += line_utf16 + 1;
    }
    (out, total)
}

/// A window of the line around UTF-16 offset `focus`; returns it and its UTF-16 start.
fn window(line: &str, focus: usize) -> (String, usize) {
    let units: Vec<u16> = line.trim_end_matches('\r').encode_utf16().collect();
    if units.len() <= SNIPPET_CHARS {
        let leading = units.iter().take_while(|&&u| u == b' ' as u16 || u == b'\t' as u16).count();
        return (String::from_utf16_lossy(&units[leading..]), leading);
    }
    let mut start = focus.saturating_sub(SNIPPET_CHARS / 3);
    let mut end = (start + SNIPPET_CHARS).min(units.len());
    // Don't split surrogate pairs.
    if start > 0 && (0xDC00..0xE000).contains(&units[start]) {
        start -= 1;
    }
    if end < units.len() && (0xDC00..0xE000).contains(&units[end]) {
        end += 1;
    }
    (String::from_utf16_lossy(&units[start..end]), start)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn fuzzy_ranks_paths() {
        let paths: Vec<String> = ["Projects/Scribe/Plan.md", "Inbox.md", "Personal/Plants.md", "Plan.md"]
            .map(String::from)
            .to_vec();
        let found = fuzzy(&paths, "plan", 10);
        let names: Vec<&str> = found.iter().map(|m| paths[m.index].as_str()).collect();
        assert_eq!(names[0], "Plan.md");
        assert!(names.contains(&"Projects/Scribe/Plan.md"));
        assert!(!names.contains(&"Inbox.md"));
        assert_eq!(found[0].positions, vec![0, 1, 2, 3]);
    }

    #[test]
    fn fuzzy_positions_are_utf16_for_unicode_paths() {
        let paths = vec!["Zażółć/Gęś.md".to_string()];
        let found = fuzzy(&paths, "ges", 10);
        assert_eq!(found.len(), 1, "diacritics are normalized");
        let units: Vec<u16> = paths[0].encode_utf16().collect();
        let picked: String = found[0].positions.iter().map(|&p| char::from_u32(units[p] as u32).unwrap()).collect();
        assert_eq!(picked.to_lowercase(), "gęś");
    }

    #[test]
    fn fuzzy_empty_query_lists_in_order() {
        let paths: Vec<String> = vec!["b".into(), "a".into()];
        assert_eq!(fuzzy(&paths, " ", 1).iter().map(|m| m.index).collect::<Vec<_>>(), vec![0]);
    }

    #[test]
    fn fold_strips_case_and_diacritics_and_maps_back() {
        let (folded, map) = fold("Żółć Łódź");
        assert_eq!(folded, "zolc lodz");
        assert_eq!(map[folded.find("lodz").unwrap()], 5);
        assert_eq!(*map.last().unwrap(), 9);
    }

    fn library() -> (tempfile::TempDir, Index) {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        fs::create_dir_all(root.join("Work")).unwrap();
        fs::write(root.join("Inbox.md"), "# Inbox\nKupić mleko i chleb.\nZadzwonić do Łukasza.\n").unwrap();
        fs::write(root.join("Work/Plan.md"), "Plan Q1\n- mleko? nie, migracja bazy\n").unwrap();
        fs::write(root.join("Work/notes.txt"), "mleko").unwrap();
        let mut index = Index::new(root);
        index.refresh().unwrap();
        (dir, index)
    }

    #[test]
    fn search_finds_lines_case_and_diacritic_insensitive() {
        let (_dir, index) = library();
        assert_eq!(index.len(), 2, "only Markdown files");
        let hits = index.search("lukasza", 10);
        assert_eq!(hits.len(), 1);
        let line = &hits[0].lines[0];
        assert_eq!(line.line, 2);
        assert_eq!(line.snippet, "Zadzwonić do Łukasza.");
        assert_eq!(line.ranges, vec![13..20]);
        let text = fs::read_to_string(_dir.path().join("Inbox.md")).unwrap();
        let units: Vec<u16> = text.encode_utf16().collect();
        assert_eq!(String::from_utf16(&units[line.offset..line.offset + line.length]).unwrap(), "Łukasza");
    }

    #[test]
    fn search_requires_all_terms_and_ranks_title_matches_first() {
        let (_dir, index) = library();
        let hits = index.search("MLEKO", 10);
        assert_eq!(hits.len(), 2);
        let hits = index.search("plan mleko", 10);
        assert_eq!(hits.len(), 1);
        assert!(hits[0].title_match);
        assert_eq!(hits[0].relative_path, "Work/Plan.md");
        assert!(index.search("   ", 10).is_empty());
    }

    #[test]
    fn refresh_picks_up_changes_and_deletions() {
        let (dir, mut index) = library();
        fs::remove_file(dir.path().join("Inbox.md")).unwrap();
        fs::write(dir.path().join("New.md"), "kosmos").unwrap();
        index.refresh().unwrap();
        assert!(index.search("chleb", 10).is_empty());
        assert_eq!(index.search("kosmos", 10).len(), 1);
    }

    #[test]
    fn long_lines_are_windowed_around_the_match() {
        let text = format!("{}needle{}", "a".repeat(300), "b".repeat(300));
        let (lines, _) = line_matches(&text, &["needle".to_string()]);
        let m = &lines[0];
        assert!(m.snippet.encode_utf16().count() <= SNIPPET_CHARS + 1);
        let units: Vec<u16> = m.snippet.encode_utf16().collect();
        assert_eq!(String::from_utf16(&units[m.ranges[0].clone()]).unwrap(), "needle");
        assert_eq!(m.offset, 300);
    }
}
