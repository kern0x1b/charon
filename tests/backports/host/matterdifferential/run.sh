#!/bin/sh
# matterdifferential/run.sh - the port's Matter clusters against the system's, one class per run.
#
# The system has Matter.framework, so the check is two-sided and the comparison is a real one: the
# port's generated file is compiled for the host with the cluster's name aliased onto it, so ONE program
# holds both the system's class and the port's, and neither can answer for the other.
#
# Every cluster the generator wrote is built, and must build, except the ones on not-built.txt with a reason: those
# are counted as skipped, and a listed cluster that builds is stale. A check against a class that does not build is
# a check of nothing, so a cluster that does not build and is not listed fails the run.
#
# What is asked of each pair is in cases.m: that both classes exist, that the two member sets agree as
# SETS, and that a plain-data attribute round-trips on the port's side. No command, cached read,
# commissioning or network call is made on either side - those need a fabric and a node.
#
# Usage: MATTER_SDK_262=<iPhoneOS 26.2 SDK> sh tests/backports/host/matterdifferential/run.sh
#        BUILD=<dir>          where the programs and their output go
#        CLUSTER_LIST=<file>  the classes to check, one a line
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
build=${BUILD:-${TMPDIR:-/tmp}/charon-matter-differential}
objects=${MATTER_OBJECTS:-$root/.agent-work/runs/matter/objects}
# The list is of CLASS names, and they are read out of each compiled file's own @implementation line
# rather than out of the file's name: three files carry a collision suffix, and asking for
# MTRBaseClusterOtaSoftwareUpdateProvider_2 checked a class that does not exist and reported the port as
# MISSING, which is how three classes came to differ when nothing about them differs.
source_dir=${MATTER_SOURCE_DIR:-$root/packages/a/apple-backports/Matter}
port_file() {
    echo "$source_dir/CharonMatter$1.m"
}

excluded=$here/../matter/excluded.txt
# The contract is a TEST FIXTURE and lives with the tests. Reading it beside the object stopped working the
# day the fixtures moved, and the check did not say so: cases.m found no contract, every selector became
# port-only, and 137 clusters came back DIFFERENT.
contracts=${CONTRACTS:-$here/../matter/contracts}
# The clusters come from what the generator WROTE, beside it: <source_dir>/clusters-emitted.txt. A cluster
# list kept beside the check is how the check came to ask for MTRBaseClusterOtaSoftwareUpdateProvider, a
# cluster the generator refuses and the SDK declares a deprecated subclass of, resolve it through a
# case-insensitive volume to the runtime-spelled file, and report the port MISSING.
list=${CLUSTER_LIST:-$source_dir/clusters-emitted.txt}
[ -f "$list" ] || { echo "no cluster list at $list: run the generator into $source_dir first" >&2; exit 2; }
# The clusters that do not build against the host, each with its reason (not-built.txt beside this script). A listed cluster
# that builds is stale, and a listed cluster that does not build is skipped; the entries are counted and the count is pinned.
skip_file=$here/not-built.txt
[ -f "$skip_file" ] || { echo "no skip list at $skip_file" >&2; exit 2; }
skip_listed=$(awk 'NF && $1 !~ /^#/ { n++ } END { print n + 0 }' "$skip_file")

