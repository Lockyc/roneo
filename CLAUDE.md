---
type: architecture
links:
  - rel: covers
    to: Sources
  - rel: see-also
    to: README.md
    note: human-facing counterpart — what roneo is and how to build it
---

# roneo — agent notes

Native macOS PDF viewer with an in-window print bar. Swift package, AppKit, PDFKit, macOS 27+.
Pre-1.0. The repo is public: tracked files carry no hostnames, usernames or machine paths. Read
[docs/architecture.md](docs/architecture.md) before changing the viewer, the print bar or the
print path.

## Layout

- `Sources/RoneoCore/` — Foundation only; never AppKit or PDFKit. Every decision the unit tests
  cover lives here.
- `Sources/RoneoPDF/` — Foundation and PDFKit only; no AppKit views.
- `Sources/Roneo/` — the AppKit executable (Sparkle for updates); no unit tests, so it takes its
  decisions from the two libraries.
- `Tests/RoneoCoreTests/`, `Tests/RoneoPDFTests/` — XCTest, `swift test`.
- `Support/Info.plist` — bundle template; `just bundle` stamps `VERSION` into it.
- `Support/icon.svg` — icon master; `just icons` renders `AppIcon.icns` and `icon.png`.
- `install.sh` — the curl-pipeable installer (latest release's `roneo.zip`, team ID and
  notarization checked).

## Invariants

- Bundle ID `com.lockyc.roneo`, executable `Roneo`, display name `roneo`; fixed from the first
  release.
- No print setting persists beyond its window: every new window starts from the same fixed
  defaults.
- Unavailable controls are disabled in place with a tooltip saying why; they never move or
  disappear.
- One window per PDF; no tabs.

## Build, test, verify, branches

- `just test`, `just gate`; `just run` builds and launches `build/roneo.app`.
- Verify UI changes by running the app (`just run`) and confirming the window renders as intended.
- Branches: `main` + `dev`. Work lands on `dev`; a release fast-forwards `main` from `dev`
  (`git merge --ff-only dev`). Docs-only changes may land on `main` and are forward-merged into
  `dev` immediately.
- Version: the root `VERSION` file is the only source; `just bundle` stamps it into the bundle. A
  release tags `v<VERSION>` and publishes a GitHub release with notes and `roneo.zip`. The release
  interface: `just gate`, `VERSION`, `just bundle` (signs with `APPLE_SIGNING_IDENTITY`, hardened
  runtime, nested Sparkle helpers re-signed; else the keychain's Developer ID, else ad-hoc), the
  `app` and `info_plist` variables, `just sparkle-bin`.
