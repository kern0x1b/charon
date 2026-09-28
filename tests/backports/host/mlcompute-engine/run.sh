#!/bin/sh
# The twenty-one activation types, asked of the host's own MLCompute and of the port's engine, and the two
# answers compared line by line - then a mutant of the port that has to be told apart from it.
#
# WIP: this does not run yet, and the two reasons are measured. Both are in building the engine for the
# host, not in the comparison.
#
#   1. The package's libggml.a is armv7, built for the release the gate builds, and cannot go into an arm64
#      Catalyst dylib. So the test compiles the same five translation units of the same pinned commit for
#      the host, out of the package's own cached tarball.
#   2. On an arm64 host that is not enough: the quantization and vector-product kernels the CPU backend
#      dispatches to live in C++ translation units the recipe does not compile - src/ggml-cpu/ops.cpp,
#      traits.cpp, vec.cpp, binary-ops.cpp and ggml-cpu.cpp beside quants.c - and the five C units leave
#      quantize_row_q8_0 and the ggml_vec_dot_* family undefined, which the link names one by one. The
#      armv7 build is unaffected: its kernels are in the C, which is why the gate's own build of the engine
#      is clean in both bands. Building the host copy therefore means compiling the engine's C++ for the
#      host, and the next question is which of those units the host needs and whether the dylib then needs
#      a C++ runtime.
#
# What is finished and in the tree: the three programs, the two-sided comparison, the mutant, and the
# finding above.
#
# The port side goes through a dylib, not a program linked against libggml.a: the archive is compiled
# -fvisibility=hidden so the engine is never API of an image that links it, and a program cannot bind to a
# hidden symbol in a static archive. The dylib is built the way the gate builds the library - the port's
# own translation units, every name renamed, the archive linked in, hidden visibility throughout - and this
# one CharonMLC entry point is what crosses the boundary.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${MLCOMPUTE_PORT:-$here/../../../../packages/a/apple-backports/MLCompute}
# The archive lives under a per-configuration hash, and the gate prints which one it used; take the
# newest, which is the one the last 6.1.3 build linked.
ggml=${MLCOMPUTE_GGML:-$(ls -td "$HOME"/.xmake/packages/g/ggml/0.25.3/*/ 2>/dev/null | head -1 | sed "s:/$::")}
build=${MLCOMPUTE_BUILD:-${TMPDIR:-/tmp}/charon-mlcompute-engine}
rm -rf "$build"
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path)
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -fobjc-arc -w -I$here"
libs="-framework Foundation -framework Accelerate"

# The names, from the port's own sources, so a class the port adds is renamed too.
python3 - "$port" "$build/rename.h" <<'PY'
import os, re, sys
port, out = sys.argv[1], sys.argv[2]
names = set()
for entry in sorted(os.listdir(port)):
    if not entry.endswith((".m", ".mm", ".h")):
        continue
    text = open(os.path.join(port, entry)).read()
    names.update(re.findall(r"^@(?:interface|implementation)\s+(MLC\w+)", text, re.M))
    names.update(re.findall(r"^(?:NSString \*|NSUInteger|BOOL|void|double)\s+(MLC\w+)\(", text, re.M))
    names.update(re.findall(r"^\s*(MLC\w+),?$", text, re.M))
    names.update(re.findall(r"\b(MLCDataType\w+|MLCPoolingType\w+)\b", text))
with open(out, "w") as handle:
    for name in sorted(names):
        handle.write("#define %s Charon%s\n" % (name, name))
print("renamed %d names" % len(names))
PY

# The engine for the host. The package's own archive is armv7, built for the release the gate builds, and
# it cannot go into an arm64 Catalyst dylib; so this test compiles the same five translation units of the
# same pinned commit for the host. The sources are the package's own extracted tree, the flags are the
# recipe's, and the only difference is the architecture - there is no second implementation of anything
# here, and the operators and formulas the port is held to are the ones the release build uses.
# The sources come from the package's own cached tarball - the file the recipe pins by its sha256 - rather
# than from a tree xmake has already cleaned away.
ggmltar=${MLCOMPUTE_GGML_TARBALL:-$(ls -t "$HOME"/.xmake/cache/packages/*/g/ggml/0.25.3/ggml-0.25.3.tar.gz 2>/dev/null | head -1)}
ggmlsrc=$build/ggml
rm -rf "$ggmlsrc" "$build/tmp"
mkdir -p "$build/tmp"
tar xzf "$ggmltar" -C "$build/tmp"
mv "$build/tmp/ggml-0.25.3" "$ggmlsrc"
ggmlhost=$build/libggml-host.a
mkdir -p "$build/hostobj" "$build/hostbuild"
printf '#pragma once\n\n#define GGML_VERSION "v0.25.3"\n#define GGML_COMMIT  "8dd76549e6e714c064348a1c89d90ed7c6306727"\n' > "$build/hostbuild/ggml-version.h"
hostobjects=""
for source in ggml.c ggml-alloc.c ggml-quants.c ggml-cpu/ggml-cpu.c ggml-cpu/quants.c; do
    object="$build/hostobj/$(echo "$source" | tr / _).o"
    xcrun clang $common -Os -fvisibility=hidden -fno-exceptions -fno-rtti -D_GNU_SOURCE -Dggml_EXPORTS \
        -I"$ggmlsrc/include" -I"$ggmlsrc/include/ggml" -I"$ggmlsrc/src" -I"$ggmlsrc/src/ggml-cpu" -I"$build/hostbuild" \
        -c "$ggmlsrc/src/$source" -o "$object"
    hostobjects="$hostobjects $object"
