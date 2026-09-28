#!/bin/sh
# values.sh -- what a request HOLDS, as against what it BINDS.
#
# run.sh reads the binary and asks whether a member is bound. A value is not a method, so this is the
# second instrument: it runs the code. Two builds of the same source in one process -- the host's own
# classes, named as the SDK header names them and linked from the framework, and the port's, which this
# process never names because the port's own build renames them.
#
# The renames are on the port's translation units only, never on values.m: a test compiled with them
# would be asking the port's version of the question and calling it the host's.
#
# How a request is made is the whole thing. ASAuthorizationRequest's header marks -init and +new
# NS_UNAVAILABLE because a request is not constructed -- it comes from a provider, and the SDK gives the
# path: [[ASAuthorizationAppleIDProvider alloc] init] createRequest, which needs no daemon, no network
# and no UI. The port's provider is not implemented yet, so the port's request is made with alloc/init,
# which the port binds because its own header does not mark it unavailable. Two constructors, one per
# side, and the report says which.
#
#   sh values.sh               measure, exit 0 only when the two builds hold the same values
#   sh values.sh --mutate      change the port's default operation and require a difference
set -eu
here=$(cd "$(dirname "$0")" && pwd)
charon=${CHARON:-$here/../../../..}
package="$charon/packages/a/apple-backports/AuthenticationServices"
framework=/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices
build=${BUILD:-$charon/.agent-work/runs/authservices-values}
mutate=${1:-}
mkdir -p "$build"

# One -D list, used by every build of the port: the three classes it implements, and the one key it owns.
# The other names in the framework -- ASAuthorizationProvider, the scope and operation typedefs, the
# operations themselves -- are the release's, and the release's are what the host is asked about.
# One line, split where it is used. This was a multi-line string handed to `set --`, which set the
# SCRIPT's positional parameters, and inside build_and_run "$@" is the function's own two arguments --
# so the compiler was handed the tag "plain" where a -D belongs.
renames="-DASAuthorizationRequest=PortASAuthorizationRequest -DASAuthorizationOpenIDRequest=PortASAuthorizationOpenIDRequest -DASAuthorizationAppleIDRequest=PortASAuthorizationAppleIDRequest -DASCharonProviderCodingKey=PortASCharonProviderCodingKey"

sources="ASAuthorizationRequest.m ASAuthorizationOpenIDRequest.m ASAuthorizationAppleIDRequest.m"

# build_and_run <source-dir> <tag>: compile the port's three sources from there under the renames, link
# them with the test into one binary, and run it. The tag is where the table lands. It returns the
# binary's status and never decides anything: a verdict is the caller's to give.
build_and_run() {
    from=$1
    tag=$2
    objects=""
    for name in $sources; do
        [ -f "$from/$name" ] || { echo "FAIL: $from/$name is not there"; return 1; }
        # shellcheck disable=SC2086
        xcrun clang -fobjc-arc -Os -g0 -I"$from" $renames -c "$from/$name" -o "$build/$tag-$name.o" \
            2> "$build/$tag-$name.log" || {
                echo "FAIL: $from/$name did not compile"; head -5 "$build/$tag-$name.log"; return 1; }
        objects="$objects $build/$tag-$name.o"
    done
    xcrun clang -fobjc-arc -framework Foundation -framework AuthenticationServices \
        -o "$build/$tag-values" "$here/values.m" $objects 2> "$build/$tag-link.log" || {
            echo "FAIL: the two builds did not link into one binary"; head -6 "$build/$tag-link.log"; return 1; }
    # The port's renames are what make them a second hierarchy rather than a second name: the three
    # Port classes are in the binary and nothing else is.
    portCount=$(nm -m "$build/$tag-values" 2>/dev/null | grep -cE 'OBJC_CLASS_[$]_PortASAuthorization(Request|OpenIDRequest|AppleIDRequest)' || true)
    if [ "$portCount" -ne 3 ]; then
        echo "FAIL: the binary does not carry the port's three renamed classes ($portCount found)"
        return 1
    fi
    "$build/$tag-values" "$framework" > "$build/$tag-table.txt" 2> "$build/$tag-table.err" || {
        echo "FAIL: the test did not run"; head -5 "$build/$tag-table.err"; return 1; }
    return 0
}

