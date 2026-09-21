#!/bin/sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
llvm=${LLVM:-$(brew --prefix llvm)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

"$llvm/bin/clang++" $("$llvm/bin/llvm-config" --cxxflags | sed 's/-fno-exceptions//') "$root/tools/air2es/air2es.cpp" -o "$work/air2es" \
    $("$llvm/bin/llvm-config" --ldflags --libs core bitreader) -Wl,-rpath,"$llvm/lib"

python3 - "$llvm" "$here/fixtures" "$work" <<'PY'
import subprocess, sys

llvm, fixtures, work = sys.argv[1:4]


def module(name):
    return subprocess.run([llvm + '/bin/llvm-as', '%s/%s.ll' % (fixtures, name), '-o', '-'], check=True, capture_output=True).stdout


for library, names in (('quad', ('quad-vertex', 'quad-fragment', 'quad-stagein', 'quad-flow')), ('pair', ('pair',))):
    open('%s/%s.metallib' % (work, library), 'wb').write(b'MTLB' + bytes(16) + b''.join(module(name) for name in names))
PY

python3 "$root/tools/air2es/metallib2es.py" "$work/air2es" "$work/quad.metallib" "$work/quad.es2" >"$work/quad.out"
cat "$work/quad.out"

for file in library.json module0.vert module0.json module1.frag module1.json module2.vert module2.json module3.frag module3.json; do
    if [ -n "${CHARON_WRITE_EXPECTED:-}" ]; then
        mkdir -p "$here/expected/quad"
        cp "$work/quad.es2/$file" "$here/expected/quad/$file"
    else
        diff -u "$here/expected/quad/$file" "$work/quad.es2/$file"
    fi
done

glslangValidator -S vert "$work/quad.es2/module0.vert"
glslangValidator -S frag "$work/quad.es2/module1.frag"
glslangValidator -S vert "$work/quad.es2/module2.vert"
glslangValidator -S frag "$work/quad.es2/module3.frag"

if python3 "$root/tools/air2es/metallib2es.py" "$work/air2es" "$work/pair.metallib" "$work/pair.es2" >"$work/pair.out"; then
    :
fi
grep -q 'FAIL fragment pairFragment: fragment output to render target 1' "$work/pair.out"
grep -q '"functions": \[\]' "$work/pair.es2/library.json"

echo "air2es: ok"
