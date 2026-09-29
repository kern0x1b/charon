#!/bin/sh
# generate.sh - regenerate every generated file of this framework.
#
# The generated files are the .m under packages/a/apple-backports/Intents/ and the six JSONs under
# packages/a/apple-backports/registry/Intents/. Each opens with a line saying it is generated, so
# this is how one is reproduced, diffed against a rerun, or audited.
#
#   PORT_SDK  the SDK the port compiles against - the toolchain's charon@iphoneos-sdk, iPhoneOS
#             16.4. Every class it declares is read from here, because this is the header the
#             implementation compiles against.
#   SDK_262   the SDK the surface is measured from, for the nine names PORT_SDK does not declare.
#             The coordinator keeps an unpacked copy under
#             $HOME/Git/projects/ios/charon/.agent-work/sdk-26.2 - a scratch directory a worktree
#             sweep deletes - so it is a variable here and facts/Intents/Intents.md names where the
#             copy comes from rather than a path that will not be there.
#   CORPUS    the SDK 26.2 surface after iOS 6.1, one row per API, which the registry is written
#             from: $HOME/Git/projects/ios/coordination/corpus/sdk-26.2-surface.tsv.
#
# The six groups are the releases the release caches measure the class symbols first exported in
# (tools/intents/measure-intents.sh, and measure-group.lua for the one class that had to be an
# object of its own). --carried is the **whole** delivery's class list, so a class of an earlier
# group is carried and no member is left dynamic for a class this delivery already has.
#
# Usage: sh tools/intents/generate.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${WORK:-$root/.agent-work/intents-generation}
PORT_SDK=${PORT_SDK:-$(ls -d "$HOME"/.xmake/packages/i/iphoneos-sdk/*/*/iPhoneOS*.sdk 2>/dev/null | head -1)}
SDK_262=${SDK_262:-$HOME/Git/projects/ios/charon/.agent-work/sdk-26.2/iPhoneOS26.2.sdk}
CORPUS=${CORPUS:-$HOME/Git/projects/ios/coordination/corpus/sdk-26.2-surface.tsv}
classes=$root/packages/a/apple-backports/Intents
registry=${REGISTRY_OUT:-$root/packages/a/apple-backports/registry/Intents}
groups=$here/groups
facts=facts/Intents/Intents.md
mkdir -p "$work" "$registry"
[ -d "$PORT_SDK" ] || { echo "no port SDK; set PORT_SDK" >&2; exit 1; }
[ -d "$SDK_262" ] || { echo "no iPhoneOS 26.2 SDK; set SDK_262" >&2; exit 1; }
[ -f "$CORPUS" ] || { echo "no corpus surface; set CORPUS" >&2; exit 1; }

# The two ASTs. The newer one is read only for a class the port's SDK does not declare at all.
echo "#import <Intents/Intents.h>" > "$work/umbrella.m"
port_version=$(basename "$PORT_SDK" | sed 's/iPhoneOS//; s/\.sdk//')
newer_version=$(basename "$SDK_262" | sed 's/iPhoneOS//; s/\.sdk//')
# The dump is keyed by what it was read from: the SDK's own header mtimes and the umbrella that
# imports them.  The plain `[ -f ]` test that was here meant that a run with a different SDK, or
# after a header changed, read a dump of something else and generated from it, and it meant that a
# second run in the same turn paid the parse again - measured, 10 minutes for the pair, and it is
# the whole cost of a rerun.  So the key is written beside the dump and compared, and a mismatch
# re-reads.
ast_dump() {           # ast_dump SDK VERSION OUT
    # The key is the newest header mtime, the number of headers, and the umbrella's own: a
    # changed header or a changed import list re-reads, and nothing else does.
    # The umbrella's own **content hash**, not its mtime: generate.sh rewrites the umbrella on
    # every run, so an mtime in the key is always new and the dump is never reused.  Measured, one
    # rerun paid the 10-minute parse for exactly that reason.
    key=$( { find "$1/System/Library/Frameworks" -name '*.h' -print0 | xargs -0 stat -f '%m' 2>/dev/null | sort -rn | head -1
             find "$1/System/Library/Frameworks" -name '*.h' | wc -l
             shasum "$work/umbrella.m" | cut -d' ' -f1; } | tr '\n' ' ')
    if [ -f "$3" ] && [ -f "$3.key" ] && [ "$(cat "$3.key")" = "$key" ]; then
        echo "    ast $3: reused, $(wc -c < "$3" | tr -d ' ') bytes"
        return 0
    fi
    echo "    ast $3: reading $1"
    xcrun clang -target "arm64-apple-ios$2" -isysroot "$1" \
        -fsyntax-only -x objective-c -Wno-everything -Xclang -ast-dump=json "$work/umbrella.m" \
        > "$3"
    echo "$key" > "$3.key"
}
ast_dump "$PORT_SDK" "$port_version" "$work/ast-port.json"
ast_dump "$SDK_262" "$newer_version" "$work/ast-262.json"

