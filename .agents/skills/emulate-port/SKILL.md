---
name: emulate-port
description: Run a charon port (a daemon, a test probe, an application, a package) on an emulated iOS device with `xmake emulate` instead of a phone — install, run, launch an app through SpringBoard and tap it, debug, log, shot, clean — and know what the emulator can and cannot prove. Use when a device is busy or not needed, for a fast loop on daemon-shaped code, to see an app's screen and output, or when asked to "run it in shade / the emulator".
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
xmake emulate install                          # the port's packages into the emulated image; registers its apps with SpringBoard
xmake emulate [-s 60] [--scale 10] run COMMAND # verdict: pass, fail, crash, timeout or boot-blocked
xmake emulate launch BUNDLE-ID [tap X Y | drag X1 Y1 X2 Y2 | home ...]
                                               # install + register + SpringBoard launch; app output and app-N.png snapshots
xmake emulate debug COMMAND                    # COMMAND as first guest process, under the debugger
xmake emulate log [TEXT]                       # what the last run left
xmake emulate shot [FILE]                      # its last frame
xmake emulate clean                            # this port's images and every port's shared tmp and cache (--all: every image and golden image)
```

Options: `-d DEVICE` (e.g. `iPhone3,1`; default the first catalog device of the configured
architecture that Shade has a profile for), `-r RELEASE` (default `apple_minimum`),
`-t/--timeout` (900 s for a whole boot), `-k/--keep` (keep the booted rootfs beside the log),
`-n isolated|loopback|host`, `--scale` (guest time scale, default 10).

- `fail(spawn error 2)`: the command is not in the image — `xmake emulate install` first.
- Configure the port (`xmake f -p iphoneos -a armv7 -y`) before `install`: the packages it copies
  must already be installed in the store.
- Pass `-d`: the default device is the first of the catalog, for armv7 an iPhone2,1, whose firmware
  is downloaded (about a gigabyte) and booted into a golden image first if it is not in `~/.charon`
  yet. `-d iPhone4,1 -r 6.1.3` is the fleet's 4S and has a golden image.

## Launching an application

```
xmake emulate -d iPhone4,1 -r 6.1.3 launch org.example.app tap 160 260
```

- The app needs a `CFBundleIdentifier` (`set_values("app.plist", "CFBundleIdentifier=...")`); `launch`
  refuses a bundle identifier the port's packages do not install and names the ones they do.
- It prints the app's standard output and error (`printf` + `fflush`, and `NSLog`), then one
  `app-N.png` per snapshot: `app-0.png` once the app is frontmost and Shade reports the screen still
  (`settle`, 60 display periods of guest time), then one after each step, settled the same way.
  They stay in the run folder; the log line names it.
- Steps are in points (320x480 on an iPhone, 768x1024 on an iPad), portrait, the status bar
  included: a view at y in its controller is at y + 20 on the screen.
- `-s` is how many guest seconds `charon-sblaunch` waits for SpringBoard to take the launch and make
  the app frontmost (at the default scale that is ten times as many host seconds). While the screen
  is locked, `launch` unlocks it over the control channel on its own. Its states carry guest seconds:
  on an idle machine SpringBoard took the launch of 6.1.3 at 15 s; on one loaded far past its cores
  it was not ready in 60, since a starved guest does less in each guest second. Raise `-s` (and `-t`)
  there rather than read the refusal as the app's.
- An animation that never stops never settles: the run ends at `-t` without the snapshot.
- A failure names its cause: SpringBoard's refusal code, the signal or status the app ended with, or
  that its process never started. Look at the snapshot before believing a pass: the verdict says the
  app ran and drew, not that it drew the right thing.

## What it proves and what it does not

- Daemons (`@addon/charon/daemon`, no `UIApplicationMain`) run: use it for them.
- A UIKit app started by `run` never reaches `application:didFinishLaunchingWithOptions:` — it
  bypasses SpringBoard's launch, and the frames drawn are SpringBoard's. Use `launch` for an app.
  The emulator is not the device: what depends on timing, the GPU or hardware is still held to
  hardware (workspace skill `device-session`).
- No audio daemon: `kAudioSessionNotInitialized` there is the emulator, not the code.
- Without a time scale the guest's own watchdogs expire (SpringBoard is lost to a mediaserverd
  timeout); keep the default `--scale 10`.
- A device without a Shade profile, or a release whose Darwin Shade does not emulate, is refused
  with the reason — not replaced by another.
- Images, and a rootfs kept with `-k`, live in the emulator root beside the dyld caches
  (`~/.charon/emulator`), not in the project; copy the log and verdict you need into
  `.agent-work/runs/`. Do not run `xmake emulate clean` while other sessions use the emulator: it
  always removes the shared `tmp.noindex` and `cache.noindex` too, and every other port's next run
  starts cold.
