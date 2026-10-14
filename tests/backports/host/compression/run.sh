#!/bin/sh
# The Compression buffer API against the HOST's own libcompression, in one process: differential.c.
# The codecs are the pinned upstreams of packages/l/lzfse, packages/z/zlib and packages/l/lz4, fetched into a fresh
# directory under the run area at the same commits the recipes pin (never built inside a shared clone). The port's
# layer is packages/a/apple-backports/Compression/CompressionBuffer.c, built with its entry points renamed to
# charon_host_* so the host's and the port's are callable in the same process. Usage: run.sh [seed]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
seed=${1:-1}
build=${COMPRESSION_BUILD:-$root/.agent-work/runs/compression-host}
rm -rf "$build"
mkdir -p "$build/src"
fetch() {
    git clone -q "$2" "$build/src/$1"
    git -C "$build/src/$1" checkout -q "$3"
}
fetch lzfse https://github.com/lzfse/lzfse.git 88e2d2788b4021d0b2eb9fe2d97352ae9190f128
fetch zlib https://github.com/madler/zlib.git da607da739fa6047df13e66a2af6b8bec7c2a498
fetch lz4 https://github.com/lz4/lz4.git fdf2ef5809ca875c454510610764d9125ef2ebbd
src="$build/src"
for f in lzfse_decode lzfse_decode_base lzfse_encode lzfse_encode_base lzfse_fse lzvn_decode_base lzvn_encode_base; do
    xcrun clang -O2 -w -c -I"$src/lzfse/src" "$src/lzfse/src/$f.c" -o "$build/$f.o"
done
for f in adler32 crc32 deflate infback inffast inflate inftrees trees zutil; do
    xcrun clang -O2 -w -c -I"$src/zlib" "$src/zlib/$f.c" -o "$build/z_$f.o"
done
xcrun clang -O2 -w -c -I"$src/lz4/lib" "$src/lz4/lib/lz4.c" -o "$build/lz4.o"
renames="-Dcompression_encode_buffer=charon_host_compression_encode_buffer -Dcompression_decode_buffer=charon_host_compression_decode_buffer -Dcompression_encode_scratch_buffer_size=charon_host_compression_encode_scratch_buffer_size -Dcompression_decode_scratch_buffer_size=charon_host_compression_decode_scratch_buffer_size"
xcrun clang -O2 -w $renames -I"$src/lzfse/src" -I"$src/zlib" -I"$src/lz4/lib" -c "$root/packages/a/apple-backports/Compression/CompressionBuffer.c" -o "$build/port.o"
xcrun clang -O2 -w "$here/differential.c" "$build"/*.o -lcompression -o "$build/differential"
status=0
"$build/differential" "$seed" > "$build/log" 2>&1 || status=1
grep -v '^ok ' "$build/log" || true
echo "logs=$build"
exit $status