carried=$groups/intents-classes.txt
# The generator's own vocabulary of why a member is not answered, written out so an absent entry's
# reason is the cause the generator recorded and not the owner class's group.
python3 "$here/gen-causes.py" --out "$work/causes.json"
# group:release:file:newer:protocols
for entry in 10_0_1:10.0.1:ios10:no:yes \
            10_3:10.3:ios10:no:yes \
            11_0:11.0:ios11:no:no \
            12_0:12.0:ios12:yes:no \
            16_0:16.0:ios16:yes:no \
            18_0:18.0:ios18:yes:no; do
    group=${entry%%:*}; rest=${entry#*:}; release=${rest%%:*}; rest=${rest#*:}
    file=${rest%%:*}; rest=${rest#*:}; newer=${rest%%:*}; protocols=${rest##*:}
    echo "=== $group ($release)"
    extra=""
    [ "$newer" = yes ] && extra="--dump-newer $work/ast-262.json"
    [ "$group" = 16_0 ] && continue
    python3 "$here/gen-intents.py" --sdk "$PORT_SDK" \
        --dump "$work/ast-port.json" $extra --classes "$groups/$group.txt" --release "$release" \
        --carried "$carried" --intents "$carried" --out "$classes/IN$group.m" \
        --report "$work/report-$group.json"
done
# The 16.0 group last, so its ALONE class is emitted with it.
python3 "$here/gen-intents.py" --sdk "$PORT_SDK" --dump "$work/ast-port.json" \
    --dump-newer "$work/ast-262.json" --classes "$groups/16_0.txt" --release 16.0 \
    --carried "$carried" --intents "$carried" --out "$classes/IN16_0.m" \
    --report "$work/report-16_0.json"

# The registry, one file per group, written from what each generator emitted and the corpus's own
# rows. The first two groups share a file, and the protocols are written once, there.
python3 "$here/gen-registry.py" --corpus "$CORPUS" --classes "$groups/10_0_1.txt" "$groups/10_3.txt" \
    --report "$work/report-10_0_1.json" --report "$work/report-10_3.json" \
    --out "$registry/ios10.json" --facts "$facts" --release 10.0.1 \
        --causes "$work/causes.json" \
        --reason "a class of a later group of this same delivery"
for entry in 11_0:11.0:ios11 \
            12_0:12.0:ios12 \
            16_0:16.0:ios16 \
            18_0:18.0:ios18; do
    group=${entry%%:*}; rest=${entry#*:}; release=${rest%%:*}; file=${rest##*:}
    extra=""
    [ "$group" = 11_0 ] && extra="--hand-written CharonIntents110.m"
    # shellcheck disable=SC2086
    python3 "$here/gen-registry.py" --corpus "$CORPUS" --classes "$groups/$group.txt" \
        --report "$work/report-$group.json" --out "$registry/$file.json" --facts "$facts" \
        --release "$release" --no-protocols --causes "$work/causes.json" $extra \
            --reason "a class of a later group of this same delivery"
done
echo "regenerated: $(ls "$classes"/IN*.m | wc -l) object files, $(ls "$registry"/ios*.json | wc -l) registry files"
