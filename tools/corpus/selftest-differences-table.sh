#!/usr/bin/env python3
# selftest.sh: run tools/corpus/differences-table.py the way its commit messages say to run it,
# and check that it says a finding rather than dying.
#
# The reason this exists: e51d3ff15 made --page append-able and left the group check calling
# page_counts() with the whole list, so EVERY form of the command - one page and six - died with
#
#   TypeError: expected str, bytes or os.PathLike object, not list
#
# and the tool's own exit status could not be told from a crash's.  So the three things this
# asserts are: the exact command lines run and exit 0, a finding is exit 1, and a crash is exit 2
# with a `tool error:` line - three different outcomes, and the two that must not be confused are
# the last two.  A self-test that only ran the command would have passed on the broken tool if the
# harness had stopped at the first non-zero and the crash had been mistaken for a finding.
#
#   tests/backports/host/../corpus/selftest-differences-table.sh CI-DIFF MODELIO-DIFF PAGE...
#
# Every case below names the command it runs, so a failure says which invocation went wrong.

set -u

here=$(cd "$(dirname "$0")" && pwd)
tool=$here/differences-table.py
if [ $# -lt 3 ]; then
    echo "selftest: usage: selftest.sh CI-DIFF MODELIO-DIFF PAGE [PAGE...]" >&2
    exit 2
fi
ci=$1; modelio=$2; shift 2
pages=("$@")

failed=0
scratch=$here/../.selftest-differences-table
rm -rf "$scratch"; mkdir -p "$scratch"
trap 'rm -rf "$scratch"' EXIT

run() {
    # run TOOL-DESC... -- expects what
    local expect=$1; shift
    local out rc
    out=$(python3 "$tool" "$ci" "$modelio" "$@" 2>&1)
    rc=$?
    case $rc in
        0)   echo "    exit 0  $*" ;;
        1)   echo "    exit 1  $*  $(echo "$out" | grep -c '^FAIL') finding(s)" ;;
        2)   echo "    exit 2  $*  CRASH: $(echo "$out" | tail -1 | cut -c1-70)" ;;
        *)   echo "    exit $rc  $*  UNEXPECTED" ;;
    esac
    case $rc in
        $expect) ;;
        *) failed=$((failed + 1)); echo "    EXPECTED exit $expect, GOT $rc" ;;
    esac
    # a finding and a crash must be distinguishable in the text as well as the status
    if [ "$expect" = 1 ]; then
        echo "$out" | grep -q '^FAIL' || { echo "    exit 1 with no FAIL line"; failed=$((failed + 1)); }
        echo "$out" | grep -q 'tool error:' && { echo "    a finding carried a tool error line"; failed=$((failed + 1)); }
    fi
    LAST_OUT=$out
}

echo "== the exact command lines the commit messages print"
run 0
run 0 --page "${pages[0]}"
if [ ${#pages[@]} -gt 1 ]; then
    args=()
    for p in "${pages[@]}"; do args+=(--page "$p"); done
    run 0 "${args[@]}"
fi

echo "== a finding is exit 1, and the two pages that quote the pair are the ones that go red"
for p in "${pages[@]}"; do
    case $p in
        *Differences.md|*Representations.md) ;;
        *) continue ;;
    esac
    broken=$scratch/$(basename "$p")
    # remove the system's-side figure from the FIRST statement of the pair only, which is the
    # case a first-match matcher would have passed
    python3 - "$p" "$broken" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
# the pages are hard-wrapped, so a figure can have a newline in the middle of it
text = re.sub(r"\s+", " ", open(src, encoding="utf-8").read())
m = re.search(r"\d+ further `repr` lines one-sided on the port's side", text)
if not m:
    sys.exit("the page does not state the pair at all")
nxt = re.search(r"( and|, while) \*\*?\d+ further `repr` lines (are )?one-sided on the system's side", text[m.end():])
if not nxt:
    sys.exit("the page states only one side")
cut = m.end() + nxt.start()
open(dst, "w", encoding="utf-8").write(text[:cut] + " and" + text[m.end() + nxt.end():])
PY
    [ -f "$broken" ] || { echo "    could not build the broken page"; failed=$((failed + 1)); continue; }
    echo "  -- one statement of the pair, on $(basename "$p"):"
    run 1 --page "$broken"
    echo "  -- a figure wrong by one, on $(basename "$p"):"
    wrong=$scratch/$(basename "$p" .md)-wrong.md
    sed 's/one-sided on the port'"'"'s side/one-sided on the port'"'"'s side/; s/`repr` lines one-sided on the port'"'"'s side/`repr` lines one-sided on the port'"'"'s side/' "$p" > /dev/null
    python3 - "$p" "$wrong" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = re.sub(r"\s+", " ", open(src, encoding="utf-8").read())
m = re.search(r"(\d+) further `repr` lines one-sided on the port's side", text)
open(dst, "w", encoding="utf-8").write(text[:m.start()] + "99" + text[m.end():])
PY
    run 1 --page "$wrong"
    echo "  -- and the page itself, unchanged:"
    run 0 --page "$p"
done

echo "== a page or a run the tool cannot read is exit 2 with a tool error, not exit 1"
missing=$scratch/not-there.md
run 2 --page "$missing"
echo "$LAST_OUT" | grep -q '^tool error:' || { echo "    exit 2 with no tool error line"; failed=$((failed + 1)); }
run 2 --page "$missing" --page "${pages[0]}"
run 2 --page "${pages[0]}" --page "$missing"

echo "== a page that quotes no figure is not asked for one"
silent=$scratch/silent.md
printf 'no figures here\n' > "$silent"
run 0 --page "$silent"

if [ $failed -eq 0 ]; then
    echo "selftest: ok"
    exit 0
fi
echo "selftest: $failed case(s) did not behave as the tool's messages say it does" >&2
exit 1
