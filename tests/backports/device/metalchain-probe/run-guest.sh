#!/bin/sh
# run-guest.sh - the emulator run of the metalchain probe, and nothing else.
#
# IT IS A SEPARATE SCRIPT BECAUSE IT IS THE ONLY HEAVY PART of this case: configure, build and install
# are a package build and a few seconds of compile, while the run boots a guest and holds a slot of the
# machine (AGENTS.md section 8). The coordinator asked for exactly this split on 2026-10-04, after a run
# of the whole script under heavy.sh came back "every package not found". So the whole procedure stays
# runnable as one command (`sh run.sh`, which calls this), and the guest alone can be queued:
#
#   $HOME/Git/projects/ios/coordination/heavy.sh sh tests/backports/device/metalchain-probe/run-guest.sh
#
# The LC_UUID gate is in run.sh and has already passed by the time this runs; this script re-checks
# nothing and re-installs nothing, so it must not be run against an image the gate has not cleared.
#
# `xmake emulate run` is given a BARE PATH and no arguments: with arguments it answers "fail(spawn
# error 2)" even for a system binary (coordinator, measured on the v-crutch5 runs of 2026-10-04).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="$here/run"
device=${METALCHAINPROBE_DEVICE:-iPhone3,1}
release=${METALCHAINPROBE_RELEASE:-6.1.3}
xmake=/opt/homebrew/bin/xmake
mkdir -p "$out"
cd "$here"

/opt/homebrew/bin/xmake emulate -d "$device" -r "$release" -t 900 -s 300 run "/usr/libexec/metalchain-probe" > "$out/run.log" 2>&1 || true
"$xmake" emulate log > "$out/guest.log" 2>&1 || true
echo
echo "run-guest.sh: the verdict is in $out/run.log and the guest's own output in $out/guest.log"