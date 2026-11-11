//! Word count and reading time for the status bar.

/// Words read per minute for the reading-time estimate.
const WORDS_PER_MINUTE: usize = 230;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Stats {
    pub words: usize,
    pub characters: usize,
    pub reading_minutes: usize,
}

/// Counts words as whitespace-separated tokens that contain a letter or digit,
/// so Markdown syntax on its own (`#`, `-`, `**`, `>`, `|`) isn't counted.
pub fn stats(text: &str) -> Stats {
    let words = text.split_whitespace().filter(|t| t.chars().any(char::is_alphanumeric)).count();
    let characters = text.chars().filter(|c| !c.is_whitespace()).count();
    let reading_minutes = if words == 0 { 0 } else { words.div_ceil(WORDS_PER_MINUTE) };
    Stats { words, characters, reading_minutes }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn markdown_syntax_is_not_counted() {
        let s = stats("# Tytuł\n\n- **pogrubione** słowo\n> cytat\n| a | b |\n");
        assert_eq!(s.words, 6);
    }

    #[test]
    fn reading_time_rounds_up() {
        assert_eq!(stats("").reading_minutes, 0);
        assert_eq!(stats("jedno").reading_minutes, 1);
        assert_eq!(stats(&"słowo ".repeat(231)).reading_minutes, 2);
    }

    #[test]
    fn characters_exclude_whitespace() {
        assert_eq!(stats("ab  c\nż").characters, 4);
    }
}
