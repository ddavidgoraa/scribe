//! Markdown → styled spans for the editor.
//!
//! The editor never renders HTML: it decorates the source text. For every element we
//! report its full range and the ranges of its *markers* (syntax characters such as
//! `**`, `# `, `` ` ``, `](url)`), so the editor can dim them (M2) or hide them unless
//! the caret is inside the element (M3).
//!
//! All offsets are UTF-16 code units, matching `NSString` / `NSRange`.

use std::ops::Range;

use pulldown_cmark::{CodeBlockKind, Event, Options, Parser, Tag, TagEnd};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    // Blocks
    Heading(u8),
    BlockQuote,
    CodeBlock,
    MathBlock,
    Table,
    ThematicBreak,
    ListItem,
    TaskMarker { checked: bool },
    Html,
    FootnoteDefinition,
    // Inlines
    Emphasis,
    Strong,
    Strikethrough,
    Code,
    Math,
    Link,
    Image,
    FootnoteReference,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Span {
    pub kind: Kind,
    /// Whole element, UTF-16 offsets. Trailing newlines of blocks are excluded.
    pub range: Range<usize>,
    /// Syntax characters inside `range`, UTF-16 offsets, ascending.
    pub markers: Vec<Range<usize>>,
}

fn options() -> Options {
    Options::ENABLE_TABLES
        | Options::ENABLE_FOOTNOTES
        | Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_TASKLISTS
        | Options::ENABLE_MATH
        | Options::ENABLE_GFM
}

/// How marker ranges are derived for a container element.
#[derive(Clone, Copy, PartialEq)]
enum Markers {
    /// Opening (start → first child) and closing (last child → end) syntax.
    Wrap,
    /// Opening syntax only (list items, footnote definitions).
    Prefix,
    /// `>` at the start of each line.
    QuoteLines,
    /// `|` pipes and the delimiter row.
    TablePipes,
    None,
}

struct Frame {
    /// Index into the output, if this container is reported as a span.
    span: Option<usize>,
    mode: Markers,
    range: Range<usize>,
    first_child: Option<usize>,
    last_child_end: Option<usize>,
}

impl Frame {
    fn touch(&mut self, child: &Range<usize>) {
        self.first_child.get_or_insert(child.start);
        self.last_child_end = Some(child.end);
    }
}

/// Parses `text` and returns its styled spans in document order (parents before children).
pub fn parse(text: &str) -> Vec<Span> {
    let mut spans: Vec<Span> = Vec::new(); // byte offsets until the final conversion
    let mut stack: Vec<Frame> = Vec::new();

    for (event, range) in Parser::new_ext(text, options()).into_offset_iter() {
        if let Some(parent) = stack.last_mut() {
            if !matches!(event, Event::End(_)) {
                parent.touch(&range);
            }
        }
        match event {
            Event::Start(tag) => {
                let (kind, mode) = classify(&tag);
                let span = kind.map(|kind| {
                    spans.push(Span { kind, range: range.clone(), markers: Vec::new() });
                    spans.len() - 1
                });
                stack.push(Frame { span, mode, range, first_child: None, last_child_end: None });
            }
            Event::End(end) => {
                let Some(frame) = stack.pop() else { continue };
                if let Some(index) = frame.span {
                    let block = is_block(end);
                    let range = if block { trim_newlines(text, frame.range.clone()) } else { frame.range.clone() };
                    spans[index].markers = container_markers(text, &frame, range.clone());
                    spans[index].range = range;
                }
            }
            Event::Code(_) => spans.push(delimited(text, Kind::Code, range, b'`', usize::MAX)),
            Event::InlineMath(_) => spans.push(delimited(text, Kind::Math, range, b'$', 1)),
            Event::DisplayMath(_) => spans.push(delimited(text, Kind::MathBlock, range, b'$', 2)),
            Event::Rule => {
                let range = trim_newlines(text, range);
                spans.push(Span { kind: Kind::ThematicBreak, markers: vec![range.clone()], range });
            }
            Event::TaskListMarker(checked) => spans.push(Span {
                kind: Kind::TaskMarker { checked },
                markers: vec![range.clone()],
                range,
            }),
            Event::FootnoteReference(_) => {
                // `[^label]`
                let markers = vec![range.start..range.start + 2, range.end - 1..range.end];
                spans.push(Span { kind: Kind::FootnoteReference, range, markers });
            }
            Event::InlineHtml(_) => spans.push(Span { kind: Kind::Html, range, markers: vec![] }),
            _ => {}
        }
    }

    to_utf16(text, spans)
}

