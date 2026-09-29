#!/bin/sh
# mutate.sh - the two functions the mutation campaign uses, and nothing else. It defines them and does
# not run them, so a test can source it without starting a campaign: mutation.sh runs its campaign on
# the spot, which is why a test that sourced it found no function to call.
#
# mutate FILE [WANT_INS WANT_DEL] reads its anchor and replacement from the environment, never as
# arguments: an anchor of C source carries ) " and $x, and as a shell word each of those is a
# metacharacter. The default is one insertion and one deletion; the gradient site's replacement is a
# comment and a store loop where its anchor is one comment, so it says 2 1 and is asserted at that.
mutate() {
    _file=$1; _want_ins=${2:-1}; _want_del=${3:-1}
    _anchor=$ANCHOR; _replacement=$REPL
    _n=$(grep -c -F -- "$_anchor" "$_file" || true)
    if [ "$_n" -ne 1 ]; then
        echo "the anchor occurs $_n times in $_file, and a mutation needs exactly one:" >&2
        printf '  %s\n' "$_anchor" >&2
        return 1
    fi
    _copy="$work/$(basename "$_file").original"
    ANCHOR="$_anchor" REPL="$_replacement" python3 - "$_file" "$_copy" <<'PYEOF'
import os, sys
path, copy = sys.argv[1], sys.argv[2]
text = open(path).read()
open(copy, 'w').write(text)
open(path, 'w').write(text.replace(os.environ['ANCHOR'], os.environ['REPL'], 1))
PYEOF
    _ins=$(diff "$_copy" "$_file" | grep -c '^>')
    _del=$(diff "$_copy" "$_file" | grep -c '^<')
    if [ "$_ins" -ne "$_want_ins" ] || [ "$_del" -ne "$_want_del" ]; then
        printf 'the mutation changed %s insertion(s) and %s deletion(s) of %s, and it must change %s and %s\n' \
            "$_ins" "$_del" "$_file" "$_want_ins" "$_want_del" >&2
        printf '  the file is put back, so a refusal leaves nothing mutated\n' >&2
        cp "$_copy" "$_file"
        return 1
    fi
    printf 'mutated: %s: %s insertion(+), %s deletion(-)\n' "$_file" "$_ins" "$_del"
}
restore() { git show "HEAD:$kernel" > "$kernel"; }
