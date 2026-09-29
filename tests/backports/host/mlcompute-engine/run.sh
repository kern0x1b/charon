#!/bin/sh
# The twenty-one activation types, asked of the host's own MLCompute and of the port's engine, and the two
# answers compared line by line - then a mutant of the port that has to be told apart from it.
#
# The engine for the host is built from the CPU backend's own source list at that commit, C and C++, and
# the dylib links the C++ runtime. That is the harness only: the release build compiles the five C units
# and is clean in both bands, because on armv7 the kernels are in the C.
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
# The engine's C++ units need the C++ runtime, which the release build does not.
dyliblibs="$libs -lc++"

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

# The engine for the host.
#
# The package's libggml.a is armv7, built for the release the gate builds, and cannot go into an arm64
# Catalyst dylib, so this test builds the engine for the host: the sources come from the package's own
# cached tarball - the file the recipe pins by its sha256 - the flags are the recipe's, and the list of
# translation units is the CPU backend's own, read out of src/ggml-cpu/CMakeLists.txt at that commit:
# the base GGML_CPU_SOURCES, and for an arm64 target the ARM branch's two arch units. The five C units the
# release build compiles are not enough here: on arm64 the dispatch and the vector-product and
# quantization kernels live in the C++ units beside them, and the link names every symbol they hold.
#
# The release build is unaffected - its kernels are in the C, which is why the gate's build of the engine
# is clean in both bands. This is the test harness and nothing else.
ggmltar=${MLCOMPUTE_GGML_TARBALL:-$(ls -t "$HOME"/.xmake/cache/packages/*/g/ggml/0.25.3/ggml-0.25.3.tar.gz 2>/dev/null | head -1)}
ggmlsrc=$build/ggml
rm -rf "$ggmlsrc" "$build/tmp"
mkdir -p "$build/tmp"
tar xzf "$ggmltar" -C "$build/tmp"
mv "$build/tmp/ggml-0.25.3" "$ggmlsrc"
mkdir -p "$build/hostbuild"
printf '#pragma once\n\n#define GGML_VERSION "v0.25.3"\n#define GGML_COMMIT  "8dd76549e6e714c064348a1c89d90ed7c6306727"\n' > "$build/hostbuild/ggml-version.h"

# The library's own base units, from the add_library(ggml-base ...) block of src/CMakeLists.txt at that
# commit, and the CPU backend's GGML_CPU_SOURCES with the ARM branch's two arch units, which is the
# whole of what an arm64 target compiles. The base units are here because the five C units the release
# build compiles are a subset: on arm64 the backend registry, the threading helpers and the dispatch
# all live in the C++ beside them, and the link names every symbol they hold.
ENGINE_C="ggml.c ggml-alloc.c ggml-quants.c"
ENGINE_CXX_BASE="ggml.cpp ggml-backend.cpp ggml-backend-meta.cpp ggml-threading.cpp"
ENGINE_CXX="ggml-cpu/ggml-cpu.c ggml-cpu/ggml-cpu.cpp ggml-cpu/repack.cpp ggml-cpu/iqp.cpp ggml-cpu/hbm.cpp ggml-cpu/quants.c ggml-cpu/traits.cpp ggml-cpu/binary-ops.cpp ggml-cpu/unary-ops.cpp ggml-cpu/vec.cpp ggml-cpu/ops.cpp ggml-cpu/arch/arm/quants.c ggml-cpu/arch/arm/repack.cpp"
ENGINE_FLAGS="-Os -fvisibility=hidden -fno-rtti -D_GNU_SOURCE -Dggml_EXPORTS"
ENGINE_INCLUDES="-I$ggmlsrc/include -I$ggmlsrc/include/ggml -I$ggmlsrc/src -I$ggmlsrc/src/ggml-cpu -I$build/hostbuild"

ggmlhost=$build/libggml-host.a
mkdir -p "$build/hostobj"
hostobjects=""
for source in $ENGINE_C $ENGINE_CXX_BASE $ENGINE_CXX; do
    object="$build/hostobj/$(echo "$source" | tr / _).o"
    # The C units with the compiler, the C++ ones with clang++ and the standard CMake asks for.
    case "$source" in
        *.cpp) compiler="xcrun clang++"; standard="-std=c++17" ;;
        *) compiler="xcrun clang"; standard="" ;;
    esac
    $compiler $common $ENGINE_FLAGS $standard $ENGINE_INCLUDES -c "$ggmlsrc/src/$source" -o "$object"
    hostobjects="$hostobjects $object"
done
xcrun libtool -static -o "$build/libggml-host.a" $hostobjects

# The dylib: the port's translation units with the renamed names, hidden, and the archive linked in.
# -dynamiclib rather than the gate's driver: the point is the arrangement, not the load command.
dylib() {
    output=$1
    sources=$2
    xcrun clang $common -I"$port" -I"$ggml/include" -fvisibility=hidden -fvisibility-inlines-hidden -fno-rtti \
        -dynamiclib -Wl,-all_load -o "$output" $sources "$ggmlhost" $dyliblibs
}

dylib "$build/libCharonMLCompute.dylib" "$port/MLCTypes14.m $port/MLCDevice15.m $port/MLCTensors14.m $port/MLCDescriptors14.m $port/MLCLayers14.m $port/CharonMLCGraph.mm"
xcrun clang $common -I"$port" "$here/port.m" $libs -o "$build/port"
xcrun clang $common "$here/system.m" $libs -framework MLCompute -o "$build/system"

"$build/system" > "$build/system.log"
"$build/port" "$build/libCharonMLCompute.dylib" > "$build/port.log"

# The comparison, case by case, on the bits of each float. Bit-identical is the rule for nineteen of
# the twenty-one cases, and the two exceptions are named with the size of their exception, measured:
#
#   tanh, tanhShrink - the framework's own tanh is one ulp off the correctly rounded value at 1, where it
#   answers 3f42f7d5 and tanhf, tanh in double and tanhf in double all answer 3f42f7d6; its tanhShrink
#   subtracts that value, which carries the error to four ulps at 1. Four is the whole of the allowance.
#
# It is per case and not one number for the file because a number wide enough for those two would be
# wide enough to hide a wrong constant: 0.797885f - the rounded spelling of the GELU's own multiplier,
# and what this file carried until the review measured it against the framework's descriptor - costs two
# ulps on the GELU, and would pass a four-ulp rule. With the GELU held to zero the wrong constant fails,
# and the mutant below is that exact value.
python3 - "$build/system.log" "$build/port.log" <<'CMP'
import re, sys

ULPS_ALLOWED = {"activation tanh": 4, "activation tanhShrink": 4}

def read(path):
    cases = {}
    for line in open(path):
        if "\t" not in line:
            continue
        name, values = line.rstrip("\n").split("\t", 1)
        fields = values.split(",")
        if len(fields) == 4 and all(re.fullmatch(r"[0-9a-f]{8}", f) for f in fields):
            cases[name] = [int(f, 16) for f in fields]
        else:
            cases[name] = None
    return cases

system, port = read(sys.argv[1]), read(sys.argv[2])
problems = []
if set(system) != set(port):
    problems.append("the two runs did not answer the same cases: %s" % sorted(set(system) ^ set(port)))
for name, left in system.items():
    right = port.get(name)
    if left is None or right is None:
        if left != right:
            problems.append("%s: host %r, port %r" % (name, left, right))
        continue
    for index, (a, b) in enumerate(zip(left, right)):
        allowed = ULPS_ALLOWED.get(name, 0)
        if a >> 23 != b >> 23 or abs(a - b) > allowed:
            problems.append("%s: value %d is 0x%08x against the host's 0x%08x (%d ulp, %d allowed)"
                            % (name, index, b, a, abs(a - b), allowed))
if problems:
    print("the port's answers differ from the host's:")
    for problem in problems[:20]:
        print("  " + problem)
    sys.exit(1)
print("the port computes all %d activations as the host does: bit for bit, bar the last bit of the"
      " two cases that go through the framework's own tanh" % len(system))
CMP

# A mutant of the port: the GELU's multiplier written the rounded way, which is the value this file
# carried until the review measured it against the framework's own descriptor. If the check cannot tell
# it apart, the check is reading a stored answer and not the code.
mutant() {
    rm -rf "$build/mutant"
    mkdir -p "$build/mutant"
    cp "$port"/*.m "$port"/*.mm "$port"/*.h "$build/mutant/"
    python3 - "$build/mutant/CharonMLCGraph.mm" <<'MUT'
import sys
path = sys.argv[1]
text = open(path).read()
before = text
text = text.replace("0.7978845608f * (x + 0.044715f * x * x * x)));",
                    "0.797885f * (x + 0.044715f * x * x * x)));")
assert text != before, "the mutant changed nothing"
open(path, "w").write(text)
MUT
    dylib "$build/mutant/libCharonMLCompute.dylib" "$build/mutant/MLCTypes14.m $build/mutant/MLCDevice15.m $build/mutant/MLCTensors14.m $build/mutant/MLCDescriptors14.m $build/mutant/MLCLayers14.m $build/mutant/CharonMLCGraph.mm"
    xcrun clang $common -I"$build/mutant" "$here/port.m" $libs -o "$build/mutant/port"
    "$build/mutant/port" "$build/mutant/libCharonMLCompute.dylib" > "$build/mutant.log" 2>&1 || true
    # The two logs are produced by the same code path, so the ulps the rule allows are identical in both
    # and cannot stand in for a difference: what a diff finds here is the mutant's own doing.
    if diff -q "$build/port.log" "$build/mutant.log" > /dev/null; then
        echo "the mutant is indistinguishable from the port: the check reads a stored answer, not the code"
        exit 1
    fi
    echo "the mutant is told apart, on the case it perturbs:"
    diff "$build/port.log" "$build/mutant.log" | grep "^[<>]" | head -2 | sed "s/^/  /"
}
mutant
echo "log=$build/system.log"
