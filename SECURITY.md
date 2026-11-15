# Security policy

## Reporting a vulnerability

Please **don't open a public issue** for security problems.
Report them privately through GitHub: **Security → Report a vulnerability** on this repository
(private vulnerability reporting). You'll get a reply as soon as possible, and a fix will be
released before the issue is made public.

Useful details: the Scribe version, macOS version, steps to reproduce and, if possible, a sample
Markdown file that triggers the problem.

## Supported versions

Only the latest release receives security fixes.

## How Scribe handles your data

- **App Sandbox.** Scribe runs in the macOS App Sandbox. It can read and write only the notes
  folder you choose (remembered with a security-scoped bookmark), files you open, paste or drag
  in, and its own container. Its entitlements are limited to user-selected files, bookmarks and
  outgoing network connections (see below).
- **No network use.** Scribe never connects to the internet: no accounts, analytics, crash
  reporting or update checks. Images from the web in your notes are not downloaded.
  The sandbox entitlement for outgoing connections is present only because Apple's WebKit,
  which renders the Help window, needs it to start even for local pages; the Help view itself
  blocks every web request with a content rule list and keeps no website data. Scribe's own
  code has no networking.
- **Your notes stay plain files** in the folder you choose; Scribe writes them atomically and
  doesn't add hidden metadata.
- **Preferences** (library location, font, modes) are stored in macOS user defaults under
  `dev.dawidgora.scribe`.
- The Help window shows guides bundled with the app and only opens `http`, `https` and `mailto`
  links in other apps.

## Build and release integrity

- Release builds run on GitHub Actions from a tagged commit, after the test and dependency
  checks pass. Third-party actions are pinned to commit SHAs; tools are checksum-verified.
- Each release lists SHA-256 checksums (`SHA256SUMS.txt`) and has a signed
  [build provenance attestation](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations).
  Verify a download with:

  ```sh
  shasum -a 256 -c SHA256SUMS.txt
  gh attestation verify Scribe-<version>-arm64.dmg --repo ddavidgoraa/scribe
  ```
- Rust dependencies are checked with [cargo-deny](https://github.com/EmbarkStudios/cargo-deny)
  for known vulnerabilities (RustSec), licenses and sources (`make audit`).

The app is not yet notarized by Apple, so macOS asks for confirmation on first launch
(see the README).
