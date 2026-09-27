#!/bin/sh
# run.sh — checks the HAP crypto layer against the published test vector of every primitive it wraps:
# RFC 7748 for X25519, RFC 8032 for Ed25519, RFC 8439 for ChaCha20-Poly1305, RFC 5869 for HKDF and
# FIPS 180-4 for the two hashes. The crypto is C over a vendored Monocypher, so the check is a host C
# program: there is no framework, no SDK and no device in it, and a difference is a difference in the
# arithmetic rather than in a link.
#
# It builds Monocypher from packages/m/monocypher, the vendored copy, and not from the network: what is
# checked here must be the tree's bytes.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
charon=${CHARON:-$here/../../../..}
crypto="$charon/packages/a/apple-backports/HomeKit/CharonHapCrypto.m"
monocypher="$charon/packages/m/monocypher"
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build/monocypher"

# Monocypher's sources include each other as "monocypher.h", so the copies are laid out the way its own
# build lays them out: both sources and both headers in one directory.
cp "$monocypher/monocypher.c" "$monocypher/monocypher.h" "$monocypher/monocypher-ed25519.c" "$monocypher/monocypher-ed25519.h" "$build/monocypher/"

cc -O2 -I"$build" -I"$charon/packages/a/apple-backports/HomeKit" \
   -o "$build/vectors" "$here/vectors.c" "$crypto" \
   "$build/monocypher/monocypher.c" "$build/monocypher/monocypher-ed25519.c"

output=$("$build/vectors")
printf '%s\n' "$output"
case "$output" in
    *"all vectors agree"*) echo "ok" ;;
    *) echo "FAIL: a primitive disagrees with its published vector"; exit 1 ;;
esac
