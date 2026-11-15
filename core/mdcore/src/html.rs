//! Markdown → HTML: "Copy as HTML" and the documentation website.
//! (Full export with KaTeX comes in v0.2.)

use std::collections::HashMap;

use pulldown_cmark::{html, CowStr, Event, Options, Parser, Tag, TagEnd};

fn options() -> Options {
    Options::ENABLE_TABLES
        | Options::ENABLE_FOOTNOTES
        | Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_TASKLISTS
        | Options::ENABLE_MATH
        | Options::ENABLE_GFM
}

pub fn to_html(markdown: &str) -> String {
    let mut out = String::with_capacity(markdown.len() * 3 / 2);
    html::push_html(&mut out, Parser::new_ext(markdown, options()));
    out
}

/// HTML for a standalone document page: headings get GitHub-style `id`s (so links like
/// `#5-math` work) and every link and image target passes through `rewrite`.
pub fn to_document_html(markdown: &str, rewrite: &dyn Fn(&str) -> String) -> String {
    let events: Vec<Event> = Parser::new_ext(markdown, options()).collect();
    let mut used: HashMap<String, usize> = HashMap::new();
    let mut ids: Vec<String> = Vec::new();

    // First pass: a unique slug per heading, from its text.
    let mut current: Option<String> = None;
    for event in &events {
        match event {
            Event::Start(Tag::Heading { .. }) => current = Some(String::new()),
            Event::Text(t) | Event::Code(t) | Event::InlineMath(t) => {
                if let Some(text) = current.as_mut() {
                    text.push_str(t);
                }
            }
            Event::End(TagEnd::Heading(_)) => {
                let base = slug(&current.take().unwrap_or_default());
                let count = used.entry(base.clone()).or_insert(0);
                ids.push(if *count == 0 { base.clone() } else { format!("{base}-{count}") });
                *count += 1;
            }
            _ => {}
        }
    }

    // Second pass: set the ids and rewrite targets.
    let mut ids = ids.into_iter();
    let events = events.into_iter().map(|event| match event {
        Event::Start(Tag::Heading { level, id: None, classes, attrs }) => Event::Start(Tag::Heading {
            level,
            id: ids.next().map(CowStr::from),
            classes,
            attrs,
        }),
        Event::Start(Tag::Link { link_type, dest_url, title, id }) => Event::Start(Tag::Link {
            link_type,
            dest_url: rewrite(&dest_url).into(),
            title,
            id,
        }),
        Event::Start(Tag::Image { link_type, dest_url, title, id }) => Event::Start(Tag::Image {
            link_type,
            dest_url: rewrite(&dest_url).into(),
            title,
            id,
        }),
        other => other,
    });
    let mut out = String::with_capacity(markdown.len() * 3 / 2);
    html::push_html(&mut out, events);
    out
}

/// GitHub's heading anchor: lowercase, letters/digits/`-`/`_` kept, spaces → `-`.
pub fn slug(text: &str) -> String {
    text.trim()
        .to_lowercase()
        .chars()
        .filter_map(|c| match c {
            c if c.is_alphanumeric() || c == '-' || c == '_' => Some(c),
            ' ' => Some('-'),
            _ => None,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugs_match_github() {
        assert_eq!(slug("1. Installation"), "1-installation");
        assert_eq!(slug("Library search: ⌘⇧F"), "library-search-f");
        assert_eq!(slug("Names from the first line"), "names-from-the-first-line");
        assert_eq!(slug("Zażółć gęślą"), "zażółć-gęślą");
    }

    #[test]
    fn document_html_has_heading_ids_and_rewritten_links() {
        let html = to_document_html(
            "# Intro\n\n## Intro\n\nSee [manual](MANUAL.md#5-math) and ![x](images/a.png).",
            &|url| url.replace("MANUAL.md", "manual.html"),
        );
        assert!(html.contains(r#"<h1 id="intro">Intro</h1>"#), "{html}");
        assert!(html.contains(r#"<h2 id="intro-1">Intro</h2>"#), "{html}");
        assert!(html.contains(r#"href="manual.html#5-math""#), "{html}");
        assert!(html.contains(r#"src="images/a.png""#), "{html}");
    }

    #[test]
    fn renders_common_syntax() {
        insta::assert_snapshot!(to_html(
            "# Title\n\n**b** *i* ~~s~~ `c` [l](u)\n\n- [x] done\n\n| a |\n|---|\n| 1 |\n\n$x^2$ and\n\n$$\n\\int\n$$\n"
        ));
    }
}
