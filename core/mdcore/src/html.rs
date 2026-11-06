//! Markdown → HTML (for "Copy as HTML"; full export with KaTeX comes in v0.2).

use pulldown_cmark::{html, Options, Parser};

pub fn to_html(markdown: &str) -> String {
    let options = Options::ENABLE_TABLES
        | Options::ENABLE_FOOTNOTES
        | Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_TASKLISTS
        | Options::ENABLE_MATH
        | Options::ENABLE_GFM;
    let mut out = String::with_capacity(markdown.len() * 3 / 2);
    html::push_html(&mut out, Parser::new_ext(markdown, options));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_common_syntax() {
        insta::assert_snapshot!(to_html(
            "# Title\n\n**b** *i* ~~s~~ `c` [l](u)\n\n- [x] done\n\n| a |\n|---|\n| 1 |\n\n$x^2$ and\n\n$$\n\\int\n$$\n"
        ));
    }
}
