#!/bin/sh
# run.sh — two things, and both of them have to be able to fail.
#
# 1. The DEVICE side: what the system's WKWebView does for every case of device/webkit-cases.m, under Mac
#    Catalyst, written where the device test reads it, so the port over UIWebView is held to the same ones.
# 2. The HOST differentials, which are what hold the web-extension families to this machine's own WebKit:
#      - webextension.m          the 77 recorded answers of the extension, pattern, action and context families
#      - webextension-controller  the controller family, asked of the SYSTEM with no port code in the process
#                                and then asked of the PORT, with the two answers compared case by case
#
# The controller test exists because a row that says implemented has to be held to something. Neither program
# was built or run by this script before, so a wrong answer in the port could not fail anything: the
# programs are the evidence and they have to be in the loop, and the script's exit status is the whole verdict.
# Each host program is built, run, and its status taken; nothing here is allowed to pass by not running.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
device=${DEVICE:-$here/../../device}
build=${BUILD:-$(mktemp -d)}
# BUILD may come from the environment, and an environment-supplied directory does not exist yet the way
# mktemp's does; nothing here creates it, so the first link fails on a missing output path.
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path)
sources=${WEBEXT_SOURCES:-$here/../../../../packages/a/apple-backports/WebKit}
harness=${WEBEXT_HARNESS:-$here/../../device}
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
frameworks="-framework WebKit -framework UIKit -framework Foundation"
status=0
note() { printf '%s\n' "$*"; }
failed() { printf 'FAIL %s\n' "$*"; status=1; }

# ---------------------------------------------------------------- the device's expectations
xcrun clang $target -fobjc-arc -w -I"$device" \
    "$here/record.m" "$device/webkit-cases.m" -framework UIKit -framework WebKit -framework Foundation -o "$build/record"
(cd "$build" && ./record "$build/webkit.json" > "$build/webkit.log" 2>&1)
python3 "$here/../foundation2/embed.py" "$build/webkit.json" "$device/webkit-expectations.h"
sed -i.bak 's/foundation2_expectations/webkit_expectations/' "$device/webkit-expectations.h" && rm -f "$device/webkit-expectations.h.bak"
note "records: $(python3 -c "import json,sys; print(len(json.load(open('$build/webkit.json'))))")"

# ---------------------------------------------------------------- the extension families' 77 answers
# WEBEXT_MANIFEST must be ABSOLUTE: a relative one takes WebKit's extension loader down (exit 137) with no
# error, which is what webextension.m's own header is about. It is resolved here rather than left to the
# caller's shell so that a run from anywhere gets the same path.
manifest=$here/manifest/manifest.json
if [ ! -f "$manifest" ]; then
    failed "no manifest at $manifest: webextension.m cannot build an extension without one"
else
    xcrun clang $target -fobjc-arc -w "$here/webextension.m" $frameworks -o "$build/webextension"
    if WEBEXT_MANIFEST="$manifest" "$build/webextension" > "$build/webextension.log" 2>&1; then
        note "webextension: exit=0 cases=$(grep -c . "$build/webextension.log") log=$build/webextension.log"
    else
        result=$?
        grep -v '^ok ' "$build/webextension.log" | head -20 || true
        failed "webextension: exit=$result log=$build/webextension.log"
    fi
fi

# ---------------------------------------------------------------- the controller family, port against system
# The port is built in two passes, because renames.sh reads the classes out of the objects and the flags that
# rename them are needed to compile them. Pass one is plain -- with -DCHARON_HOST_DIFFERENTIAL, so the port's
# own headers step aside and the host's declarations are used, which is what keeps the port's @implementation
# and the SDK's @interface from being two declarations of one name. Pass two adds the renames, and the test is
# compiled with the same flags, so the scenario's class names name the port's classes and not Apple's.
. "$here/renames.sh"
port_files="WKWebExtension.m WKWebExtensionAction.m WKWebExtensionContext.m WKWebExtensionController.m WKWebExtensionMatchPattern.m"
port_headers="CharonWebExtension.h CharonWebExtensionController.h"
port_flags="-DCHARON_HOST_DIFFERENTIAL=1 -fobjc-arc -fvisibility=hidden -w"
mkdir -p "$build/plain" "$build/port"
plain=""
for f in $port_files; do
    if ! xcrun clang $target $port_flags -I"$sources" -c "$sources/$f" -o "$build/plain/$f.o" 2> "$build/plain/$f.diagnostic"; then
        failed "the port's $f does not compile for the host"
        grep -m3 'error:' "$build/plain/$f.diagnostic" | sed 's|^|    |'
    fi
    plain="$plain $build/plain/$f.o"
done
rename_inputs=""
for f in $port_headers $port_files; do rename_inputs="$rename_inputs $sources/$f"; done
renames "$rename_inputs" $plain > "$build/renames.flags"
note "renamed: $(grep -c "" "$build/renames.flags" | tr -d ' ') class and symbol names"
built=""
for f in $port_files; do
    if xcrun clang $target $port_flags -I"$sources" $(cat "$build/renames.flags") -c "$sources/$f" -o "$build/port/$f.o" 2> "$build/port/$f.diagnostic"; then
        built="$built $build/port/$f.o"
    else
        failed "the port's $f does not compile with the renames"
        grep -m3 'error:' "$build/port/$f.diagnostic" | sed 's|^|    |'
    fi
done

expected="$build/controller.expected"
# The scenario asks two cases of a REAL extension, and it asks them the same way on both sides or the
# comparison would be of two different question lists. WEBEXT_MANIFEST is exported rather than passed to
# one program, for that reason.
WEBEXT_MANIFEST="$manifest"
export WEBEXT_MANIFEST
# the system side first, and in a process with none of the port's code: this is what the port is held to
xcrun clang $target -fobjc-arc -w -I"$harness" -I"$here" "$here/webextension-controller_system.m" "$harness/check.m" $frameworks -o "$build/controller-system"
if CHARON_EXPECTED="$expected" "$build/controller-system" > "$build/controller-system.log" 2>&1; then
    # the recorder's own count, not wc -l: the file is N records joined by N-1 newlines
    note "controller-system: exit=0 answers=$(grep -c '^case ' "$expected" | tr -d ' ') log=$build/controller-system.log"
else
    result=$?
    failed "controller-system: exit=$result log=$build/controller-system.log"
fi
# then the port, against those answers
xcrun clang $target -fobjc-arc -w -I"$harness" -I"$here" -I"$sources" -DCHARON_HOST_DIFFERENTIAL=1 $(cat "$build/renames.flags") \
    "$here/webextension-controller_test.m" "$harness/check.m" $built $frameworks -o "$build/controller-port"
if CHARON_EXPECTED="$expected" "$build/controller-port" > "$build/controller-port.log" 2>&1; then
    result=0
else
    result=$?
fi
grep -v '^ok ' "$build/controller-port.log" || true
note "controller-port: exit=$result log=$build/controller-port.log"
[ "$result" = 0 ] || failed "the port's controller family does not answer what this host answers"

exit $status
