#!/bin/sh
# swiftc -typecheck for one file at armv7-apple-ios6.1.3, with the port's own flags: the 26.2 SDK
# under the lift's vfs overlay, the swift-runtime's armv7 swiftmodules and its shim modulemap, and
# the toolchain's own clang include so stdarg.h resolves. Every path from the environment, so the
# file carries none of this machine's.
: "${CHARON_SWIFT_RUNTIME:?the installed charon@swift-runtime}"
: "${CHARON_SWIFTC:?the swift compiler}"
: "${CHARON_SDK26:?the 26.2 SDK}"
: "${CHARON_LIFT_VFS:?the lift's vfs.yaml}"
: "${CHARON_SWIFT_CLANG_INCLUDE:?the toolchain's clang include}"
exec "$CHARON_SWIFTC" -typecheck -target armv7-apple-ios6.1.3 -sdk "$CHARON_SDK26" \
  -resource-dir "$(dirname "$(dirname "$CHARON_SWIFTC")")" \
  -I "$CHARON_SWIFT_RUNTIME/lib/swift/iphoneos" \
  -Xcc "-fmodule-map-file=$CHARON_SWIFT_RUNTIME/lib/swift/shims/module.modulemap" \
  -Xcc -ivfsoverlay -Xcc "$CHARON_LIFT_VFS" \
  -Xcc -I -Xcc "$CHARON_SWIFT_CLANG_INCLUDE" "$@"
