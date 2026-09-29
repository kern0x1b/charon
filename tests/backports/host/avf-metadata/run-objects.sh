#!/bin/sh
# run-objects.sh — the metadata objects, host against port, and the mutations that must be noticed.
#
# One program (objects.m) linked twice: plain, where every name is Apple's own, and with the rename
# list and the port's five files, where the same names are the port's own classes in the same binary.
# The two tables are joined on the key and every row falls into one of three classes:
#
#   must match   the host answers it and the port answers it, and the two must agree. A difference is
#                a failure unless ALLOWANCES names it, and ALLOWANCES is a short list of differences
#                in APPLE'S build, each with the measurement that explains it.
#   ~ port-only  the key starts with ~: it is a row about the port's OWN Charon-prefixed
#                construction, which Apple has no factory for, so there is nothing to compare it to.
#                These are held against the UNMUTATED BASELINE instead - which is where a mutation of
#                a charon initializer shows up. A mutation inside an ALLOWANCES row is invisible by
#                construction, which is why the list is short and why no mutant aims at one.
#   answers less the host answers it and the port does not. Always a failure.
#
# **Directionality.** The check is not "nothing differs" - it is "a mutation must turn a RIGHT answer
# wrong". So a mutant run is judged against the baseline, and it must show all three of:
#
#   1. a row that CHANGED against the baseline, or the mutation did nothing;
#   2. that change is on a row that was RIGHT - a must-match row that matched the host, or a
#      port-only row - or the mutation made the port agree MORE closely with the host, which is not a
#      mutation a check may accept (the filterNil mutant of the last round did exactly that and the
#      run passed, which is the finding this assertion exists for);
#   3. a red verdict overall, or the mutation was not noticed where it counts.
#
# A control runs each mutant's UNMUTATED source through the identical build-and-run path and must stay
# green, so a red mutant is the mutation and not the path.
#
# Usage: sh tests/backports/host/avf-metadata/run-objects.sh              the differential
#        AVFMUTANT=<name> ... run-objects.sh                             a mutant, which must be noticed
#        AVFMUTANT=<name> CONTROL=1 ... run-objects.sh                   its control, which must be green
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
avf=$root/packages/a/apple-backports/AVFoundation
build=${AVF_OBJECTS_BUILD:-$root/.agent-work/avf-objects}
# The baseline lives BESIDE the build directory, not inside it: the build directory is removed
# and rebuilt on every run, and a baseline that a run deletes is a baseline no mutant can be
# judged against. This was the first version's fault and the mutants said so by name.
baseline_dir=${AVF_OBJECTS_BASELINE:-$root/.agent-work/avf-objects-baseline}
sources="AVMetadataItemFilter AVMetadataItemFilter7 AVMetadataGroup9 AVTimedMetadataGroup4 AVMetadataBodyObjects13 AVMetadataItemValueRequest9 AVMetadataItemGroups7"
rm -rf "$build"
mkdir -p "$build/src" "$build/o"

renames=""
# AVMetadataItemFilter is deliberately NOT in this list: the release carries that class (8.4.1 exports
# it) and the port only adds members to it, so renaming it would build a second class and the probe
# would read the port's instead of the release's.
for name in AVMetadataGroup \
            AVDateRangeMetadataGroup AVMutableDateRangeMetadataGroup AVMetadataItemValueRequest \
            AVMetadataBodyObject AVMetadataCatBodyObject AVMetadataDogBodyObject \
            AVMetadataHumanBodyObject AVMetadataSalientObject; do
    renames="$renames -D$name=charon_host_$name"
done

