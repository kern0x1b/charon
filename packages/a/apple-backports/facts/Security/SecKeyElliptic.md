# The elliptic half of SecKey, iOS 10: sign, verify, exchange, and what a key can do

`SecKeyCreateSignature`, `SecKeyVerifySignature`, `SecKeyCopyKeyExchangeResult` and
`SecKeyIsAlgorithmSupported` arrived with `SecKey` in iOS 10. `Security/SecKey100.m` already carries
the rest of that surface — random keys, the public half, encrypt and decrypt, the external
representation — over the release's own keychain, and recorded the four of these as `absent` because
iOS 6.1.3 has no curve to sign with. This is the other half of that decision.

## Why the arithmetic is a package and not a file in this one

iOS 6.1.3's CommonCrypto has no elliptic curve at all: the armv7 shared cache of that release exports
no `kCCAlgorithm*` symbol, no `CCEccKey` and no `kCCKeySizeEC256` (measured, `coordination/corpus` and
the cache itself), and `SecKeyCreateSignature` is iOS 8. So the curve arithmetic is taken rather than
written: `charon@micro-ecc` is Kenneth MacKay's micro-ecc, BSD-2, pinned at
`541b3a78026420a3e369c4c9281c396b5e531113`, built for the port's architecture as a static archive with
every symbol hidden. The JOSE around it — SHA-256, the minimal DER a JOSE verifier reads, the low-s
half, the `0x04` tag Apple's own Security writes — is `CharonCKWebAuth.c` in that package, and the
ECDH is now beside it.

Three entry points were added to that wrapper for this file, and they are the whole of the difference
between signing a message and signing a digest:

- `CharonCKDigestSignES256` and `CharonCKDigestVerifyES256` sign and verify a **digest the caller
  already took**. The wrapper's existing pair hashes the message first, and Security's
  `…ECDSASignatureDigestX962SHA256` says *Digest*: the 32 bytes the caller hashed are the message, and
  hashing them again would sign a different message than the one asked for. The message-level pair is
  now these two with a SHA-256 in front, so the DER reading and the low-s step exist once.
- `CharonCKSharedSecretES256` is the ECDH: `uECC_shared_secret` between a 32 byte private key and a
  65 byte uncompressed public point, which micro-ecc has and the wrapper had no use for.

The package's recipe also builds that wrapper now (`packages/m/micro-ecc/xmake.lua`). It did not:
`on_install` compiled `uECC.c` alone and installed only micro-ecc's own three headers, so
`CharonCKWebAuth.h` was in the package's source and not in its `include/`, and nothing that included it
could compile. That was a gap in the package, not in its users, and it is fixed at the source.

## Where the key material comes from, and how it is found

The key is not the port's: `SecKeyCreateRandomKey` (`Security/SecKey100.m`) makes it with the
**release's own** `SecKeyGeneratePair`, so it lives in iOS 6's keychain. Reading it back is what
`SecKeyCopyAttributeDictionary` and `SecKeyCopyPublicBytes` are for, the same two private entry points
`SecKey100.m` already uses.

The release does not say where in the stored bytes the private scalar is, and **that shape cannot be
read from here**: no release this port runs can be asked, and the host's own `SecKey` keeps a
different shape again — measured, its P-256 private external representation is 97 bytes, a `0x04` tag,
a length byte, then the scalar and the two coordinates, while a public key's is the 65 byte
uncompressed point.

So the scalar is **found, not assumed**: every 32 byte window of the stored bytes is tried as a
private key, the public point it derives is compared with the point the key itself publishes, and the
window that derives *that* point is the scalar. A blob whose shape nothing matches is refused with
`errSecParam`, so a wrong answer cannot be signed with — the check is what makes an unmeasurable shape
safe rather than a guess. The same comparison is what the host's 97 bytes are read with, and it is
what tells the two candidate windows apart on the host (offset 2 matches the published X, offset 1 does
not).

## What the port answers

