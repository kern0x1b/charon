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
if [ "${1:-}" = "mutant" ]; then
    # The result type is a property the header declares and the class must honour: a request that
    # was given ObjectIDs and answers StatusOnly is a wrong answer, not a default. The port's
    # property is a @synthesize, so the mutation is the STORAGE it reads - change what -init puts
    # there from StatusOnly to ObjectIDs and the bare request answers a different type than Apple's.
    sed -i.bak 's/_charonResultType = NSBatchInsertRequestResultTypeStatusOnly;/_charonResultType = NSBatchInsertRequestResultTypeObjectIDs;/' "$build/port.m" 2>/dev/null || true
    echo "MUTANT: the port's -init stores ObjectIDs where Apple's default is StatusOnly"
fi
sed -i.bak '/#import "CharonCoreData.h"/d' "$build/port.m" 2>/dev/null || true
rm -f "$build"/*.bak

xcrun clang -fobjc-arc -w -I"$FP/CoreData" -c "$build/port.m" -o "$build/port.o"
xcrun clang -fobjc-arc -w "$here/differential.m" "$build/port.o" \
    -framework Foundation -framework CoreData -o "$build/differential"
"$build/differential" > "$build/port.tsv" 2>/dev/null || true

# The expected, written down: what Apple's own answers are, and the class's own default. The
# verdict is a diff against it, so a port that answers something else is red.
cat > "$build/expected.tsv" <<'EXPECTED'
byEntity.entity	Row
byEntity.entityName	(nil)
byName.entityName	Row
byName.firstRow.name	one
byName.objects	2
byName.resultType.set	1
dictionaryHandler.called	0
dictionaryHandler.present	true
init.entityName	
init.objects	0
init.resultType	0
in-memory store	added
managedObjectHandler.called	0
managedObjectHandler.present	true
ResultTypeCount	2
EXPECTED
LC_ALL=C sort "$build/port.tsv" > "$build/port.sorted"
LC_ALL=C sort "$build/expected.tsv" > "$build/expected.sorted"
if diff "$build/expected.sorted" "$build/port.sorted" > "$build/diff"; then
    echo "VERDICT: green - the port answers what Apple's answers on every line"
    exit 0
fi
cat "$build/diff"
echo "VERDICT: RED - $(wc -l < "$build/diff" | tr -d ' ') line(s) of diff"
exit 1