# Every excluded name, and whether it resolves to a file the generator should not have written. On a
# case-insensitive volume an excluded name and the runtime spelling are the same path, so "is there a file"
# is asked case-insensitively and an answer of yes is an ERROR, not a cluster to check.
excluded_names=0
excluded_collisions=0
if [ -f "$excluded" ]; then
    while read -r name reason; do
        case "$name" in ""|\#*) continue ;; esac
        excluded_names=$((excluded_names + 1))
        # On a case-insensitive volume this name and its runtime twin are ONE path, so a case-insensitive
        # match is expected and is not the finding. What matters is the spelling ON DISK: it must not BE
        # the excluded name, or the file was written for the deprecated subclass rather than the class the
        # runtime registers.
        # awk rather than `grep ... || true`: grep exits 1 when it matches nothing, and under `set -e`
        # that needs silencing, which is what `|| true` was doing here. A count or a lookup that depends
        # on no exit status cannot be silenced into a wrong answer.
        ondisk=$(ls "$source_dir" 2>/dev/null | awk -v want="CharonMatter${name}.m" \
            'tolower($0) == tolower(want) { print; exit }')
        if [ -z "$ondisk" ]; then
            echo "excluded   $name  (no file; $reason)"
        elif [ "$ondisk" = "CharonMatter${name}.m" ]; then
            echo "EXCLUDED NAME HAS ITS OWN FILE: $ondisk is the deprecated subclass's own file" >&2
            excluded_collisions=$((excluded_collisions + 1))
        else
            echo "excluded   $name  (one path with $ondisk on this volume; that file is the class the runtime registers; $reason)"
        fi
    done < "$excluded"
fi
[ "$excluded_collisions" -eq 0 ] || exit 1
rm -rf "$build"
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path)
if [ ! -f "$sdk/System/Library/Frameworks/Matter.framework/Headers/MTRBaseClusters.h" ]; then
    echo "this host has no Matter.framework, so there is no oracle for the port" >&2
    exit 2
fi

# The port's object for this cluster is the one the compile produced; a cluster with no object did not
# compile and is not checked.
# A plant runs against a COPY of the tree, so the source directory is overridable and the run says
# which directory it read.

# Four verdicts, four counters, and a verdict LOG the loop appends to. One counter for all of them was
# the defect: `failed` counted a cluster that DID NOT BUILD and a cluster whose members differ, so the
# summary printed 144 against 141 DIFFERENT lines and neither number meant what it said. The summary is
# now counted back out of the log and the two are asserted equal, so a summary that disagrees with its
# own lines fails the run instead of being read as a verdict.
# The DECLARED set: the instance selectors each class declares in SDK 26.2's own headers, its @interface AND its
# categories, read by the compiler's AST. cases.m holds the port to it. It is not read by the generator's reader:
# a reader that agreed with the generator by construction could not find a declaration the generator did not read.
sdk262=${MATTER_SDK_262:-}
if [ -z "$sdk262" ] || [ ! -f "$sdk262/System/Library/Frameworks/Matter.framework/Headers/MTRBaseClusters.h" ]; then
    echo "MATTER_SDK_262 must name the iPhoneOS 26.2 SDK: the declared set is read from its Matter headers" >&2
    exit 2
fi
headers="$sdk262/System/Library/Frameworks/Matter.framework/Headers"
printf '#import "%s/MTRBaseClusters.h"\n#import "%s/MTRClusters.h"\n' "$headers" "$headers" > "$build/declared.m"
xcrun clang -fsyntax-only -fobjc-arc -x objective-c -target arm64-apple-ios16.0 -isysroot "$sdk262" \
    -Xclang -ast-dump "$build/declared.m" > "$build/declared.ast" 2> "$build/declared.err"
# A method line is a child of a top-level @interface or @category: `| |-ObjCMethodDecl ... - selector 'type'`. A
# category's class is named by its child `ObjCInterface 'Name'`, and a top-level line of any other kind ends the
# class. Instance methods only (`- `), and the selector is the token after the dash.
awk '
/^[|`]-ObjCInterfaceDecl/ { kind = "iface"; cls = $NF; next }
/^[|`]-ObjCCategoryDecl/  { kind = "cat"; cls = ""; next }
/^[|`]-/                  { kind = ""; cls = ""; next }
kind == "cat" && cls == "" && /ObjCInterface 0x/ { split($0, q, "\047"); cls = q[2]; next }
/^(\| |  )[|`]-ObjCMethodDecl/ && cls != "" && / - / {
    split($0, parts, " - "); split(parts[2], rest, " "); print cls "\t" rest[1]
}' "$build/declared.ast" | sort -u > "$build/declared.tsv"
declared_rows=$(awk 'END { print NR }' "$build/declared.tsv")
if [ "$declared_rows" -lt 1000 ]; then
    echo "the declared set has $declared_rows rows: the AST did not read the SDK's Matter classes (see $build/declared.err)" >&2
    exit 1
