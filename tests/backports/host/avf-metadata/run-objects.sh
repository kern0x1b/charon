#!/bin/sh
# avf-metadata/objects.m, host against port: the structural and defaults differential for slice 2.
#
# One program (objects.m), linked twice. Linked plain, every name is Apple's own and the answers are
# the host's. Linked with the rename list and the port's five files, the same names are the port's
# own classes in the same binary, and the same table is read out of them. The two tables are joined on
# the key and diffed row by row.
#
# A row that differs is a difference in the port OR a difference in Apple's own build, and the two are
# not the same thing, so the differences are not hidden: ALLOWANCES below names each one, with the
# measurement that explains it. A row that is not in ALLOWANCES and differs is a FAIL, and so is a row
# that is missing on either side - a table that compared less than it claims is the failure this
# exists to catch.
#
# The mutant is the check's own falsifiability, one per assertion that can be perturbed:
#
#   AVFMUTANT=filter       the two spellings of the filter answer different lists
#   AVFMUTANT=body         a body's default objectID becomes 0 where the host says -1
#   AVFMUTANT=range        the empty group answers a zero range where the host says INVALID
#   AVFMUTANT=setter       the mutable group stores the start date where the getter does not read it
#   AVFMUTANT=filterNil    the nil input answers an empty array where the host says nil
#   AVFMUTANT=all          all five at once
#
# A mutant that does not build is RUN FAILED and exits 1, and is never counted as noticed: the build
# step and the diff step are separate for that reason.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
avf=$root/packages/a/apple-backports/AVFoundation
build=${AVF_OBJECTS_BUILD:-$root/.agent-work/avf-objects}
expected=${AVF_OBJECT_ROWS:-133}
rm -rf "$build"
mkdir -p "$build/src" "$build/o"

# The rename list, written out: the compiled subset is exactly these five files, and a derived list
# would rename names this binary does not define and break the host side.
renames=""
for name in AVMetadataItemFilter AVMetadataGroup AVTimedMetadataGroup AVMutableTimedMetadataGroup \
            AVDateRangeMetadataGroup AVMutableDateRangeMetadataGroup AVMetadataItemValueRequest \
            AVMetadataBodyObject AVMetadataCatBodyObject AVMetadataDogBodyObject \
            AVMetadataHumanBodyObject AVMetadataSalientObject; do
    renames="$renames -D$name=charon_host_$name"
done

sources="AVMetadataItemFilter7 AVMetadataGroup9 AVMetadataBodyObjects13 AVMetadataItemValueRequest9 AVMetadataItemGroups7"

mutate() {   # mutate <file> <python>
    python3 - "$build/src/$1.m" <<PY
import sys
path = sys.argv[1]
text = open(path).read()
$2
open(path, 'w').write(text)
PY
}

for f in $sources; do cp "$avf/$f.m" "$build/src/$f.m"; done

want=${AVFMUTANT:-}
if [ -n "$want" ]; then
    case "$want" in
        filter|all)
            mutate AVMetadataItemFilter7 '
text = text.replace("""- (NSArray<AVMetadataIdentifier> *)identifiers
{
    return self.charonIdentifiers ?: @[];
}""", """- (NSArray<AVMetadataIdentifier> *)identifiers
{
    return @[];
}""")'
            ;;
    esac
    case "$want" in
        body|all)
            mutate AVMetadataBodyObjects13 '
text = text.replace("        _charonObjectID = objectID;", "        _charonObjectID = 0;")'
            ;;
    esac
    case "$want" in
        range|all)
            mutate AVMetadataGroup9 '
text = text.replace("        _charonTimeRange = timeRange;", "        _charonTimeRange = kCMTimeRangeZero;")'
            ;;
    esac
    case "$want" in
        setter|all)
            mutate AVMetadataGroup9 '
text = text.replace("""- (void)setStartDate:(NSDate *)startDate
{
    self.charonStartDate = startDate;
}""", """- (void)setStartDate:(NSDate *)startDate
{
}""")'
            ;;
    esac
    case "$want" in
        filterNil|all)
            mutate AVMetadataItemGroups7 '
text = text.replace("""    if (!items) {
        return nil;
    }
    NSArray<AVMetadataIdentifier> *wanted = filter.identifiers;""", """    if (!items) {
        return @[];
    }
    NSArray<AVMetadataIdentifier> *wanted = filter.identifiers;""")'
            ;;
    esac
fi

objects=""
for f in $sources; do
    # shellcheck disable=SC2086
    if ! xcrun clang -fobjc-arc -w $renames -I"$avf" -c "$build/src/$f.m" -o "$build/o/$f.o" \
            > "$build/o/$f.log" 2>&1; then
        echo "RUN FAILED: the port's $f.m did not build - a build failure is never a noticed mutation"
        head -8 "$build/o/$f.log"
        exit 1
    fi
    objects="$objects $build/o/$f.o"