# verdict <table>: the host's answers are the reference and the port's half is the same lines. A
# difference is a behavioural difference an application can observe, and no member list can see it.
# It reports and returns non-zero; it does not exit, because a function that returns a verdict has no
# business deciding whether the run continues.
verdict() {
    python3 - "$1" <<'PYTHON'
import re, sys
host, port, side = {}, {}, None
for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    if line in ("host", "port"):
        side = line
        continue
    if side and line.startswith("  "):
        parts = [part for part in re.split(r"\s{2,}", line.strip()) if part]
        if len(parts) >= 3:
            (host if side == "host" else port)[parts[0] + " " + parts[1]] = parts[-1]
        elif len(parts) == 2:
            (host if side == "host" else port)[parts[0]] = parts[1]
built = [(side, table.get("built request class")) for side, table in (("host", host), ("port", port))]
built = [(side, name) for side, name in built if name]
if len(built) == 2:
    if built[0][1] == built[1][1]:
        print("\nFAIL: both sides built their request from %s: that is one class, not two" % built[0][1])
        sys.exit(1)
    print("\n   two call targets: the host's request came from %s and the port's from %s"
          % (built[0][1], built[1][1]))
differ = [key for key in host if not key.startswith("built") and port.get(key) != host[key]]
print("   %d keys, %d differ between the two builds" % (len(host), len(differ)))
for key in differ:
    print("     DIFFERS %-32s host %-8s port %s" % (key, host[key], port.get(key)))
sys.exit(1 if differ else 0)
PYTHON
}

build_and_run "$package" plain

cat "$build/plain-table.txt"
status=0
verdict "$build/plain-table.txt" || status=$?
echo

if [ "$mutate" != "--mutate" ]; then
    if [ "$status" -ne 0 ]; then
        echo "FAIL: the two builds disagree about what a request holds"
        exit 1
    fi
    echo "ok: the host's and the port's requests hold the same values, asked through the provider"
    exit 0
fi

# The value mutant, in the port's own source: a fresh request's default operation becomes the implicit
# one, which is what this port shipped until the host was asked what it actually holds. The copy is
# built the same way from the same list, so the mutant and the original differ in one value and in
# nothing else.
echo "== mutant: the port's fresh requestedOperation becomes the implicit operation"
rm -rf "$build/mutant"
mkdir -p "$build/mutant"
for name in $sources; do cp "$package/$name" "$build/mutant/$name"; done
cp "$package"/*.h "$build/mutant/" 2>/dev/null || true
before=$(cksum < "$package/ASAuthorizationOpenIDRequest.m")
perl -pi -e 's/_requestedOperation = nil;/_requestedOperation = [ASAuthorizationOperationImplicit copy];/' \
    "$build/mutant/ASAuthorizationOpenIDRequest.m"
after=$(cksum < "$build/mutant/ASAuthorizationOpenIDRequest.m")
if [ "$before" = "$after" ]; then
    echo "FAIL: the mutation did not apply: the pattern is not what the source has"
    exit 1
fi
echo "   the source changed: cksum $before -> $after"
grep -n "requestedOperation = \[" "$build/mutant/ASAuthorizationOpenIDRequest.m" | sed 's/^/     /'
cmp -s "$package/ASAuthorizationOpenIDRequest.m" "$build/mutant/ASAuthorizationOpenIDRequest.m" \
    && { echo "FAIL: cmp says the mutant and the original are the same file"; exit 1; }
echo "   cmp: the mutant differs from the port's source"

build_and_run "$build/mutant" mutant
echo
diff "$build/plain-table.txt" "$build/mutant-table.txt" | sed 's/^/   /'
if cmp -s "$build/plain-table.txt" "$build/mutant-table.txt"; then
    echo "FAIL: the mutation changed nothing the check can see"
    exit 1
fi
echo
echo "ok: the mutation changed a value and the check noticed, and the port's own source and library"
echo "    were not touched by this run"
