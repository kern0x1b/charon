#!/bin/sh
# run.sh — the four names a stream task's transaction reports about the socket, against the host's own.
#
# The port's classes are compiled under names of their own (uikit2/renames.sh with "*", which renames
# the classes and leaves the selectors), so the two sides never meet. The listener is the test's own
# and writes one byte when a connection lands, and the test bounds its own run, so a run that goes
# wrong fails rather than hanging the host test sweep.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
sources=${SOURCES:-$here/../../../../packages/a/apple-backports/Foundation}
harness=${HARNESS:-$here/../../device}
build=${BUILD:-$(mktemp -d)}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
# CHARON_HOST_BUILD: this is a host differential - the port's classes are renamed into names of their
# own and the system's Foundation is in the same process, so there is no release class for a
# charon_alias.h proxy to stand in for, nothing for the library's loader to re-parent and no name to
# export. The header's own comment gives the two measurements: the macOS linker refuses the metaclass
# alias ("ld: null objc class data for '_OBJC_METACLASS_$_Charon<Name>'", from the smallest file that
# carries nothing but CHARON_ALIAS), and a name built by ## cannot be renamed the way the line below
# renames classes. What the alias is FOR is a device band; here the class of the release's name is the
# class, and the seven members below are measured on it.
flags="-fobjc-arc -fvisibility=hidden -DCHARON_HOST_BUILD -Wall -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-incomplete-implementation -Wno-objc-property-implementation -Wno-nullability-completeness"
files="NSURLSessionStreamTask9.m NSURLSession+StreamTask9.m CharonStreamTaskState.m NSURLSessionTaskMetrics.m NSURLSessionTaskTransactionMetrics+Counts13.m"
mkdir -p "$build/plain" "$build/ported"
. "$here/../uikit2/renames.sh"
objects=""
for file in $files; do
    xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$file.o"
    objects="$objects $build/plain/$file.o"
done
renames "$objects" "*" > "$build/flags"
# Which of the five files carries a category on a class the RELEASE owns, and which on a class the port
# defines, decides how that file is built. The second kind needs nothing: the -D line above gave that
# class a name of its own, its methods land on it, and none of them can reach the host's class of the
# same name. The first kind needs two more things, and both are there for the same measured reason:
#   * its selectors renamed, by prefix_selectors.py, which is what test.m has been asking for all along
#     (charonHost_streamTaskWithHostName:port:): -[NSURLSession streamTaskWithHostName:port:] is the
#     RELEASE's own method of that selector, so a category carrying it unchanged replaced it at load.
#     Measured 2026-10-04 on this tree: the task this test calls "the host's own" was a
#     CharonHostNSURLSessionStreamTask made by the port's factory, so the run died on the LEFT side of
#     the differential and every answer compared was the port's against the port's.
#   * its category section renamed to __charon_catlist, so the loader does not apply it at load and
#     host-attach.c applies it at run time under those prefixed names.
# A category on a class the port defines keeps __objc_catlist: host-attach.c's class_addMethod refuses a
# selector the class already answers, and the port's own NSURLSessionTaskTransactionMetrics has
# -isProxyConnection already, auto-synthesized out of the SDK's own @property. The device's loader makes
# the same cut, in attach.c's charon_collect: a member the class already implements is not collected.
#
# WHICH IS WHICH is read out of the objects, not listed beside them, so a source added to the line above
# is built the right way without this file being edited: a method symbol of a category carries its owner
# ([-NSURLSession(CharonStreamTask) ...]), and the owners that are among the classes the objects define
# are the port's own. That is the same cut prefix_selectors.py makes in its own ported().
defined=$(xcrun nm -gU "$build"/plain/*.o | awk '$3 ~ /^_OBJC_CLASS_\$_/ { sub(/^_OBJC_CLASS_\$_/, "", $3); print $3 }' | sort -u)
built=""
for file in $files; do
    owners=$(xcrun nm "$build/plain/$file.o" |
        awk 'match($0, /[-+][[][A-Za-z0-9_]+[(]Charon[A-Za-z0-9_]*[)]/) { owner = substr($0, RSTART, RLENGTH); sub(/^[-+][[]/, "", owner); sub(/[(]Charon.*/, "", owner); print owner }' |
        sort -u)
    release_owns=""
    for owner in $owners; do
        if ! printf '%s\n' "$defined" | grep -qx "$owner"; then
            release_owns=yes
        fi
    done
    if [ -n "$release_owns" ]; then
        # shellcheck disable=SC2046
        python3 "$here/../prefix_selectors.py" "$sources/$file" "$build/ported/$file" charonHost_ \
            $target -DCHARON_HOST_BUILD -I"$sources" -- $build/plain/*.o
        # shellcheck disable=SC2046
        xcrun clang $target $flags -I"$sources" $(cat "$build/flags") -c "$build/ported/$file" -o "$build/ported/$file.o"
        perl -0777 -pi -e 's/__objc_catlist\0\0/__charon_catlist/g' "$build/ported/$file.o"
    else
        # shellcheck disable=SC2046
        xcrun clang $target $flags $(cat "$build/flags") -c "$sources/$file" -o "$build/ported/$file.o"
    fi
    built="$built $build/ported/$file.o"
done
xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/test.m" "$harness/check.m" "$here/../foundation2/host-attach.c" $built \
    -framework Foundation -framework CoreServices -framework Security -framework SystemConfiguration -o "$build/test"
if command -v gtimeout >/dev/null 2>&1; then outer="gtimeout 300"; else outer=""; fi
if $outer "$build/test" > "$build/test.log" 2>&1; then result=0; else result=$?; fi
grep -v '^ok ' "$build/test.log" || true
echo "streammetrics: exit=$result log=$build/test.log"
exit "$result"
