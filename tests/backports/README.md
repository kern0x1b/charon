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
    sh host/foundation2/run.sh  writes device/foundation2-expectations.h when it passes

`host/foundation2/run.sh` runs the cases of `device/foundation2-cases.m`, the
ones the device runs, against the host's Foundation and against the renamed
backports, compares the two and embeds the host's answers in
`device/foundation2-expectations.h`; it attaches the categories itself
(`host-attach.c`), since the host linker leaves `__objc_catlist` alone.

## Device

The device tests run on an emulated iOS 6.0 (iPhone3,1). Until Charon runs the
emulator itself, a test is built by hand against the 6.0 band of the package
and started by the emulator lab:

    clang -target armv7-apple-ios6.0 -isysroot SDK -fuse-ld=LD64 -fobjc-arc -Idevice \
        device/url.m device/check.m -LBAND -lFoundationBackports -framework Foundation -o url
    ldid -S url BAND/*.dylib

and the libraries reach `/usr/lib/charon/org.charon.apple-backports/` of the
emulated root filesystem the way a device gets them: the data of
`org.charon.apple-backports_<revision>_iphoneos-arm.deb` unpacked into it and its
postinst run with `DPKG_ROOT` set to it.

- `mechanism.m`, `url.m`: a process of their own, Foundation only; they print
  `ok`/`FAIL` lines and exit with the number of failures. `url.m` includes
  `url_expectations.h`, the host's results that `host/url/run.sh` writes there
  when it passes, so the device is held to the same answers.
- `session.m` with `session-scenarios.m`: started from a LaunchDaemon on a full
  boot, with `host/session/server.py` running on the host and its port as the
  second argument (`session session PORT`); it writes
  `/private/var/backports/session.log` and `session.done`.
- `foundation2.m` with `foundation2-cases.m`: a process of their own, the second
  Foundation batch; it holds each case to `foundation2-expectations.h` and
  names, for every backported method, the image its implementation comes from,
  so a method the release already has is never taken from the library.
- `tolerance.m`: a process of its own, the timer tolerance, which is a property
  and two CoreFoundation functions.
- `alert.m`, `layout.m`: applications (`alert-Info.plist`, `layout-Info.plist`)
  launched from SpringBoard; they write `/private/var/backports/NAME.log` and
  `NAME.done`, and `alert.m` logs a `SCREENSHOT <label>` line and pauses before
  each state worth a snapshot. `layout.m` holds a table of the system
  UIStackView's frames written by `host/layout/expectations.m`.