# ---- the five mutations. Each one changes a line the table READS, and each names the row it must
#      break, so "the mutant went red" and "the mutant broke the thing it aimed at" are one claim.
mutate() {
    python3 - "$build/src/$1.m" "$2" <<'PY'
import sys
path, which = sys.argv[1], sys.argv[2]
text = open(path).read()
MUTATIONS = {
    # the body's default objectID, which the table reads as "DEFAULTS ... objectID" and which the
    # host's own instances answer -1
    "bodyinit": ("_charonObjectID = CharonAVMetadataNoObject;", "_charonObjectID = 0;"),
    # the filter's stored list, read by the two ~CONSTRUCTED rows through both spellings. The text is
    # the CATEGORY's - the class is the release's - so this mutation follows the file that owns the
    # list, and its "did not apply" guard is what said so when the filter became a category.
    "filterlist": ("""    return ((id (*)(id, SEL))objc_msgSend)(self, @selector(charon_storedIdentifiers));""",
                    "    return @[];"),
    # the group initializer's stored range, read by "~CONSTRUCTED group timeRange"
    "grouprange": ("_charonTimeRange = timeRange;", "_charonTimeRange = kCMTimeRangeZero;"),
    # -isEqual:, read by "~CONSTRUCTED group copy equals the original" and its body-object twin
    "copyeq": ("return [self.items isEqualToArray:that.items] && CMTimeRangeEqual(self.timeRange, that.timeRange);",
               "return YES;"),
    # the asynchronous handler, read by "~CONSTRUCTED value request the asynchronous load calls the handler"
    "handler": ("""    if (handler) {
        handler();
    }""", """    (void)handler;"""),
}
before, after = MUTATIONS[which]
if before not in text:
    raise SystemExit("the %s mutation did not apply, so this run proves nothing" % which)
open(path, "w").write(text.replace(before, after, 1))
print("# applied the %s mutation" % which)
PY
}

want=${AVFMUTANT:-}
control=${CONTROL:-0}
for f in $sources; do cp "$avf/$f.m" "$build/src/$f.m"; done
# A control perturbs NOTHING and writes NO baseline. The first version applied the mutation under
# CONTROL=1 as well, so the control was a second mutant (and red), and because a control wrote the
# baseline, the next mutant was judged against a mutated table and four of the five reported "the
# mutation changed nothing the check looks at" - a false report produced by the harness, not by the
# mutation. Both are fixed here: the case below is entered only for a real mutant, and only a run with
# no AVFMUTANT at all writes the baseline.
if [ "$control" = 0 ]; then
case "$want" in
    bodyinit)  mutate AVMetadataBodyObjects13 bodyinit ;;
    filterlist) mutate AVMetadataItemFilter7 filterlist ;;
    grouprange) mutate AVMetadataGroup9 grouprange ;;
    copyeq)    mutate AVMetadataGroup9 copyeq ;;
    handler)   mutate AVMetadataItemValueRequest9 handler ;;
    "")        ;;
    *)         echo "FAIL: no such mutant: $want"; exit 1 ;;
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
set +e; "$build/host" > "$build/host.table" 2> "$build/host.stderr"; host_status=$?; set -e

# 2. the same probe against the port's own classes
# shellcheck disable=SC2086
xcrun clang -fobjc-arc -w -I"$avf" $renames "$here/objects.m" $objects \
    -framework Foundation -framework AVFoundation -framework CoreMedia \
    -o "$build/port" > "$build/port.log" 2>&1 || {
        echo "FAIL: the port probe did not build"; head -8 "$build/port.log"; exit 1; }
set +e; "$build/port" > "$build/port.table" 2> "$build/port.stderr"; port_status=$?; set -e

# 3. the baseline. Written on an unmutated run and read by a mutant run, so the comparison is
#    "against what the port answered before", not against the host - which is the whole point.
if [ -z "$want" ]; then
    mkdir -p "$baseline_dir"
    cp "$build/port.table" "$baseline_dir/port.baseline"
    cp "$build/host.table" "$baseline_dir/host.baseline"
else
    [ -f "$baseline_dir/port.baseline" ] || {
        echo "FAIL: the mutant was asked for with no baseline beside it. Run this script once with no"
        echo "      AVFMUTANT first: a mutant is judged against what the port answered unmutated, and"
        echo "      a run that measured nothing is not a baseline."
        exit 1
    }
fi

# 4. the join and the verdict
set +e
python3 - "$build" "$baseline_dir" <<'PYEOF'
import sys, os
build, baseline_dir = sys.argv[1], sys.argv[2]

