#!/bin/sh
# THE RED CONTROL for the contentunavailable group: the comparison must GO RED when the port answers a
# value the system does not, and must be GREEN on the unplanted source.
#
# WHY THIS GROUP NEEDS ONE MORE THAN THE OTHERS.  The group is built for arm64-apple-ios15.0-macabi,
# where the four iOS 17.0 classes do not exist in the system UIKit at all.  So there IS a system side -
# the test holds UIContentUnavailableTextProperties and friends under their own names and builds the
# port's objects beside them with prefixed selectors - but the class EXISTENCE is carried by the test's
# own @interface declarations rather than by the SDK.  That is a weaker position than a group whose
# system side comes out of a framework, and the review is right that a check which has only ever seen its
# own clean output has not been shown to fail.  So the plant below makes the port answer something the
# system does not and proves the run says so, by NAME.
#
# The plants are made in a SCRATCH COPY of the port source, never in the tree: UIKIT2_SOURCES already
# overrides where the group reads its sources from, so the control points that variable at a copy and
# runs the real run.sh unchanged.  The control asserts the real source is untouched afterwards, so a
# control that forgot to copy could not pass by editing the repository.
#
# What this proves and what it does not: it proves the comparison RESPONDS to a wrong value on a key
# that agrees today, and it names that key.  It does not prove the harness builds the group at all - a
# group that fails to build is a different failure and the run says so in its own words.
#
# Exit 0 when the plant went red and the unplanted source is green.  Exit 1 when the plant stayed green,
# because a control that cannot fail is not a control.  Exit 2 when the unplanted run is already red,
# because then the plant proves nothing and the first thing to fix is the group itself.
set -eu

root=$(cd "$(dirname "$0")/../../../.." && pwd)
here="$root/tests/backports/host/uikit2"
build="$root/.agent-work/runs/uikit2-red-control"
scratch="$build/sources"
source_file="UIContentUnavailableProperties.m"
logdir="$build/logs"

fail() { echo "RED CONTROL FAILED: $1" >&2; exit 1; }

rm -rf "$build"
mkdir -p "$scratch" "$logdir"

# The plant is on the line count of a FRESH text bag.  It is a key the test asserts on ("a fresh text bag
# holds the same line count") and it is a VALUE, so the group still builds and still links: a plant that
# broke the build would prove the compiler works, not that the comparison works.
#
# The anchor is the ivar's default in -init, which is where a fresh bag's line count is decided.  It is
# _numberOfLines = 0 and NOT `return 0`, because numberOfLines is a synthesised PROPERTY over an ivar -
# there is no getter to edit, and an earlier version of this control matched on "return" and silently
# planted nothing, which the file-unchanged assertion caught.  A control that cannot tell a no-op plant
# from a real one is a control that will one day report a green run as a green plant.
plant_value() {
    src=$1
    dst=$2
    awk '
        /_numberOfLines = 0;/ && !done {
            sub(/_numberOfLines = 0;/, "_numberOfLines = 99;")
            print
            print "        // RED CONTROL: a line count no fresh bag would have"
            done = 1
            next
        }
        { print }' "$src" > "$dst"
}

run_group() {
    label=$1
    sources=$2
    UIKIT2_SOURCES="$sources" UIKIT2_ONLY=contentunavailable \
        sh "$here/run.sh" > "$logdir/$label.txt" 2>&1 || true
}

# 1. GREEN on the real source.  This must pass BEFORE the plant means anything.
echo "== the unplanted group, which must be green"
run_group green "$root/packages/a/apple-backports/UIKit"
green_line=$(grep -E '^contentunavailable: exit=' "$logdir/green.txt" | tail -1 || true)
[ -n "$green_line" ] || { cat "$logdir/green.txt"; fail "the control could not find the group's own result line, so it cannot judge the plant"; }
echo "   $green_line"
case "$green_line" in
    *"exit=0"*) : ;;
    *) sed -n '1,40p' "$logdir/green.txt"; fail "the group is red BEFORE any plant, so a plant here would prove nothing" ;;
esac

# 2. The plant.  A copy of the whole sources directory is made first, so the group has every file it
# lists and only ONE of them differs.
echo "== planting a line count nothing keyed asked for, in a scratch copy"
mkdir -p "$scratch"
for f in "$root/packages/a/apple-backports/UIKit/"*.m "$root/packages/a/apple-backports/UIKit/"*.h; do
    [ -f "$f" ] && cp "$f" "$scratch/"
done
cp "$root/packages/a/apple-backports/UIKit/$source_file" "$build/source.before.m"
plant_value "$root/packages/a/apple-backports/UIKit/$source_file" "$scratch/$source_file"
cmp -s "$build/source.before.m" "$scratch/$source_file" && fail "the plant did not change the file, so it is not a plant"

# the tree must be untouched, and this asserts it rather than assuming it
cmp -s "$build/source.before.m" "$root/packages/a/apple-backports/UIKit/$source_file" \
    || fail "the plant edited the repository instead of the scratch copy"

echo "== the planted group, which must be RED and must NAME the key"
run_group red "$scratch"
red_line=$(grep -E '^contentunavailable: exit=' "$logdir/red.txt" | tail -1 || true)
[ -n "$red_line" ] || { sed -n '1,40p' "$logdir/red.txt"; fail "the planted run produced no result line"; }
echo "   $red_line"
# Only the PLANTED KEY is evidence, by its exact line.  main's own buttonconfig group carries an in-harness
# red control that runs alongside and prints its own FAILs, and a filter broad enough to pick those up
# would let this control pass on a failure it did not cause - which is the same mistake as planting on a
# key that was already red.
echo "   the lines the planted group printed:"
grep -E "^FAIL a fresh text bag holds the same line count" "$logdir/red.txt" | sed 's/^/     /' || true

case "$red_line" in
    *"exit=0"*) sed -n '1,40p' "$logdir/red.txt"; fail "the plant left the group GREEN - the comparison does not read this key" ;;
esac

# The point of naming the key: a red run that only says "exit=1" has not told anyone what disagrees.
if ! grep -qiE 'line count|numberOfLines' "$logdir/red.txt"; then
    fail "the group went red but never named the line-count key, so the failure is not attributable"
fi
echo "   the planted run names the line-count key, so the disagreement is attributable"

# 3. And the real source is still the real source.
cmp -s "$build/source.before.m" "$root/packages/a/apple-backports/UIKit/$source_file" \
    || fail "the run left the repository's source changed"

echo "RED CONTROL OK: green before, red after, naming the key, tree untouched"