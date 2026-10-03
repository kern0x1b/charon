BUILD_FLAGS="-Os -g0 -Wall -Wno-unguarded-availability-new -Wno-unguarded-availability -Werror=objc-missing-property-synthesis -Werror=incompatible-pointer-types -fobjc-arc"

# WHY THIS FILE IS TRACKED, since .agent-work/ is excluded and the point of holding the flags is that a
# later compile uses them.  A band that keeps its compiler flags in its own scratch area re-derives them
# by memory, and a re-derived pair is how the gate's -Wincompatible-pointer-types finding was missed:
# -Wall alone does not make a pointer-type mismatch an error.
#
# NOTHING READS THIS FILE, and this line used to say otherwise.  It claimed the flags were read at
# modules/apple/backports.lua:473; `git grep build-flags` finds no reader in this repository, and
# backports.lua:473 is a function header, not a read.  A tracked artefact that names a reader it does not
# have reads as authoritative to the next band, which is the exact failure the file exists to prevent, so
# what the build actually does is named here instead.  The build assembles its own list:
#
#   modules/apple/backports.lua:497   per source: -Os -g0 -Wall -Wno-unguarded-availability-new
#                                                    -Wno-unguarded-availability, and
#                                                    -Werror=objc-missing-property-synthesis (ObjC) or
#                                                    -fvisibility=hidden (C)
#   modules/apple/backports.lua:551   compile_arguments(), the same list for a caller that asks
#   modules/apple/backports.lua:313   -fobjc-arc for an Objective-C source, and :315
#                                    -Xclang -fobjc-runtime-has-weak below a 5.0 deployment
#
# SO THE LIST ABOVE IS NOT THE BUILD'S, and differs from it in exactly two flags:
# -Werror=incompatible-pointer-types and -fobjc-arc are this file's, not the build's.  -fobjc-arc the
# build does pass, from :313 rather than from the list at :497; -Werror=incompatible-pointer-types it does
# not, and that is the point of a hand-kept copy - a per-file compile that makes a pointer-type mismatch
# an error finds the gate's finding without the gate.  Read the three lines above before believing a flag
# here is the build's: nothing checks this file against them, and a build that changes its list leaves
# this one stale.
#
# WHERE 4.3 ACTUALLY COMES FROM, since a wrong mechanism here is what this file is for.  There is ONE
# armv7 architecture whose first release is 3.0 (modules/apple/architectures.lua:5) - that file lists
# ARCHITECTURES, and a DEPLOYMENT FLOOR is a different axis, which is how the earlier version of this
# comment came to claim "two deployment floors" and be wrong.  4.3 is a PER-SOURCE minimum, read out of
# the registry: floors() takes the highest `minimum` of a source's own rows
# (modules/apple/backports.lua:743-745, collected into floor[file] at :770), and a compiled object whose
# own minimum is above the deployment is built for that minimum with the triple
# opt.architecture .. "-apple-ios" .. minimum (modules/apple/backports.lua:841-843).  So an object is
# absent below its own rows' floor and present from it, over one deployment.
#
# THE WEAK REFERENCE AT 4.3, re-measured rather than carried.  This file used to claim that only
# -fobjc-runtime=ios-6.1.3 removed an error, one variable at a time on main's own UIAlertController.m at
# armv7-apple-ios4.3.  That does not reproduce with this tree's clang
# (~/.xmake/packages/l/llvm/23.1.1/*/bin/clang), measured today, -c as well as -fsyntax-only, each run
# counting the lines matching " error: ":
#
#   -fobjc-arc                                              0 errors
#   -fobjc-arc -fobjc-weak                                  0 errors
#   -fobjc-arc -fobjc-weak -fobjc-runtime=ios-6.1.3         0 errors
#   -fobjc-arc -Xclang -fobjc-runtime-has-weak              0 errors
#
# So the diagnostic the old measurement caught does not fire with this compiler at all, and the rule that
# follows is not "add the runtime flag" but "pass what the build passes": -Xclang -fobjc-runtime-has-weak,
# which backports.lua:315 adds below a 5.0 deployment.  A manual compile at 4.3 that leaves it out is not
# compiling the way the package compiles.