fi
echo "declared set: $declared_rows (class, selector) rows read from $headers"

mkdir -p "$build"
verdicts="$build/verdicts.txt"
: > "$verdicts"
checked=0
not_built=0
skipped=0
stale=0
differing=0
no_source=0
for cluster in $(cat "$list"); do
    name=CharonMatter$cluster
    source=$(port_file "$cluster")
    if [ ! -f "$source" ]; then
        echo "no generated source for $cluster" >&2
        echo "no-source $cluster" >> "$verdicts"
        no_source=$((no_source + 1))
        continue
    fi
    # Built from a COPY, as behaviour.sh builds it. A superclass the object reaches (an alias's, through
    # CharonMatterQueueStorage.h) is built with it and aliased the same way, or the link has no offset to resolve.
    work="$build/src-$cluster"
    mkdir -p "$work"
    cp "$source" "$work/"
    [ -f "$source_dir/CharonMatterQueueStorage.h" ] && cp "$source_dir/CharonMatterQueueStorage.h" "$work/"
    supers=$(sed -n 's/.*((\([A-Za-z0-9_]*\) \*)self)->_charon_queue.*/\1/p' "$source" | sort -u)
    # The header the object is built with is the port's own CharonMatterTypes.h, cut to this class and its superclasses:
    # the preamble (the guard, the imports, the nullability region) and, for each of those classes the header declares,
    # its properties as a class EXTENSION, `@interface NAME ()`. The host SDK declares the classes themselves, and the
    # header's own `@interface NAME : Super` blocks would be a second declaration of each: the compiler's "duplicate
    # interface definition", which is what the 79 port-only blocks did when the whole header was copied in.
    keep="$cluster $(printf '%s\n' $supers | tr '\n' ' ')"
    awk -v keep="$keep" '
        BEGIN { n = split(keep, k, " "); for (i = 1; i <= n; i++) want[k[i]] = 1 }
        !seen && /^@interface / { seen = 1 }
        !seen { print; next }
        /^@interface [A-Za-z0-9_]+ : / { blk = ($2 in want); if (blk) { print "@interface " $2 " ()" }; next }
        blk && /^@end/ { print; blk = 0; next }
        blk && /^@property/ { print; next }
        blk { next }
        /^NS_ASSUME_NONNULL_END|^#endif/ { print }' "$source_dir/CharonMatterTypes.h" > "$work/CharonMatterTypes.h"
    # The port's own storage, by name: the `...Values` properties the header declares for the object's table (no SDK declares them).
    # Each is its getter and its setter, which is what the class answers for it.
    sed -n 's/^@property .*[ *]\([A-Za-z0-9_]*Values\);$/\1/p' "$work/CharonMatterTypes.h" \
        | awk '{ print; print "set" toupper(substr($0, 1, 1)) substr($0, 2) ":" }' > "$build/storage-$cluster.txt"
    listed=$(awk -v c="$cluster" '$1 == c { print; exit }' "$skip_file")
    aliases="-D$cluster=CharonPort$cluster"
    sources="$work/CharonMatter$cluster.m"
    for each in $supers; do
        cp "$source_dir/CharonMatter$each.m" "$work/"
        aliases="$aliases -D$each=CharonPort$each"
        sources="$sources $work/CharonMatter$each.m"
    done
    # shellcheck disable=SC2086
    if ! xcrun clang -target arm64-apple-macos26.0 -isysroot "$sdk" -fobjc-arc -O0 -Wall \
        -Wno-nonnull -Wno-objc-protocol-property-synthesis -Wno-incomplete-implementation \
        $aliases "-DCHARN_PORT_CLUSTER=\"CharonPort$cluster\"" -I"$work" \
        "$here/cases.m" $sources -framework Foundation -framework Matter \
        -o "$build/$name" 2> "$build/$name.log"; then
        if [ -n "$listed" ]; then
            echo "skipped    $cluster  $(echo "$listed" | awk '{ $1 = ""; sub(/^ +/, ""); print }')"
            echo "skipped $cluster" >> "$verdicts"
            skipped=$((skipped + 1))
            continue
        fi
        echo "differential did not build for $cluster:" >&2
        tail -10 "$build/$name.log" >&2
        echo "not-built $cluster" >> "$verdicts"
        not_built=$((not_built + 1))
        continue
    fi
    if [ -n "$listed" ]; then
        echo "STALE      $cluster  builds against the host now: take it off $skip_file" >&2
        echo "stale $cluster" >> "$verdicts"
        stale=$((stale + 1))
        continue
    fi
    checked=$((checked + 1))
    if ! CHARON_DECLARED="$build/declared.tsv" CHARON_CONTRACT="$contracts/CharonMatter$cluster.m.contract" \
        CHARON_STORAGE="$build/storage-$cluster.txt" "$build/$name" "$cluster" > "$build/$name.out" 2>&1; then
        differing=$((differing + 1))
        echo "different $cluster" >> "$verdicts"
        echo "DIFFERENT  $cluster"
        sed 's/^/  /' "$build/$name.out" | head -8
    else
        echo "same       $cluster  $(grep -c . "$build/$name.out") lines, $(grep -c "not carried" "$build/$name.out") not carried, $(grep -c "shape-differs" "$build/$name.out") shape-differs"
        echo "same $cluster" >> "$verdicts"
    fi
