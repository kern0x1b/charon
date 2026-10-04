#!/bin/sh
# The host's Matter.framework and the port's own plain data classes, over the same driver, compared.
#
# ONE program runs on both sides - tests/backports/host/matter/params-probe.m - because it takes its class
# names, its member names and its alias pairs from the driver file and reads nothing at compile time, so the
# only difference between the two outputs is behaviour.
#
#   host side   xcrun clang ... -framework Matter, against /System/Library/Frameworks/Matter.framework
#   port side   the port's own objects, regenerated for THIS host with the generator's own rule applied to
#               the host's SDK as the target: --sdk26.2 --sdk16 <the host SDK> declares what THAT SDK does
#               not declare, which is the same rule the shipped tree applies to iPhoneOS16.4. The bodies are
#               the same generator's output; only the declarations differ, and only because the target does.
#
# A RED CONTROL is not optional: the comparison is run again against a copy of one port object with one
# value changed, and the run must FAIL on it. A check that has never been seen to fail examines nothing.
#
#   sh tests/backports/host/matter/params-diff.sh
#
# The SDKs come from the same places the package and relcheck take them, and the script STOPS when it cannot
# find one: a check that quietly falls back to nothing reports green without having looked at anything.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
build=${MATTER_PARAMS_DIFF_BUILD:-$root/.agent-work/runs/params-diff}

# The library SDK: the pin the package's xmake.lua records, then the SDK store, then the machine's. The first
# one that exists wins and the script says which, because "it worked" and "it found an SDK" are different
# facts and a run has to say which one happened.
sdk16=""
for candidate in \
    "${MATTER_SDK_LIBRARY:-}" \
    "$HOME/.xmake/packages/i/iphoneos-sdk/16.4"/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk
do
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
        sdk16="$candidate"
        break
    fi
done
if [ -z "$sdk16" ]; then
    echo "params-diff: no iPhoneOS 16.4 SDK. Put MATTER_SDK_LIBRARY=<path> in the environment, or install" >&2
    echo "  the package's SDK pin; nothing is compared against nothing here." >&2
    exit 2
fi
# The SDK the PORT's declarations are read from, the one tools/matter-generate.py reads. The workspace keeps
# it at charon/.agent-work/sdk-26.2/iPhoneOS26.2.sdk (coordination/api-worker-brief.md), and a worktree has no
# .agent-work of its own for it, so the environment names it and the script says which one it used.
sdk26=""
for candidate in \
    "${MATTER_SDK_262:-}" \
    "$root/.agent-work/sdk-26.2/iPhoneOS26.2.sdk" \
    "$root/.agent-work/sdk262"
do
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
        sdk26=$(cd "$candidate" && pwd)
        break
    fi
done
if [ -z "$sdk26" ]; then
    echo "params-diff: no iPhoneOS 26.2 SDK. Put MATTER_SDK_262=<path> in the environment, or put the tree's" >&2
    echo "  own SDK at $root/.agent-work/sdk-26.2/iPhoneOS26.2.sdk - it is what the port's declarations are" >&2
    echo "  read from, and nothing here is measured against nothing." >&2
    exit 2
fi
host_sdk=$(xcrun --show-sdk-path)
[ -d "$host_sdk/System/Library/Frameworks/Matter.framework" ] || {
    echo "params-diff: this host has no Matter.framework, so there is nothing to compare the port against." >&2
    exit 2; }
echo "params-diff: library SDK $sdk16"
echo "params-diff: port SDK    $sdk26"
echo "params-diff: host SDK    $host_sdk  (Matter.framework $(defaults read "$host_sdk/System/Library/Frameworks/Matter.framework/Resources/Info" CFBundleShortVersionString 2>/dev/null || echo unknown))"

rm -rf "$build"
mkdir -p "$build/host" "$build/port" "$build/port-mutant" "$build/port-nested" "$build/port-name" \
    "$build/port-storage" "$build/objects" "$build/objects-mutant" "$build/objects-nested" \
    "$build/objects-name" "$build/objects-storage"

