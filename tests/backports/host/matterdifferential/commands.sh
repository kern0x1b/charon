#!/bin/sh
# matterdifferential/commands.sh - every command and every reader of every Matter class the port generated, called on
# a controller that has been shut down, on the system's class and on the port's, and the answers compared.
#
# The classes are the base clusters (clusters-emitted.txt) and the generic clusters (generic-clusters-emitted.txt,
# the non-base MTRCluster<Name> classes that carry the expectedValues commands). The question is commands.m's: what the
# completion of each selector receives, on each side, with nothing to reach.
#
# What is called and how is read from the SDK's own headers by the compiler's AST: every instance selector each class
# declares, and for each one the arity of its completion block (1 for MTRStatusCompletion, 2 for a response block, 0 when
# the selector takes no completion). That is read here, not by the generator, so it cannot agree with the generator by
# construction.
#
# Writes and subscribes are not called (commands.m's header says why); the count of each is printed.
#
# A class that does not build is a failure unless it is on not-built.txt beside this script, as run.sh's rule. A class
# on the generic list with no generated source is counted and named, not called: the generator writes no file for it.
#
# Usage: MATTER_SDK_262=<iPhoneOS 26.2 SDK> sh tests/backports/host/matterdifferential/commands.sh
#        BUILD=<dir>  where the programs and their output go
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
build=${BUILD:-${TMPDIR:-/tmp}/charon-matter-commands}
source_dir=${MATTER_SOURCE_DIR:-$root/packages/a/apple-backports/Matter}
sdk262=${MATTER_SDK_262:-}
if [ -z "$sdk262" ] || [ ! -f "$sdk262/System/Library/Frameworks/Matter.framework/Headers/MTRBaseClusters.h" ]; then
    echo "MATTER_SDK_262 must name the iPhoneOS 26.2 SDK: the selectors and their completion arity are read from its Matter headers" >&2
    exit 2
fi
sdk=$(xcrun --show-sdk-path)
if [ ! -f "$sdk/System/Library/Frameworks/Matter.framework/Headers/MTRBaseClusters.h" ]; then
    echo "this host has no Matter.framework, so there is no oracle for the port" >&2
    exit 2
fi
base_list=$source_dir/clusters-emitted.txt
generic_list=$source_dir/generic-clusters-emitted.txt
for each in "$base_list" "$generic_list"; do
    [ -f "$each" ] || { echo "no cluster list at $each: run the generator into $source_dir first" >&2; exit 2; }
done
base_skip=$here/not-built.txt
generic_skip=$here/not-built-generic.txt
for each in "$base_skip" "$generic_skip"; do
    [ -f "$each" ] || { echo "no skip list at $each" >&2; exit 2; }
done

rm -rf "$build"
mkdir -p "$build"
headers="$sdk262/System/Library/Frameworks/Matter.framework/Headers"
printf '#import "%s/MTRBaseClusters.h"\n#import "%s/MTRClusters.h"\n' "$headers" "$headers" > "$build/declared.m"
xcrun clang -fsyntax-only -fobjc-arc -x objective-c -target arm64-apple-ios16.0 -isysroot "$sdk262" \
    -Xclang -ast-dump "$build/declared.m" > "$build/declared.ast" 2> "$build/declared.err"

