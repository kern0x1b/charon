#!/bin/sh
# run.sh — measures a framework's exported string constants on the host and diffs them against the
# values this package carries, with tools/corpus/host-probe.c as the instrument.
#
# The two families this covers are HomeKit and AuthenticationServices. For each it asks the host's own
# copy of the framework for every constant the registry lists, and compares. The comparison is the
# point: a port that writes a constant from the name rather than from the release will show up here as
# a difference, and a port that invents one will show up as a name the host does not export.
#
# A framework's *class* names are not string constants and are not asked about: dlsym does not see a
# bare class name (the symbol is _OBJC_CLASS_$_Name), and a class that answered here would be a class
# reported as a constant. The registry's class rows are checked by check-model.sh against the tree
# instead, which is the right instrument for them.
#
# Run with no arguments it measures both families and writes a table per family into
# coordination/corpus/ledger/constant-values-<framework>.tsv, next to the HomeKit and
# AuthenticationServices ones it reproduces. Exit 0 only when every value agrees.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
charon=${CHARON:-$here/../../../..}
registry="$charon/packages/a/apple-backports/registry"
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"
ledger=${LEDGER:-$HOME/Git/projects/ios/coordination/corpus/ledger}

cc -O2 -Wno-unused-parameter -framework CoreFoundation -o "$build/host-probe" "$charon/tools/corpus/host-probe.c"

failed=0
measure() {
    framework="$1"
    source="$2"
    names="$build/$framework-names.txt"
    measured="$build/$framework.tsv"
    table="$ledger/constant-values-$framework.tsv"

    # The names come from the registry, not from a list here: the registry is what the port claims,
    # so the set of questions is exactly the set of claims.
    python3 - "$registry/$framework" "$names" <<'PYTHON'
import json, os, sys
folder, out = sys.argv[1], sys.argv[2]
names = []
for name in sorted(os.listdir(folder)):
    if not name.endswith(".json"):
        continue
    with open(os.path.join(folder, name)) as f:
        for entry in json.load(f).get("entries", []):
            if entry.get("kind") == "constant":
                names.append(entry["api"])
open(out, "w").write("".join(name + "\n" for name in sorted(set(names))))
PYTHON

    echo "== $framework: $(wc -l < "$names" | tr -d ' ') constants, asking $source"
    if ! "$build/host-probe" "$source" "$names" > "$measured"; then
        echo "   the probe reported names it could not measure; the comparison below says which"
    fi
    set +e
    python3 - "$registry/$framework" "$measured" "$table" "$framework" <<'PYTHON'
import json, os, subprocess, sys
folder, measured, table, framework = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
intro = {}
for name in sorted(os.listdir(folder)):
    if not name.endswith(".json"):
        continue
    with open(os.path.join(folder, name)) as f:
        for entry in json.load(f).get("entries", []):
            if entry.get("kind") == "constant":
                intro[entry["api"]] = (entry.get("introduced", "-"), entry.get("effect", ""))
def carried(effect):
    """The value a registry row says the port carries, read out of its effect text.

    Most rows read "the string <value>, which is the value the release gives <name>" with the value in
    quotes, and a few read it unquoted. An earlier version of this only understood the quoted form and
    reported every unquoted row as a difference, which is how a row whose port and host values are
    identical -- ASWebAuthenticationSessionErrorDomain -- was called a difference. Both forms are read,
    and a row that yields nothing is reported by name rather than compared against nothing.
    """
    start = effect.find('"')
    end = effect.find('"', start + 1)
    if start >= 0 and end > start:
        return effect[start + 1:end]
    marker = "the string "
    begin = effect.find(marker)
    if begin >= 0:
        begin += len(marker)
        stop = effect.find(",", begin)
        return effect[begin:stop if stop > begin else len(effect)].strip()
    return None
rows = {}
with open(measured) as f:
    next(f, None)
    for line in f:
        if line.strip():
            fields = line.rstrip("\n").split("\t")
            rows[fields[0]] = fields[3]
agree, differ, absent, unextractable = [], [], [], []
for name, (at, effect) in sorted(intro.items()):
    want = carried(effect)
    got = rows.get(name)
    if got == "-":
        absent.append(name)
    elif want is None:
        unextractable.append(name)
    elif got == want:
        agree.append(name)
    else:
        differ.append((name, want, got))
print("   %d agree, %d differ, %d not exported by the host, %d rows with no value to compare"
      % (len(agree), len(differ), len(absent), len(unextractable)))
for name in unextractable:
    print("     NO VALUE IN THE ROW %s" % name)
for name, want, got in differ:
    print("     DIFFERS %-56s port %s host %s" % (name, want, got))
for name in absent:
    print("     NOT ON THE HOST %s" % name)
build = subprocess.run(["sw_vers", "-buildVersion"], capture_output=True, text=True).stdout.strip() or "unknown"
source = rows and measured or measured
if agree:
    out = ["api\tintroduced\tc-type\tvalue\thow-measured\tsource-binary\tos-build"]
    for name in sorted(agree):
        out.append("\t".join([name, intro[name][0], "NSString *const", rows[name],
                              "dlopen + dlsym on the host, decoded through CFStringGetCString as UTF-8, "
                              "by tools/corpus/host-probe.c", source, "macOS " + build]))
    with open(table, "w") as f:
        f.write("\n".join(out) + "\n")
    print("   table written: %s (%d rows)" % (table, len(agree)))
sys.exit(1 if differ or absent else 0)
PYTHON
    rc=$?
    set -e
    [ "$rc" -eq 0 ] || failed=1
}

measure HomeKit /System/Library/PrivateFrameworks/HomeKit.framework/Versions/A/HomeKit
measure AuthenticationServices /System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices

if [ "$failed" -ne 0 ]; then
    echo "FAIL: a value the port carries is not the value the host holds"
    exit 1
fi
echo "ok: every constant both families carry is the host's own"