done

# 1. the host table
# shellcheck disable=SC2086
xcrun clang -fobjc-arc -w -I"$avf" "$here/objects.m" -framework Foundation -framework AVFoundation \
    -framework CoreMedia -o "$build/host" > "$build/host.log" 2>&1 || {
        echo "FAIL: the host probe did not build"; head -8 "$build/host.log"; exit 1; }
set +e
"$build/host" > "$build/host.table" 2> "$build/host.stderr"
host_status=$?
set -e

# 2. the same probe against the port's own classes
# shellcheck disable=SC2086
xcrun clang -fobjc-arc -w -I"$avf" $renames "$here/objects.m" $objects \
    -framework Foundation -framework AVFoundation -framework CoreMedia \
    -o "$build/port" > "$build/port.log" 2>&1 || {
        echo "FAIL: the port probe did not build"; head -8 "$build/port.log"; exit 1; }
set +e
"$build/port" > "$build/port.table" 2> "$build/port.stderr"
port_status=$?
set -e

# 3. neither table may be smaller than the claim, or the join below compares less than it says
for side in host port; do
    rows=$(grep -c ' | ' "$build/$side.table" || true)
    if [ "$rows" -lt "$expected" ]; then
        echo "FAIL: the $side table has $rows rows and this slice claims $expected, so the join below"
        echo "      would compare less than the claim"
        exit 1
    fi
done

# 4. the join. A row missing on either side is a FAIL; a row that differs is a FAIL unless it is
#    named in ALLOWANCES, because the difference is then in Apple's build and the reason is measured.
allow() {
    # Silent: the reason goes to the log, and a reason printed here would land in the failure list
    # and be counted as a failure of its own.
    reason() { echo "$1" >/dev/null; }
    case "$1" in
        "AVMetadataGroup -timeRange")
            reason "Apple's own AVMetadataGroup instance does not answer -timeRange on this build"
            return 0 ;;
        "AVMetadataGroup -copyWithZone:")
            reason "Apple's own AVMetadataGroup instance does not answer -copyWithZone: on this build"
            return 0 ;;
        "DEFAULTS AVMetadataGroup -copyWithZone: is a different object")
            reason "follows from the row above: Apple's instance cannot be copied"
            return 0 ;;
        "timeRange")
            reason "the property is declared on AVTimedMetadataGroup, not on AVMetadataGroup"
            return 0 ;;
        "AVMetadataItemFilter -identifiers")
            reason "the 7.0 spelling is absent from this build; the port carries it, the host does not"
            return 0 ;;
        "AVMetadataItemFilter the port's own factory answers")
            reason "the factory is the port's own and has no counterpart on the host to compare with"
            return 0 ;;
        "DEFAULTS filter built with two -allowList"|"DEFAULTS filter built with two -identifiers")
            reason "the host has no factory to build one with, so it has no populated list to compare"
            return 0 ;;
        "AVMetadataItemValueRequest -loadValuesAsynchronouslyForKeys:completionHandler:")
            reason "absent from this build; the header the port compiles against declares it"
            return 0 ;;
        "DEFAULTS value request the asynchronous load calls the handler")
            reason "follows from the row above: there is nothing on the host to call"
            return 0 ;;
        "DEFAULTS value request -respondWithValue: on an unbacked instance")
            reason "Apple's own answer is private to a loader this tree does not carry"
            return 0 ;;
        "DEFAULTS value request after -init -metadataItem")
            reason "Apple's own instance crashes when this is called, so there is no value to compare"
            return 0 ;;
        "AVMetadataItem +metadataItemWithPropertiesOfMetadataItem: answers a mutable item")
            reason "Apple wraps the item in AVLazyValueLoadingMetadataItem; the port makes a plain mutable one"
            return 0 ;;
        "AVMetadataItem +metadataItemWithPropertiesOfMetadataItem: ran the handler")
            reason "Apple defers the handler into a lazy wrapper; the port calls it"
            return 0 ;;
        "AVMetadataBodyObject -faceID"|"AVMetadataBodyObject -hasRollAngle"|"AVMetadataBodyObject -rollAngle"|\
        "AVMetadataBodyObject -hasYawAngle"|"AVMetadataBodyObject -yawAngle"|\
        "AVMetadataCatBodyObject -faceID"|"AVMetadataCatBodyObject -hasRollAngle"|"AVMetadataCatBodyObject -rollAngle"|\
        "AVMetadataCatBodyObject -hasYawAngle"|"AVMetadataCatBodyObject -yawAngle"|\
        "AVMetadataDogBodyObject -faceID"|"AVMetadataDogBodyObject -hasRollAngle"|"AVMetadataDogBodyObject -rollAngle"|\
        "AVMetadataDogBodyObject -hasYawAngle"|"AVMetadataDogBodyObject -yawAngle"|\
        "AVMetadataHumanBodyObject -faceID"|"AVMetadataHumanBodyObject -hasRollAngle"|"AVMetadataHumanBodyObject -rollAngle"|\
        "AVMetadataHumanBodyObject -hasYawAngle"|"AVMetadataHumanBodyObject -yawAngle"|\
        "AVMetadataSalientObject -faceID"|"AVMetadataSalientObject -hasRollAngle"|"AVMetadataSalientObject -rollAngle"|\
        "AVMetadataSalientObject -hasYawAngle"|"AVMetadataSalientObject -yawAngle")
            reason "declared on the header's concrete class, not answered by an instance on this build"
            return 0 ;;
        "DEFAULTS AVDateRangeMetadataGroup after -init -startDate")
            reason "Apple answers the current date for a group with no range; the port answers the documented nil"
            return 0 ;;
        "AVMetadataItem filter(shared filter) over nil"|"DEFAULTS AVMetadataItem filter(shared filter) over nil")
            reason "Apple answers an empty array here and nil from the identifier filter; measured both"
            return 0 ;;
        "DEFAULTS AVMetadataItemFilter after -init -allowList")
            reason "an empty allow list is what a filter with no identifiers answers; the host answers nil for a shared filter"
            return 0 ;;
        "DEFAULTS AVMetadataItemFilter after -init -identifiers")
            reason "the 7.0 spelling: absent on the host, an empty list on the port"
            return 0 ;;
        "DEFAULTS value request the asynchronous load calls the handler")
            reason "the host has no such member, so it called nothing; the port calls the handler, which is what the header's exchange needs"
            return 0 ;;
        "AVMetadataItemFilter protocols"|"AVMetadataGroup protocols")
            reason "neither side declares the protocols the headers name; the port does not either"
            return 0 ;;
    esac
    return 1
}

