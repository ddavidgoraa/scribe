//! Scribe core: Markdown parsing, library index, search, file watching.

/// Version of the core library.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// Greeting used to verify the Rust <-> Swift bridge.
pub fn greet(name: &str) -> String {
    format!("Hello, {name}, from Rust core v{}", version())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greet_includes_name_and_version() {
        let s = greet("Scribe");
        assert!(s.contains("Scribe"));
        assert!(s.contains(version()));
    }
}
