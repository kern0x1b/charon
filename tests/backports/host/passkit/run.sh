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
# nothing, and FAILS if the real run made fewer than 31 members, because then it is not covering the
# thirty-one the registry rows name. The floor counts the 31 MEMBERS, not the check lines: the
# operations each take two lines (the ok flag and the error's shape) and that is the honest unit.
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
        -DCHARON_PASSKIT_STANDIN=1 \
        "$build/port-classes.o" "$port/CharonPassKit.m" "$port/PKSecureElement8.m" "$port/PKWallet.m" \
        "$port/PKPaymentAuthorizationController10.m" "$port/PKPaymentAuthorizationViewController8.m" \
        "$port/PKPaymentAuthorizationViewController9.m" -o "$out" 2> "$build/cc.log" || {
            grep -m5 ': error:' "$build/cc.log" || true; exit 1; }
}
build_port "$build/libport.dylib"
# The mutant: the SAME source, one line changed -- a NO that becomes YES, which is the answer a row
# forbids. mutate.py asserts the line is there, so a renamed line fails the build rather than
# producing a mutant that is quietly identical to the real run.
# The NO that becomes YES now lives in the class object, since that is where the class and its
# capability answers are: the two controller categories left PKSecureElement8.m in the previous commit,
# so mutating THAT file is mutating a file that no longer has the line -- and the assert below is what
# says so instead of producing a mutant that is quietly the real run.
cp "$port/PKPaymentAuthorizationController10.m" "$build/PKPaymentAuthorizationController10.mutated.m"
python3 - "$build/PKPaymentAuthorizationController10.mutated.m" <<'PY'
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
# A SECOND mutant, on the shared error rather than on a capability: one code changed, so the
# comparison is shown to see the error's VALUE and not only the NO. Two mutants, because one kind of
# mutation that goes red is not evidence that the other would.
cp "$port/CharonPassKit.m" "$build/CharonPassKit.mutated.m"
python3 - "$build/CharonPassKit.mutated.m" <<'PY2'
import sys
text = open(sys.argv[1]).read()
old = "code:PKUnsupportedVersionError"
new = "code:PKInvalidSignature"
assert old in text, "the code the mutant changes is not there"
open(sys.argv[1], "w").write(text.replace(old, new, 1))
PY2
xcrun clang -fobjc-arc -Wall -fPIC -dynamiclib $TARGET -DCHARON_HOST_PROBE=1 $RENAME \
    -I"$port" -framework Foundation -framework PassKit -framework UIKit \
    "$build/port-classes.o" "$port/CharonPassKit.m" "$build/PKSecureElement8.mutated.m" "$port/PKWallet.m" \
    -o "$build/libmutant.dylib" 2> "$build/ccmut.log" || {
        grep -m5 ': error:' "$build/ccmut.log" || true; exit 1; }
xcrun clang -fobjc-arc -Wall -fPIC -dynamiclib $TARGET -DCHARON_HOST_PROBE=1 $RENAME \
    -I"$port" -framework Foundation -framework PassKit -framework UIKit \
    -DCHARON_PASSKIT_STANDIN=1 \
    "$build/port-classes.o" "$build/CharonPassKit.mutated.m" "$port/PKSecureElement8.m" "$port/PKWallet.m" \
    "$port/PKPaymentAuthorizationController10.m" "$port/PKPaymentAuthorizationViewController8.m" \
    "$port/PKPaymentAuthorizationViewController9.m" -o "$build/libmutant2.dylib" 2> "$build/ccmut2.log" || {
        grep -m5 ': error:' "$build/ccmut2.log" || true; exit 1; }

xcrun clang -fobjc-arc -Wall $TARGET -ldl -framework Foundation -framework PassKit -framework UIKit \
    "$here/runner.m" -o "$build/runner" 2> "$build/runner.log" || {
        grep -m5 ': error:' "$build/runner.log" || true; exit 1; }

DYLD_FRAMEWORK_PATH="$MACOSX_SDK/System/iOSSupport/System/Library/Frameworks" \
    CHARON_PORT_DYLIB="$build/libport.dylib" "$build/runner" > "$build/real.txt" 2>&1 && true
DYLD_FRAMEWORK_PATH="$MACOSX_SDK/System/iOSSupport/System/Library/Frameworks" \
    CHARON_PORT_DYLIB="$build/libmutant.dylib" "$build/runner" > "$build/mutant.txt" 2>&1 && true
DYLD_FRAMEWORK_PATH="$MACOSX_SDK/System/iOSSupport/System/Library/Frameworks" \
    CHARON_PORT_DYLIB="$build/libmutant2.dylib" "$build/runner" > "$build/mutant2.txt" 2>&1 && true
cat "$build/real.txt"; cat "$build/mutant.txt"; cat "$build/mutant2.txt"

# the member lines, and the continuation lines under them: an operation's error is checked in
# a line of its own, and a filter that drops those checks six answers without a word
body() { grep -E '^ +(\.|[A-Za-z])' "$1"; }
body "$build/real.txt" > "$build/real.body"
body "$build/mutant.txt" > "$build/mutant.body"
body "$build/mutant2.txt" > "$build/mutant2.body"
lines=$(wc -l < "$build/real.body" | tr -d ' ')
# one case line per member, plus one extra for each operation, which reports its ok flag and then the
# error's own shape on a continuation line, plus the six CLASS cases the two payment controllers add.
# Counted from the transcript rather than hard-coded, so a member or a class that stops being answered
# stops being counted
ops=$(grep -c '^    \.\.\.' "$build/real.body" || true)
members=$((lines - ops))
echo "--- the real run made $members member case(s) over $lines check line(s):"
if [ "$members" -lt 37 ]; then
    echo "FAIL only $members of the thirty-one members reached, so the probe is not covering them"
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
if diff -q "$build/real.body" "$build/mutant2.body" >/dev/null 2>&1; then
    echo "FAIL the second mutant -- a wrong error CODE, PKUnsupportedVersionError -> PKInvalidSignature"
    echo "     -- does not differ, so nothing here checks the error's own value"
    exit 1
fi
echo "ok the second mutant differs too, so the error's code is checked and not just its presence"
diff -u "$build/real.body" "$build/mutant2.body" | sed -n '1,8p'
exit 0
