#!/bin/sh
# The end-to-end check for a minted Apple Music developer token: mint one from a key generated here
# and ask OpenSSL to verify the signature over the first two parts joined by a dot, which is what a
# JOSE verifier does.
#
# It exists because the two checks this module has are not enough on their own: the C differential
# proves the signature, and a base64url unit test proves the encoding, and neither can see a token
# that is well formed in each half and wrong as a whole. This can - and did, three times.
#
# The module is built for the host with the toolchain's own macOS Swift, because the port's
# swift-runtime ships its standard library for iOS only. The C the module reaches is compiled for the
# host here for the same reason.
#
#   sh run.sh

set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../../.." && pwd)
musickit=${CHARON_ROOT:-$root}/packages/m/musickit
charon=${CHARON_ROOT:-$root}
openssl=${OPENSSL:-openssl}
work=${TMPDIR:-/tmp}/musickit-jose-$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

# uECC's sources, wherever they are: the package fetches them, so a checkout that has not built the
# package has none. micro-ecc upstream is the same file and the recipe pins the commit.
uecc=$(ls -d "$HOME"/.xmake/packages/m/micro-ecc/*/* 2>/dev/null | head -1)
if [ -z "$uecc" ]; then
    echo "SKIP: charon@micro-ecc is not installed; build it once and this runs"
    exit 0
fi
swiftc=${SWIFTC:-$(xcrun -sdk macosx --find swiftc 2>/dev/null)}
[ -n "$swiftc" ] || { echo "SKIP: no macOS swiftc"; exit 1; }

"$openssl" ecparam -name prime256v1 -genkey -noout -out "$work/key.pem" 2>/dev/null
"$openssl" pkcs8 -topk8 -nocrypt -in "$work/key.pem" -out "$work/key8.pem" 2>/dev/null

xcrun -sdk macosx clang -O1 -w -I "$musickit/files/include" -I "$charon/packages/m/micro-ecc/files" \
     -I "$uecc/include" -c "$musickit/files/CharonC.c" -o "$work/shim.o"
xcrun -sdk macosx clang -O1 -w -I "$charon/packages/m/micro-ecc/files" -I "$uecc/include" \
     -c "$charon/packages/m/micro-ecc/files/CharonCKWebAuth.c" -o "$work/web.o"
xcrun -sdk macosx clang -O1 -w -I "$uecc/include" -c "$uecc/include/uECC.c" -o "$work/u.o"
[ -f "$work/u.o" ] || xcrun -sdk macosx clang -O1 -w -I "$uecc/include" -c "$uecc/../../../uECC.c" -o "$work/u.o" 2>/dev/null || \
    xcrun -sdk macosx clang -O1 -w -I "$uecc/include" -c "$uecc"/uECC.c -o "$work/u.o"

"$swiftc" -O -module-name M -import-objc-header "$musickit/files/include/MusicKitC.h" \
     -I "$musickit/files/include" -Xcc -I"$uecc/include" -Xcc -I"$charon/packages/m/micro-ecc/files" \
     -o "$work/mint" "$here/mint.mint.swift" "$musickit/files/MusicKit/Authorization.swift" \
     "$work/shim.o" "$work/u.o" "$work/web.o"

"$work/mint" "$work/key8.pem" ABCDE12345 TEAMID9999

python3 - "$work" <<'PY'
import base64, subprocess, sys, os
work = sys.argv[1]
parts = [open(os.path.join(work, 'part%d.txt' % i)).read().strip() for i in range(3)]
if len(parts) != 3 or parts[0] == 'nil':
    print("FAIL: mint returned no token")
    raise SystemExit(1)
def b64u(text):
    return base64.urlsafe_b64decode(text + '=' * (-len(text) % 4))
header, payload, signature = b64u(parts[0]), b64u(parts[1]), b64u(parts[2])
print("header  :", header.decode())
print("payload :", payload.decode())
print("signature bytes:", len(signature), "(JOSE ES256 is the raw r || s, 64)")
if len(signature) != 64:
    print("FAIL: the signature part is not the raw pair")
    raise SystemExit(1)
n = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC63FF51
if int.from_bytes(signature[32:], 'big') > n // 2:
    print("FAIL: the signature is not low-s")
    raise SystemExit(1)
def der_int(value):
    body = value.lstrip(b'\x00') or b'\x00'
    if body[0] & 0x80:
        body = b'\x00' + body
    return bytes([0x02, len(body)]) + body
inner = der_int(signature[:32]) + der_int(signature[32:])
open(os.path.join(work, 'sig.der'), 'wb').write(bytes([0x30, len(inner)]) + inner)
open(os.path.join(work, 'signing.txt'), 'w').write(parts[0] + '.' + parts[1])
subprocess.run(['openssl', 'ec', '-in', os.path.join(work, 'key.pem'), '-pubout',
                '-out', os.path.join(work, 'pub.pem')], capture_output=True)
verified = subprocess.run(['openssl', 'dgst', '-sha256', '-verify', os.path.join(work, 'pub.pem'),
                           '-signature', os.path.join(work, 'sig.der'),
                           os.path.join(work, 'signing.txt')], capture_output=True, text=True)
print("OpenSSL  :", verified.stdout.strip() or verified.stderr.strip().splitlines()[-1])
raise SystemExit(0 if 'Verified OK' in verified.stdout else 1)
PY