done
xcrun libtool -static -o "$ggmlhost" $hostobjects

# The dylib: the port's translation units with the renamed names, hidden, and the archive linked in.
# -dynamiclib rather than the gate's driver: the point is the arrangement, not the load command.
dylib() {
    output=$1
    sources=$2
    xcrun clang $common -I"$port" -I"$ggml/include" -fvisibility=hidden -fvisibility-inlines-hidden -fno-rtti \
        -dynamiclib -Wl,-all_load -o "$output" $sources "$ggmlhost" $libs
}

dylib "$build/libCharonMLCompute.dylib" "$port/MLCTypes14.m $port/MLCDevice15.m $port/MLCTensors14.m $port/MLCDescriptors14.m $port/MLCLayers14.m $port/CharonMLCGraph.mm"
xcrun clang $common -include "$build/rename.h" -I"$port" "$here/port.m" "$build/libCharonMLCompute.dylib" $libs -o "$build/port"
xcrun clang $common "$here/system.m" $libs -framework MLCompute -o "$build/system"

"$build/system" > "$build/system.log"
"$build/port" "$build/libCharonMLCompute.dylib" > "$build/port.log"

if ! diff -u "$build/system.log" "$build/port.log"; then
    echo "the port's answers differ from the host's, above"
    exit 1
fi
echo "the port computes all $(( $(grep -c '	' "$build/system.log") )) activations as the host does"

# A mutant of the port: the GELU's bound, one digit changed, in the port's own formula. If the check above
# can be told apart from it, the check is reading the port's code and not a stored answer.
mutant() {
    rm -rf "$build/mutant"
    mkdir -p "$build/mutant"
    cp "$port"/*.m "$port"/*.mm "$port"/*.h "$build/mutant/"
    python3 - "$build/mutant/CharonMLCGraph.mm" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
before = text
text = text.replace("return a * x * 0.5f * (1.0f + erff(b * x * 0.70710678118654752440f));",
                    "return a * x * 0.5f * (1.0f + erff(b * x * 0.71710678118654752440f));")
assert text != before, "the mutant changed nothing"
open(path, "w").write(text)
PY
    dylib "$build/mutant/libCharonMLCompute.dylib" "$build/mutant/MLCTypes14.m $build/mutant/MLCDevice15.m $build/mutant/MLCTensors14.m $build/mutant/MLCDescriptors14.m $build/mutant/MLCLayers14.m $build/mutant/CharonMLCGraph.mm"
    xcrun clang $common -include "$build/rename.h" -I"$build/mutant" "$here/port.m" "$build/mutant/libCharonMLCompute.dylib" $libs -o "$build/mutant/port"
    "$build/mutant/port" "$build/mutant/libCharonMLCompute.dylib" > "$build/mutant.log" 2>&1 || true
    if diff -q "$build/system.log" "$build/mutant.log" > /dev/null; then
        echo "the mutant is indistinguishable from the port: the check reads a stored answer, not the code"
        exit 1
    fi
    echo "the mutant is told apart:"
    diff "$build/system.log" "$build/mutant.log" | grep "^[<>]" | head -4 | sed "s/^/  /"
}
mutant
echo "log=$build/system.log"
