# Contributor guide

Orientation for anyone — human or AI assistant — working on this repository.
Read it before making changes. The deep material lives in the two long-form
documents at the root; this file is the map to them and to the tree.

## What this is

If the effort has to be rebuilt from nothing — every session gone — read
[COORDINATION.md](COORDINATION.md) first. It carries the team structure, the flow patches
travel through, the traps already paid for, and the restart procedure. This file stays the
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

- **A framework's own entry in `modules/apple/backports.lua`'s `LIBRARIES` table must not name
  itself in `frameworks` unless the release actually carries that framework.** CoreVideo and Metal
  do (the framework exists on-device, only some of its symbols are missing), so `GraphicsBackports`
  and `MetalBackports` list themselves; GameController, Vision and CallKit do not exist on iOS 6 at
  all, so `GameControllerBackports`, `VisionBackports` and `CallKitBackports` list every framework
  they need *except* their own. Listing a framework the release never shipped makes the linker emit
  an `LC_LOAD_DYLIB` the device cannot satisfy, and the imports check fails with "neither the device
  nor this build provides" it — this cost a full gate run on the CoreSpotlight backport, which
  needs the framework's headers to compile against but must not link against the framework itself.

- **A device-side binary built with the host's own `cc`/`clang` instead of this
  driver's `apple-ios` toolchain can crash with `Bad system call: 12` (SIGSYS)
  on old iOS before any of its own output runs.** The symptom looks like a
  codesigning or sandbox rejection; it is not — it reproduces even for a
  trivial Foundation program, ad-hoc `ldid -S` signed, run as root. The real
  cause is a Mach-O built for a target the device's very old kernel does not
  understand. Build every device-side tool — including throwaway probes, not
  just ports — through a `target()` using `@addon/charon/daemon` (or `app`/
  `tweak`) against `thumbv7-apple-ios6.0.0` like any other port; that alone
  fixed it. Confirmed against an iPhone 4S, kernel build 10B329 (iOS 6.1.3).

- **`NSMapTable` sends `retain`/`release` to its keys and values by default, even for
  `strongToWeakObjectsMapTable` and friends.** A key that is not really an Objective-C object — a
  `JSGlobalContextRef` or any other opaque C pointer bridged in with `(__bridge id)` — crashes
  inside `objc_retain` the first time something is inserted, with a backtrace that points at
  `NSConcreteMapTable` and nothing about the actual mistake. Build such a table with
  `+mapTableWithKeyOptions:valueOptions:` and `NSPointerFunctionsOpaqueMemory |
  NSPointerFunctionsOpaquePersonality` for the non-object side. Paid for on the JSContext
  registry (`JavaScriptCore/JSContext.m`), keying a context lookup table on the
  `JSGlobalContextRef` itself.

- **A block's callable address is its `invoke` field, not the block's own pointer.** A block
  literal is `{isa, flags, reserved, invoke, ...captures}`; casting the block pointer itself to a C
  function type and calling it jumps into the `isa` field's bytes as if they were code — an
  instant crash inside the block's own frame, `frame #0` showing the block's compiler-generated
  symbol as if it corrupted itself. Read `invoke` out of the struct first. Also: ARC forbids
  calling an Objective-C pointer as a raw function pointer at all (`cast ... disallowed with ARC`)
  — bridge through `void *` before either step. Paid for boxing an `NSBlock` as a callable
  `JSValue`.

- **`-[NSInvocation setArgument:atIndex:]` copies bytes, not objects — it does not retain an
  object argument unless `-retainArguments` has been called.** An argument set from a local that
  goes out of scope before `-invoke` runs (the ordinary case when arguments are filled in a loop
  inside a helper function) leaves a dangling pointer; the crash lands inside the *callee*'s own
  ARC-generated argument-retain prologue, `objc_storeStrong`, which looks exactly like a bug in
  the method being called rather than in how it was invoked. Call `-retainArguments` right after
  creating the invocation, before setting any arguments. Paid for on the generic JSExport method
  dispatcher (`JavaScriptCore/JSExportBridge.m`).

- **A non-ASCII character in a `.m` file compiled through `tests/backports/host/*/prefix_selectors.py`
  corrupts unrelated selectors elsewhere in the same file, not the line the character is on.** The
  tool renames selectors by byte offset from a clang AST dump; one multi-byte UTF-8 character (an
  em dash in a comment, in this case) shifts every byte offset after it by two, so renames later in
  the file land one character into the target identifier — `component:fromDate:` becomes
  `ccharonHost_omponent:fromDate:`, which reads as a build tool bug in a completely different
  method. Keep comments in files that go through that pipeline ASCII-only.

- **Mixing `NSInteger` and `NSUInteger` in the same expression silently promotes the signed side
  to unsigned**, per C's usual arithmetic conversions — `signedValue - calendar.firstWeekday`
  (`firstWeekday` is `NSUInteger`) does not go negative when `signedValue` is smaller, it wraps to
  a huge positive number, and a later `% 7` on that gives a plausible-looking but wrong small
  integer with no crash anywhere. Cast the `NSUInteger` side explicitly before subtracting. Paid
  for on every weekday computation in `NSCalendar+Components.m` until a host differential caught
  the wrong answers — nothing crashed, nothing warned, the numbers were just wrong.