def load(path):
    rows = {}
    if not os.path.exists(path):
        return rows
    for line in open(path):
        if not line.strip():
            continue
        key, _, value = line.rstrip("\n").strip().partition(" | ")
        rows[key.strip()] = value.strip()
    return rows

host = load(os.path.join(build, "host.table"))
port = load(os.path.join(build, "port.table"))
base = load(os.path.join(baseline_dir, "port.baseline"))

# The differences that are in APPLE'S build and not in the port's. Each with the measurement.
ALLOWANCES = {
 "AVMetadataGroup -timeRange": "Apple's own AVMetadataGroup instance does not answer -timeRange on this build",
 "AVMetadataGroup -copyWithZone:": "Apple's own AVMetadataGroup instance does not answer -copyWithZone: on this build",
 "DEFAULTS AVMetadataGroup -copyWithZone: is a different object": "follows from the row above: Apple's instance cannot be copied",
 "timeRange": "the property is declared on AVTimedMetadataGroup, not on AVMetadataGroup",
 "AVMetadataItemFilter -identifiers": "the 7.0 spelling is absent from this build; the port carries it, the host does not",
 "DEFAULTS AVMetadataItemFilter after -init -identifiers": "the 7.0 spelling: absent on the host, an empty list on the port",
 "DEFAULTS AVMetadataItemFilter after -init -allowList": "an empty allow list is what a filter with no identifiers answers; the host answers nil for a shared filter",
 "DEFAULTS AVDateRangeMetadataGroup after -init -startDate": "Apple answers the current date for a group with no range; the port answers the documented nil",
 "AVMetadataItem +metadataItemWithPropertiesOfMetadataItem: answers a mutable item": "Apple wraps the item in AVLazyValueLoadingMetadataItem; the port makes a plain mutable one",
 "AVMetadataItem +metadataItemWithPropertiesOfMetadataItem: ran the handler": "Apple defers the handler into a lazy wrapper; the port calls it",
 "AVMetadataItem filter(shared filter) over nil": "Apple answers an empty array here and nil from the identifier filter; both measured",
 "AVMetadataItemValueRequest -metadataItem DEFAULTS after -init": "declared, and calling it on an unbacked host instance crashes, so there is no value to compare",
 "AVMetadataItemValueRequest -respondWithValue: DEFAULTS after -init": "declared, and calling it on an unbacked host instance crashes",
 "AVMetadataItemValueRequest -respondWithError: DEFAULTS after -init": "declared, and calling it on an unbacked host instance crashes",
 "AVMetadataItemValueRequest -loadValuesAsynchronouslyForKeys:completionHandler:": "absent from this build; the header the port compiles against declares it",
}
# The members the header declares on a concrete body class and an instance of this build does not
# answer. Twenty-five rows, one reason.
for cls in ("AVMetadataBodyObject", "AVMetadataCatBodyObject", "AVMetadataDogBodyObject",
            "AVMetadataHumanBodyObject", "AVMetadataSalientObject"):
    for member in ("-faceID", "-hasRollAngle", "-rollAngle", "-hasYawAngle", "-yawAngle"):
        ALLOWANCES["%s %s" % (cls, member)] = ("declared on the header's concrete class, not answered by an "
                                                "instance on this build")
    for member in ("DEFAULTS faceID", "DEFAULTS rollAngle", "DEFAULTS yawAngle"):
        ALLOWANCES["%s %s" % (cls, member)] = "the host's instance does not answer the member this row reads"

less = more = differs = 0
unexplained = []
for key in sorted(set(host) | set(port)):
    if key.startswith("~"):
        # port-only: held against the baseline, not against the host
        if key not in port:
            print("PORT-ONLY MISSING  %s" % key); less += 1
        continue
    if key not in port:
        print("ANSWERS LESS       %s" % key); less += 1
    elif key not in host:
        print("HOST LACKS IT      %s" % key); more += 1
    elif host[key] != port[key]:
        differs += 1
        if key in ALLOWANCES:
            print("ALLOWED            %-58s %s" % (key, ALLOWANCES[key]))
        else:
            print("UNEXPLAINED        %-58s host=[%s] port=[%s]" % (key, host[key], port[key]))
            unexplained.append(key)
