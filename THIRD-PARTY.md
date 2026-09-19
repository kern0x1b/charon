# Third-party code, and where each piece stands

This repository contains almost no third-party source. Every dependency below is
declared by a recipe or package under `recipes/` and `packages/` that names the
upstream it fetches and the version it pins; nothing external is vendored into
the tree. Each package copies its upstream license file under `licenses/` when
it installs.

The point of this file is that a reader can tell, without building anything,
exactly what a port built with Charon links against, what builds it, and under
what terms. Versions and licenses here are taken from the package recipes.

## Libraries a port links

Fetched by the package named beside each, built for the target architecture, and
carried into the program that ships to the device.

| Component | Version | License | Package |
| --- | --- | --- | --- |
| libc++, libc++abi | 23.1.1 | Apache-2.0 WITH LLVM-exception | `packages/l/libcxx` |
| The Swift runtime and standard library, with the system-framework overlays | 6.4.0 | Apache-2.0 WITH Swift-exception | `packages/s/swift-runtime` |
| Styx — a `Combine` module for platforms without Apple's framework | 2026.09.20 | MIT (the upstream MIT copyright is kept in its `LICENSE`) | `packages/s/styx`, from [`kern0x1b/styx`](https://github.com/kern0x1b/styx) |

## The compiler, linker, signer and SDK

These run on the build machine. The compiler and its runtime reach the device;
the linker, signer and SDK stubs do not.

| Component | Version | License | Package |
| --- | --- | --- | --- |
| Swift compiler | 6.4.0 | Apache-2.0 WITH Swift-exception | `packages/s/swift`, `packages/s/swift-bootstrap` |
| LLVM / clang | 23.1.1 | Apache-2.0 WITH LLVM-exception | `packages/l/llvm` |
| ld64, from cctools-port (with apple-libtapi to read the SDK's `.tbd` stubs) | 956.6 | APSL-2.0; libtapi is Apache-2.0 WITH LLVM-exception plus NCSA | `packages/l/ld64` |
| ldid | 2.1.5-procursus7+23.gaf86971 | AGPL-3.0-or-later (build-time signer; linked into nothing that ships) | `packages/l/ldid` |
| iPhone OS SDK | 16.4 | Apple SDK license terms (from [`theos/sdks`](https://github.com/theos/sdks)) | `packages/i/iphoneos-sdk` |

## The emulator, the signer, and their libraries

Used to sign, run and test binaries on the build machine; none of it is linked
into the port binary that ships to a device.

| Component | Version | License | Package |
| --- | --- | --- | --- |
| Shade — Charon's ARM/iOS userland emulator | 2026.09.20 | MPL-2.0 (notices in its `NOTICE`) | `packages/s/shade`, from [`kern0x1b/shade`](https://github.com/kern0x1b/shade) |
| SwiftShader | 2026.09.16 | Apache-2.0 | `packages/s/swiftshader` |
| libplist | 2.7.0 | LGPL-2.1-or-later | `packages/l/libplist` — read/write plist for the ldid signer and the Shade emulator |
| OpenSSL | 4.0.2 | Apache-2.0 | `packages/o/openssl` — used by the ldid signer and the Shade emulator |

## First-party

`packages/a/apple-compat`, `packages/a/apple-backports`, `packages/e/emulator-guest`
and `packages/f/firmware-tools`, and the recipes under `recipes/`, are Charon's
own (MIT); they are not third-party and are not listed here.