done

# Counted back out of the log, and each asserted against the counter the loop kept. A summary that
# disagrees with its own lines is not a summary.
# Counted with awk, which exits 0 whatever it finds, so nothing here needs its exit status silenced.
# `grep -c ... || true` read as a number that cannot be wrong; these counts decide whether the run passes.
log_differing=$(awk '/^different / { n++ } END { print n + 0 }' "$verdicts")
log_same=$(awk '/^same / { n++ } END { print n + 0 }' "$verdicts")
log_not_built=$(awk '/^not-built / { n++ } END { print n + 0 }' "$verdicts")
log_no_source=$(awk '/^no-source / { n++ } END { print n + 0 }' "$verdicts")
[ "$log_differing" -eq "$differing" ] || { echo "SUMMARY DISAGREES: differing counted $differing, the log has $log_differing" >&2; exit 1; }
[ "$log_same" -eq "$((checked - differing))" ] || { echo "SUMMARY DISAGREES: checked $checked less differing $differing is not same $log_same" >&2; exit 1; }
[ "$log_not_built" -eq "$not_built" ] || { echo "SUMMARY DISAGREES: not built $not_built, the log has $log_not_built" >&2; exit 1; }
[ "$log_no_source" -eq "$no_source" ] || { echo "SUMMARY DISAGREES: no source $no_source, the log has $log_no_source" >&2; exit 1; }
log_skipped=$(awk '/^skipped / { n++ } END { print n + 0 }' "$verdicts")
log_stale=$(awk '/^stale / { n++ } END { print n + 0 }' "$verdicts")
[ "$log_skipped" -eq "$skipped" ] || { echo "SUMMARY DISAGREES: skipped $skipped, the log has $log_skipped" >&2; exit 1; }
[ "$log_stale" -eq "$stale" ] || { echo "SUMMARY DISAGREES: stale $stale, the log has $log_stale" >&2; exit 1; }
# Every entry of the skip list is a cluster the run met and skipped: an entry the list no longer names is not counted here.
[ "$skipped" -eq "$skip_listed" ] || { echo "the skip list has $skip_listed entries and the run skipped $skipped: a listed cluster was not met" >&2; exit 1; }
echo "clusters listed: $((checked + not_built + skipped + stale + no_source)), no generated source: $no_source, not built: $not_built, skipped: $skipped (not-built.txt), stale: $stale, checked: $checked, differing: $differing   (source: $source_dir)"
[ "$differing" -eq 0 ] && [ "$not_built" -eq 0 ] && [ "$stale" -eq 0 ]
