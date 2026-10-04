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

"$xmake" emulate -d "$device" -r "$release" -t 900 -s 300 run "/usr/libexec/metalchain-probe" > "$out/run.log" 2>&1 || true
"$xmake" emulate log > "$out/guest.log" 2>&1 || true

# THE VERDICT IS ANSWERED HERE, not left in a file for a reader to find: `xmake emulate run` exits
# non-zero on a failed verdict BY DESIGN - a FAIL is a result - so `|| true` above keeps that exit from
# stopping the script before the result is read, and what decides the exit below is the probe's own
# summary line and the framework's verdict word. Both are printed with the line they came from.
summary=$(grep -a 'check(s),' "$out/run.log" | tail -1 || true)
if [ -z "$summary" ]; then
  echo "run-guest.sh: the run left no summary line, so the probe did not finish; the log is $out/run.log"
  exit 1
fi
# The emulator's own word is on the line that names the device and the release - "error: fail(exit 1) on
# iPhone3,1 6.1.3 (10B329) in 0.0 guest s" - and the line is read whole rather than through a pattern, so
# the verdict word cannot be missed by a regexp that does not know how xmake spells it.
verdict_line=$(grep -a 'on iPhone' "$out/run.log" | tail -1 || true)
printf 'run-guest.sh: %s\n' "$summary"
if [ -n "$verdict_line" ]; then
  printf 'run-guest.sh: the emulator says: %s\n' "$verdict_line"
fi
echo "run-guest.sh: the full log is $out/run.log and the guest's own output $out/guest.log"

# AND THE REFUSALS ARE COUNTED AGAINST WHAT THE CODE SAYS. Every member of @protocol MTL4CommandQueue the
# port refuses answers with an NSLog line naming the facility it would have needed, and those lines reach
# this log - so if the probe reported twelve refusals that returned and the log carries fewer than twelve
# "Metal:" lines, then some of them refused silently, which is the defect those twelve rows would be
# claiming the absence of.
refusals_reported=$(grep -ac '^ok   MTL4CommandQueue_refusal' "$out/run.log" || true)
refusal_lines=$(grep -ac 'Metal: ' "$out/run.log" || true)
printf 'run-guest.sh: %s refusal(s) reported, %s refusal line(s) in the guest output\n' \
    "$refusals_reported" "$refusal_lines"

# A probe that reported a failure or a case it could not answer has NOT passed, whatever the emulator's
# own word is: the probe exits non-zero in both cases and prints its own counts, and those counts are
# what this script holds it to.
case "$summary" in
  *"0 failure(s), 0 not answered"*)
    if [ "$refusal_lines" -lt "$refusals_reported" ]; then
      echo "run-guest.sh: NOT a pass - $refusals_reported refusals reported and only $refusal_lines refusal line(s) in the guest output"
      exit 1
    fi
    exit 0 ;;
  *) echo "run-guest.sh: NOT a pass - the probe reported a failure or a case it could not answer"; exit 1 ;;
esac