#!/bin/sh
# The committed check for NSBatchInsertRequest: the framework's own class and the port's, asked the
# same ten questions, and the diff between the two answers.
#
#   ./check.sh        the control: an empty diff is green
#
# Nothing persisted - the store in the other probe is NSInMemoryStoreType - and no CloudKit here.
# The reference is reference-host.tsv, generated on the host at build time and committed with the
# versions it came from (reference-host.OS.txt).
#
# THE PORT BINARY RENAMES THE CLASS, with -DNSBatchInsertRequest=CharonBatchInsertRequest, because it
# links -framework CoreData and the runtime answers "Class NSBatchInsertRequest is implemented in
# both CoreData and .../port" otherwise - a real collision for anything that links both. That is also
# why -init's reason text is the LITERAL and not NSStringFromClass: a class-name substitution would
# spell the renamed class where Apple spells NSBatchInsertRequest.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
FP=${COREDATA:-$here/../../../../packages/a/apple-backports}
build=${COREDATA_CHECK:-$here/../../../../.agent-work/runs/coredata-check}
rm -rf "$build"; mkdir -p "$build"

cp "$FP/CoreData/NSBatchInsertRequest.m" "$build/port.m"
grep -v '#import "CharonCoreData.h"' "$build/port.m" > "$build/port.buildable.m"
mv "$build/port.buildable.m" "$build/port.m"

echo "=== the port builds"
xcrun clang -fobjc-arc -w -DNSBatchInsertRequest=CharonBatchInsertRequest \
    -I"$FP/CoreData" -c "$build/port.m" -o "$build/port.o"

echo "=== the host and the port, as two processes"
xcrun clang -fobjc-arc -w "$here/per-initializer.m" \
    -framework Foundation -framework CoreData -o "$build/host"
xcrun clang -fobjc-arc -w -DNSBatchInsertRequest=CharonBatchInsertRequest \
    "$here/per-initializer.m" "$build/port.o" \
    -framework Foundation -framework CoreData -o "$build/port"

"$build/host" > "$build/host.txt" 2>/dev/null
"$build/port" > "$build/port.txt" 2>/dev/null
for side in host port; do
    lines=$(wc -l < "$build/$side.txt" | tr -d ' ')
    if [ "$lines" -lt 20 ]; then
        echo "NO ANSWER: the $side run printed $lines line(s) and twenty-two were asked for, so a"
        echo "diff of two empty or short files would be a green that measured nothing."
        exit 3
    fi
done

if diff "$build/host.txt" "$build/port.txt" > "$build/diff"; then
    echo "VERDICT: green - the port answers exactly what Apple's own answers, on all 22 lines"
    exit 0
fi
cat "$build/diff"
echo "VERDICT: RED - $(wc -l < "$build/diff" | tr -d ' ') line(s) differ"
exit 1
