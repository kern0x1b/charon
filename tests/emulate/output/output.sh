#!/bin/bash
# output.sh [DEVICE] [RELEASE]: a run's program output, measured, on a real guest. Two runs: one program
# that ends, and one the deadline kills, which flushes no buffer - so what it printed before is what the
# host must still have. Both are greps on the host for the line the program printed, which is the claim
# under test: the program's own output reaches the host, in the run's own files and in `xmake emulate
# log`, whether it ended or was killed.
#
# The run's files are found through the run's own verdict, not through a line on the console: the
# verdict carries the absolute paths of what the program wrote, and it is written whether the addon is
# the installed one or this tree's, so the check does not depend on which.
set -eu
cd "$(dirname "$0")"
device=${1:-iPhone2,1}
release=${2:-6.1.3}
out=${OUT_DIR:-.agent-work/output}
known=charon-emulate-output
mkdir -p "$out"
xmake f -p iphoneos -a armv7 -y > "$out/configure.log" 2>&1
xmake emulate install -d "$device" -r "$release" > "$out/install.log" 2>&1

# The newest run's verdict under this device and release, and the two files it names.
verdict() {
  ls -t "$HOME/.charon/emulator/images.noindex"/*/"${device}_"*/run/verdict.json 2>/dev/null | head -1
}
named() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$1" "$2"; }

status=0
for mode in end hang; do
  log=$out/$mode.log
  if [ "$mode" = hang ]; then
    xmake emulate -d "$device" -r "$release" -s 6 -t 900 \
        run /usr/libexec/emulateoutput --hang > "$log" 2>&1 || status=$?
  else
    xmake emulate -d "$device" -r "$release" -s 60 -t 900 \
        run /usr/libexec/emulateoutput > "$log" 2>&1 || status=$?
  fi
  v=$(verdict)
  if [ -z "$v" ]; then
    echo "$mode: no run's verdict was written; the log is $log" >&2
    status=1
    continue
  fi
  stdout=$(named "$v" stdout)
  stderr=$(named "$v" stderr)
  # The program's own line, read from the file the verdict names - the file in the guest, not a line on
  # the console, so a run that only echoed the verdict cannot pass this.
  if [ -n "$stdout" ] && grep -q "$known: stdout reached the host" "$stdout"; then
    echo "$mode: the program's stdout is in the file the verdict names"
  else
    echo "$mode: the program's stdout is NOT there (${stdout:-no path})" >&2
    status=1
  fi
  if [ -n "$stderr" ] && grep -q "$known: stderr reached the host" "$stderr"; then
    echo "$mode: the program's stderr is in the file the verdict names"
  else
    echo "$mode: the program's stderr is NOT there (${stderr:-no path})" >&2
    status=1
  fi
  # The same line through `xmake emulate log`, which is what a band reads after the fact: a run that
  # only had the first is half a fix.
  xmake emulate -d "$device" -r "$release" log "$known" > "$out/$mode-filtered.log" 2>&1 || true
  if grep -q "$known: stdout reached the host" "$out/$mode-filtered.log"; then
    echo "$mode: the program's stdout comes back through xmake emulate log"
  else
    echo "$mode: the program's stdout does NOT come back through xmake emulate log" >&2
    status=1
  fi
  if [ "$mode" = hang ]; then
    if grep -q "not captured" "$log"; then
      echo "hang: the run said the output was not captured, which it must not" >&2
      status=1
    else
      echo "hang: a program the deadline killed did not lose what it printed"
    fi
  fi
done
exit $status
