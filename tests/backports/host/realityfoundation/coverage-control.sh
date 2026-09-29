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
