#!/bin/sh
# run.sh - the port's P-256 signature and ECDH (charon@micro-ecc's arithmetic and this repository's
# JOSE around it) against the host's own Security.framework, in both directions: a signature the port
# makes must verify under the host's key, a signature the host makes must verify under the port's, and
# both sides must reach the same shared secret.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
package=${PACKAGE:-$here/../../../../packages/m/micro-ecc}
build=${SECKEYCURVE_BUILD:-$(mktemp -d)}
rm -rf "$build"
mkdir -p "$build"
clone="$build/micro-ecc"
git clone --quiet --depth 1 https://github.com/kmackay/micro-ecc.git "$clone" > /dev/null 2>&1
[ -f "$clone/uECC.h" ] || { echo "FAIL micro-ecc did not clone: no uECC.h in $clone"; exit 1; }
xcrun clang -std=c11 -Os -w -fvisibility=hidden -fno-strict-aliasing -I"$clone" -I"$package/files" \
    -c "$clone/uECC.c" -o "$build/uECC.o"
xcrun clang -std=c11 -Os -w -fvisibility=hidden -fno-strict-aliasing -I"$clone" -I"$package/files" \
    -c "$package/files/CharonCKWebAuth.c" -o "$build/wrapper.o"
# OpenSSL is the oracle for the exchange: the host's own SecKeyCopyKeyExchangeResult reads through
# an in-memory key and dies (measured, a SIGSEGV inside Security.framework), so the two P-256 pairs
# and the secret OpenSSL derives from them are made here and the differential compares that file
# with what the port derives from the same keys.
openssl ecparam -genkey -name prime256v1 -noout -out "$build/one.pem" 2>/dev/null
openssl ecparam -genkey -name prime256v1 -noout -out "$build/two.pem" 2>/dev/null
openssl ec -in "$build/one.pem" -pubout -out "$build/one.pub.pem" 2>/dev/null
openssl ec -in "$build/two.pem" -pubout -out "$build/two.pub.pem" 2>/dev/null
openssl pkeyutl -derive -inkey "$build/one.pem" -peerkey "$build/two.pub.pem" -out "$build/openssl.secret" 2>/dev/null
openssl ec -in "$build/one.pem" -text -noout 2>/dev/null | sed -n '/priv:/,/pub:/p' | sed -e 's/priv://' -e 's/pub://' -e 's/^[[:space:]]*//' -e '/^$/d' | tr -d ' \n:' | cut -c1-64 | fold -w2 > "$build/one.scalar"
openssl ec -in "$build/one.pem" -pubout -outform DER 2>/dev/null | tail -c 65 > "$build/one.point"
openssl ec -in "$build/two.pem" -text -noout 2>/dev/null | sed -n '/priv:/,/pub:/p' | sed -e 's/priv://' -e 's/pub://' -e 's/^[[:space:]]*//' -e '/^$/d' | tr -d ' \n:' | cut -c1-64 | fold -w2 > "$build/two.scalar"
openssl ec -in "$build/two.pem" -pubout -outform DER 2>/dev/null | tail -c 65 > "$build/two.point"
[ -s "$build/openssl.secret" ] || { echo "FAIL openssl made no shared secret: nothing to compare the port's against"; exit 1; }
for one in one two; do
    bytes=$(tr -d '\n' < "$build/$one.scalar" | wc -c | tr -d ' ')
    [ "$bytes" = 64 ] || { echo "FAIL openssl gave no 32 byte scalar for key $one ($bytes hex digits)"; exit 1; }
done
xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations -I"$here/../../device" -I"$package/files" \
    "$here/differential.m" "$here/../../device/check.m" "$build/uECC.o" "$build/wrapper.o" \
    -framework Foundation -framework Security -o "$build/differential"
"$build/differential" "$build"