# The driver: written by the generator, from the same buckets it emits from.
cp "$root/packages/a/apple-backports/Matter/clusters-emitted.txt" "$build/port/clusters-emitted.txt"
python3 "$root/tools/matter-generate.py" --sdk "$sdk26" --out "$build/port" \
    --contracts "$build/port-contracts" --sdk16 "$sdk16" --shared-types --params \
    --cases "$build/cases.tsv" > "$build/cases.log" 2>&1
echo "params-diff: driver $(grep -c . "$build/cases.tsv") lines, $(grep -c alias "$build/cases.tsv" || true) alias pairs"

xcrun clang -fobjc-arc -Wall -o "$build/host/probe" "$here/params-probe.m" \
    -framework Foundation -framework Matter
"$build/host/probe" "$build/cases.tsv" > "$build/host.tsv"

# The port side, out of the generator's own objects for THIS host, compiled one at a time and linked once -
# 1067 sources through one clang invocation does not finish in a useful time.
# The SAME measurement file the shipped tree is generated with, and the reason is not tidiness: without it
# the generator writes no -description and no alias conversion, because it cannot know what the host does,
# and the comparison then measures the absence of the argument rather than the port. That is what the first
# run of this script did: 66 of 918 on ownDescription, which is exactly the count of classes that do NOT
# override it.
python3 "$root/tools/matter-generate.py" --sdk "$sdk26" --out "$build/port" \
    --contracts "$build/port-contracts" --sdk16 "$host_sdk" --shared-types --params \
    --host-measurements "$here/host-measurements.tsv" \
    > "$build/port-generate.log" 2>&1
