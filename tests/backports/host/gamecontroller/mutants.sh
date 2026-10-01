#!/bin/sh
# Mutants for the snapshot differential and the touchpad: each one changes one rule of the port's
# copy, and each has to make tests/backports/host/gamecontroller fail. A mutant that does not build is RUN FAILED, never
# counted as noticed, so every mutant here is one the compiler still accepts - each is a change of a
# comparison or a value, not of the file's shape.
#
#   sh tests/backports/host/gamecontroller/mutants.sh
#
# The tree is left as it was found: each mutation is written over the file, run, and put back with
# `git show HEAD:<file> > <file>` - never `git checkout --`, which this repository's rules forbid -
# and the script ends by refusing to pass if the file is left changed.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tree=$(cd "$here/../../../.." && pwd)
rel=${MUTATE_FILE:-packages/a/apple-backports/GameController/CharonGCSnapshot.h}
source_file="$tree/$rel"
out=${BUILD:-$here/../../../../.agent-work/fin/mutants}
mkdir -p "$out"

restore() {
    git -C "$tree" show "HEAD:$rel" > "$source_file"
}

# Writes the mutation over the port's file, with python so that the text being replaced never has to
# survive a shell's quoting. Answers 0 when it changed something.
mutate() {
    python3 -c '
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
if old not in text:
    sys.exit(3)
open(path, "w").write(text.replace(old, new, 1))
' "$source_file" "$1" "$2"
}

failures=0

# $1 the text to replace, $2 what replaces it, $3 what the mutant is called. The name is a
# single word on purpose: run.sh expands its object list unquoted, so a name with spaces would split
# the compiler's own arguments and look like a broken build rather than a mutant.
check() {
    old=$1
    new=$2
    name=$3
    if ! mutate "$old" "$new"; then
        printf 'MUTANT %-52s RUN FAILED (the text to mutate is not in the file: the mutation is wrong, not the code)\n' "$name"
        restore
        failures=$((failures + 1))
        return 0
    fi
    mkdir -p "$out/$name"
    if BUILD="$out/$name" sh "$here/run.sh" > "$out/$name.log" 2>&1; then
        printf 'MUTANT %-52s NOTICED=no (the differential passed with the mutant in place)\n' "$name"
        failures=$((failures + 1))
    else
        lines=$(grep -c DIFFERING "$out/$name.log" || true)
        lines=$((lines + $(grep -c DIFFERENT "$out/$name.log" || true)))
        if [ "$lines" -gt 0 ]; then
            printf 'MUTANT %-52s NOTICED=yes (%s differing lines, the run exited non-zero)\n' "$name" "$lines"
            grep -A2 DIFFERENT "$out/$name.log" | head -3 | sed 's/^/    /'
        else
            printf 'MUTANT %-52s RUN FAILED (non-zero exit and no differing line: the build broke, which is not notice)\n' "$name"
            tail -3 "$out/$name.log" | sed 's/^/    /'
            failures=$((failures + 1))
        fi
    fi
    restore
}

check 'return data.length >= length && header[0] != 0;' \
      'return data.length >= length - 1 && header[0] != 0;' \
      'gamepad-reader-takes-a-byte-less'

check 'return data.length >= length && header[0] != 0;' \
      'return data.length >= length;' \
      'gamepad-reader-ignores-the-version'

check 'return header[1] <= length;' \
      'return YES;' \
      'readers-ignore-the-declared-size'

check 'if (header[0] == 0)' \
      'if (header[0] == 0xFFFF)' \
      'encoders-leave-an-empty-version'

check 'if (header[1] == 0)' \
      'if (header[1] == 0xFFFF)' \
      'encoders-leave-an-empty-size'

# The touchpad's own rules, in the file that writes them. Each is one the host's touch state
# group compares against the host's own touchpad, so a mutation has to move a compared line.
touchpad_rel=packages/a/apple-backports/GameController/GCControllerTouchpad14.m
touchpad_file="$tree/$touchpad_rel"
restore_touchpad() {
    git -C "$tree" show "HEAD:$touchpad_rel" > "$touchpad_file"
}
mutate_touchpad() {
    python3 -c '
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
if old not in text:
    sys.exit(3)
open(path, "w").write(text.replace(old, new, 1))
' "$touchpad_file" "$1" "$2"
}
check_touchpad() {
    old=$1
    new=$2
    name=$3
    if ! mutate_touchpad "$old" "$new"; then
        printf 'MUTANT %-52s RUN FAILED (the text to mutate is not in the file: the mutation is wrong, not the code)\n' "$name"
        restore_touchpad
        failures=$((failures + 1))
        return 0
    fi
    mkdir -p "$out/$name"
    if BUILD="$out/$name" sh "$here/run.sh" > "$out/$name.log" 2>&1; then
        printf 'MUTANT %-52s NOTICED=no (the differential passed with the mutant in place)\n' "$name"
        failures=$((failures + 1))
    else
        lines=$(grep -c DIFFERING "$out/$name.log" || true)
        lines=$((lines + $(grep -c DIFFERENT "$out/$name.log" || true)))
        if [ "$lines" -gt 0 ]; then
            printf 'MUTANT %-52s NOTICED=yes (%s differing lines, the run exited non-zero)\n' "$name" "$lines"
            grep -A2 DIFFERENT "$out/$name.log" | head -3 | sed 's/^/    /'
        else
            printf 'MUTANT %-52s RUN FAILED (non-zero exit and no differing line: the build broke, which is not notice)\n' "$name"
            tail -3 "$out/$name.log" | sed 's/^/    /'
            failures=$((failures + 1))
        fi
    fi
    restore_touchpad
}

# The touch state is the pair the header tells a caller to poll, so each of the four values it
# takes is a rule: Up before a touch, Down on the first one, Moving while a touch stays down,
# Up again when it lifts.
check_touchpad 'if (!touchDown)
        state = GCTouchStateUp;' \
           'if (!touchDown)
        state = GCTouchStateDown;' \
           'touchpad-stays-down-when-it-lifts'

check_touchpad 'else if (_touchState == GCTouchStateDown)
        state = GCTouchStateMoving;' \
           'else if (_touchState == GCTouchStateUp)
        state = GCTouchStateMoving;' \
           'touchpad-moves-only-from-a-fresh-down'

check_touchpad '    else
        state = GCTouchStateDown;' \
           '    else
        state = GCTouchStateMoving;' \
           'touchpad-never-reports-down'

check_touchpad '    GCTouchState state;
    if (!touchDown)' \
           '    GCTouchState state;
    if (touchDown)' \
           'touchpad-inverts-the-down-flag'

# The header's own default is the other thing both copies are held to, and it contradicts the
# header's comment.
check_touchpad '_reportsAbsoluteTouchSurfaceValues = NO;' \
           '_reportsAbsoluteTouchSurfaceValues = YES;' \
           'touchpad-default-follows-the-header-comment'

if ! git -C "$tree" diff --quiet -- "$rel" "$touchpad_rel"; then
    echo "MUTANTS: the source is left changed; a mutation was not put back"
    failures=$((failures + 1))
fi

echo "mutants: 10 run, $failures not noticed"
[ "$failures" -eq 0 ]
