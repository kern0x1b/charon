#!/bin/sh
# Runs the host tests this tweak replays and writes their answers to uikit11-expectations.h.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
host=$here/../../host
work=${TMPDIR:-/tmp}/charon-uikit11-expectations
rm -rf "$work"
mkdir -p "$work"
for test in interactions systemspacing gesturename batchupdates contentsize; do
    TMPDIR="$work/" sh "$host/$test/run.sh" > "$work/$test.out" 2>/dev/null
done
python3 "$here/expectations.py" interactions="$work/charon-interactions-host/log" systemspacing="$work/systemspacing.out" \
    gesturename="$work/gesturename.out" batchupdates="$work/batchupdates.out" contentsize="$work/contentsize.out" \
    > "$here/uikit11-expectations.h"
