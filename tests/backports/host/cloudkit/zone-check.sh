#!/bin/bash
# The zone differential's own check, and the only thing that attests it.
#
# It runs FOUR things, and the first two exist because a change to this family that passes only the
# first two has not been checked:
#
#   1. every CloudKit source compiles for the port's own target - armv7-apple-ios6.1.3 against the 16.4
#      device SDK. The port compiles against headers that have no CKRecordZoneEncryptionScope and no
#      encryptionScope, while the host harness compiles against 26.2 headers that have both, so a
#      declaration written for one sysroot is a redefinition or an unknown type on the other. That is not
#      a hypothetical: this series shipped it once.
#   2. the host harness builds and links with no CloudKit framework.
#   3. the UNPLANTED comparison reads no difference, through compare.py, over binaries built here from a
#      cleared directory.
#   4. the PLANTED control fires - a plant in a scratch copy, never in a tracked file, with a sentinel
#      symbol checked in the linked binary BEFORE the plant is allowed to count, so a stale link fails
#      loudly instead of quietly reporting the previous answer.
#
# A check that cannot fail is not evidence, so a script that only did 1 and 2 would be claiming a
# comparison it never ran. It runs all four and exits non-zero if any of them does not hold.
#
#     bash tests/backports/host/cloudkit/zone-check.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../../../.." || exit 1
CL=packages/a/apple-backports/CloudKit
INC="-I packages/a/apple-backports -I $CL"
WARN="-Werror=objc-missing-property-synthesis"
WORK=${TMPDIR:-/tmp}/charon-zone-check
HOST_SDK=$(xcrun --show-sdk-path --sdk macosx)
fails=0

