# Backport tests

## Host

Differential tests against the host's own classes. Each script compiles the
backports for macOS (UIKit ones through Mac Catalyst) with every class they
define renamed, and compares the result with the system class on the same
inputs.

    sh host/url/run.sh
    sh host/session/run.sh      starts host/session/server.py on a free 127.0.0.1 port
    sh host/alert/run.sh
    sh host/layout/run.sh

## Device

The device tests run on an emulated iOS 6.0 (iPhone3,1). Until Charon runs the
emulator itself, a test is built by hand against the 6.0 band of the package
and started by the emulator lab:

    clang -target armv7-apple-ios6.0 -isysroot SDK -fuse-ld=LD64 -fobjc-arc -Idevice \
        device/url.m device/check.m -LBAND -lFoundationBackports -framework Foundation -o url
    ldid -S url BAND/*.dylib

and the libraries go to `/usr/lib/charon/org.charon.apple-backports/` of the
emulated root filesystem.

- `mechanism.m`, `url.m`: a process of their own, Foundation only; they print
  `ok`/`FAIL` lines and exit with the number of failures. `url.m` includes
  `url_expectations.h`, the host's results that `host/url/run.sh` writes there
  when it passes, so the device is held to the same answers.
- `session.m` with `session-scenarios.m`: started from a LaunchDaemon on a full
  boot, with `host/session/server.py` running on the host and its port as the
  second argument (`session session PORT`); it writes
  `/private/var/backports/session.log` and `session.done`.
- `alert.m`, `layout.m`: applications (`alert-Info.plist`, `layout-Info.plist`)
  launched from SpringBoard; they write `/private/var/backports/NAME.log` and
  `NAME.done`, and `alert.m` logs a `SCREENSHOT <label>` line and pauses before
  each state worth a snapshot. `layout.m` holds a table of the system
  UIStackView's frames written by `host/layout/expectations.m`.