echo "params-diff: $(grep -c 'every object compiles' "$build/port-generate.log") compile-check line(s) in the generator log"
# One compile per source directory, and the DIRECTORY IS AN ARGUMENT: the three red controls below each
# plant into a copy of the port's own sources, and a compile that reached for $build/port whatever it was
# given compiled the pristine tree - so the control measured nothing and the run said the control had
# failed. That is what the first run of this script did, and the message it printed named a mutation the
# binary did not carry.
compile() {
    from=$1; into=$2
    logs="$into.logs"
    rm -rf "$logs"
    mkdir -p "$logs"
    # One log per object, and the errors read out of them afterwards. Four compiles writing into one pipe
    # interleave into unreadable lines - a run of this printed `...Fatal error: :'CharonMatterTypes.h' file
    # not found9` - and a check whose output cannot be read is a check nobody can act on.
    ls "$from"/*.m | xargs -P "${MATTER_DIFF_JOBS:-4}" -n 1 sh -c \
        'xcrun clang -fobjc-arc -O0 -I'"$from"' -c "$0" -o "'"$into"'/$(basename "$0" .m).o" \
         2> "'"$logs"'/$(basename "$0" .m).log" || true'
    grep -h ' error: ' "$logs"/*.log 2>/dev/null | sort -u | head -10 || true
    # `set -e` and a pipeline whose last command found nothing is a non-zero status, so the count of objects
    # written is the verdict. A check that exits on "no errors found" is a check that only ever fails.
    written=$(ls "$into" | wc -l | tr -d ' ')
    if [ "$written" -lt "$(ls "$from"/*.m | wc -l | tr -d ' ')" ]; then
        echo "params-diff: only $written objects of $(ls "$from"/*.m | wc -l | tr -d ' ') compiled from $from" >&2
        head -3 "$logs"/*.log >&2
        return 1
    fi
    return 0
}
# A plant is a complete copy of the port's own sources, the types header beside them: an object that imports
# `CharonMatterTypes.h` and cannot find it compiles nothing, which is how the first run of this script's red
# control answered - 0 objects of 1068, and a message about a header rather than about the mutation.
copy_port() {
    mkdir -p "$1"
    cp "$build/port"/*.m "$build/port"/*.h "$1"/
}
# A mutation that did not apply is not a survivor, and a script that cannot tell the two apart will one day
# report a green run as a green plant: every plant below is compared with the file it was made from, and the
# run stops when a plant is byte-identical to the original.
planted() {
    if cmp -s "$2" "$1"; then
        echo "params-diff: FAIL the red control - the mutation did not change $2, so it would prove" >&2
        echo "  nothing and a green run would be a green mutant" >&2
        exit 1
    fi
    echo "params-diff: red control $(basename "$2") differs from the port's own file, so it is applied"
}
compile "$build/port" "$build/objects"
xcrun clang -o "$build/port/probe" "$build/objects"/*.o "$here/params-probe.m" -framework Foundation
"$build/port/probe" "$build/cases.tsv" > "$build/port.tsv"

# `description` and `fresh` are PREDICTED, not compared: the host's Matter.framework is built from a later
# SDK than the port implements, so it renames members and reorders them, and a difference the two SDKs'
# DECLARATIONS account for is a difference between two releases. predict.py lays the port's own values out in
# the host SDK's declaration order and set, read from that SDK's headers with the generator's own reader,
# and reports what is identical, what is predicted by a declaration difference, and what is UNEXPLAINED. The
# last must be zero, and that is the gate this comparison exists for.
MATTER_SDK_262="$sdk26" python3 "$here/predict.py" "$host_sdk" "$build/host.tsv" "$build/port.tsv" | tee "$build/predicted.txt"
grep -q ' 0 unexplained' "$build/predicted.txt" || status=1

present=$(awk -F'\t' '$1=="present" && $4=="present"' "$build/host.tsv" | wc -l | tr -d ' ')
absent=$(awk -F'\t' '$1=="present" && $4=="absent"' "$build/host.tsv" | wc -l | tr -d ' ')
raised=$(awk -F'\t' '$1=="raised"' "$build/host.tsv" | wc -l | tr -d ' ')
printf 'params-diff: classes the host has %s, absent %s, raised %s\n' "$present" "$absent" "$raised"

status=0
for question in ownDescription alias storage; do
    awk -F'\t' -v q="$question" '$1==q' "$build/host.tsv" | sort > "$build/host.$question"
    awk -F'\t' -v q="$question" '$1==q' "$build/port.tsv" | sort > "$build/port.$question"
    host_n=$(wc -l < "$build/host.$question" | tr -d ' ')
    same=$(comm -12 "$build/host.$question" "$build/port.$question" | wc -l | tr -d ' ')
    printf 'params-diff: %-14s %s of the hosts %s readings the port answers identically\n' \
        "$question" "$same" "$host_n"
    [ "$same" = "$host_n" ] || status=1
done

# The RED CONTROL: one value in one port object changed, and the comparison must notice.
copy_port "$build/port-mutant"
victim="$build/port-mutant/CharonMatterMTRGroupsClusterAddGroupParams.m"
sed -i '' 's/_groupID = @0;/_groupID = @7;/' "$victim"
planted "$build/port/CharonMatterMTRGroupsClusterAddGroupParams.m" "$victim"
compile "$build/port-mutant" "$build/objects-mutant"
xcrun clang -o "$build/port/probe-mutant" "$build/objects-mutant"/*.o "$here/params-probe.m" -framework Foundation
"$build/port/probe-mutant" "$build/cases.tsv" > "$build/port-mutant.tsv"
awk -F'\t' '$1=="fresh" || $1=="description"' "$build/port.tsv" | sort > "$build/port.mutated-bytes"
awk -F'\t' '$1=="fresh" || $1=="description"' "$build/port-mutant.tsv" | sort > "$build/port.mutant-bytes"
moved=$(comm -13 "$build/port.mutated-bytes" "$build/port.mutant-bytes" | wc -l | tr -d ' ')
if [ "$moved" -lt 1 ]; then
    echo "params-diff: FAIL the red control - a port object with _groupID = @7 reads the same as the original" >&2
    exit 1
fi
printf 'params-diff: red control %s readings move, so this comparison can fail\n' "$moved"
# and it must move the PREDICTION too, or the prediction is not looking at the port's values at all
# `|| true` and the reason: predict.py EXITS NON-ZERO when a reading is unexplained, which is what a
# mutant is supposed to produce, and under `set -e` that ended the run right here - which is why the first
# run of this script stopped after its first red control and reported nothing about it.
MATTER_SDK_262="$sdk26" python3 "$here/predict.py" "$host_sdk" "$build/host.tsv" "$build/port-mutant.tsv" \
    > "$build/predicted-mutant.txt" || true
moved_predicted=$(grep -c 'UNEXPLAINED' "$build/predicted-mutant.txt" || true)
if [ "$moved_predicted" -lt 1 ]; then
    echo "params-diff: FAIL the red control - mutating a port value did not move the prediction, so the" >&2
    echo "  prediction is not reading the port's values and would pass on anything." >&2
    exit 1
fi
printf 'params-diff: red control %s readings become UNEXPLAINED, so the prediction looks at the port\n' \
    "$moved_predicted"

# The SECOND red control, and it is the one that matters for a recursive rule: a NESTED member planted in
# the port only. A rule that excuses every difference it can walk into would swallow this, so it has to come
# back out as a NAMED reading - either predicted with the member named, or unexplained - and never as silence.
# MTRUnitTestingClusterSimpleStruct is the class to plant in: the host's SDK declares it and so does the
# port's, so the planted member is not a version difference and cannot be excused as one.
copy_port "$build/port-nested"
nested="$build/port-nested/CharonMatterMTRUnitTestingClusterSimpleStruct.m"
python3 - "$nested" <<'PYTHON'
import sys
path = sys.argv[1]
plant = "plantedByTheRedControl"
text = open(path).read()
edits = [
    ("@implementation MTRUnitTestingClusterSimpleStruct\n",
     "@interface MTRUnitTestingClusterSimpleStruct ()\n"
     "@property (nonatomic, copy) NSNumber *%s;\n@end\n\n"
     "@implementation MTRUnitTestingClusterSimpleStruct\n\n"
     "@synthesize %s = _%s;\n" % (plant, plant, plant)),
    ('    [text appendString:@">"];',
     '    [text appendFormat:@"%s:%%@; ", self.%s];\n'
     '    [text appendString:@">"];' % (plant, plant)),
]
# Every needle is asserted before it is replaced and every plant is counted after: str.replace on a missing
# needle is a silent no-op, and a "planted" run over an unplanted file then reports a mutant as applied. The
# count is a DELTA and not a total, because `@synthesize x = _x;` carries the name twice.
for needle, replacement in edits:
    where = text.count(needle)
    assert where == 1, "the needle %r occurs %d times in %s, not once" % (needle, where, path)
    before = text.count(plant)
    text = text.replace(needle, replacement, 1)
    assert text.count(plant) > before, "the plant did not land at %r" % needle
open(path, "w").write(text)
PYTHON
planted "$build/port/CharonMatterMTRUnitTestingClusterSimpleStruct.m" "$nested"
compile "$build/port-nested" "$build/objects-nested"
xcrun clang -o "$build/port/probe-nested" "$build/objects-nested"/*.o "$here/params-probe.m" -framework Foundation
"$build/port/probe-nested" "$build/cases.tsv" > "$build/port-nested.tsv"
MATTER_SDK_262="$sdk26" python3 "$here/predict.py" "$host_sdk" "$build/host.tsv" "$build/port-nested.tsv" \
    > "$build/predicted-nested.txt" || true
planted_readings=$(grep -c 'plantedByTheRedControl' "$build/predicted-nested.txt" || true)
if [ "$planted_readings" -lt 1 ]; then
    echo "params-diff: FAIL the nested red control - a member planted inside a port struct was not named" >&2
    echo "  anywhere, so a recursive rule that walks into values can swallow a difference silently." >&2
    exit 1
fi
printf 'params-diff: nested red control %s reading(s) name plantedByTheRedControl, so a planted nested\n' \
    "$planted_readings"
printf 'params-diff:   member is reported and not excused\n'

# The THIRD red control, and it is the one that holds the class-name clause of the rule down. The predictor
# excuses a differing class name exactly when one of the two is the deprecated spelling of the other - 120
# such pairs, each read out of the deprecated class's own `MTR_DEPRECATED("Please use X")` - so BOTH halves
# of that have to be shown: a name no annotation pairs has to come out UNEXPLAINED, and a name that IS in a
# pair has to come out predicted WITH THE PAIR NAMED. One plant of each, in one binary, because a rule that
# excuses everything and a rule that excuses nothing are both wrong and only the pair of them is a check.
#
#   MTRUnitTestingClusterNestedStruct      planted with MTRTestClusterClusterNestedStruct, which is its own
#                                         deprecated spelling: predicted, and the pair named
#   MTRUnitTestingClusterNestedStructList  planted with MTRDataTypeViewportStruct, which no annotation
#                                         pairs with anything: unexplained
#
# The first of those two is the reading the port used to get wrong, before its -init stored the class the
# framework's own -init stores (MTRStructsObjc.mm:14623); the second is a name nothing relates to it.
copy_port "$build/port-name"
python3 - "$build/port-name" <<'PYTHON'
import os, sys
where = sys.argv[1]
planted = {
    # (file, the class its own description should print instead, why)
    ("CharonMatterMTRUnitTestingClusterNestedStruct.m", "MTRTestClusterClusterNestedStruct",
     "the deprecated spelling of that same class, which MTR_DEPRECATED pairs it with"),
    ("CharonMatterMTRUnitTestingClusterNestedStructList.m", "MTRDataTypeViewportStruct",
     "a class no annotation pairs it with"),
}
needle = "NSStringFromClass([self class])"
for name, planted_as, why in planted:
    path = os.path.join(where, name)
    text = open(path).read()
    where_ = text.count(needle)
    assert where_ == 1, "the class-name plant found %d call sites in %s, not one" % (where_, path)
    text = text.replace(needle, '@"%s"' % planted_as, 1)
    assert text.count(planted_as) >= 1, "the plant did not land in %s" % path
    open(path, "w").write(text)
    print("planted %s -> %s, %s" % (name, planted_as, why))
PYTHON
planted "$build/port/CharonMatterMTRUnitTestingClusterNestedStruct.m" \
    "$build/port-name/CharonMatterMTRUnitTestingClusterNestedStruct.m"
planted "$build/port/CharonMatterMTRUnitTestingClusterNestedStructList.m" \
    "$build/port-name/CharonMatterMTRUnitTestingClusterNestedStructList.m"
compile "$build/port-name" "$build/objects-name"
xcrun clang -o "$build/port/probe-name" "$build/objects-name"/*.o "$here/params-probe.m" -framework Foundation
"$build/port/probe-name" "$build/cases.tsv" > "$build/port-name.tsv"
MATTER_SDK_262="$sdk26" python3 "$here/predict.py" "$host_sdk" "$build/host.tsv" "$build/port-name.tsv" \
    > "$build/predicted-name.txt" || true
# The grep is on the PLANTED NAME inside an unexplained line, not on classify()'s wording: the reading of a
# member whose value is a struct holding an NSArray ends mid-string on both sides (a field cannot hold the
# newline an empty array's -description carries), so classify() has no level to read and says "a value
# difference" rather than naming the class. The name in the port's half is what makes it this plant's.
name_unexplained=$(grep -c 'UNEXPLAINED.*MTRDataTypeViewportStruct' "$build/predicted-name.txt" || true)
if [ "$name_unexplained" -lt 1 ]; then
    echo "params-diff: FAIL the class-name red control - MTRDataTypeViewportStruct is in no deprecation" >&2
    echo "  pair and came out predicted or identical, so the predictor would excuse any name a port" >&2
    echo "  printed. What it said instead:" >&2
    grep -m3 "MTRUnitTestingClusterNestedStructList" "$build/predicted-name.txt" >&2
    exit 1
fi
name_predicted=$(grep -c "the class inside is the port.s MTRTestClusterClusterNestedStruct" \
    "$build/predicted-name.txt" || true)
if [ "$name_predicted" -lt 1 ]; then
    echo "params-diff: FAIL the class-name red control - the DEPRECATED spelling of the very class" >&2
    echo "  MTR_DEPRECATED pairs did not come out predicted, so the rule does not excuse a spelling it" >&2
    echo "  should excuse and the rule above is not that rule." >&2
    exit 1
fi
# And the port's OWN reading must have nothing to classify here, or the clause is being tested against a
# port that already disagrees with the host.
grep -q ' 0 unexplained' "$build/predicted.txt" || {
    echo "params-diff: FAIL - the port's own reading has unexplained rows, so the class-name clause is" >&2
    echo "  being tested against a port that does not agree with the host in the first place." >&2
    exit 1; }
printf 'params-diff: class-name red control %s reading(s) name an unpaired class as UNEXPLAINED, and %s\n' \
    "$name_unexplained" "$name_predicted"
printf 'params-diff:   reading(s) name a PAIRED one as predicted, so the clause excuses the spelling and\n'
printf 'params-diff:   nothing else, and the reading of the unmutated port is 0 unexplained either way\n'
# The FOURTH red control, and it is the one that holds the ALIAS STORAGE shape down. 60 of the port's classes
# are a deprecated spelling of another one, and the framework's own @implementation for a class shaped that
# way is `@dynamic` and nothing else - no ivar, no accessor, no -init - so the two names share ONE storage. A
# port that synthesises an ivar per member has TWO, which no value read can see on its own because Objective-C
# dispatch walks up from the RECEIVER's class and never from the static type of the variable: writing a member
# through an alias reference and reading it through a current one answers the same either way. So the plant
# gives one alias object its storage back - the class extension with an ivar per member and `@synthesize` in
# place of `@dynamic`, which is exactly what the port emitted before - and the run requires the `storage`
# comparison above to FAIL on it.
#
#   MTRTestClusterClusterSimpleStruct  8 members, none of them declared by MTRUnitTestingClusterSimpleStruct's
#                                      own list in the alias's object, so the plant is 8 ivars and 8
#                                      `@synthesize` lines and nothing else changes.
copy_port "$build/port-storage"
python3 - "$build/port-storage" "$host_sdk" <<'PYTHON'
import os, re, sys
where, sdk = sys.argv[1], sys.argv[2]
name = "MTRTestClusterClusterSimpleStruct"
path = os.path.join(where, "CharonMatter%s.m" % name)
text = open(path).read()
members = re.findall(r"^@dynamic (\w+);$", text, re.M)
assert members, "the plant found no @dynamic line in %s, so there is no storage to give back" % path
# The ivar types come from the header the objects compile AGAINST - the host SDK's own Matter headers, which
# is where the declarations in scope for this binary live. Not from the port's CharonMatterTypes.h: that file
# carries a class extension only for the properties the target SDK does not declare, and the host SDK
# declares all eight of this class's, so the extension this plant would have read does not exist.
headers = os.path.join(sdk, "System/Library/Frameworks/Matter.framework/Headers")
types, blocks = {}, 0
for header in sorted(os.listdir(headers)):
    if not header.endswith(".h"):
        continue
    body = open(os.path.join(headers, header), errors="replace").read()
    for found in re.finditer(r"@interface %s\b(.*?)@end" % re.escape(name), body, re.S):
        blocks += 1
        for line in found.group(1).splitlines():
            declared = re.match(r"\s*@property\s*\(([^)]*)\)\s*(.+);", line.strip())
            if declared:
                # The declaration's OWN annotation comes off before the name is read off the end of it:
                # `@property (nonatomic, copy) NSNumber * _Nonnull a MTR_DEPRECATED("Please use X", ios(...));`
                # ends in the annotation, not in the name, and a reader that split the whole line read the
                # last token of `ios(16.1, 16.4), ...` as the member's name and placed none of the eight.
                words = re.split(r"\s+(?:MTR_|API_)(?:DEPRECATED|AVAILABLE|PROVISIONALLY_AVAILABLE)\b",
                                 declared.group(2))[0].split()
                # Every header that declares the class, not the first one found: MTRBackwardsCompatShims.h
                # declares deprecated subclasses of clusters and sorts before MTRStructsObjc.h, so a reader
                # that stopped at the first match found a block with no properties in it and reported that
                # the type of all eight members is missing.
                types.setdefault(words[-1], " ".join(words[:-1]))
assert blocks, "no Matter header of %s declares %s" % (sdk, name)
missing = [each for each in members if each not in types]
assert not missing, "the header declares no type for %s" % ", ".join(missing)
extension = ("\n// The plant: the storage this object must NOT hold, one ivar per member, so that the\n"
             "// run's `storage` comparison has something to fail on. Every ivar is `@synthesize`d in place\n"
             "// of the `@dynamic` line that was there, which is what the port emitted before this shape.\n"
             "@interface %s () {\n" % name)
for each in members:
    extension += "    %s _%s;\n" % (types[each], each)
extension += "}\n@end\n\n@implementation %s\n\n" % name
needle = "@implementation %s\n" % name
assert text.count(needle) == 1, "the @implementation line occurs %d times in %s" % (text.count(needle), path)
text = text.replace(needle, extension, 1)
for each in members:
    line = "@dynamic %s;" % each
    assert text.count(line) == 1, "the @dynamic line for %s occurs %d times in %s" % (each, text.count(line), path)
    text = text.replace(line, "@synthesize %s = _%s;" % (each, each), 1)
open(path, "w").write(text)
print("planted %d member(s) of storage back into CharonMatter%s.m, ivar types read out of the host SDK"
      % (len(members), name))
PYTHON
planted "$build/port/CharonMatterMTRTestClusterClusterSimpleStruct.m" \
    "$build/port-storage/CharonMatterMTRTestClusterClusterSimpleStruct.m"
compile "$build/port-storage" "$build/objects-storage"
xcrun clang -o "$build/port/probe-storage" "$build/objects-storage"/*.o "$here/params-probe.m" -framework Foundation
"$build/port/probe-storage" "$build/cases.tsv" > "$build/port-storage.tsv"
awk -F'\t' '$1=="storage"' "$build/port.tsv" | sort > "$build/port.storage"
awk -F'\t' '$1=="storage"' "$build/port-storage.tsv" | sort > "$build/port-storage.storage"
moved_storage=$(comm -13 "$build/port.storage" "$build/port-storage.storage" | wc -l | tr -d ' ')
if [ "$moved_storage" -lt 1 ]; then
    echo "params-diff: FAIL the alias-storage red control - a port object given an ivar per member reads the" >&2
    echo "  same as the one that holds none, so this comparison cannot see two storages where the" >&2
    echo "  framework has one and the rule that would keep them is not being held down." >&2
    echo "  What it said instead:" >&2
    head -2 "$build/port.storage" >&2
    exit 1
fi
# And the plant must move the SHAPE, not only the values: a comparison that only noticed the values would
# also pass on a port that held one ivar per member and read it back correctly.
moved_shape=$(comm -13 "$build/port.storage" "$build/port-storage.storage" | grep -c 'ownIvars=' || true)
if [ "$moved_shape" -lt 1 ]; then
    echo "params-diff: FAIL the alias-storage red control - giving the object its storage back did not move" >&2
    echo "  any ownIvars=, so nothing here reads the shape the runtime reports." >&2
    exit 1
fi
printf 'params-diff: alias-storage red control %s reading(s) move and %s of them name ownIvars=, so one\n' \
    "$moved_storage" "$moved_shape"
printf 'params-diff:   storage for a deprecated alias class is something this comparison can see failing\n'

echo "params-diff: outputs under $build"
exit $status
