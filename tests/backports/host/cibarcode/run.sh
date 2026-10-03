#!/bin/sh
# run.sh - the ORACLE for CoreImage's barcode descriptors, and why the port's own object cannot be compared
# with it on this machine.
#
# WHAT THIS RUNS: cases.m against the HOST's own CoreImage, every group, and a diff against the answers
# recorded in host-answers.tsv. measure.sh is what writes that file; this script re-measures it on every run
# and fails if a single answer moved, so the table is today's host and not a frozen one.
#
# WHAT IT DOES NOT RUN, and why, with the measurement: the port's five classes carry the same names as the
# host's, and on macOS EVERY process that uses Foundation has CoreImage loaded - DYLD_PRINT_LIBRARIES on a
# program that links Foundation alone prints CoreImage coming in through DataDetection and
# AppleNeuralEngine. A port build in such a process is a duplicate class and the runtime answers a duplicate
# with whichever class registered first. Taking CoreImage out of the LINK is not enough, because it is
# loaded rather than linked, so the port build cannot be shown to be the one answering: a dladdr record on
# one method says "port" while another class's selector still resolves to the host's implementation, and the
# port build then dies exactly where the host dies.
#
# That was measured, not assumed. An earlier version of this harness compiled cases.m twice - once with the
# port's object and once without - and BOTH builds printed identical answers for all 140338 combinations,
# because only one of them was running the code under test. The binding record in cases.m is what caught it,
# and it is why the record is there.
#
# So what is left for this family on this machine is the oracle, and this script is it. The port's object,
# the registry rows and the pixel comparison of a rendered symbol all wait for a decision that is not a
# worker's to make: see the "what this family needs" section of packages/a/apple-backports/facts/CoreImage/
# BarcodeDescriptor.md.
set -eu
here=$(cd "$(dirname "$0")" && pwd)

sh "$here/measure.sh"

answers=$here/host-answers.tsv
records=$(grep -c . "$answers" || true)
sweeps=$(grep -c 'ranges answered' "$answers" || true)
[ "$sweeps" -eq 4 ] || { echo "FAIL  the table holds $sweeps sweep records, and there are four classes"; exit 1; }
echo "  ORACLE: $records records of the host's own answers, all four ranges swept whole"
echo "  NOT COMPARABLE HERE: the port's five classes share the host's names and every Foundation process on"
echo "    macOS has CoreImage loaded, so a port build is a duplicate class and cannot be shown to answer. The"
echo "    cause, the measurement and the three ways out are in facts/CoreImage/BarcodeDescriptor.md."
exit 0
