BUILD_FLAGS="-Os -g0 -Wall -Wno-unguarded-availability-new -Wno-unguarded-availability -Werror=objc-missing-property-synthesis -Werror=incompatible-pointer-types -fobjc-arc"

# WHY THIS FILE IS TRACKED, since .agent-work/ is excluded and the point of holding the flags is that a
# later compile uses them.  A band that keeps its compiler flags in its own scratch area re-derives them
# by memory, and a re-derived pair is how the gate's -Wincompatible-pointer-types finding was missed:
# -Wall alone does not make a pointer-type mismatch an error.
#
# It is read at modules/apple/backports.lua:473.  If that line changes, this file is stale - which is
# why the line number is in the comment above rather than only here.
#
# TWO DEPLOYMENT FLOORS, not one.  There is ONE armv7 architecture whose first release is 3.0
# (modules/apple/architectures.lua:5) - that file lists ARCHITECTURES, and a deployment floor is a
# different axis - and the package builds it at the two floors it declares, 6.1.3 and 4.3.  The triple
# is architecture-architecture .. "-apple-ios" .. minimum at backports.lua:819, so the two floors are two
# triples over one architecture.  The package names the 4.3 gate in its own comments and bisected it over
# 2fde39f4 (backports.lua:1396-1397).
#
# AND THE RUNTIME FLAG IS WHAT MAKES 4.3 WORK, measured one variable at a time on main's own
# UIAlertController.m at armv7-apple-ios4.3:
#
#   -fobjc-arc                                        1 error
#   -fobjc-arc -fobjc-weak                            1 error
#   -fobjc-arc -fobjc-weak -fobjc-runtime=ios-6.1.3   0 errors
#
# -fobjc-weak is NOT what makes __weak legal at 4.3; the objc RUNTIME is, and the build passes it
# (backports.lua:291, -Xclang -fobjc-runtime-has-weak).  Leave it out and every __weak in the package
# fails, which looks like 73 broken files - on main's own - and is nothing of the sort.
