---
name: emulate-port
description: Run a charon port (a daemon, a test probe, a package) on an emulated iOS device with `xmake emulate` instead of a phone — install, run, debug, log, shot, clean — and know what the emulator can and cannot prove. Use when a device is busy or not needed, for a fast loop on daemon-shaped code, or when asked to "run it in shade / the emulator".
---

# `xmake emulate`

macOS arm64 hosts only. The emulator is Shade, built by the `charon@shade` package (pinned by
commit, patches under `packages/s/shade/patches/`); the `shade` repository is its source, not what
this command runs.

## Setup in the port's xmake.lua

```lua
includes("@addon/charon/apple-ios")
includes("@addon/charon/emulate")      -- after apple-ios; requires charon@shade, charon@swiftshader, charon@emulator-guest
```

## Commands (from the port's project directory)

```
xmake emulate install                          # the port's packages into the emulated image
xmake emulate [-s 60] [--scale 10] run COMMAND # verdict: pass, fail, crash, timeout or boot-blocked
xmake emulate debug COMMAND                    # COMMAND as first guest process, under the debugger
xmake emulate log [TEXT]                       # what the last run left
xmake emulate shot [FILE]                      # its last frame
xmake emulate clean                            # this port's images (--all: every image and golden image)
```

Options: `-d DEVICE` (e.g. `iPhone3,1`; default the first catalog device of the configured
architecture that Shade has a profile for), `-r RELEASE` (default `apple_minimum`),
`-t/--timeout` (900 s for a whole boot), `-k/--keep` (keep the booted rootfs beside the log),
`-n isolated|loopback|host`, `--scale` (guest time scale, default 10).

- `fail(spawn error 2)`: the command is not in the image — `xmake emulate install` first.
- Configure the port (`xmake f -p iphoneos -a armv7 -y`) before `install`: the packages it copies
  must already be installed in the store.

## What it proves and what it does not

- Daemons (`@addon/charon/daemon`, no `UIApplicationMain`) run: use it for them.
- A UIKit app started by `run` never reaches `application:didFinishLaunchingWithOptions:` — it
  bypasses SpringBoard's launch. The frames drawn are SpringBoard's. Anything living inside an app
  (text views, collection layout, gestures) is checked on hardware (workspace skill
  `device-session`).
- No audio daemon: `kAudioSessionNotInitialized` there is the emulator, not the code.
- Without a time scale the guest's own watchdogs expire (SpringBoard is lost to a mediaserverd
  timeout); keep the default `--scale 10`.
- A device without a Shade profile, or a release whose Darwin Shade does not emulate, is refused
  with the reason — not replaced by another.
- Images, and a rootfs kept with `-k`, live in the emulator root beside the dyld caches
  (`~/.charon/emulator`), not in the project; copy the log and verdict you need into
  `.agent-work/runs/`, then `xmake emulate clean`.
