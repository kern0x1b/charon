#!/bin/sh
# accessibilitymap/mutants.sh - every mutant of AXBrailleMap has to be told apart by the case of
# run.sh, and by the failure report run.sh prints.
#
# A differential that examines nothing says it passed, and a mutant that stops the build says nothing
# either, so a mutant here has to be held by the comparison - a line of the two answers that do not
# match and the whole diff the run prints when they do not, both required - and the suite fails if no
# mutant dies that way.
#
# The rules each mutant breaks:
#   M1  a pin is not stored, so nothing reads back
#   M2  a height is clamped to the unit range, where the host clamps nothing
#   M3  a negative point is refused, where the host takes one
#   M4  the copy shares the original's store, where the host's copy is its own map
#   M5  the copy drops the pins, where the host's copy carries them
#   M6  the archive drops the pins, where the host's own round trip carries them
#   M7  the size is not carried through the copy
#   M8  the factory answers the size it was asked for
#   M9  a copy's store is mutable again, where the system's is frozen and a write to a copy raises
#
# Usage: sh tests/backports/host/accessibilitymap/mutants.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
package=$root/packages/a/apple-backports
sources=${ACCESSIBILITY_SRC:-$package/Accessibility}
work=${BUILD:-${TMPDIR:-/tmp}/charon-accessibilitymap-mutants}
rm -rf "$work"
mkdir -p "$work"
survived=0
ran=0
killed=0
died_wrong=0

mutant() {
    # name, which occurrence of the line, the line, what it becomes
    name=$1
    nth=$2
    old=$3
    new=$4
    if [ -z "$nth" ]; then
        echo "mutant $name does not say which occurrence of its line it changes" >&2
        return 1
    fi
    dir="$work/$name"
    # The copy keeps the package's own shape, because the source reaches its headers by a relative path.
    # A copy that did not would stop the build, and a mutant that dies of a build error has told nobody
    # anything - which is what the kill below insists on.
    mkdir -p "$dir/pkg/Accessibility"
    cp "$sources/CharonBrailleMap.m" "$dir/pkg/Accessibility/"
    cp "$sources/CharonBrailleMap.h" "$dir/pkg/Accessibility/"
    cp "$package/CharonSayOnce.h" "$dir/pkg/"
    MUTATE="$dir/pkg/Accessibility/CharonBrailleMap.m" MUTATE_OLD="$old" MUTATE_NEW="$new" \
        MUTATE_NTH="$nth" python3 "$here/../common/mutate.py"
    ran=$((ran + 1))
    if ACCESSIBILITY_SRC="$dir/pkg/Accessibility" BUILD="$dir/build" sh "$here/run.sh" > "$dir/out.txt" 2>&1; then
        echo "MUTANT SURVIVED: $name"
        survived=$((survived + 1))
        return 0
    fi
    if grep -q 'the two answers do not match what this case declares' "$dir/out.txt" &&
       grep -qE '^(@@|--- |\+\+\+ )' "$dir/out.txt"; then
        killed=$((killed + 1))
        echo "killed by the diff: $name: $(grep -m1 -E 'UNDECLARED DIFFERENCE|DECLARED DIFFERENCE' "$dir/out.txt")"
        return 0
    fi
    if grep -q 'says so once' "$dir/out.txt"; then
        killed=$((killed + 1))
        echo "killed by the once-only count: $name: $(grep -m1 'says so once' "$dir/out.txt")"
        return 0
    fi
    # A factory that answers the wrong size fails its own probe, and that probe is part of the run.
    if grep -q 'the factory probe did not pass' "$dir/out.txt"; then
        killed=$((killed + 1))
        # The branch is a condition and not `|| true`: the empty answer is the signal that the probe
        # failed for a reason this script does not name, and it is reported two lines below.
        if line=$(grep -m1 'FAILED' "$dir/out.txt"); then
            echo "killed by the factory probe: $name: $line"
        else
            echo "killed by the factory probe: $name: (the probe failed before it named a check)"
        fi
        return 0
    fi
    echo "MUTANT DIED FOR THE WRONG REASON: $name"
    tail -5 "$dir/out.txt"
    died_wrong=$((died_wrong + 1))
}

mutant M1-pin-not-stored 1 \
    '    [_pins setObject:@(height) forKey:CharonBrailleMapKey(point)];' \
    '    (void)point;'

mutant M2-height-clamped 1 \
    '    [_pins setObject:@(height) forKey:CharonBrailleMapKey(point)];' \
    '    [_pins setObject:@(height < 0.0f ? 0.0f : (height > 1.0f ? 1.0f : height)) forKey:CharonBrailleMapKey(point)];'

mutant M3-negative-point-refused 1 \
    '    if (!_pins) {' \
    '    if (point.x < 0 || point.y < 0) {
        return;
    }
    if (!_pins) {'

mutant M4-copy-shares-store 1 \
    '    copy->_pins = _pins ? (id<CharonBrailleMapPinStore>)[NSDictionary dictionaryWithDictionary:(NSDictionary *)_pins] : nil;' \
    '    copy->_pins = _pins;'

mutant M5-copy-drops-pins 1 \
    '    copy->_pins = _pins ? (id<CharonBrailleMapPinStore>)[NSDictionary dictionaryWithDictionary:(NSDictionary *)_pins] : nil;' \
    '    copy->_pins = nil;'

mutant M6-archive-drops-pins 1 \
    '    [coder encodeObject:_pins forKey:@"pins"];' \
    '    (void)coder;'

mutant M7-copy-drops-size 1 \
    '    copy->_size = _size;' \
    '    copy->_size = CGSizeZero;'

mutant M8-factory-wrong-size 1 \
    '    map->_size = dimensions;' \
    '    map->_size = CGSizeMake(1, 1);'

# The frozen copy, which the parity decision of 2026-09-29 added: a copy that took the write would
# answer the system differently on two cases, and this is the mutant that says so.
mutant M9-copy-not-frozen 1 \
    '    copy->_pins = _pins ? (id<CharonBrailleMapPinStore>)[NSDictionary dictionaryWithDictionary:(NSDictionary *)_pins] : nil;' \
    '    copy->_pins = _pins ? (id<CharonBrailleMapPinStore>)[(NSDictionary *)_pins mutableCopy] : nil;'

echo "mutants run: $ran, killed: $killed, died for another reason: $died_wrong, survived: $survived"
[ "$survived" -eq 0 ] && [ "$died_wrong" -eq 0 ] && [ "$killed" -eq "$ran" ]
