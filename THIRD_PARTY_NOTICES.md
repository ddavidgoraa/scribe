# Third-party notices

Scribe is MIT-licensed (see [LICENSE](LICENSE)). It includes or depends on the following
open-source software.

## Bundled in the app

| Component | License | Notes |
|---|---|---|
| [iA Writer Duo, Mono, Quattro](https://github.com/iaolo/iA-Fonts) | SIL Open Font License 1.1 | © Information Architects Inc., Reserved Font Name "iA Writer"; based on IBM Plex. Unmodified; license texts in `app/Scribe/Resources/Fonts/`. |
| [SwiftMath](https://github.com/mgriebling/SwiftMath) | MIT | Math rendering, including its bundled math fonts (see the package for their licenses). |
| [pulldown-cmark](https://github.com/pulldown-cmark/pulldown-cmark) | MIT | Markdown parsing and HTML. |
| [nucleo-matcher](https://github.com/helix-editor/nucleo) | MPL-2.0 | Fuzzy matching for Quick Open (unmodified). |
| [notify](https://github.com/notify-rs/notify), notify-debouncer-full | CC0-1.0; MIT or Apache-2.0 | File watching. |
| [UniFFI](https://github.com/mozilla/uniffi-rs) runtime | MPL-2.0 | Rust ↔ Swift bridge (unmodified). |
| Other Rust crates (walkdir, tempfile, thiserror, unicode-normalization, unicode-segmentation, …) | MIT, Apache-2.0, Unlicense or Unicode-3.0 (as each crate states) | Full list: `cd core && cargo tree`. |

`cargo deny check licenses` (run in CI) enforces that every Rust dependency uses one of the
licenses allowed in [`core/deny.toml`](core/deny.toml).