fn classify(tag: &Tag) -> (Option<Kind>, Markers) {
    match tag {
        Tag::Heading { level, .. } => (Some(Kind::Heading(*level as u8)), Markers::Wrap),
        Tag::BlockQuote(_) => (Some(Kind::BlockQuote), Markers::QuoteLines),
        Tag::CodeBlock(CodeBlockKind::Fenced(_)) => (Some(Kind::CodeBlock), Markers::Wrap),
        Tag::CodeBlock(CodeBlockKind::Indented) => (Some(Kind::CodeBlock), Markers::None),
        Tag::HtmlBlock => (Some(Kind::Html), Markers::None),
        Tag::Item => (Some(Kind::ListItem), Markers::Prefix),
        Tag::FootnoteDefinition(_) => (Some(Kind::FootnoteDefinition), Markers::Prefix),
        Tag::Table(_) => (Some(Kind::Table), Markers::TablePipes),
        Tag::Emphasis => (Some(Kind::Emphasis), Markers::Wrap),
        Tag::Strong => (Some(Kind::Strong), Markers::Wrap),
        Tag::Strikethrough => (Some(Kind::Strikethrough), Markers::Wrap),
        Tag::Link { .. } => (Some(Kind::Link), Markers::Wrap),
        Tag::Image { .. } => (Some(Kind::Image), Markers::Wrap),
        _ => (None, Markers::None),
    }
}

fn is_block(end: TagEnd) -> bool {
    matches!(
        end,
        TagEnd::Heading(_)
            | TagEnd::BlockQuote(_)
            | TagEnd::CodeBlock
            | TagEnd::HtmlBlock
            | TagEnd::Item
            | TagEnd::FootnoteDefinition
            | TagEnd::Table
    )
}

fn container_markers(text: &str, frame: &Frame, range: Range<usize>) -> Vec<Range<usize>> {
    let bytes = text.as_bytes();
    match frame.mode {
        Markers::None => vec![],
        Markers::Wrap | Markers::Prefix => {
            let (Some(first), Some(last)) = (frame.first_child, frame.last_child_end) else {
                // No content (e.g. `![](x)`, an empty fenced block): it's all syntax.
                return if range.is_empty() { vec![] } else { vec![range] };
            };
            let mut markers = Vec::new();
            if first > range.start {
                // Keep a trailing space (`# `, `- `) but not a newline (code fences).
                let prefix = trim_newlines(text, range.start..first.min(range.end));
                markers.push(prefix);
            }
            if frame.mode == Markers::Wrap && last < range.end {
                // Only the syntax itself: `###` of a closing sequence, `===` of a setext underline.
                let raw = &text[last..range.end];
                let start = last + (raw.len() - raw.trim_start().len());
                if start < range.end {
                    markers.push(start..range.end);
                }
            }
            markers
        }
        Markers::QuoteLines => {
            let mut markers = Vec::new();
            for line in line_starts(text, &range) {
                let mut i = line;
                while i < range.end && bytes[i] == b' ' {
                    i += 1;
                }
                let start = i;
                // One level only: a nested quote reports its own `>`.
                if i < range.end && bytes[i] == b'>' {
                    i += 1;
                    if i < range.end && bytes[i] == b' ' {
                        i += 1;
                    }
                }
                if i > start {
                    markers.push(start..i);
                }
            }
            markers
        }
        Markers::TablePipes => {
            let mut markers = Vec::new();
            for (n, line) in line_starts(text, &range).into_iter().enumerate() {
                let line_end = text[line..range.end].find('\n').map_or(range.end, |i| line + i);
                if n == 1 {
                    // Delimiter row: `| --- | :-: |`
                    markers.push(line..line_end);
                    continue;
                }
                // GFM splits cells on every unescaped `|`, even inside code spans.
                for i in line..line_end {
                    if bytes[i] == b'|' && (i == 0 || bytes[i - 1] != b'\\') {
                        markers.push(i..i + 1);
                    }
                }
            }
            markers
        }
    }
}

/// Leaf spans delimited by a run of `delim` (at most `max`) on both ends.
fn delimited(text: &str, kind: Kind, range: Range<usize>, delim: u8, max: usize) -> Span {
    let range = trim_newlines(text, range);
    let bytes = &text.as_bytes()[range.clone()];
    let open = bytes.iter().take_while(|&&b| b == delim).count().min(max);
    let close = bytes.iter().rev().take_while(|&&b| b == delim).count().min(max).min(bytes.len() - open);
    let mut markers = Vec::new();
    if open > 0 {
        markers.push(range.start..range.start + open);
    }
    if close > 0 {
        markers.push(range.end - close..range.end);
    }
    Span { kind, range, markers }
}

