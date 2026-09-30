BUILD_FLAGS="-Os -g0 -Wall -Wno-unguarded-availability-new -Wno-unguarded-availability -Werror=objc-missing-property-synthesis -Werror=incompatible-pointer-types -fobjc-arc"

# WHY THIS FILE IS TRACKED, since .agent-work/ is excluded and the point of holding the flags is that a
# later compile uses them.  A band that keeps its compiler flags in its own scratch area re-derives them
# by memory, and a re-derived pair is how the gate's -Wincompatible-pointer-types finding was missed:
# -Wall alone does not make a pointer-type mismatch an error.
#
# It is read at modules/apple/backports.lua:473.  If that line changes, this file is stale - which is
# why the line number is in the comment above rather than only here.
#
# ONE BAND, NOT TWO.  There is one armv7 band and it deploys 6.1.3 (modules/apple/architectures.lua:5);
# no architecture names 4.3.  Compiling at an invented armv7-apple-ios4.3 makes clang apply its own
# weak-reference floor and every __weak in the package fails, which looks like 73 broken files and is
# not one of them.
