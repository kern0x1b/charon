#!/bin/sh
# run.sh -- the text drag and drop order on an emulated 6.1.3: the tree, then the same tree with the
# drop's gate moved after the proposal, then the tree back. Both halves through heavy.sh's bulk lane.
# The verdict is the addon's verdict.json and the two files the program wrote in the image; the
# runner's log carries neither of those.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${DDR_ROOT:-$here/../../../..}
build=${DDR_BUILD:-${TMPDIR:-/tmp}/charon-tdd-device}
device=${DDR_DEVICE:-iPhone3,1}
releases=${DDR_RELEASES:-"6.1.3"}
export DDR_ROOT=$root

seq=$root/packages/a/apple-backports/UIKit/UITextView+TextDragDrop11.m
mutated=$here/UITextView+TextDragDrop11.mutated.m
original=$here/UITextView+TextDragDrop11.m.original
cp "$seq" "$original"

rm -rf "$build"
mkdir -p "$build"
cp "$here/xmake.lua" "$here/control" "$build/"
cd "$build"
xmake f -p iphoneos -a armv7 -y > configure.log 2>&1
xmake build -y > build.log 2>&1

run_one() {
    release=$1
    half=$2
    image=$3
    DDR_ROOT=$root xmake build -r -y > "build-$half-$release.log" 2>&1 || {
        echo "$half $release: BUILD-FAIL"; tail -3 "build-$half-$release.log"; return 1; }
    DDR_ROOT=$root xmake emulate -d "$device" -r "$release" install > "install-$half-$release.log" 2>&1 || {
        echo "$half $release: INSTALL-FAIL"; tail -3 "install-$half-$release.log"; return 1; }
    set +e
    DDR_ROOT=$root xmake emulate -d "$device" -r "$release" -k launch /usr/libexec/textdragdrop > "$release-$half.log" 2>&1
    status=$?
    set -e
    if [ "$status" -eq 137 ]; then
        echo "$half $release: killed (status 137) before the guest ran -- the machine was out of memory, not a verdict"
        return 1
    fi
    verdict=$(ls -d "$HOME/.charon/emulator/images.noindex/$image/iPhone3,1_"*"/run/verdict.json" 2>/dev/null | head -1)
    [ -n "$verdict" ] && echo "$half $release: $(python3 -c "
import json
d=json.load(open('$verdict'))
print(d.get('state','?'), d.get('reason',''))" 2>/dev/null)"
    if [ "$status" -eq 0 ] && grep -Eq 'pass.{0,12} on iPhone' "$release-$half.log"; then
        echo "$half $release: pass"
        return 0
    fi
    echo "$half $release: not a pass (status $status)"
    grep -aE '^FAIL|fail|crash|timeout|blocked' "$release-$half.log" | head -2 || true
    return 1
}

guest_lines() {
    release=$1
    half=$2
    image=$3
    rootfs=$(ls -d "$HOME/.charon/emulator/images.noindex/$image/iPhone3,1_"*"/run/rootfs" 2>/dev/null | head -1)
    [ -n "$rootfs" ] || { echo "$half: no image rootfs"; return 0; }
    done_file="$rootfs/private/var/backports/textdragdrop.done"
    asked_file="$rootfs/private/var/backports/textdragdrop.asked"
    if [ -f "$done_file" ]; then
        printf '%s .done: ' "$half"; tr -d '\n' < "$done_file"; echo
    else
        echo "$half: no .done file -- the program did not reach the check"
    fi
    [ -f "$asked_file" ] && { echo "$half asked:"; sed 's/^/    /' "$asked_file"; }
    return 0
}

failed=0
image=$(ls -td "$HOME/.charon/emulator/images.noindex/"textdragdrop-* 2>/dev/null | head -1 | xargs basename 2>/dev/null)
for release in $releases; do
    [ -n "$image" ] || image=$(ls -td "$HOME/.charon/emulator/images.noindex/"textdragdrop-* 2>/dev/null | head -1 | xargs basename)
    run_one "$release" clean "$image" && guest_lines "$release" clean "$image" || failed=1
done
cp "$mutated" "$seq"
for release in $releases; do
    run_one "$release" mutated "$image" && guest_lines "$release" mutated "$image" || true
done
cp "$original" "$seq"
exit $failed