fn trim_newlines(text: &str, range: Range<usize>) -> Range<usize> {
    let trimmed = text[range.clone()].trim_end_matches(['\n', '\r']);
    range.start..range.start + trimmed.len()
}

fn line_starts(text: &str, range: &Range<usize>) -> Vec<usize> {
    let mut starts = vec![range.start];
    starts.extend(text[range.clone()].match_indices('\n').map(|(i, _)| range.start + i + 1).filter(|&s| s < range.end));
    starts
}

fn to_utf16(text: &str, spans: Vec<Span>) -> Vec<Span> {
    // utf16[b] = UTF-16 offset of byte offset b (valid at char boundaries).
    let mut utf16 = vec![0usize; text.len() + 1];
    let mut offset = 0;
    for (b, c) in text.char_indices() {
        utf16[b] = offset;
        offset += c.len_utf16();
    }
    utf16[text.len()] = offset;
    let map = |r: &Range<usize>| utf16[r.start]..utf16[r.end];
    spans
        .into_iter()
        .map(|s| Span { kind: s.kind, range: map(&s.range), markers: s.markers.iter().map(map).collect() })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Readable rendering for snapshots: kind, source snippet, marker snippets.
    fn render(text: &str) -> String {
        let units: Vec<u16> = text.encode_utf16().collect();
        let slice = |r: &Range<usize>| String::from_utf16(&units[r.clone()]).unwrap();
        parse(text)
            .iter()
            .map(|s| {
                let markers: Vec<String> = s.markers.iter().map(|m| format!("{:?}", slice(m))).collect();
                format!("{:?} {:?} [{}]", s.kind, slice(&s.range), markers.join(", "))
            })
            .collect::<Vec<_>>()
            .join("\n")
    }

    #[test]
    fn headings() {
        insta::assert_snapshot!(render("# One\n\n### Three ###\n\nSetext\n===\n"));
    }

    #[test]
    fn inline_styles() {
        insta::assert_snapshot!(render("Some *em*, **strong**, ***both***, ~~gone~~ and `code` or ``a ` b``.\n"));
    }

    #[test]
    fn links_and_images() {
        insta::assert_snapshot!(render("See [the docs](https://x.y \"t\"), <https://auto.link> and ![alt](img.png) ![](empty.png).\n"));
    }

    #[test]
    fn math() {
        insta::assert_snapshot!(render("Inline $e^{i\\pi}+1=0$ here.\n\n$$\n\\int_0^1 x\\,dx\n$$\n"));
    }

    #[test]
    fn code_blocks() {
        insta::assert_snapshot!(render("```rust\nfn main() {}\n```\n\n    indented\n\n```\n```\n"));
    }

    #[test]
    fn lists_and_tasks() {
        insta::assert_snapshot!(render("- one\n- [ ] todo\n- [x] done\n\n1. first\n   - nested *em*\n"));
    }

    #[test]
    fn quotes() {
        insta::assert_snapshot!(render("> quoted **bold**\n> > nested\n"));
    }

    #[test]
    fn table() {
        insta::assert_snapshot!(render("| a | `b\\|c` |\n|---|:-:|\n| 1 | 2 |\n"));
    }

    #[test]
    fn footnotes_rule_html() {
        insta::assert_snapshot!(render("Text[^1] <br>\n\n---\n\n[^1]: The note.\n"));
    }

    #[test]
    fn offsets_are_utf16() {
        // "😀" is two UTF-16 units, "ż" one: ranges must index the NSString correctly.
        let text = "😀 ż **b**";
        let spans = parse(text);
        assert_eq!(spans[0].kind, Kind::Strong);
        assert_eq!(spans[0].range, 5..10);
        assert_eq!(spans[0].markers, vec![5..7, 8..10]);
    }

    /// `cargo test --release -p mdcore -- --ignored perf --nocapture`
    #[test]
    #[ignore]
    fn perf_large_document() {
        let section = "## Heading\n\nSome *em* and **strong** with `code`, [a link](x) and $x^2$.\n\n- [ ] task\n- item\n\n```\ncode\n```\n\n";
        let text = section.repeat(5_000); // ~600 KB
        let start = std::time::Instant::now();
        let spans = parse(&text);
        eprintln!("{} KB, {} spans in {:?}", text.len() / 1024, spans.len(), start.elapsed());
    }

    #[test]
    fn plain_text_has_no_spans() {
        assert!(parse("just words\n\nmore words").is_empty());
        assert!(parse("").is_empty());
    }
}
