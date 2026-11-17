//! Builds the static Scribe website from `site/` templates and the Markdown guides.
//!
//!     cargo run -p scribe-site -- <repo root> <output dir>
//!
//! Pages are rendered with the same Markdown code as the app (`mdcore`), so the
//! website and the in-app Help read the same.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

const REPO_URL: &str = "https://github.com/ddavidgoraa/scribe";

/// Markdown sources turned into pages: (source, output file, title, nav key).
const PAGES: &[(&str, &str, &str, &str)] = &[
    ("docs/GETTING-STARTED.md", "getting-started.html", "Getting started", "guide"),
    ("docs/MANUAL.md", "manual.html", "Manual", "manual"),
    ("SECURITY.md", "security.html", "Privacy & security", "security"),
];

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let root = PathBuf::from(args.get(1).map(String::as_str).unwrap_or("."));
    let out = PathBuf::from(args.get(2).map(String::as_str).unwrap_or("site/_build"));
    build(&root, &out)?;
    println!("site built in {}", out.display());
    Ok(())
}

fn build(root: &Path, out: &Path) -> io::Result<()> {
    if out.exists() {
        fs::remove_dir_all(out)?;
    }
    fs::create_dir_all(out.join("images"))?;

    let site = root.join("site");
    let page_template = fs::read_to_string(site.join("page.html"))?;
    let index = fs::read_to_string(site.join("index.html"))?;
    fs::write(out.join("index.html"), with_nav(&index, "home"))?;
    fs::copy(site.join("style.css"), out.join("style.css"))?;
    // GitHub Pages: serve files as-is (no Jekyll processing).
    fs::write(out.join(".nojekyll"), "")?;

    for entry in fs::read_dir(root.join("docs/images"))? {
        let path = entry?.path();
        if path.extension().is_some_and(|e| e == "png") {
            fs::copy(&path, out.join("images").join(path.file_name().unwrap()))?;
        }
    }

    for (source, file, title, key) in PAGES {
        let markdown = fs::read_to_string(root.join(source))?;
        let source_dir = Path::new(source).parent().unwrap_or(Path::new(""));
        let content = mdcore::html::to_document_html(&markdown, &|url| rewrite(url, source_dir));
        let page = page_template.replace("{{title}}", title).replace("{{content}}", &content);
        fs::write(out.join(file), with_nav(&page, key))?;
    }
    Ok(())
}

/// Marks the current page in the navigation (`{{current-<key>}}` placeholders).
fn with_nav(html: &str, current: &str) -> String {
    let mut html = html.to_string();
    for key in ["home", "guide", "manual", "security"] {
        let marker = format!("{{{{current-{key}}}}}");
        html = html.replace(&marker, if key == current { r#" aria-current="page""# } else { "" });
    }
    html
}

/// Maps a link or image target in `source_dir/*.md` to the website.
fn rewrite(url: &str, source_dir: &Path) -> String {
    if url.starts_with('#') || url.contains("://") || url.starts_with("mailto:") {
        return url.to_string();
    }
    let (path, fragment) = match url.split_once('#') {
        Some((p, f)) => (p, format!("#{f}")),
        None => (url, String::new()),
    };
    let full = normalize(&source_dir.join(path));
    for (source, file, _, _) in PAGES {
        if full == Path::new(source) {
            return format!("{file}{fragment}");
        }
    }
    if full.starts_with("docs/images") {
        return format!("images/{}", full.file_name().unwrap().to_string_lossy());
    }
    // Anything else in the repository: link to it on GitHub.
    format!("{REPO_URL}/blob/main/{}{fragment}", full.display())
}

/// Resolves `..` and `.` components without touching the file system.
fn normalize(path: &Path) -> PathBuf {
    let mut parts: Vec<&std::ffi::OsStr> = Vec::new();
    for component in path.components() {
        match component {
            std::path::Component::ParentDir => {
                parts.pop();
            }
            std::path::Component::Normal(p) => parts.push(p),
            _ => {}
        }
    }
    parts.iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rewrites_links_between_guides_and_to_github() {
        let docs = Path::new("docs");
        assert_eq!(rewrite("MANUAL.md#5-math", docs), "manual.html#5-math");
        assert_eq!(rewrite("GETTING-STARTED.md", docs), "getting-started.html");
        assert_eq!(rewrite("images/02-writing.png", docs), "images/02-writing.png");
        assert_eq!(rewrite("../SECURITY.md", docs), "security.html");
        assert_eq!(rewrite("../LICENSE", docs), format!("{REPO_URL}/blob/main/LICENSE"));
        assert_eq!(rewrite("#install", docs), "#install");
        assert_eq!(rewrite("https://example.com", docs), "https://example.com");
    }

    #[test]
    fn marks_the_current_page() {
        let html = with_nav(r#"<a href="manual.html"{{current-manual}}>"#, "manual");
        assert_eq!(html, r#"<a href="manual.html" aria-current="page">"#);
        assert_eq!(with_nav("{{current-home}}", "guide"), "");
    }

    #[test]
    fn builds_the_site_from_the_repository() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let out = std::env::temp_dir().join(format!("scribe-site-test-{}", std::process::id()));
        build(&root, &out).unwrap();
        for file in ["index.html", "getting-started.html", "manual.html", "security.html", "style.css", ".nojekyll"] {
            assert!(out.join(file).exists(), "{file} missing");
        }
        let manual = fs::read_to_string(out.join("manual.html")).unwrap();
        assert!(manual.contains(r#"id="5-math""#));
        assert!(manual.contains(r#"href="getting-started.html""#));
        assert!(!manual.contains("{{"), "unfilled placeholder");
        assert!(out.join("images/02-writing.png").exists());
        fs::remove_dir_all(out).unwrap();
    }
}
