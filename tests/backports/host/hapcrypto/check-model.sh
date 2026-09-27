#!/bin/sh
# check-model.sh — what the registry says is implemented against what the library really defines.
#
# The gate's own check is the authority; this is the one you can run in a second before reporting, and
# it exists because a class listed as implemented with no @implementation behind it is a false claim
# that no amount of "it compiles" will catch: an empty .m file compiles clean.
#
# It reads the @implementations of the library's own sources, reads the registry's class and protocol
# rows, and prints the two differences. A row the registry calls implemented and the tree does not
# define is a failure; a class the tree defines and the registry does not list is a failure the other
# way round. Exits non-zero on either.
#
# Usage: sh check-model.sh [<package dir>]   (default: this repository's apple-backports)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${1:-$here/../../../..}
package=${PACKAGE:-$root/packages/a/apple-backports}
framework=${FRAMEWORK:-HomeKit}

implemented=$(mktemp)
listed=$(mktemp)
missing=$(mktemp)
unlisted=$(mktemp)
trap 'rm -f "$implemented" "$listed" "$missing" "$unlisted"' EXIT

# What the library defines: every @implementation of a class, which is the name the runtime binds.
grep -ho '@implementation[[:space:]]\+[A-Za-z_][A-Za-z0-9_]*' "$package/$framework"/*.m \
    | awk '{ print $2 }' | sort -u > "$implemented" || true

# What the registry lists as implemented, for this framework: the class and protocol rows only, because
# a member row is answered by a selector and the selectors are what check_categories measures.
python3 - "$package/registry/$framework" "$listed" <<'PYTHON'
import json, os, sys
folder, out = sys.argv[1], sys.argv[2]
names = set()
for name in sorted(os.listdir(folder)):
    if not name.endswith(".json"):
        continue
    with open(os.path.join(folder, name)) as f:
        held = json.load(f)
    for entry in held.get("entries", held):
        if entry.get("status") == "implemented" and entry.get("kind") in ("class", "protocol"):
            names.add(entry["api"])
open(out, "w").write("".join(name + "\n" for name in sorted(names)))
PYTHON

comm -23 "$listed" "$implemented" > "$missing"
# The port's own classes are not API: modules/apple/backports.lua filters a name starting with `Charon`
# out of what an object is weighed for, and a store the model sits on is the substrate rather than a row
# of the surface. They are named here so the difference is visible, and not counted as a failure.
comm -13 "$listed" "$implemented" | grep -v '^Charon' > "$unlisted" || true

printf '%s\n' "registry $framework: classes and protocols the tree defines and the registry lists"
printf '  %-44s %s\n' "defined by the library:" "$(wc -l < "$implemented" | tr -d ' ')"
printf '  %-44s %s\n' "listed as implemented:" "$(wc -l < "$listed" | tr -d ' ')"
printf '%s\n' "  listed as implemented, and the tree defines nothing of that name:"
if [ -s "$missing" ]; then sed 's/^/    /' "$missing"; else printf '    (none)\n'; fi
printf '%s\n' "  defined by the library, and the registry does not list it (the port's own names excluded):"
if [ -s "$unlisted" ]; then sed 's/^/    /' "$unlisted"; else printf '    (none)\n'; fi

if [ -s "$missing" ] || [ -s "$unlisted" ]; then
    exit 1
fi
printf '%s\n' "  ok: the registry and the tree agree"
