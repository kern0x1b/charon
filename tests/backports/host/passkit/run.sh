#!/bin/sh
# The PassKit Secure Element and the wallet: one case per member, driven against the PORT'S OWN
# renamed classes, with a mutant that answers YES where a registry row says NO.
#
# The port's categories are compiled onto classes the run renames (charonHost_PKPassLibrary and the
# rest), so the runner reaches the port through the runtime and never the host's PassKit. The value
# is checked against the port's own registry rows, because a Mac answers these from a real Secure
# Element and this device has none -- the host is not the oracle for what a 4S should say. It IS the
# oracle for PKPassKitErrorDomain, and the last case uses it.
#
# The probe FAILS if the mutant does not differ, because a green mutant is a comparison that decides
# nothing, and FAILS if the real run made fewer than 31 cases, because then it is not covering the
# thirty-one members the registry rows name.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${PORT:-$here/../../../../packages/a/apple-backports/PassKit}
# BUILD goes under the repository's own .agent-work, never the system temp: the run output is
# evidence and belongs with the band's runs. Same rule as the other probes in this package.
build=${PASSKIT_BUILD:-$PWD/.agent-work/runs/passkit}
mkdir -p "$build"
rm -f "$build"/cc.log "$build"/runner.log "$build"/*.txt "$build"/*.body "$build"/*.dylib "$build"/runner
MACOSX_SDK=$(xcrun --sdk macosx --show-sdk-path)
TARGET="-target arm64-apple-ios17.0-macabi -isysroot $MACOSX_SDK -isystem $MACOSX_SDK/System/iOSSupport/usr/include -F $MACOSX_SDK/System/iOSSupport/System/Library/Frameworks"
RENAME="-DPKPassLibrary=charonHost_PKPassLibrary \
    -DPKPaymentAuthorizationController=charonHost_PKPaymentAuthorizationController \
    -DPKPaymentAuthorizationViewController=charonHost_PKPaymentAuthorizationViewController \
    -DPKAddPassesViewController=charonHost_PKAddPassesViewController"

# The shim names the four classes literally, so it is compiled WITHOUT the -D renames -- the renames
# exist to move the PORT's references, and the shim's whole job is to declare what they moved onto.
xcrun clang -fobjc-arc -Wall -fPIC $TARGET -DCHARON_HOST_PROBE=1 \
    -I"$port" -framework Foundation -framework PassKit -framework UIKit \
    -c "$here/port-classes.m" -o "$build/port-classes.o" 2> "$build/ccclasses.log" || {
        grep -m5 ': error:' "$build/ccclasses.log" || true; exit 1; }

build_port() {
    out=$1
    shift
    xcrun clang -fobjc-arc -Wall -fPIC -dynamiclib $TARGET -DCHARON_HOST_PROBE=1 $RENAME \
        -I"$port" -framework Foundation -framework PassKit -framework UIKit \
        "$build/port-classes.o" "$port/CharonPassKit.m" "$port/PKSecureElement8.m" "$port/PKWallet.m" -o "$out" 2> "$build/cc.log" || {
            grep -m5 ': error:' "$build/cc.log" || true; exit 1; }
}
build_port "$build/libport.dylib"
# The mutant: the SAME source, one line changed -- a NO that becomes YES, which is the answer a row
# forbids. mutate.py asserts the line is there, so a renamed line fails the build rather than
# producing a mutant that is quietly identical to the real run.
cp "$port/PKSecureElement8.m" "$build/PKSecureElement8.mutated.m"
python3 - "$build/PKSecureElement8.mutated.m" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = """+ (BOOL)canMakePayments
{
    return NO;
}"""
new = """+ (BOOL)canMakePayments
{
    return YES;
}"""
assert old in text, "the line the mutant changes is not there: the mutant would be the real run"
open(path, "w").write(text.replace(old, new, 1))
PY
xcrun clang -fobjc-arc -Wall -fPIC -dynamiclib $TARGET -DCHARON_HOST_PROBE=1 $RENAME \
    -I"$port" -framework Foundation -framework PassKit -framework UIKit \
    "$build/port-classes.o" "$port/CharonPassKit.m" "$build/PKSecureElement8.mutated.m" "$port/PKWallet.m" \
    -o "$build/libmutant.dylib" 2> "$build/ccmut.log" || {
        grep -m5 ': error:' "$build/ccmut.log" || true; exit 1; }

xcrun clang -fobjc-arc -Wall $TARGET -ldl -framework Foundation -framework PassKit -framework UIKit \
    "$here/runner.m" -o "$build/runner" 2> "$build/runner.log" || {
        grep -m5 ': error:' "$build/runner.log" || true; exit 1; }

DYLD_FRAMEWORK_PATH="$MACOSX_SDK/System/iOSSupport/System/Library/Frameworks" \
    CHARON_PORT_DYLIB="$build/libport.dylib" "$build/runner" > "$build/real.txt" 2>&1 && true
DYLD_FRAMEWORK_PATH="$MACOSX_SDK/System/iOSSupport/System/Library/Frameworks" \
    CHARON_PORT_DYLIB="$build/libmutant.dylib" "$build/runner" > "$build/mutant.txt" 2>&1 && true
cat "$build/real.txt"; cat "$build/mutant.txt"

body() { grep -E '^  [A-Za-z]' "$1"; }
body "$build/real.txt" > "$build/real.body"
body "$build/mutant.txt" > "$build/mutant.body"
cases=$(wc -l < "$build/real.body" | tr -d ' ')
echo "--- the real run made $cases check line(s):"
if [ "$cases" -lt 31 ]; then
    echo "FAIL only $cases of the thirty-one members reached, so the probe is not covering them"
    exit 1
fi
if grep -q 'FAIL$' "$build/real.body"; then
    echo "FAIL the real run has a failing case:"
    grep 'FAIL$' "$build/real.body"
    exit 1
fi
echo "ok the real run's every case matches the row it checks"
if diff -q "$build/real.body" "$build/mutant.body" >/dev/null 2>&1; then
    echo "FAIL the mutant does not differ from the real run: this comparison cannot see a wrong"
    echo "     answer, so a green run here would decide nothing"
    exit 1
fi
echo "ok the mutant differs, so the comparison does see the value it is checking"
diff -u "$build/real.body" "$build/mutant.body" | sed -n '1,8p'
exit 0
