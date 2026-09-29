#!/bin/sh
# coverage.py's control: a row whose `source` is edited by hand must be caught, and --write must
# regenerate it.
#
# The review measured that the old coverage.py could not do this - it printed a report and exited 0
# with a hand-edited row's blanket claim still in the file, so the property the sources have (each one
# saying what actually measures it) was true by hand and unguarded. The control is the same edit the
# reviewer made, in a copy under the worktree's run directory, and the two verdicts it must produce:
#
#   red   --check on the hand-edited copy exits non-zero, and says the row claims a measurement the
#          loop did not find
#   green --write on that copy, then --check, exits 0
#
# Nothing here touches the registries: the copy is the subject, and it is rewritten every run, so the
# control is the same experiment each time rather than a one-off.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../../.." && pwd)
runs="$repo/.agent-work/runs/realityfoundation"
mkdir -p "$runs"
coverage="$here/coverage.py"
registry="$repo/packages/s/swift-runtime/registry/RealityFoundation.json"
copy="$runs/control-realityfoundation.json"

cp "$registry" "$copy"
python3 - "$copy" <<'PY'
import json, sys
path = sys.argv[1]
document = json.load(open(path))
for entry in document["entries"]:
    if entry.get("status") == "implemented":
        entry["source"] = ("HAND EDITED BY THE CONTROL: the host differential measures every one of "
                           "these")
        break
json.dump(document, open(path, "w"), indent=4)
open(path, "a").write("\n")
PY

# The control for the guard's own bug: its expected text for a *covered* row was the declaration
# sentence, because what_this_row_should_say tested the verdict in slot 0 and the hit carried the
# token. So the tree's 140 covered rows all said "No check measures it" and the guard agreed with
# them: exit 0 on a tree where a measured row claimed no measurement.
#
# Reproducing that needs the pre-repair state, so the copy is built with every implemented row saying
# the declaration sentence, and then two guards are run on it:
#
#   the guard as it was  exit 0 - it agrees with the dead branch, which is the bug
#   the guard as it is   exit non-zero, and the mismatches are exactly the covered rows
#
# The old guard sits beside main.swift for the run - it resolves the differential relative to its own
# path - and is removed after.
declaration_sentence="the declaration in packages/s/swift-runtime/files/, which tests/backports/host/swiftregistry holds to a name, and the interface line it was read from. No check in this series measures it"
cp "$registry" "$runs/control-covered.json"
python3 - "$runs/control-covered.json" "$declaration_sentence" <<'PYEOF'
import json, sys
path, sentence = sys.argv[1], sys.argv[2]
document = json.load(open(path))
for entry in document["entries"]:
    if entry.get("status") == "implemented":
        entry["source"] = sentence
json.dump(document, open(path, "w"), indent=4)
open(path, "a").write("\n")
PYEOF
covered_count=$(python3 "$coverage" "$registry" 2>/dev/null | grep -c '^covered  ' || true)
[ -n "$covered_count" ] || covered_count=0
git -C "$repo" show HEAD:tests/backports/host/realityfoundation/coverage.py > "$here/.coverage-old.py"
echo "control: a copy where every row says no measurement, $covered_count of them covered"
if python3 "$here/.coverage-old.py" --check "$runs/control-covered.json" > "$runs/control-covered-old.txt" 2>&1; then
    echo "  the guard as it was exits 0: it agrees with a covered row that claims no measurement, which is the bug"
else
    echo "  the old guard exited $? on that tree, which is NOT the failure the review describes:"
    head -3 "$runs/control-covered-old.txt" | sed 's/^/    /'
fi
rm -f "$here/.coverage-old.py"
if python3 "$coverage" --check "$runs/control-covered.json" > "$runs/control-covered-new.txt" 2>&1; then
    echo "  CONTROL FAILED: the guard as it is also accepts a covered row that claims no measurement"
    exit 1
fi
flagged=$(grep -c "^  MISMATCH" "$runs/control-covered-new.txt" || true)
[ -n "$flagged" ] || flagged=0
echo "  the guard as it is exits non-zero, and flags $flagged rows - the covered ones, each one a row"
echo "    that says no check measures it while the differential names it"
if [ "$flagged" != "$covered_count" ]; then
    echo "    and that is not the $covered_count the report calls covered - read the two numbers"
    exit 1
fi
rm -f "$runs/control-covered.json"

printf 'control: a hand-edited row, red first\n'
if python3 "$coverage" --check "$copy" > "$runs/control-red.txt" 2>&1; then
    echo "CONTROL FAILED: --check exited 0 on a hand-edited row, so the guard is not guarding"
    exit 1
fi
echo "  --check exited non-zero, and it says so here:"
grep -E "MISMATCH|CLAIMS A MEASUREMENT|not what this loop decides" "$runs/control-red.txt" | head -3 | sed 's/^/    /'

printf 'control: --write regenerates it, green after\n'
python3 "$coverage" --write "$copy" > "$runs/control-write.txt" 2>&1
if ! python3 "$coverage" --check "$copy" > "$runs/control-green.txt" 2>&1; then
    echo "CONTROL FAILED: --check exited non-zero after --write regenerated the row"
    exit 1
fi
echo "  --check exits 0 after --write: the row now says what the loop decides"
rm -f "$copy"
echo "control: OK - the guard catches the edit and the generator repairs it"
