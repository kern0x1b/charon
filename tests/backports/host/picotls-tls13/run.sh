#!/bin/sh
# One TLS 1.3 handshake between two picotls connections, to prove the TLS stack the port builds for
# a QUIC handshake is usable.
#
# The C is the same on both sides of the port: picotls's own sources, compiled here for the host
# because a pump that has never run is a guess, and for the device by the same recipe the package
# builds it with. Where the sources come from is the installed package when there is one and a
# checkout of the pinned commit when there is not, so this runs before the package is ever built.
#
# The certificate and the key are made here, by the host's own openssl, into the build directory: the
# port's tree holds neither, and both are thrown away with the directory.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
BACKPORTS=${BACKPORTS:-$here/../../../../packages}
PICOTLS_URL=https://github.com/h2o/picotls.git
PICOTLS_COMMIT=d6c3da61b47cc3ccecaf9aa093c24e4aafebd52a
build=${PICOTLS_BUILD:-${TMPDIR:-/tmp}/charon-picotls-tls13}

# the sources: the installed package's, or a checkout at the commit the recipe pins
source_root=$(ls -d "$HOME"/.xmake/packages/p/picotls/*/ 2>/dev/null | head -1 || true)
if [ -n "$source_root" ] && [ -d "${source_root}include/picotls.h" ]; then
    sources="$source_root"
    echo "picotls: the installed package"
else
    sources="$build/picotls"
    rm -rf "$build"
    mkdir -p "$build"
    git clone --quiet --depth 1 "$PICOTLS_URL" "$sources"
    git -C "$sources" checkout --quiet "$PICOTLS_COMMIT"
    echo "picotls: $PICOTLS_COMMIT checked out"
fi

mkdir -p "$build/obj"
# picotls-core, then picotls-minicrypto: the two archives the project itself builds, and the crypto is
# its own (minicrypto) rather than OpenSSL, which the port has no armv7 build of.
for source in lib/hpke.c lib/picotls.c lib/pembase64.c \
              deps/micro-ecc/uECC.c deps/cifra/src/aes.c deps/cifra/src/blockwise.c deps/cifra/src/chacha20.c \
              deps/cifra/src/chash.c deps/cifra/src/curve25519.c deps/cifra/src/drbg.c deps/cifra/src/hmac.c \
              deps/cifra/src/gcm.c deps/cifra/src/gf128.c deps/cifra/src/modes.c deps/cifra/src/poly1305.c \
              deps/cifra/src/sha256.c deps/cifra/src/sha512.c \
              lib/cifra.c lib/cifra/x25519.c lib/cifra/chacha20.c lib/cifra/aes128.c lib/cifra/aes256.c \
              lib/cifra/random.c lib/minicrypto-pem.c lib/uecc.c lib/asn1.c lib/ffx.c; do
    object="$build/obj/$(echo "$source" | tr / _).o"
    xcrun clang -std=c99 -Os -w -I "$sources/deps/cifra/src/ext" -I "$sources/deps/cifra/src" \
        -I "$sources/deps/micro-ecc" -I "$sources/deps/picotest" -I "$sources/include" \
        -c "$sources/$source" -o "$object"
done
xcrun clang -std=c99 -Os -w -I "$sources/include" -o "$build/probe" "$here/probe.c" "$build/obj"/*.o

# the certificate and the key, made here and left here
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
    -keyout "$build/key.pem" -out "$build/cert.pem" -subj "/CN=charon probe" >/dev/null 2>&1
openssl pkcs8 -topk8 -nocrypt -in "$build/key.pem" -outform DER -out "$build/key.der" 2>/dev/null
# picotls's own signer takes the raw secp256r1 scalar, which is the last 32 bytes of the PKCS#8 form
python3 - "$build/key.der" "$build/key.raw" <<'PY'
import sys
open(sys.argv[2], "wb").write(open(sys.argv[1], "rb").read()[-32:])
PY

"$build/probe" "$build/cert.pem" "$build/key.raw" > "$build/log" 2>&1 && result=0 || result=$?
grep -v '^ok ' "$build/log" | head -20 || true
echo "log=$build/log"
exit $result