print("SUMMARY must-match rows: host=%d port=%d  answers-less=%d host-lacks=%d unexplained=%d"
      % (len([k for k in host if not k.startswith("~")]), len([k for k in port if not k.startswith("~")]),
         less, more, len(unexplained)))
print("SUMMARY port-only rows: port=%d baseline=%d" % (len([k for k in port if k.startswith("~")]),
                                                       len([k for k in base if k.startswith("~")])))
sys.exit(1 if (less or unexplained) else 0)
PYEOF
join_status=$?
set -e

# 5. the directionality assertion, and the control
if [ -n "$want" ] && [ "$control" = 0 ]; then
    changed=$(python3 - "$build" "$baseline_dir" <<'PYEOF'
import sys, os
build, baseline_dir = sys.argv[1], sys.argv[2]
def load(name):
    rows = {}
    for line in open(os.path.join(build, name)):
        if not line.strip():
            continue
        key, _, value = line.rstrip("\n").strip().partition(" | ")
        rows[key.strip()] = value.strip()
    return rows
base, port, host = (load(os.path.join(baseline_dir, "port.baseline")), load(os.path.join(build, "port.table")),
                       load(os.path.join(build, "host.table")))
changed, right_then_wrong, closer = [], [], []
for key in set(base) | set(port):
    if base.get(key) == port.get(key):
        continue
    changed.append(key)
    if key.startswith("~"):
        right_then_wrong.append(key)
    elif key in host and base.get(key) == host[key] and port.get(key) != host[key]:
        right_then_wrong.append(key)
    elif key in host and base.get(key) != host[key] and port.get(key) == host[key]:
        closer.append(key)
for key in sorted(changed):
    print("CHANGED            %-58s before=[%s] after=[%s]" % (key, base.get(key), port.get(key)))
for key in sorted(right_then_wrong):
    print("BROKE A RIGHT ONE   %s" % key)
for key in sorted(closer):
    print("MOVED TOWARD HOST   %s" % key)
print("DIRECTIONALITY changed=%d right-then-wrong=%d moved-toward-host=%d"
      % (len(changed), len(right_then_wrong), len(closer)))
sys.exit(0 if (changed and right_then_wrong and not closer) else 1)
PYEOF
)
    dir_status=$?
    set -e
    set -e
    if [ "$dir_status" != 0 ]; then
        echo "FAIL: the $want mutation was NOT noticed in the required direction: it did not turn a"
        echo "      right answer wrong, or it moved the port TOWARD the host, which is the failure the"
        echo "      filterNil mutant of the last round showed and this assertion exists for."
        echo "$changed"
        exit 1
    fi
    if [ "$join_status" = 0 ]; then
        # Not a failure. A mutation that breaks only a ~ port-only row is noticed by the directionality
        # check and leaves the host-versus-port join green, which is what a port-only row IS: there is
        # no Apple answer to it to disagree with. Saying so is the point - an earlier version demanded
        # a red join as well and so three of the five mutants could never be noticed at all.
        echo "ok  the $want mutation was noticed, turned a right answer wrong; the host join stayed green"
        echo "    because what it broke is a port-only row, which has no Apple answer to disagree with"
    else
        echo "ok  the $want mutation was noticed, turned a right answer wrong, and the join went red:"
    fi
    echo "$changed" | grep -E '^(CHANGED|BROKE|MOVED)' | head -8
    echo "DIRECTIONALITY $(echo "$changed" | tail -1)"
    echo "log=$build"
    exit 0
fi

if [ -n "$want" ] && [ "$control" != 0 ]; then
    if [ "$join_status" != 0 ]; then
        echo "FAIL: the $want control is not green. The control runs the UNMUTATED source through the"
        echo "      identical build-and-run path, so a red here is the path, not the mutation."
        exit 1
    fi
    echo "ok  the $want control is green: the unmutated source through the same path"
    echo "log=$build"
    exit 0
fi

if [ "$join_status" != 0 ]; then
    echo "FAIL: the differential is not green"
    exit 1
fi
echo "ok  every row the host answers is answered by the port, and nothing differs without a measured reason"
echo "log=$build"
