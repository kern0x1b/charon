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


for library, names in (('quad', ('quad-vertex', 'quad-fragment', 'quad-stagein', 'quad-flow', 'quad-constants', 'quad-fetch', 'depth-vertex', 'depth-fragment', 'quad-pair')), ('pair', ('fetch-pair',))):
    open('%s/%s.metallib' % (work, library), 'wb').write(b'MTLB' + bytes(16) + b''.join(module(name) for name in names))
PY

python3 "$root/tools/air2es/metallib2es.py" "$work/air2es" "$work/quad.metallib" "$work/quad.es2" >"$work/quad.out"
cat "$work/quad.out"

for file in library.json module0.vert module0.json module1.frag module1.json module2.vert module2.json module3.frag module3.json module4.frag module4.json module5.frag module5.json module6.vert module6.json module7.frag module7.json module8.frag module8.json; do
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
sed '1a\
#define charon_fc0 1\
#define charon_fc1 0.5\
#define charon_fc1_defined 1' "$work/quad.es2/module4.frag" >"$work/specialised.frag"
glslangValidator -S frag "$work/specialised.frag"
sed '/GL_EXT_shader_framebuffer_fetch/d; s/gl_LastFragData\[0\]/vec4(0.0)/' "$work/quad.es2/module5.frag" >"$work/fetching.frag"
glslangValidator -S frag "$work/fetching.frag"
glslangValidator -S vert "$work/quad.es2/module6.vert"
glslangValidator -S frag "$work/quad.es2/module7.frag"
glslangValidator -S frag "$work/quad.es2/module8.frag"
grep -q "GL_EXT_shader_framebuffer_fetch" "$work/quad.es2/module5.frag"

if python3 "$root/tools/air2es/metallib2es.py" "$work/air2es" "$work/pair.metallib" "$work/pair.es2" >"$work/pair.out"; then
    :
fi
grep -q 'FAIL fragment fetchPairFragment: reading the colour attachment in a function that writes several render targets' "$work/pair.out"
grep -q '"functions": \[\]' "$work/pair.es2/library.json"

echo "air2es: ok"
