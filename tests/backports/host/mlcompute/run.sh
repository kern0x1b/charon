#!/bin/sh
# cases.m and record.m, run once against the host's own MLCompute and once against the port's four
# translation units, with every name the port defines renamed so both answers can be in one process tree.
# The host's answers are what the port is held to; run.sh says nothing about whether they are right, and
# facts/MLCompute/ carries what was measured and where it came from.
#
# The names come from the port's own sources, not from a list kept here, so a class the port adds is
# renamed too.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
port=${MLCOMPUTE_PORT:-$here/../../../../packages/a/apple-backports/MLCompute}
registry=${MLCOMPUTE_REGISTRY:-$here/../../../../packages/a/apple-backports/registry/MLCompute}
build=${MLCOMPUTE_BUILD:-${TMPDIR:-/tmp}/charon-mlcompute-host}
rm -rf "$build"
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path)
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk -fobjc-arc -w -I$here"
libs="-framework Foundation -framework Accelerate"

# Every MLC name the port's own sources define, taken from the sources so that nothing can be added to one
# and missed here. The classes come from the @interface and @implementation lines and the functions from the
# definitions; the enumerations are header values with no symbol, and are renamed by the same list so a
# case may name one of them.
python3 - "$port" "$build/rename.h" <<'PY'
import os, re, sys
port, out = sys.argv[1], sys.argv[2]
names = set()
classes = re.compile(r"^@(?:interface|implementation)\s+(MLC\w+)", re.M)
functions = re.compile(r"^(?:NSString \*|NSUInteger|void|BOOL)\s+(MLC\w+)\(", re.M)
for entry in sorted(os.listdir(port)):
    if not entry.endswith((".m", ".h")):
        continue
    text = open(os.path.join(port, entry)).read()
    names.update(classes.findall(text))
    names.update(functions.findall(text))
    names.update(re.findall(r"^\s*(MLC\w+),?$", text, re.M))     # the enumerations of a case list
    names.update(re.findall(r"\b(MLCDataType\w+|MLCPoolingType\w+)\b", text))
# The port's own private names never collide with the framework's and are not renamed.
with open(out, "w") as handle:
    for name in sorted(names):
        handle.write("#define %s Charon%s\n" % (name, name))
print("renamed %d names" % len(names))
PY

# The system side: the host's framework answers every case.
xcrun clang $common "$here/record.m" "$here/cases.m" "$here/layer-cases.m" $libs -framework MLCompute -o "$build/system"
"$build/system" > "$build/system.log" 2>&1 || { echo "the system run failed:"; tail -20 "$build/system.log"; exit 1; }

# The port side: the same program with the port's own files, which answer every case in their place. A
# Metal device does not exist for the port to name, so the cases that ask MLCDevice about a GPU get the
# answer a machine with no GPU gives; the run.sh notes those lines below as the ones that are meant to
# differ, and they are the only ones.
xcrun clang $common -include "$build/rename.h" -I"$port" "$here/record.m" "$here/cases.m" "$here/layer-cases.m" \
    "$port/MLCTypes14.m" "$port/MLCDevice15.m" "$port/MLCTensors14.m" "$port/MLCDescriptors14.m" "$port/MLCLayers14.m" $libs -o "$build/port"
"$build/port" > "$build/port.log" 2>&1 || { echo "the port run failed:"; tail -20 "$build/port.log"; exit 1; }

# The names of the two must be the same set, or a case is answered by one and not by the other.
if [ "$(grep -c "	" "$build/system.log")" != "$(grep -c "	" "$build/port.log")" ]; then
    echo "the two runs answered a different number of cases: $(grep -c "	" "$build/system.log") and $(grep -c "	" "$build/port.log")"
    exit 1
fi
# The cases whose answer is about hardware this release has none of, and which are therefore meant to
# differ. A GPU through Metal and the Neural Engine: the host has both, the port has neither, and each side
# answers as a machine with what it has. The cases record the difference rather than hide it, and the facts
# say what the port answers and why.
names="gpuDevice|aneDevice|deviceWithType (GPU|CPU|Any|Any multiple)|cpuDevice|cpuDevice copy|deviceWithGPUDevices empty"
allowed="^($names)$"
tab=$(printf '\t')
diffout=$(diff "$build/system.log" "$build/port.log" || true)
system_only=$(echo "$diffout" | grep "^<" | sed "s/^< //" || true)
# Both sides of the diff, not only the left one: a case the port answered and the host did not is as much a
# divergence as the other way round, and looking at one side alone passed it.
port_only=$(echo "$diffout" | grep "^>" | sed "s/^> //" || true)
unexpected=$(printf '%s\n%s\n' "$system_only" "$port_only" | cut -f1 | grep -v -E "$allowed" | grep -v '^$' || true)
if [ -n "$unexpected" ]; then
    echo "the port answers differently where it should not:"
    echo "$unexpected" | while IFS= read -r name; do
        printf '%s\n%s\n' "$system_only" "$port_only" | grep -F "$(printf '%s\t' "$name")"
    done | head -40
    echo "log=$build/system.log $build/port.log"
    exit 1
fi
echo "the port answers as the host does on every case that is not about hardware this release lacks"
echo "the cases that differ, and are meant to:"
echo "$system_only" | grep -E "^($names)${tab}" | sed "s/^/  system /" | head -20
echo "$diffout" | grep "^>" | sed "s/^> //" | grep -E "^($names)${tab}" | sed "s/^/  port   /" | head -20
echo "cases=$(grep -c "	" "$build/system.log") log=$build/system.log"