- `SecKeyCreateSignature` returns a **DER** ECDSA signature (the SEQUENCE of two INTEGERs, each as
  short as its value needs) of the 32 byte digest given, in the **low-s half**, which is the form
  Apple's own `SecKeyCreateSignature` produces and the one a CloudKit web services token is checked
  against. A nil key or data, an algorithm other than `…ECDSASignatureDigestX962SHA256`, a digest that
  is not 32 bytes, and a key whose scalar cannot be found, each answer NULL with a `CFError` in
  `NSOSStatusErrorDomain` naming which; a failure of the curve itself is `errSecInternalError`.
- `SecKeyVerifySignature` answers true when that DER is a signature of that digest under the point the
  key publishes, false otherwise, and **a signature that is not a signature is a false and not an
  error** — which is what the host does, and what a caller of a verify loop relies on. The same four
  refusals as above, with `errSecParam`.
- `SecKeyCopyKeyExchangeResult` returns the **X coordinate of the shared point**, 32 bytes, for an
  algorithm of the ECDH family whose name ends in no digest, and the **SHA-256** of it for one that
  does — which is what Security's two families (`…StandardX963*`, `…CofactorX963*`) say they hand
  back, and what a caller needs to make a key with. There is no `kSecKeyAlgorithmECDH` constant in any
  SDK this port builds against, only that family, and the header of the function tells the caller to
  pass "kSecKeyAlgorithmECDH", which is the family's own prefix; so the *name* is matched.
- `SecKeyIsAlgorithmSupported` answers true for sign and verify with
  `kSecKeyAlgorithmECDSASignatureDigestX962SHA256` and for key exchange with any algorithm of that
  ECDH family, false for encrypt and decrypt (P-256 has no encryption in Security's own vocabulary
  either), false for every other algorithm — the RSA ones are `SecKey100.m`'s business and it answers
  for those — and false for a key the release publishes no point for. A nil key or algorithm is false.

## What was measured, and what was not

**Measured**, against the host's own Security.framework in both directions
(`tests/backports/host/seckeycurve`, 34 checks, none differing): a signature the port makes verifies
under the host's `SecKeyVerifySignature`, and one the host makes verifies through the port, for
messages of 0, 65 and 130 bytes; the host refuses the port's signature under SHA-384, so the
algorithm is not being ignored; the port refuses the host's signature for another message; every
signature is the low-s half on **both** sides over 24 samples, which is the form only Apple's own
producer takes; and the shape of what a P-256 key exports is read from the host — the 65 byte
uncompressed public point, the 97 byte private blob, and the two candidate windows in it that only one
of which derives the key's own published point.

The **ECDH is held to OpenSSL**, not to the host, and the reason is measured: the host's own
`SecKeyCopyKeyExchangeResult` reads through a key that is only in memory and dies with a SIGSEGV inside
Security.framework. So `run.sh` makes two P-256 pairs with OpenSSL, derives the secret OpenSSL makes
from them, and the differential compares that with what the port derives from the same two keys, byte
for byte — after checking that the scalar and the point OpenSSL printed are one key (the scalar derives
the point OpenSSL published for it) and not the other. The exchange is then made in both directions and
a third pair of keys is shown to give a third secret.

**Not measured: the release side.** The keychain extraction — which window of *iOS 6's* stored bytes is
the scalar — has not run on a device or in the emulator, and the gate that would build it has not run
(this is the patch the coordinator holds ungated, waiting for a heavy slot). The design is what makes
that safe rather than a claim that it is right: the scalar is accepted only when it derives the key's
own published public point, so the worst case on a shape nobody has read yet is a refusal, never a
signature of the wrong bytes.

**One thing this cost to find**, and it is the kind the differential exists for: the wrapper's
`CharonCKSignES256` hashed the message and passed `sizeof digest` to `uECC_sign`. When the digest-level
entry point was factored out, `digest` became a pointer parameter and `sizeof` became eight — so
micro-ecc was asked to sign an eight byte hash. The port's own verification accepted those signatures
(the same wrong length went in and came out), and only the host's `SecKeyVerifySignature` refused
them. The length is now `CC_SHA256_DIGEST_LENGTH` by name. What it costs is that `LAPublicKey`, `LAPrivateKey` and the rights API
of LocalAuthentication, which are built on these four, should not be carried before one device run has
confirmed the extraction — that is the next round, and it is named in the delivery rather than guessed at.
