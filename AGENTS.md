# Contributor guide

Orientation for anyone — human or AI assistant — working on this repository.
Read it before making changes. The deep material lives in the two long-form
documents at the root; this file is the map to them and to the tree.

## What this is

If the effort has to be rebuilt from nothing — every session gone — read
[COORDINATION.md](COORDINATION.md) first. It carries the team structure, the flow patches
travel through, the known traps, and the restart procedure. This file stays the
map of the code.

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
- **Skills** (`.agents/skills/`): `backports-gate` — gating apple-backports and reading the
  verdict; `corpus-regen` — the registry export and demand data after a push; `emulate-port` —
  `xmake emulate`. The `xmake-*` skills are vendored (`VENDORED.md`).
- **Workspace-wide procedures** are skills in `$HOME/Git/projects/ios/.agents/skills/`:
  `device-session` (claim, run, install, launch, tap on a real device), `canon-install`,
  `patch-merge`, `worktree-sweep`, `session-handoff`, `band-launch`, `band-supervise`. A session
  started inside this repository does not list them — read `<name>/SKILL.md` there.

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
  prefixes or scope tags. Keep the AI-attribution trailer:
  an agent's commit ends with its own `Co-Authored-By:` line — the work is openly AI-built
  and we keep the mark.
- **A recipe takes a dependency by platform, not by name.** `package:dep(name)` is keyed by the package's name, and a host tool
  in the graph (ldid) brings its own dependencies with it, so a target's openssl and the host's meet at one key and the later
  wins: tdlib linked a macOS libcrypto that way. Use `modules/apple/dependency.lua`'s `target_dependency(package, name)`
  wherever a dependency's folder goes to CMake or a linker, and do not put a host tool or anything with library
  dependencies into a recipe that other packages depend on: what it depends on, they depend on too.
- **Build artifacts are never committed** (`build/`, `.xmake/`, and per-package
  build trees are gitignored) and are reproducible from the recipes.
- This repository receives frequent merges through a separate flow; coordinate
  before landing wide changes.

## Traps

Each entry: wrong pattern → right pattern → the mechanical reason.

- **The shared `~/.xmake` store, not a private one.** Wrong: `xmake require --force`,
  `xrepo install --force`, `rm -rf ~/.xmake/packages/...`, or a private `XMAKE_GLOBALDIR` to pick
  up a changed recipe or patch. Right: just rebuild normally against the shared store. Reason:
  every package that matters here (`apple-backports`, `llvm`, `swift-runtime`, `libcxx`, `swift`)
  hashes its own sources, patches and recipe into a readonly digest config (`sources`/`recipe` —
  see `packages/a/apple-backports/xmake.lua` and `packages/s/swift-runtime/digest.lua`), so a
  changed backport, patch or recipe is already a different package with its own install path —
  no force needed, no collision with another band's build (a change that's only a comment or
  layout is deliberately excluded from the digest, by design). A private store instead
  re-resolves the whole dependency chain from network, up to rebuilding LLVM from source — never do
  that either. If a build's own output needs
  to survive the shared store regardless of any package (a crash log, failure text), redirect it
  to your own file instead of isolating anything: `xmake -y > build.log 2>&1`.

- **Device-side binaries and the toolchain.** Wrong: building a device-side binary — including a
  throwaway probe — with the host's own `cc`/`clang`. Right: build it through a `target()` using
  `@addon/charon/daemon` (or `app`/`tweak`) against this driver's `apple-ios` toolchain, same as
  any port. Reason: a Mach-O built for the wrong target crashes with `Bad system call: 12`
  (SIGSYS) before its own code runs on the device's old kernel — indistinguishable from a
  codesigning/sandbox rejection by symptom alone.

- **`NSMapTable` and non-object keys/values.** Wrong: building an `NSMapTable` with default
  options (including `strongToWeakObjectsMapTable`) when a key or value is an opaque C pointer
  bridged with `(__bridge id)` (e.g. a `JSGlobalContextRef`). Right: build it with
  `+mapTableWithKeyOptions:valueOptions:`, using `NSPointerFunctionsOpaqueMemory |
  NSPointerFunctionsOpaquePersonality` for the non-object side. Reason: default options send
  `retain`/`release` to keys and values, and `objc_retain` on a non-object crashes inside
  `NSConcreteMapTable` with no hint of the real cause.

- **Calling a block by its own pointer.** Wrong: casting a block's own pointer to a C function
  type and calling it. Right: read the `invoke` field out of the block's layout
  (`{isa, flags, reserved, invoke, ...captures}`) and call that, bridging through `void *` first
  (ARC forbids calling an Objective-C pointer as a raw function pointer). Reason: the block
  pointer's own bytes are `isa`, not code.

- **`NSInvocation` argument lifetime.** Wrong: calling `-setArgument:atIndex:` without first
  calling `-retainArguments`, when the argument's source local can go out of scope before
  `-invoke` runs. Right: call `-retainArguments` immediately after creating the invocation, before
  setting any arguments. Reason: `-setArgument:atIndex:` copies bytes, not objects, so the pointer
  dangles once its scope ends — and the crash then lands in the *callee's* ARC prologue
  (`objc_storeStrong`), not at the real cause.

- **Non-ASCII in `prefix_selectors.py` input.** Wrong: a non-ASCII character (e.g. an em dash) in
  a comment of a `.m` file compiled through `tests/backports/host/prefix_selectors.py`. Right:
  keep comments in files on that pipeline ASCII-only. Reason: the tool renames selectors by byte
  offset from a clang AST dump, so one multi-byte UTF-8 character shifts every later offset and
  corrupts an unrelated selector further down the file (e.g. `component:fromDate:` becomes
  `ccharonHost_omponent:fromDate:`).

- **Mixing `NSInteger` and `NSUInteger`.** Wrong: subtracting an `NSUInteger` (e.g.
  `calendar.firstWeekday`) from a smaller `NSInteger` without a cast. Right: cast the `NSUInteger`
  side to `NSInteger` explicitly before subtracting. Reason: C's usual arithmetic conversions
  promote the signed side to unsigned, so the result wraps to a huge positive number instead of
  going negative — wrong answer, no crash, no warning.

- **`charon.libraries` and `verify_placed`.** Wrong: a `daemon`/`app`/`tweak` target
  `add_requires`s a backport package and `add_packages`s it, but link still fails with "these
  imports are not exported by the device's iOS ... neither the device nor this build provides".
  Right: add `set_values("charon.libraries", "<the alias add_requires gave the package>")` to the
  target. Reason: `modules/apple/platform.lua`'s `verify_placed` takes the plain, weak-linked path
  whenever `target:values("charon.libraries")` is empty and the target shares no runtime, and that
  path does not recognize the backport dylib as build-provided; `set_values` switches it to the
  branch that copies the library in and retargets the load command. Related trap: `@addon/charon/*`
  resolves to a version-pinned copy of this repository (`~/.xmake/addons/charon/<version>/`), not
  the working tree `add_repositories` points at, so an uncommitted edit under `modules/` never
  reaches a build that includes the addon by version — only a commit does.