# The 16.4 SDK is picked by asking the store for an iPhoneOS16.4 and taking the first candidate that
# really is one, by its own SDKSettings.json - the shape coordination/lift-remeasure.sh:152 uses. A
# hardcoded digest is a path that stops existing.
sdk16=""
for candidate in "$HOME"/.xmake/packages/i/iphoneos-sdk/16.4/*/iPhoneOS16.4.sdk; do
    if [ -f "$candidate/SDKSettings.json" ] &&
       grep -q '"CanonicalName":"iphonesimulator16.4"\|"CanonicalName":"iphoneos16.4"' "$candidate/SDKSettings.json"; then
        sdk16="$candidate"; break
    fi
done

echo "== 1. the port's own target, armv7-apple-ios6.1.3 against iPhoneOS16.4 =="
if [ -z "$sdk16" ]; then
    echo "  no 16.4 SDK with an SDKSettings.json naming it; set CHARKIT_SDK_16 to one"
    fails=$((fails + 1)); sdk16=""
else
    echo "  SDK: $sdk16"
    n=0; bad=0
    for f in $CL/*.m; do
        n=$((n + 1))
        if ! xcrun clang -target armv7-apple-ios6.1.3 -isysroot "$sdk16" -fobjc-arc -Wall \
                $WARN -fsyntax-only $INC "$f" 2>"$WORK.err"; then
            bad=$((bad + 1)); echo "  FAIL $(basename "$f")"; head -2 "$WORK.err"
        fi
    done
    echo "  $n sources, $((n - bad)) exit 0, $bad non-zero"
    [ "$bad" -ne 0 ] && fails=$((fails + 1))
fi

echo "== 2. the host harness, no framework linked =="
rm -rf "$WORK"; mkdir -p "$WORK/obj" "$WORK/plant"
for f in $CL/*.m; do
    xcrun clang -c -target arm64-apple-ios13.1-macabi -isysroot "$HOST_SDK" -fobjc-arc \
        $INC -o "$WORK/obj/$(basename "${f%.m}").o" "$f" 2>/dev/null
done
link_port() {   # $1 = the CKRecords8 object to use, $2 = the binary
    xcrun clang -target arm64-apple-ios13.1-macabi -isysroot "$HOST_SDK" -fobjc-arc \
        -framework Foundation -framework CoreLocation $INC -I tests/backports/host/cloudkit \
        -o "$2" tests/backports/host/cloudkit/zone-port.m tests/backports/host/cloudkit/database-cases.m \
        "$1" "$WORK/obj/CKConstants8.o" 2>"$WORK.link.log"
}
if link_port "$WORK/obj/CKRecords8.o" "$WORK/zone-port"; then
    echo "  exit 0, binary $(stat -f %z "$WORK/zone-port") bytes"
else
    echo "  FAIL the link:"; head -4 "$WORK.link.log"; fails=$((fails + 1))
fi
xcrun clang -target arm64-apple-ios13.1-macabi -isysroot "$HOST_SDK" \
    -framework Foundation -framework CloudKit -o "$WORK/host" \
    tests/backports/host/cloudkit/database-host.m tests/backports/host/cloudkit/database-cases.m \
    2>"$WORK.host.log" || { echo "  FAIL the host build:"; head -3 "$WORK.host.log"; fails=$((fails + 1)); }

echo "== 3. the unplanted comparison, through compare.py =="
if [ -x "$WORK/zone-port" ] && [ -x "$WORK/host" ]; then
    CLOUDKIT_DATABASE="$WORK/host.json" "$WORK/host" >/dev/null 2>&1
    CLOUDKIT_ZONE="$WORK/port.json" "$WORK/zone-port" >/dev/null 2>&1
    out=$(python3 tests/backports/host/cloudkit/compare.py "$WORK/host.json" "$WORK/port.json" 2>&1)
    code=$?
    echo "$out" | sed 's/^/  /'
    if [ "$code" -ne 0 ]; then
        echo "  FAIL the unplanted comparison must read no difference"; fails=$((fails + 1))
    fi
else
    echo "  skipped: a binary is missing"; fails=$((fails + 1))
fi

echo "== 4. the planted control, in a scratch copy, sentinel checked first =="
if [ -x "$WORK/zone-port" ]; then
    cp $CL/CKRecords8.m "$WORK/plant/CKRecords8.m"
    python3 - "$WORK/plant/CKRecords8.m" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
zone = text.index("@implementation CKRecordZone {")
at = text.index("- (BOOL)isEqual:(id)other", zone)      # inside CKRecordZone, not CKRecordZoneID's
text = text[:at] + "int CharonPlantMarker = 1;\n\n- (NSInteger)capabilities { return 7; }\n\n" + text[at:]
open(path, "w").write(text)
PY
    xcrun clang -c -target arm64-apple-ios13.1-macabi -isysroot "$HOST_SDK" -fobjc-arc \
        $INC -o "$WORK/plant/CKRecords8.o" "$WORK/plant/CKRecords8.m" 2>"$WORK.plant.log" \
        || { echo "  FAIL the scratch copy did not compile"; fails=$((fails + 1)); }
    if link_port "$WORK/plant/CKRecords8.o" "$WORK/zone-planted" &&
       nm "$WORK/zone-planted" 2>/dev/null | grep -q CharonPlantMarker; then
        CLOUDKIT_ZONE="$WORK/port-planted.json" "$WORK/zone-planted" >/dev/null 2>&1
        out=$(python3 tests/backports/host/cloudkit/compare.py "$WORK/host.json" "$WORK/port-planted.json" 2>&1)
        code=$?
        echo "  the sentinel IS in the linked binary, so the link is not stale"
        echo "$out" | grep -E "^[0-9]+ differ|differ:" | sed 's/^/  /'
        if [ "$code" -eq 0 ]; then
            echo "  FAIL the planted control did not fire - the comparison is not sensitive"
            fails=$((fails + 1))
        else
            echo "  the control fired: the comparison catches a wrong answer"
        fi
    else
        echo "  FAIL the planted link or the sentinel: a stale link would report the previous answer"
        fails=$((fails + 1))
    fi
else
    echo "  skipped: the port binary is missing"; fails=$((fails + 1))
fi

echo "zone-check: $fails failing step(s)"
[ "$fails" -eq 0 ] || exit 1
exit 0
