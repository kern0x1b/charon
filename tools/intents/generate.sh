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
registry=$root/packages/a/apple-backports/registry/Intents
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
[ -f "$work/ast-port.json" ] || xcrun clang -target "arm64-apple-ios$port_version" -isysroot "$PORT_SDK" \
    -fsyntax-only -x objective-c -Wno-everything -Xclang -ast-dump=json "$work/umbrella.m" \
    > "$work/ast-port.json"
[ -f "$work/ast-262.json" ] || xcrun clang -target "arm64-apple-ios$newer_version" -isysroot "$SDK_262" \
    -fsyntax-only -x objective-c -Wno-everything -Xclang -ast-dump=json "$work/umbrella.m" \
    > "$work/ast-262.json"

carried=$groups/intents-classes.txt
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
    --reason "the class this member's type names is in a later group of this same delivery"
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
        --release "$release" --no-protocols $extra \
        --reason "the class this member's type names is in a later group of this same delivery"
done
echo "regenerated: $(ls "$classes"/IN*.m | wc -l) object files, $(ls "$registry"/ios*.json | wc -l) registry files"
