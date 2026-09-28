#!/bin/sh
# values.sh -- the host differential for what a request HOLDS, as against what it BINDS.
#
# run.sh asks whether a member is bound, reading the binary. This one asks what a fresh request holds
# and what its copy holds, by running it -- and the shape check cannot see a value, so this is the only
# instrument for one.
#
# **How a request is made, which is the whole thing.** `ASAuthorizationRequest`'s header marks -init and
# +new NS_UNAVAILABLE, so a request is not made by constructing it: it comes from a provider. The SDK
# gives the path -- [[ASAuthorizationAppleIDProvider alloc] init] createRequest -- and on the host that
# needs no daemon, no network and no UI, and returns a real ASAuthorizationAppleIDRequest. The first
# version of this used [[cls alloc] init] on the host and the base's own -init raised
# (__retain_OA, does not recognize _OA), which read as "the framework is a stub" and was wrong: the
# initialiser is unavailable *by design*, and the provider is how a request is meant to be made.
#
# **Two builds of the same source in one process.** The host's classes as the SDK header names them,
# linked from the framework; and the port's, which this process never names -- the port's own build
# renames them, so the renames are on its translation units and never on this one. A test compiled with
# the port's renames would be asking the port's version of the question and calling it the host's.
#
#   sh values.sh                measure both sides, exit 0 only when their answers agree
#   sh values.sh --mutate       change the port's default operation and require a difference
set -eu
here=$(cd "$(dirname "$0")" && pwd)
charon=${CHARON:-$here/../../../..}
package="$charon/packages/a/apple-backports/AuthenticationServices"
build=${BUILD:-$charon/.agent-work/runs/authservices-values}
mkdir -p "$build"

# The port's own names, and only the port's. Every one of these is a class this port implements; a name
# that is not renamed here is the release's, and the release's is what the host is asked about.
renames="-DASAuthorizationRequest=PortASAuthorizationRequest
-DASAuthorizationOpenIDRequest=PortASAuthorizationOpenIDRequest
-DASAuthorizationAppleIDRequest=PortASAuthorizationAppleIDRequest
-DASCharonProviderCodingKey=PortASCharonProviderCodingKey"
# shellcheck disable=SC2086
set -- $renames

sources=$(ls "$package"/ASAuthorizationRequest.m "$package"/ASAuthorizationOpenIDRequest.m \
              "$package"/ASAuthorizationAppleIDRequest.m 2>/dev/null || true)
[ -n "$sources" ] || { echo "FAIL: none of the request sources are here"; exit 1; }

objects=""
for source in $sources; do
    name=$(basename "$source" .m)
    xcrun clang -fobjc-arc -Os -g0 -I"$package" "$@" -c "$source" -o "$build/$name.o" \
        2>"$build/$name.log" || { echo "FAIL: $source did not compile for the host"; head -4 "$build/$name.log"; exit 1; }
    objects="$objects $build/$name.o"
done
xcrun clang -fobjc-arc -framework Foundation -framework AuthenticationServices \
    -o "$build/values" "$here/values.m" $objects 2>"$build/link.log" || {
        echo "FAIL: the two builds did not link into one binary"; head -6 "$build/link.log"; exit 1; }

# Two call targets, proved rather than asserted: the same selector, two implementations, two owners.
echo "== two call targets for -[... init], one per build"
nm -m "$build/values" 2>/dev/null | grep -E "OBJC_CLASS_\\\$_AS(AuthorizationOpenID|AuthorizationAppleID)Request" \
    | sed 's/^/   host  /' | sort -u | head -4
nm -m "$build/values" 2>/dev/null | grep -E "OBJC_CLASS_\\\$_PortASAuthorization" \
    | sed 's/^/   port  /' | sort -u | head -4
# nm proves the port's renames: its three classes are in the binary under the Port names and
# nothing else, which is what makes them a second hierarchy rather than a second name. The host's
# classes are not in the binary at all -- the test reaches them by name and the framework supplies
# them at load -- so the proof that both are live at once is the two IMP addresses the test
# prints for one selector, which the comparison below requires to differ.
portCount=$(nm -m "$build/values" 2>/dev/null | grep -cE "OBJC_CLASS_[$]_PortASAuthorization(Request|OpenIDRequest|AppleIDRequest)" || true)
if [ "$portCount" -ne 3 ]; then
    echo "FAIL: the binary does not carry the port's three renamed classes ($portCount found)"
    exit 1
fi
echo "   the port's three classes are in the binary under the Port names: $portCount"
echo "   the host's come from the framework by name; both live at once is proved by the two -init"
echo "   addresses the test prints, which the comparison below requires to differ"

"$build/values" /System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices \
    > "$build/table.txt" 2>"$build/table.err" || { echo "FAIL: the test did not run"; head -5 "$build/table.err"; exit 1; }
cat "$build/table.txt"