# One row per (class, instance selector): the class, the selector and the arity of its completion block. A method line is
# a child of a top-level @interface or @category; its ParmVarDecl children give the block's parameters, read from the
# type the AST prints after the colon ('void (^)(MTRX * _Nullable, NSError * _Nullable)'). A selector with no block
# parameter has arity 0. Commas are counted outside angle brackets, so a generic parameter type is one parameter.
awk '
BEGIN { arity = 0 }
function flush() {
    if (cls != "" && sel != "") { print cls "\t" sel "\t" arity }
    sel = ""; arity = 0
}
function blockArity(line,   s, i, c, depth, angle, params, n) {
    # The block declarator is "(^ _Nonnull __strong)" in the AST, so the parameter list starts after the ")(" that
    # follows it, not after a fixed "(^)(".
    s = substr(line, index(line, "(^"))
    s = substr(s, index(s, ")(") + 2)
    depth = 1; angle = 0; params = ""; n = 0
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "(") depth++
        else if (c == ")") { depth--; if (depth == 0) break }
        else if (c == "<") angle++
        else if (c == ">") angle--
        else if (c == "," && depth == 1 && angle == 0) n++
        params = params c
    }
    if (params == "void" || params == "") return 0
    return n + 1
}
/^[|`]-ObjCInterfaceDecl/ { flush(); kind = "iface"; cls = $NF; next }
/^[|`]-ObjCCategoryDecl/  { flush(); kind = "cat"; cls = ""; next }
/^[|`]-/                  { flush(); kind = ""; cls = ""; next }
kind == "cat" && cls == "" && /ObjCInterface 0x/ { split($0, q, "\047"); cls = q[2]; next }
/^(\| |  )[|`]-ObjCMethodDecl/ && cls != "" && / - / {
    flush(); split($0, parts, " - "); split(parts[2], rest, " "); sel = rest[1]; next
}
sel != "" && /ParmVarDecl/ && /\(\^/ { arity = blockArity($0); next }
END { flush() }
' "$build/declared.ast" | sort -u > "$build/declared-arity.tsv"
rows=$(awk 'END { print NR }' "$build/declared-arity.tsv")
if [ "$rows" -lt 1000 ]; then
    echo "the declared set has $rows rows: the AST did not read the SDK's Matter classes (see $build/declared.err)" >&2
    exit 1
fi
echo "declared selectors: $rows (class, selector, arity) rows read from $headers"

verdicts=$build/verdicts.txt
: > "$verdicts"
not_built=0
skipped=0
stale=0
no_source=0
did_not_run=0
differing=0
run_classes=0

run_list() {
    list=$1
    skip_file=$2
    for cluster in $(cat "$list"); do
        # COMMANDS_ONLY=<pattern> runs the classes whose names match, for a quick look; the check itself runs them all.
        if [ -n "${COMMANDS_ONLY:-}" ] && ! echo "$cluster" | grep -q "$COMMANDS_ONLY"; then continue; fi
        source=$source_dir/CharonMatter$cluster.m
        if [ ! -f "$source" ]; then
            echo "no-source  $cluster  (the generator wrote no file for it)"
            echo "no-source $cluster" >> "$verdicts"
            no_source=$((no_source + 1))
            continue
        fi
        listed=$(awk -v c="$cluster" '$1 == c { print; exit }' "$skip_file")
        # Built from a COPY, as run.sh builds it: a superclass the object reaches is built with it and aliased the same way.
        work="$build/src-$cluster"
        mkdir -p "$work"
        cp "$source" "$work/"
        [ -f "$source_dir/CharonMatterQueueStorage.h" ] && cp "$source_dir/CharonMatterQueueStorage.h" "$work/"
        supers=$(sed -n 's/.*((\([A-Za-z0-9_]*\) \*)self)->_charon_queue.*/\1/p' "$source" | sort -u)
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
            "$here/commands.m" $sources -framework Foundation -framework Matter -framework Security \
            -o "$build/$cluster" 2> "$build/$cluster.log"; then
            if [ -n "$listed" ]; then
                echo "skipped    $cluster  $(echo "$listed" | awk '{ $1 = ""; sub(/^ +/, ""); print }')"
                echo "skipped $cluster" >> "$verdicts"
                skipped=$((skipped + 1))
                continue
            fi
            echo "not built  $cluster (see $build/$cluster.log)" >&2
            tail -6 "$build/$cluster.log" >&2
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
        run_classes=$((run_classes + 1))
        rc=0
        CHARON_DECLARED="$build/declared-arity.tsv" "$build/$cluster" "$cluster" > "$build/$cluster.out" 2>&1 || rc=$?
        summary=$(awk '/commands compared/ { print; exit }' "$build/$cluster.out")
        if [ "$rc" -ne 0 ] && [ -z "$(awk '/^DIFFERENT/ { print; exit }' "$build/$cluster.out")" ] \
            || [ -z "$summary" ]; then
            echo "DID NOT RUN $cluster (exit $rc, see $build/$cluster.out)" >&2
            echo "did-not-run $cluster" >> "$verdicts"
            did_not_run=$((did_not_run + 1))
            continue
        fi
        class_differing=$(awk '/^DIFFERENT/ { n++ } END { print n + 0 }' "$build/$cluster.out")
        if [ "$class_differing" -gt 0 ]; then
            differing=$((differing + class_differing))
            echo "different $cluster $class_differing"
            awk '/^DIFFERENT/ || /^\t\t\t\tport:/ { print "  " $0 }' "$build/$cluster.out" | head -8
            echo "different $cluster" >> "$verdicts"
        else
            echo "same      $cluster  $(echo "$summary" | awk -F'\t' '{ print $2 }')"
            echo "same $cluster" >> "$verdicts"
        fi
    done
}

run_list "$base_list" "$base_skip"
run_list "$generic_list" "$generic_skip"

# Counted back out of each class's own output, so the total is what the programs said and not what the loop counted.
totals=$(for each in "$build"/*.out; do
    awk '/commands compared/ { print }' "$each"
done | awk -F'\t' '
# The number after the first occurrence of key in the summary line, 0 when the line does not carry it.
function count(s, key,   i, t) {
    i = index(s, key)
    if (!i) return 0
    t = substr(s, i + length(key))
    match(t, /^[0-9]+/)
    return substr(t, 1, RLENGTH) + 0
}
{
    s = $2
    c += count(s, "commands compared ")
    r += count(s, ", readers compared ")
    y += count(s, ", synchronous readers compared ")
    w += count(s, ", writes not called ")
    u += count(s, ", subscribes not called ")
    i += count(s, ", initialisers not called ")
    z += count(s, ", without a completion ")
    n += count(s, ", not carried by the host ")
}
END { print c + 0, r + 0, y + 0, w + 0, u + 0, i + 0, z + 0, n + 0 }')
set -- $totals
commands=$1; readers=$2; syncreaders=$3; writes=$4; subscribes=$5; initialisers=$6; nocompletion=$7; notcarried=$8
log_differing=$(awk '/^different / { n++ } END { print n + 0 }' "$verdicts")
echo "classes run: $run_classes, commands compared: $commands, readers compared: $readers, synchronous readers compared: $syncreaders, writes not called: $writes, subscribes not called: $subscribes, initialisers not called: $initialisers, selectors without a completion: $nocompletion, not carried by the host: $notcarried"
echo "DIFFERENT lines: $differing (in $log_differing classes), not built: $not_built, skipped: $skipped (not-built.txt), stale: $stale, did not run: $did_not_run, no generated source: $no_source"
[ "$differing" -eq 0 ] && [ "$not_built" -eq 0 ] && [ "$stale" -eq 0 ] && [ "$did_not_run" -eq 0 ] && [ "$commands" -gt 0 ]
