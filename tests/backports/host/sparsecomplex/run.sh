#!/bin/sh
# The port's complex sparse family, as a dylib, held against the host's own Accelerate from a table of
# cases. Cases are data; the loop and the switch are the only code that reads them.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=${CHARON_WORKTREE:-$HOME/Git/projects/ios/charon/.agent-work/worktrees/api-bnns-sparse}
ACCELERATE=${ACCELERATE:-$root/packages/a/apple-backports/Accelerate}
COMPLEX=${COMPLEX:-$root/.agent-work/wip/sparsecomplex}
build=${SPARSECOMPLEX_BUILD:-$root/.agent-work/build/sparsecomplex}
rm -rf "$build"
mkdir -p "$build"

# The port's two halves in one dylib: the complex family, and the real half that owns the entry points
# the SDK declares with a void * matrix for, which a complex matrix answers on the same terms. It is
# dlopen'd RTLD_LOCAL | RTLD_FIRST and reached by dlsym, so nothing of the port's can interpose the
# host's and the host's Accelerate is the one the process already has.
xcrun clang -fobjc-arc -w -dynamiclib -I"$COMPLEX" -I"$ACCELERATE" -framework Accelerate -framework Foundation \
    -install_name @rpath/libComplexPort.dylib \
    -o "$build/libComplexPort.dylib" "$COMPLEX/SparseComplex18.m" "$ACCELERATE/SparseBLAS9.m"
xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable \
    -o "$build/differential-complex" "$here/differential.m" \
    -framework Foundation -framework Accelerate
"$build/differential-complex" "$build/libComplexPort.dylib" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" || true
echo "log=$build/log"
exit $result