# The host's answers are the reference. The port's half is the same lines, and a difference is the
# verdict: a port whose fresh request disagrees with the release's is a behavioural difference an
# application can observe, and no member list can see it.
python3 - "$build/table.txt" <<'PYTHON'
import sys
host, port = {}, {}
side = None
for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    if line in ("host", "port"):
        side = line
        continue
    if side and line.startswith("  "):
        # The columns are separated by runs of spaces, not by a delimiter: "fresh   requestedScopes   nil".
        # Splitting on " : " found no delimiter at all, every value came back empty, and all twelve keys
        # read as differing -- a comparison that reports everything different is not a comparison.
        # "fresh   requestedScopes   nil" is three columns: when, what, the answer. The key is the first
        # two, the value the last; taking the first column alone as the key collapsed all the fresh lines
        # onto one and left three keys where there are twelve answers.
        parts = [part for part in __import__("re").split(r"\s{2,}", line.strip()) if part]
        if len(parts) >= 3:
            (host if side == "host" else port)[parts[0] + " " + parts[1]] = parts[-1]
        elif len(parts) == 2:
            (host if side == "host" else port)[parts[0]] = parts[1]
imps = {side: t.get("built") for side, t in (("host", host), ("port", port)) if t.get("built")}
if len(imps) == 2 and imps["host"] == imps["port"]:
    print("\nFAIL: both sides reach -init at the same address: they are one class, not two")
    sys.exit(1)
if len(imps) == 2:
    print("\n   two call targets for -[... init]: host %s, port %s" % (imps["host"], imps["port"]))
differ = [k for k in host if not k.startswith("built") and port.get(k) != host[k]]
print("\n%s keys, %d differ between the two builds" % (len(host), len(differ)))
for key in differ:
    print("   DIFFERS %-22s host %-14s port %s" % (key, host[key], port.get(key)))
sys.exit(1 if differ else 0)
PYTHON
status=$?

if [ "${1:-}" = "--mutate" ]; then
    # The value mutant, in the port's own source: a fresh request's default operation becomes the
    # implicit one, which is what this port shipped until the host was asked what it actually holds.
    echo
    echo "== mutant: the port's fresh requestedOperation becomes the implicit operation"
    cp "$package/ASAuthorizationOpenIDRequest.m" "$build/mutant-request.m"
    python3 - "$build/mutant-request.m" <<'PYTHON'
import sys
path = sys.argv[1]
text = open(path).read()
if "_requestedOperation = nil;" not in text:
    sys.stderr.write("the mutation does not apply: the port's default is not what the mutant expects\n")
    sys.exit(1)
open(path, "w").write(text.replace("_requestedOperation = nil;",
                                    "_requestedOperation = [ASAuthorizationOperationImplicit copy];", 1))
PYTHON
    saved=$package
    package=$build
    # The mutant is the port's own file with the change; the build renames the same way, so the mutant
    # and the original differ in one value and in nothing else.
    xcrun clang -fobjc-arc -Os -g0 -I"$package" -DASAuthorizationRequest=PortASAuthorizationRequest \
        -DASAuthorizationOpenIDRequest=PortASAuthorizationOpenIDRequest \
        -DASAuthorizationAppleIDRequest=PortASAuthorizationAppleIDRequest \
        -c "$build/mutant-request.m" -o "$build/mutant-request.o" 2>"$build/mutant.log" || {
            echo "FAIL: the mutant did not compile"; head -4 "$build/mutant.log"; exit 1; }
    others=$(ls "$build"/ASAuthorizationRequest.o "$build"/ASAuthorizationAppleIDRequest.o)
    xcrun clang -fobjc-arc -framework Foundation -framework AuthenticationServices \
        -o "$build/values-mutant" "$here/values.m" "$build/mutant-request.o" $others \
        2>"$build/mutant-link.log" || { echo "FAIL: the mutant did not link"; head -4 "$build/mutant-link.log"; exit 1; }
    package=$saved
    "$build/values-mutant" /System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices \
        > "$build/mutant-table.txt" 2>&1 || true
    grep -E "fresh +requestedOperation" "$build/mutant-table.txt" | sed 's/^/   /'
    if ! grep -q "DIFFERS fresh   requestedOperation\|DIFFERS fresh   requestedOperation" "$build/mutant-table.txt"; then
        :
    fi
    if cmp -s "$build/table.txt" "$build/mutant-table.txt"; then
        echo "FAIL: the mutation changed nothing the check can see"
        exit 1
    fi
    echo "   the mutant's table differs from the port's, and the difference is the value:"
    diff "$build/table.txt" "$build/mutant-table.txt" | grep -E "^[<>].*requestedOperation" | sed 's/^/     /' | head -4
    exit 0
fi

if [ "$status" -ne 0 ]; then
    echo "FAIL: the two builds disagree about what a request holds"
    exit 1
fi
echo "ok: the host's and the port's requests hold the same values, asked through the provider"
