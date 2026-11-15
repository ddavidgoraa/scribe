# Scribe

A minimal, distraction-free Markdown editor for macOS with LaTeX math, inspired by iA Writer.

- **Live preview** (Typora-style): Markdown syntax hides until your cursor touches it — the file stays plain text
- **Math** with `$…$` and `$$…$$`, rendered natively ([SwiftMath](https://github.com/mgriebling/SwiftMath)); live preview while editing
- **iA Writer typography**: iA Writer Duo / Mono / Quattro, a ~64 character column, light & dark
- **Focus mode** (⌘D) and **typewriter mode** (⌘T)
- **Library**: your notes are `.md` files in a folder you choose; autosave, external changes picked up
- **Quick open** (⌘P) and **full-text search** (⌘⇧F, ignores case and diacritics)
- **Images**: paste or drag them in — they're saved to an `assets` folder next to the note and previewed inline
- Formatting shortcuts (⌘B ⌘I ⌘K ⌘1–6 ⌘⇧M …), **Copy as HTML** (⌥⌘C)

> Status: v0.1 — see [PLAN.md](PLAN.md) for scope and roadmap. New to Scribe? Start with [Getting started](docs/GETTING-STARTED.md); every detail is in the [user manual](docs/MANUAL.md).

## Install

Download `Scribe-<version>-arm64.dmg` from Releases (macOS 14+, Apple Silicon) and drag Scribe to Applications.

The app is not notarized yet. On first launch macOS will block it: open **System Settings → Privacy & Security**
and click **Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Scribe.app`.

## Build

Requirements: Xcode 16+, Rust (stable) with `aarch64-apple-darwin`, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make test               # Rust + Swift tests
make run                # build and launch Scribe.app
./scripts/make-dmg.sh   # Release build → dist/Scribe-<version>-arm64.dmg
```

The Rust core (`core/`) parses Markdown, indexes and searches the library and watches files; it is bridged to
the Swift app (`app/`) with UniFFI (`make core`). `app/Scribe.xcodeproj` is generated from `app/project.yml`.

## Privacy and security

Scribe works entirely offline: no accounts, analytics, crash reporting or update checks, and it
never downloads images from the web. Your notes are plain `.md` files in your folder.
See [SECURITY.md](SECURITY.md) for how to report a vulnerability and how to verify a release.

## License

MIT. Bundled fonts: iA Writer Duo, Mono and Quattro © Information Architects Inc., SIL Open Font License 1.1
(see `app/Scribe/Resources/Fonts/`). Other components: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
