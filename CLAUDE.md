# Contributor guide

Orientation for anyone — human or AI assistant — working on this repository.
Read it before making changes. The deep material lives in the two long-form
documents at the root; this file is the map to them and to the tree.

## What this is

Charon builds legacy Apple platforms for [xmake](https://xmake.io) and Conan:
armv6 (iPhone OS 2.0–4.2.1), armv7 (from iPhone OS 3.0), armv7s (from iOS 6) and
arm64 (from iOS 7), driven by clang from the `llvm` package with no Xcode. A
port is an ordinary declaration in each module; Charon adds only what the build
system does not already know about these platforms:

- an **addon / driver** — the `apple-ios` toolchain, the `tweak`/`daemon`/`app`
  rules, the Mach-O checks every binary is held to where it links (Thumb
  interworking, `__PAGEZERO`, `LC_ENCRYPTION_INFO`, missing syscalls, imports
  against the device's own dyld shared cache), strip and `ldid` signing,
  reproducible Debian packages, and the device transport;
- a **package repository** — the SDK, ld64 (cctools-port), ldid, libplist, the
  C++ runtime, and the libraries ports share, each under `charon@name`.

The driver is meant to be as usable for other platforms (old macOS, current iOS,
Android) as it is here; iOS 6 is the first platform it targets, not its limit.

## Where to look

- **`README.md`** — the authoritative reference: how to write a port, the rules
  and the values each reads, the Conan driver, the package layout, packaging and
  the linker. Start here for anything task-specific.
- **`DESIGN.md`** — how the pieces fit and *why*, including the Gradle/Maven →
  Charon mapping for anyone arriving from the JVM world.

## Repository layout

| Path | Holds |
| --- | --- |
| `config/` | Conan configuration: settings, hooks, and the `charon` driver + platform facts under `config/extensions/`. |
| `recipes/` | Conan recipes — the SDK, ld64, ldid, libplist, libcxx, the imports check, and the `charon-base` / `charon-apple` bases every port extends. |
| `modules/` | build modules / ports. |
| `packages/` | package definitions. |
| `plugins/` | build plugins. |
| `rules/` | build rules. |
| `toolchains/` | toolchain definitions. |
| `addons/`, `includes/` | xmake addon and shared includes. |
| `tools/` | diagnostic/maintenance helpers (e.g. `sdk-usage.py`, `assets-extract/`, which writes a compiled asset catalogue as loose files). |
| `tests/` | the test suites. |

## Conventions

- **No personal data in the repo.** No device addresses, hostnames, credentials,
  or absolute `/Users/<name>/…` paths in tracked files — use `$HOME`,
  placeholders, and a gitignored `device.env`.
- **Commit messages:** plain imperative subject describing the change, no type
  prefixes or scope tags. Keep the AI-attribution trailer
  `Co-Authored-By: Claude <noreply@anthropic.com>` — the work is openly AI-built
  and we keep the mark.
- **Build artifacts are never committed** (`build/`, `.xmake/`, and per-package
  build trees are gitignored) and are reproducible from the recipes.
- This repository receives frequent merges through a separate flow; coordinate
  before landing wide changes.
