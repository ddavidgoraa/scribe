# Scribe

A minimal, distraction-free Markdown editor for macOS with LaTeX math, inspired by iA Writer.

- Live preview editing (Typora-style): markup hides until your cursor touches it
- Math via `$…$` and `$$…$$`
- Your notes are plain `.md` files in a folder you choose

> Status: early development (milestone M0). See [PLAN.md](PLAN.md).

## Requirements

- macOS 14+ on Apple Silicon
- Xcode 16+, Rust (stable) with `aarch64-apple-darwin`, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```sh
make test   # Rust + Swift tests
make run    # build and launch Scribe.app
```

`make core` builds the Rust core (`core/`) into an XCFramework and generates Swift
bindings via UniFFI into `app/Packages/MdCore`. `make project` regenerates
`app/Scribe.xcodeproj` from `app/project.yml`.

## License

MIT