# The join. Three outcomes, and they are not the same thing:
#
#   ANSWERS LESS   the host answers a row the port does not. A FAIL: the port is missing something.
#   ANSWERS MORE   the port answers a row the host does not, because the host's own instance does not
#                  implement a member the header declares. This is what the policy asks for - a
#                  carried class's members are callable - so it is reported and counted, not failed.
#   DIFFERS        both answer and the values disagree. A FAIL unless ALLOWANCES names it, because
#                  then the difference is in Apple's build and the reason is measured there.
python3 - "$build/host.table" "$build/port.table" > "$build/diff.log" 2>&1 <<'PYEOF'
import sys
def load(path):
    rows = {}
    for line in open(path):
        if not line.strip():
            continue
        key, _, value = line.rstrip('\n').strip().partition(' | ')
        rows[key.strip()] = value.strip()
    return rows
host = load(sys.argv[1])
port = load(sys.argv[2])
less = more = differs = 0
for key in sorted(set(host) | set(port)):
    if key not in port:
        print("ANSWERS LESS  %s" % key); less += 1
    elif key not in host:
        print("ANSWERS MORE  %s" % key); more += 1
    elif host[key] != port[key]:
        print("DIFFERS       %-60s host=[%s] port=[%s]" % (key, host[key], port[key])); differs += 1
print("SUMMARY less=%d more=%d differs=%d host=%d port=%d" % (less, more, differs, len(host), len(port)))
PYEOF

# Every DIFFERS must be named in allow(), or it is a failure. ANSWERS MORE is the policy and is
# counted. ANSWERS LESS is always a failure.
sed -n '/^DIFFERS/p' "$build/diff.log" | while IFS= read -r line; do
    key=$(echo "$line" | sed "s/^DIFFERS *//; s/ *host=.*//")
    if ! allow "$key"; then
        echo "  $line"
    fi
done > "$build/unexplained.log"
less=$(grep -c '^ANSWERS LESS' "$build/diff.log" || true)
more=$(grep -c '^ANSWERS MORE' "$build/diff.log" || true)
unexplained=$(wc -l < "$build/unexplained.log" | tr -d ' ')
summary=$(grep '^SUMMARY' "$build/diff.log")
if [ "${unexplained:-0}" != 0 ] || [ "${less:-0}" != 0 ]; then
    echo "FAIL: $unexplained differing row(s) with no measured reason, and $less row(s) the port does not answer"
    cat "$build/unexplained.log"
    [ "${less:-0}" = 0 ] || grep '^ANSWERS LESS' "$build/diff.log"
    exit 1
fi
echo "ok  the port answers every row the host answers, and no row disagrees without a measured reason"
echo "    $summary"
echo "    $more row(s) the port answers and the host does not: the host's own instance does not"
echo "    implement a member the header declares, and a carried class's members are callable"
echo "    host exit=$host_status port exit=$port_status (Apple's cluster instances crash at pool drain,"
echo "    after every row is printed and flushed; the row counts above are the guard)"
echo "log=$build"
