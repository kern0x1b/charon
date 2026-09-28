#!/bin/sh
# run.sh -- the host differential for AuthenticationServices' surface shape, with a mutant.
#
# **Where a class's member list comes from.** From the header the port is written to, parsed at run
# time: the framework's own headers in the SDK the build compiles against. Not from a table here --
# a hand-kept list is a second place to forget an entry, and the first version of this had one, and a
# class missing from it was asked about `init` alone and passed.
#
# **A class the registry carries and whose header cannot be found is an error.** That is the gap this
# closes: before, a class with no entry in the member table was silently narrowed to one member; now
# there is no table to be left out of, and a class whose header is missing stops the run and says so.
#
# **The host's list is the authority on whether a member exists at all**, which is what the check is
# for: an application that links a selector the release does not have crashes, and one that finds a class
# missing at runtime cannot name it. A member the host has and the port does not is a difference; a
# member the port has and the host does not is a difference too. A private method the release has and
# neither the header nor the port claims is not asked about, because it is not a claim.
#
#   sh run.sh                measure, and exit 0 only when every case agrees
#   sh run.sh --mutate       drop one member from a copy of the port's source and require red
set -eu
here=$(cd "$(dirname "$0")" && pwd)
charon=${CHARON:-$here/../../../..}
package="$charon/packages/a/apple-backports/AuthenticationServices"
registry="$charon/packages/a/apple-backports/registry/AuthenticationServices"
framework=${AS_FRAMEWORK:-/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices}
headers=${AS_HEADERS:-}
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"

# The SDK's headers are where the port's own declarations come from; find them the way the build finds
# them, and say so rather than asking about a class whose header is not there.
if [ -z "$headers" ]; then
    headers=$(ls -d "$HOME"/.xmake/packages/i/iphoneos-sdk/*/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk/System/Library/Frameworks/AuthenticationServices.framework/Headers 2>/dev/null | head -1)
fi
if [ ! -d "$headers" ]; then
    echo "FAIL: the AuthenticationServices headers are not on this machine, and the member list comes from them."
    echo "      Set AS_HEADERS to a framework's Headers directory. Not measuring against a list kept"
    echo "      here instead: that is the gap this run exists to close."
    exit 1
fi
echo "headers: $headers"

cc -O2 -Wno-unused-parameter -o "$build/shapes" "$here/shapes.c" -framework Foundation

# The cases: every class the registry carries, with the public members its header declares. A class
# with no header is an error, named.
python3 - "$registry" "$headers" "$build/cases.txt" <<'PYTHON'
import json, os, re, sys
registry, headers, out = sys.argv[1], sys.argv[2], sys.argv[3]

rows = []
for name in sorted(os.listdir(registry)):
    if not name.endswith(".json"):
        continue
    with open(os.path.join(registry, name)) as f:
        for entry in json.load(f).get("entries", []):
            if entry.get("kind") == "class" and entry.get("status") in ("implemented", "inert"):
                rows.append(entry["api"])

def members_of(className):
    """The public instance and class selectors the header declares, in the order the header gives them.

    An @interface's method declarations are lines that start with - or + and a parenthesised return
    type; an @property is not asked separately, because the accessors it stands for are either among
    those declarations or are the compiler's to synthesise. A method the header marks unavailable is
    still asked: the release has it, and the port has to answer it.
    """
    path = os.path.join(headers, className + ".h")
    if not os.path.isfile(path):
        return None
    text = open(path, encoding="utf-8", errors="replace").read()
    blocks = re.findall(r"@interface\s+" + re.escape(className) + r"\b[^\n]*\n(.*?)@end", text, re.S)
    selectors, seen = [], set()
    for block in blocks:
        for line in block.split("\n"):
            line = line.strip()
            if not line or line[0] not in "-+":
                continue
            match = re.match(r"[-+]\s*\([^)]*\)\s*(\w+:?)", line)
            if match and match.group(1) not in seen:
                seen.add(match.group(1))
                selectors.append(match.group(1))
    return selectors

missing, cases = [], []
for className in sorted(set(rows)):
    members = members_of(className)
    if members is None:
        missing.append(className)
        continue
    for member in members:
        cases.append("%s\t%s\n" % (className, member))

if missing:
    sys.stderr.write("no header for: %s\n" % ", ".join(missing))
    sys.exit(1)
if not cases:
    sys.stderr.write("no class in the registry has a header with any method in it\n")
    sys.exit(1)
with open(out, "w") as f:
    f.writelines(cases)
print("%d class rows, %d members" % (len(set(rows)), len(cases)))
PYTHON

measure() {
    label="${1:?}"
    portdir="${2:?}"
    set +e
    "$build/shapes" "$framework" "$build/cases.txt" "$portdir" "$portdir" > "$build/$label.txt" 2>"$build/$label.err"
    status=$?
    set -e
    cat "$build/$label.txt"
    cat "$build/$label.err"
    return $status
}

if [ "${1:-}" = "--mutate" ]; then
    # One member removed from a copy: the base request's -provider, which the header declares and the
    # host has. The tree is not touched, and the run after this one measures the real thing again.
    source="$package/ASAuthorizationRequest.m"
    [ -f "$source" ] || { echo "no ASAuthorizationRequest.m to mutate; nothing to show"; exit 1; }
    mkdir -p "$build/mutant"
    cp "$source" "$build/mutant/ASAuthorizationRequest.m"
    python3 - "$build/mutant/ASAuthorizationRequest.m" <<'PYTHON'
import re, sys
path = sys.argv[1]
text = open(path).read()
before = text
text = re.sub(r"- \(id<ASAuthorizationProvider>\)provider\n\{\n    return _provider;\n\}\n", "", text)
text = text.replace("@synthesize provider = _provider;\n", "")
if text == before:
    sys.stderr.write("the mutation changed nothing: the member's text is not what the pattern expects\n")
    sys.exit(1)
open(path, "w").write(text)
PYTHON
    echo "== mutant: the base request's -provider removed from a copy of the source"
    set +e
    "$build/shapes" "$framework" "$build/cases.txt" "$build/mutant" "$build/mutant" > "$build/mutant.txt" 2>&1
    mutant=$?
    set -e
    grep -E "provider|differences" "$build/mutant.txt" | sed 's/^/   /'
    if [ "$mutant" -eq 0 ]; then
        echo "FAIL: the check passed with a member the port no longer defines"
        exit 1
    fi
    echo "   the check exited $mutant, which is what a check that can see a removed member does"
    echo
    echo "== the real tree, measured again"
fi

set +e
measure tree "$package"
status=$?
set -e
cases=$(($(wc -l < "$build/tree.txt") - 1))
echo "cases: $cases"
if [ "$status" -ne 0 ]; then
    echo "FAIL: a class the registry carries is not a shape the host has and the port defines"
    exit 1
fi
echo "ok: every class the registry carries, and every public member its header declares, is a member"
echo "    the host has and the port defines"
