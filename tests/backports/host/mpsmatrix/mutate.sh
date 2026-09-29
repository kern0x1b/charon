#!/bin/sh
# mutate.sh - the two functions the mutation campaign uses, and nothing else. It defines them and
# does not run them, so a test can source it without starting a campaign: mutation.sh runs its
# campaign on the spot, which is why a test that sourced it found no function to call.
# One substitution in a whole file, guarded at both ends. The anchor must occur exactly once, the
# change must be exactly one line, and the rest of the file is untouched: the earlier mechanism wrote
# the replacement line over the file, which is how a broken build was read as a red mutant. Restoring
# is git show, so it cannot be a captured copy that was itself captured wrong.
mutate() {
    _file=$1; _anchor=$2; _replacement=$3
    _n=$(grep -c -F -- "$_anchor" "$_file" || true)
    if [ "$_n" -ne 1 ]; then
        echo "the anchor occurs $_n times in $_file, and a mutation needs exactly one:" >&2
        printf '  %s\n' "$_anchor" >&2
        return 1
    fi
    _copy="$work/$(basename "$_file").original"
    python3 - "$_file" "$_anchor" "$_replacement" "$_copy" <<'PYEOF'
import sys
path, anchor, replacement, copy = sys.argv[1:5]
text = open(path).read()
open(copy, 'w').write(text)
open(path, 'w').write(text.replace(anchor, replacement, 1))
PYEOF
    _changed=$(diff "$_copy" "$_file" | grep -c '^>')
    if [ "$_changed" -ne 1 ]; then
        printf 'the mutation changed %s lines of %s, and it must change one\n' "$_changed" "$_file" >&2
        return 1
    fi
    printf 'mutated: %s: 1 line changed\n' "$_file"
}
restore() { git show "HEAD:$kernel" > "$kernel"; }
