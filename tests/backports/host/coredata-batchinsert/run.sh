#!/bin/sh
# The differential for NSBatchInsertRequest, built against the port's own .m and run. The shape is
# tests/backports/host/fileprovider/run.sh: the port's file compiled for the host with xcrun clang,
# the probe built and run, and the mutant applied to a COPY so the tree is never edited.
#
#   ./run.sh            the control
#   ./run.sh mutant     the port's file with one line changed, which must turn the diff red
set -eu
here=$(cd "$(dirname "$0")" && pwd)
FP=${FILEPROVIDER:-$here/../../../../packages/a/apple-backports}
build=${COREDATA_BUILD:-${TMPDIR:-/tmp}/charon-coredata-batchinsert}
rm -rf "$build"; mkdir -p "$build"

cp "$FP/CoreData/NSBatchInsertRequest.m" "$build/port.m"
cp "$build/port.m" "$build/port.pristine"   # what the mutation is compared against
if [ "${1:-}" = "mutant" ]; then
    # The result type is a property the header declares and the class must honour: a request that
    # was given ObjectIDs and answers StatusOnly is a wrong answer, not a default. The port's
    # property is a @synthesize, so the mutation is the STORAGE it reads - change what -init puts
    # there from StatusOnly to ObjectIDs and the bare request answers a different type than Apple's.
    # A mutation that CHANGES something: the rows are dropped, so a request configured with two
    # of them answers none, and every line that reads them is wrong.
    sed -i.bak 's/_charonObjectsToInsert = \[dictionaries copy\];/_charonObjectsToInsert = nil;/' "$build/port.m"
    echo "MUTANT: objectsToInsert is nil where the rows were copied"
fi
# A MUTATION THAT CHANGED NOTHING IS NOT A MUTANT, and a runner that prints MUTANT either way
# makes a green control look defended. The comparison is against the copy AS IT WAS BEFORE the
# mutation, and it happens BEFORE the host-build normalisation below - the copy always differs from
# the original after that, so comparing against the original here is always true and the guard
# never fires.
if [ "${1:-}" = "mutant" ] && cmp -s "$build/port.pristine" "$build/port.m"; then
    echo "MUTANT FAILED: the copy is byte-identical to the file before the mutation, so nothing was"
    echo "mutated and a green verdict would prove nothing. The sed target is not in the file."
    exit 2
fi
sed -i.bak '/#import "CharonCoreData.h"/d' "$build/port.m" 2>/dev/null || true
rm -f "$build"/*.bak


# Two builds of the SAME probe: once against the port's class, once against the framework's own.
# The host Mac has a real NSBatchInsertRequest from the same header, so the two runs are the same
# thirteen questions asked of two implementations, and the verdict is the diff between them.
# Nothing is persisted: the store is NSInMemoryStoreType, and there is no CloudKit here.
xcrun clang -fobjc-arc -w -I"$FP/CoreData" -c "$build/port.m" -o "$build/port.o"
xcrun clang -fobjc-arc -w "$here/differential.m" "$build/port.o" \
    -framework Foundation -framework CoreData -o "$build/differential-port"
xcrun clang -fobjc-arc -w "$here/differential-host.m" \
    -framework Foundation -framework CoreData -o "$build/differential-host"
"$build/differential-port" > "$build/port.tsv"
"$build/differential-host" > "$build/host.tsv"
# Both runs must have answered: `diff` of two empty files is equal, and two silent runs would
# print a green that measured nothing. The line count is the check.
for side in port host; do
    lines=$(wc -l < "$build/$side.tsv" | tr -d ' ')
    if [ "$lines" -lt 13 ]; then
        echo "NO ANSWER: the $side run printed $lines line(s) and thirteen were asked for, so a"
        echo "diff of two empty or short files would be a green that measured nothing."
        exit 3
    fi
done

# The verdict is the host's answers against the port's. The table of expected values only
# DOCUMENTS the run now; it is not what green means.
LC_ALL=C sort "$build/port.tsv" > "$build/port.sorted"
LC_ALL=C sort "$build/host.tsv" > "$build/host.sorted"
echo "--- host.tsv"; cat "$build/host.tsv"
if diff "$build/host.sorted" >/dev/null 2>&1; then :; fi
if diff "$build/host.sorted" "$build/port.sorted" > "$build/diff"; then
    echo "VERDICT: green - the port answers exactly what Apple's own answers, on all 13 lines"
    exit 0
fi
cat "$build/diff"
echo "VERDICT: RED - $(wc -l < "$build/diff" | tr -d ' ') line(s) of diff"
exit 1

