#!/bin/bash
# output.sh [DEVICE] [RELEASE]: a run's program output, measured, on a real guest. Two runs:
# one program that ends, and one the deadline kills, which flushes no buffer - so what it printed
# before is what the host must still have. Both are greps on the host for the line the program
# printed, which is the claim under test: the program's own output reaches the host, in the run
# folder and in `xmake emulate log`, whether it ended or was killed.
set -eu
cd "$(dirname "$0")"
device=${1:-iPhone4,1}
release=${2:-6.1.3}
out=${OUT_DIR:-.agent-work/output}
mkdir -p "$out"
xmake f -p iphoneos -a armv7 -y > "$out/configure.log" 2>&1

known=charon-emulate-output
status=0
for mode in end hang; do
  log=$out/$mode.log
  rm -rf "${out:?}/$mode"
  if [ "$mode" = hang ]; then
    xmake emulate -d "$device" -r "$release" -s 6 -t 900 \
        run /usr/libexec/emulateoutput --hang > "$log" 2>&1 || status=$?
  else
    xmake emulate -d "$device" -r "$release" -s 60 -t 900 \
        run /usr/libexec/emulateoutput > "$log" 2>&1 || status=$?
  fi
  folder=$(sed -n 's/^run folder //p' "$log" | tail -1)
  # The file in the run folder, and the same line through `xmake emulate log`, which is what a band
  # reads after the fact: a run that only had the first is half a fix.
  if [ -n "$folder" ] && grep -q "$known: stdout reached the host" "$folder/results/test.stdout" 2>/dev/null; then
    echo "$mode: the program's stdout is in the run folder"
  else
    echo "$mode: the program's stdout is NOT in the run folder ($folder)" >&2; status=1
  fi
  xmake emulate -d "$device" -r "$release" log "$known" > "$out/$mode-filtered.log" 2>&1 || true
  if grep -q "$known: stderr reached the host" "$out/$mode-filtered.log"; then
    echo "$mode: the program's stderr comes back through xmake emulate log"
  else
    echo "$mode: the program's stderr does NOT come back through xmake emulate log" >&2; status=1
  fi
  if [ "$mode" = hang ]; then
    if grep -q "not captured" "$log"; then
      echo "hang: the run said the output was not captured, which it must not" >&2; status=1
    else
      echo "hang: a program the deadline killed did not lose what it printed"
    fi
  fi
done
exit $status
