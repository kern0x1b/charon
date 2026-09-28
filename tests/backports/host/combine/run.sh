#!/bin/sh
# The differential: does this port's Combine behave as the host's own Combine does?
#
# One source - Harness.swift, Table.swift and main.swift here - is compiled twice, once
# against the host's own Combine and once against the module this port builds, and the two
# runs are compared line for line. A differing line is a place where a caller of the two
# would see something different.
#
# The module is built HERE, from the fork's own sources and this repository's layer, before
# either probe is built against it. That is the whole point: a run that linked a prebuilt
# object would measure the object, so a change to the module's Swift could sit in the
# sources and the run would answer `identical`. A mutation of the source read as a pass,
# which is the one thing this test must never do. README.md has the mutation and what it
# prints.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../../.." && pwd)
build=${COMBINE_DIFFERENTIAL_BUILD:-${TMPDIR:-/tmp}/charon-combine-differential}
sources=${COMBINE_SOURCES:-}
swifc=${SWIFTC:-/usr/bin/swiftc}
clangxx=${CLANGXX:-clang++}

# The fork's own sources are not in this repository - the recipe fetches them - so they come
# from the xmake source cache when the package has been built, or from $COMBINE_SOURCES.
if [ -z "$sources" ]; then
    sources=$(ls -d "$HOME"/.xmake/cache/packages/*/s/styx/*/source/styx/Sources 2>/dev/null | head -1 || true)
fi
if [ -z "$sources" ] || [ ! -d "$sources/Combine" ]; then
    echo "cannot find the fork's Combine sources."
    echo "Build charon@styx once, or point COMBINE_SOURCES at the Sources/Combine directory of"
    echo "kern0x1b/styx at the commit packages/s/styx/xmake.lua pins."
    exit 1
fi
if [ ! -d "$repo/packages/s/styx/files/CombineKit" ]; then
    echo "no layer at $repo/packages/s/styx/files/CombineKit; this is a worktree of charon."
    exit 1
fi

rm -rf "$build"
mkdir -p "$build/stage/Combine" "$build/swift/CombineKit.swiftmodule" "$build/objects"

# ---------------------------------------------------------------- the module

# The host copy is called CombineKit, not Combine. On macOS the SDK's own Foundation
# imports Apple's Combine, and a module called Combine links Apple's Combine beside it
# through the autolink its interface carries; the two sets of classes then collide. Twelve
# files of the sources name the module's own types with the module's own prefix, which only
# resolves when the module carries that name, so the staged copy has that prefix rewritten
# to the name it is built under. OCombine is a nested namespace of the fork's own whose name
# ends in the same six letters, so it is put aside for the moment the substitution happens.
cp -R "$sources/Combine/." "$build/stage/Combine/"
rm -rf "$build/stage/Combine/Foundation" "$build/stage/Combine/Schedulers"
mkdir -p "$build/stage/Combine/CombineKit"
cp "$repo"/packages/s/styx/files/CombineKit/*.swift "$build/stage/Combine/CombineKit/"
find "$build/stage" -name '*.swift' -print0 \
    | xargs -0 sed -i '' -e 's/OCombine/@@NESTED@@/g' -e 's/Combine\./CombineKit./g' \
                          -e 's/@@NESTED@@/OCombine/g'

helpers="$sources/CombineHelpers"
"$clangxx" -target arm64-apple-macosx11.0 -std=c++17 -O2 \
    -I "$helpers/include" \
    -c "$helpers/CombineHelpers.cpp" -o "$build/objects/CombineHelpers.o"
"$swifc" -target arm64-apple-macosx11.0 -wmo -module-name CombineKit -O -parse-as-library \
    -I "$build/stage" -I "$helpers/include" \
    -Xcc -fmodule-map-file="$helpers/include/module.modulemap" \
    -emit-module -emit-module-path "$build/swift/CombineKit.swiftmodule/arm64-apple-macos.swiftmodule" \
    -c $(find "$build/stage/Combine" -name '*.swift') -o "$build/objects/Combine.o"

# ---------------------------------------------------------------- the two probes

# The three files are one source compiled twice; the only difference is the module each
# imports, which is a conditional at the top of each.
"$swifc" -O -D APPLE_COMBINE -o "$build/apple" -module-cache-path "$build/mc-apple" \
    "$here/Harness.swift" "$here/Table.swift" "$here/main.swift"
"$swifc" -O -o "$build/ours" -module-cache-path "$build/mc-ours" \
    -I "$build/swift" -I "$helpers/include" \
    -Xcc -fmodule-map-file="$helpers/include/module.modulemap" \
    "$here/Harness.swift" "$here/Table.swift" "$here/main.swift" \
    "$build/objects/Combine.o" "$build/objects/CombineHelpers.o"

if otool -L "$build/ours" | grep -q "System/Library/Frameworks/Combine.framework"; then
    echo "REFUSING: ours links Apple's Combine beside ours; the two would collide"
    exit 1
fi

# ---------------------------------------------------------------- the two runs

"$build/apple" > "$build/apple.txt"
"$build/ours" > "$build/ours.txt"
echo "cases: $(tail -1 "$build/apple.txt")"
if diff -u "$build/apple.txt" "$build/ours.txt" > "$build/diff.txt"; then
    echo "DIFFERENTIAL: identical"
else
    echo "DIFFERENTIAL: $(grep -c '^[-+][^-+]' "$build/diff.txt") differing lines, in $build/diff.txt"
    head -60 "$build/diff.txt"
    exit 1
fi
