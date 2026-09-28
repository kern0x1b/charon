#!/bin/sh
# run.sh -- the host differential for AuthenticationServices' surface shape, with a mutant.
#
# The value half of this family is checked by tests/backports/host/constants/run.sh, which asks the host
# for every constant the registry lists and compares it with the row and with the built library. This
# one asks the other question: for a class the registry claims, does the host's own
# AuthenticationServices have it and answer its members, and does this port's tree?
#
# The cases come from the registry, so the set of questions is the set of claims. A difference is a
# failure in either direction: an application that links against a selector the release does not have
# crashes, and one that finds a class missing at runtime cannot name it.
#
#   sh run.sh                      measure, and exit 0 only when every case agrees
#   sh run.sh --mutate             drop one member from a copy of the port's source and require red
#
# The mutant is the check being load-bearing: without it a differential that compares nothing would
# pass, and with a comparison that cannot see a removed member it would pass too. The mutation is made
# on a copy, so the tree is not touched and the next run measures the real thing again.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
charon=${CHARON:-$here/../../../..}
package="$charon/packages/a/apple-backports/AuthenticationServices"
framework=${AS_FRAMEWORK:-/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices}
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"

cc -O2 -Wno-unused-parameter -o "$build/shapes" "$here/shapes.c" -framework Foundation

# The cases: the class rows the registry carries as implemented, with the members each is asked about.
# A member in a second column overrides the default set.
python3 - "$package/../registry/AuthenticationServices" "$build/cases.txt" <<'PYTHON'
import json, os, sys
folder, out = sys.argv[1], sys.argv[2]
rows = []
for name in sorted(os.listdir(folder)):
    if not name.endswith(".json"):
        continue
    with open(os.path.join(folder, name)) as f:
        for entry in json.load(f).get("entries", []):
            if entry.get("kind") == "class" and entry.get("status") in ("implemented", "inert"):
                rows.append(entry["api"])
# The members asked per class. A class with none named is asked the default set the tool carries, which
# is the set every class of this family has, so a new class is covered the moment it is named.
MEMBERS = {
    "ASAuthorizationRequest": ["provider", "copyWithZone:", "encodeWithCoder:"],
}
with open(out, "w") as f:
    for name in sorted(set(rows)):
        for member in MEMBERS.get(name, []):
            f.write("%s\t%s\n" % (name, member))
        if name not in MEMBERS:
            f.write("%s\n" % name)
print("%d class rows" % len(set(rows)))
PYTHON

if [ "${1:-}" = "--mutate" ]; then
    # Drop one member from a copy of the port's source: the base request's -provider, which the host
    # has and the copy will not. The tree is not touched.
    source="$package/ASAuthorizationRequest.m"
    [ -f "$source" ] || { echo "no ASAuthorizationRequest.m to mutate; nothing to show"; exit 1; }
    mkdir -p "$build/mutant"
    cp "$source" "$build/mutant/ASAuthorizationRequest.m"
    python3 - "$build/mutant/ASAuthorizationRequest.m" <<'PYTHON'
import re, sys
path = sys.argv[1]
text = open(path).read()
# The member's definition, and the @synthesize that would still declare it.
text = re.sub(r"- \(id<ASAuthorizationProvider>\)provider\n\{\n    return _provider;\n\}\n", "", text)
text = text.replace("@synthesize provider = _provider;\n", "")
open(path, "w").write(text)
PYTHON
    if grep -q "provider" "$build/mutant/ASAuthorizationRequest.m" && grep -q "ASCharonProviderCodingKey" "$build/mutant/ASAuthorizationRequest.m"; then
        :
    fi
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
"$build/shapes" "$framework" "$build/cases.txt" "$package" "$package" > "$build/report.txt" 2>"$build/report.err"
status=$?
set -e
cat "$build/report.txt"
cat "$build/report.err"
cases=$(($(wc -l < "$build/report.txt") - 1))
echo "cases: $cases"
if [ "$status" -ne 0 ]; then
    echo "FAIL: a class the registry carries is not a shape the host has and the port defines"
    exit 1
fi
echo "ok: every class the registry carries is a class the host has and the port defines"
