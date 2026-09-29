#!/bin/sh
# mutate-selftest.sh - can mutate() refuse? A guard that has never refused is a guard that cannot, and
# this one is the difference between a broken build and a red mutant, so it is shown refusing here.
#
# Three cases in a scratch directory: an anchor that occurs once and must change exactly one line, and
# an anchor that occurs twice and an anchor that occurs not at all, both of which must abort with the
# file byte-identical afterwards. The third case's abort is what proves the second is not a coincidence.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/mutate.sh"
scratch=${1:-$here/../../../.agent-work/runs/mutate-selftest}
rm -rf "$scratch"; mkdir -p "$scratch"; work=$scratch
fail=0

# one occurrence: exactly one line changes
printf 'alpha\nbeta\ngamma\n' > "$scratch/one.txt"
printf 'one.txt before: %s\n' "$(md5 -q "$scratch/one.txt")"
mutate "$scratch/one.txt" 'beta' 'BETA'
changed=$(diff "$work/one.txt.original" "$scratch/one.txt" | grep -c '^>')
printf 'case 1 anchor once     : diff lines %s, want 1 -> %s\n' "$changed" "$([ "$changed" -eq 1 ] && echo ok || { fail=1; echo FAILED; })"

# two occurrences: refuses, and leaves the file exactly as it was
printf 'alpha\nbeta\ngamma\nbeta\n' > "$scratch/two.txt"
before=$(md5 -q "$scratch/two.txt")
if mutate "$scratch/two.txt" 'beta' 'BETA' 2>"$scratch/two.err"; then
    printf 'case 2 anchor twice    : it did NOT abort -> FAILED\n'; fail=1
else
    after=$(md5 -q "$scratch/two.txt")
    if [ "$before" = "$after" ]; then
        printf 'case 2 anchor twice    : aborted, file byte-identical (%s) -> ok\n' "$after"
    else
        printf 'case 2 anchor twice    : aborted but the file changed -> FAILED\n'; fail=1
    fi
    printf '                         message: %s\n' "$(head -1 "$scratch/two.err")"
fi

# no occurrence: refuses too, so the refusal is the count and not the accident of one input
printf 'alpha\ngamma\n' > "$scratch/zero.txt"
before=$(md5 -q "$scratch/zero.txt")
if mutate "$scratch/zero.txt" 'beta' 'BETA' 2>"$scratch/zero.err"; then
    printf 'case 3 anchor absent   : it did NOT abort -> FAILED\n'; fail=1
elif [ "$before" = "$(md5 -q "$scratch/zero.txt")" ]; then
    printf 'case 3 anchor absent   : aborted, file byte-identical -> ok\n'
    printf '                         message: %s\n' "$(head -1 "$scratch/zero.err")"
else
    printf 'case 3 anchor absent   : aborted but the file changed -> FAILED\n'; fail=1
fi

[ "$fail" -eq 0 ] || { echo "mutate() cannot be trusted to refuse"; exit 1; }
echo "mutate() changes one line for one anchor and refuses both a doubled and an absent one, leaving the file alone"
