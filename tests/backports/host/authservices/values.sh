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

# Before anything is built or run: the host half must not name any of the four methods that write this
# Mac's AutoFill state. See host-write-guard.sh -- the rule is that the host's side of this family is
# read-only and the writing half is documented from the header, not measured here.
python3 "$here/host-write-guard.py" "$here/values.m" "$here/hostshape.c"

# One -D list, used by every build of the port: the three classes it implements, and the one key it owns.
# The other names in the framework -- ASAuthorizationProvider, the scope and operation typedefs, the
# operations themselves -- are the release's, and the release's are what the host is asked about.
# One line, split where it is used. This was a multi-line string handed to `set --`, which set the
# SCRIPT's positional parameters, and inside build_and_run "$@" is the function's own two arguments --
# so the compiler was handed the tag "plain" where a -D belongs.
renames="-DASAuthorizationRequest=PortASAuthorizationRequest \
-DASAuthorizationOpenIDRequest=PortASAuthorizationOpenIDRequest \
-DASAuthorizationAppleIDRequest=PortASAuthorizationAppleIDRequest \
-DASAuthorizationAppleIDProvider=PortASAuthorizationAppleIDProvider \
-DASCharonProviderCodingKey=PortASCharonProviderCodingKey \
-DASCredentialServiceIdentifier=PortASCredentialServiceIdentifier \
-DASCredentialServiceIdentifierType=PortASCredentialServiceIdentifierType \
-DASPasswordCredentialIdentity=PortASPasswordCredentialIdentity \
-DASCredentialIdentityStore=PortASCredentialIdentityStore \
-DASCredentialIdentityStoreState=PortASCredentialIdentityStoreState \
-DASCredentialIdentityStoreErrorDomain=PortASCredentialIdentityStoreErrorDomain \
-DASCredentialIdentityStoreErrorCodeInternalError=PortASStoreErrorInternal \
-DASCredentialIdentityStoreErrorCodeStoreDisabled=PortASStoreErrorDisabled \
-DASCredentialIdentityStoreErrorCodeStoreBusy=PortASStoreErrorBusy"

: "${AS_CREDENTIAL_STORE_PATH:=$build/credential-store.plist}"
: "${CHICON_RUNS:=$build}"
export AS_CREDENTIAL_STORE_PATH CHICON_RUNS

sources="ASConstants12_0.m ASConstants13_0.m ASAuthorizationRequest.m ASAuthorizationOpenIDRequest.m ASAuthorizationAppleIDRequest.m \
ASAuthorizationAppleIDProvider.m ASCredentialServiceIdentifier.m ASPasswordCredentialIdentity.m \
ASCredentialIdentityStoreState.m ASCredentialIdentityStore.m"

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
    portCount=$(nm -m "$build/$tag-values" 2>/dev/null | grep -cE 'OBJC_CLASS_[$]_PortASAuthorization(Request|OpenIDRequest|AppleIDRequest|AppleIDProvider)' || true)
    if [ "$portCount" -ne 4 ]; then
        echo "FAIL: the binary does not carry the port's four renamed classes ($portCount found)"
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

# The mutants, in the port's own source. Two, because the two claims each have one: a fresh request's
# default operation becomes the implicit one, which is what this port shipped until the host was asked
# what it actually holds; and the store's replace keeps the old set instead of replacing it, which is
# the behaviour the coordinator had rejected. Each copy is built the same way from the same list, so a
# mutant and the original differ in one value and in nothing else.
#
#   $1 is the case: "operation" or "replace"
echo "== mutants: each one has to be red, and neither is the other's"

# run_mutant <tag> <file> <old> <new> <what it is>
run_mutant() {
    tag=$1
    target=$2
    old=$3
    new=$4
    what=$5
    echo
    echo "-- $tag: $what"
    rm -rf "$build/$tag"
    mkdir -p "$build/$tag"
    for source in $sources; do cp "$package/$source" "$build/$tag/$source"; done
    cp "$package"/*.h "$build/$tag/" 2>/dev/null || true
    if [ ! -f "$build/$tag/$target" ]; then
        echo "FAIL: the mutation names $target, which is not one of the port's sources"
        return 1
    fi
    OLDPATTERN="$old" NEWPATTERN="$new" python3 -c '
import os, sys
path = sys.argv[1]
text = open(path).read()
old, new = os.environ["OLDPATTERN"], os.environ["NEWPATTERN"]
if old not in text:
    sys.stderr.write("the pattern is not in %s\n" % path)
    sys.exit(1)
open(path, "w").write(text.replace(old, new, 1))
' "$build/$tag/$target" || { echo "FAIL: the $tag mutation did not apply"; return 1; }
    cmp -s "$build/$tag/$target" "$package/$target" && { echo "FAIL: the mutation changed nothing"; return 1; }
    echo "   $target changed:"
    diff "$package/$target" "$build/$tag/$target" | grep -E "^[<>]" | sed 's/^/     /' | head -4
    set +e
    build_and_run "$build/$tag" "$tag"
    built=$?
    set -e
    [ "$built" -eq 0 ] || { echo "FAIL: the $tag build did not complete"; return 1; }
    # The same comparison the check makes, over the same rows, and nothing else: a raw cmp notices a
    # relocated method address, which every mutation of any size moves, and that is not a value. The
    # `built` rows are excluded by verdict() because the whole point of them is that the two builds are
    # DIFFERENT classes.
    set +e
    python3 - "$build/plain-table.txt" "$build/$tag-table.txt" <<'PYTHON' > "$build/$tag-verdict.txt"
import re, sys
def rows(path):
    out, side = {}, None
    for line in open(path):
        line = line.rstrip("\n")
        if line in ("host", "port"):
            side = line
            continue
        if not side or not line.startswith("  "):
            continue
        parts = [p for p in re.split(r"\s{2,}", line.strip()) if p]
        if len(parts) >= 2:
            out[(side, parts[0], parts[1])] = parts[-1]
    return out
plain, mutant = rows(sys.argv[1]), rows(sys.argv[2])
# Everything the port holds that is not a `built` row: a row the CHECK measures.
measured = {k[1:] for k in mutant if k[0] == "port" and not k[1].startswith("built")}
changed = sorted(k for k in measured if plain.get(("port",) + k) != mutant.get(("port",) + k))
for key in changed:
    print("CHANGED %-46s was %-10s now %s" % (key[1], plain.get(("port",) + k.join(()), "?"), mutant.get(("port",) + k)))
print("VERDICT %d of %d measured rows differ" % (len(changed), len(measured)))
sys.exit(1 if changed else 0)
PYTHON
    judged=$?
    set -e
    cat "$build/$tag-verdict.txt" | sed 's/^/     /'
    if [ "$judged" -eq 0 ]; then
        echo "FAIL: the $tag mutation changed no row the check measures -- a relocated address is not a value"
        return 1
    fi
    echo "   the $tag mutation is red, and the row that changed is named above"
    return 0
}

status=0
run_mutant operation ASAuthorizationOpenIDRequest.m "_requestedOperation = nil;" "_requestedOperation = [ASAuthorizationOperationImplicit copy];" "a fresh request's default operation becomes the implicit one" || status=1
run_mutant replace ASCredentialIdentityStore.m "NSMutableArray *records = [NSMutableArray array];" "NSMutableArray *records = [self charon_records];" "the store's replace keeps the old set instead of replacing it" || status=1
exit "$status"
