# HAP's crypto, and the one part of it that is not here

HomeKit Accessory Protocol pairs in two steps, and both need key agreement this release has no API
for: `pair-setup` runs SRP-6a against the accessory's setup code, and `pair-verify` runs X25519 and
Ed25519 between the controller's and the accessory's long-term keys. What is here is everything under
both of them, checked against published vectors; what is not here is SRP-6a itself, and the reason is
the group's value.

## What is here, and what it is checked against

`CharonHapCrypto.m` is a thin layer: every primitive it exposes is either iOS 6's own CommonCrypto or
Monocypher's, and the layer exists so that the transport's code reads as HAP's derivation and not as a
call into a hash library. The checks are the published vectors of each primitive, run as a host test
(`tests/backports/host/hapcrypto`), and all nine agree:

| what | vector | verdict |
| --- | --- | --- |
| X25519 | RFC 7748 §5.2 vector 1 | agrees |
| Ed25519 sign | RFC 8032 §7.1 TEST 2 | agrees |
| ChaCha20-Poly1305 ciphertext | RFC 8439 §2.8.2 | agrees |
| ChaCha20-Poly1305 tag | RFC 8439 §2.8.2 | agrees |
| ChaCha20-Poly1305 open | its own ciphertext | opens |
| HKDF-SHA256 | RFC 5869 test case 1 | agrees |
| HKDF-SHA256, no salt | RFC 5869 test case 3 | agrees |
| SHA-256("abc") | FIPS 180-4 | agrees |
| SHA-512("abc") | FIPS 180-4 | agrees |

The AEAD is `crypto_aead_init_ietf`, not Monocypher's own `crypto_aead_init_x`. That distinction is
the whole reason this library is the one: HAP's session keys are **ChaCha20-Poly1305 with a 12-byte
nonce**, the IETF construction, and the XChaCha20-Poly1305 that Monocypher's own initialiser builds
would produce a ciphertext no accessory could read. Monocypher 4.0 seals through a context rather than
through a one-shot call, so `charon_hap_seal` initialises a context, writes once, and lets it go.

`crypto_aead_write` and `crypto_aead_read` also mean the context carries the counter, so a session
that needs several frames increments the nonce itself — which is what HAP's framing does, and what
`CharonHAPSession.m` does when it lands.

## The library, and why this one

Monocypher 4.0.2, vendored at `packages/m/monocypher`, is **BSD-2-Clause OR CC0-1.0** — the licence
states both, with CC0 as the one the author intends for the public domain and BSD as the fallback.
The recipe pins the tarball's sha256 (`38d0717…0879c`) and the vendored sources are the 4.0.2 release
it names; `LICENCE.md` is installed beside the library.

The alternatives were TweetNaCl, which is public domain and has the same AEAD, and `csrp` for SRP.
TweetNaCl's 2014-04-27 tarball is no longer served from any address this machine can reach (four URLs
tried, all 404), and the two that did answer were a 403 and a different project's 404. **`csrp` is not
used at all**, and that is the better answer rather than the fallback: SRP-6a is a hundred lines of
exponentiation and hashing over a modular exponentiation this package already has in
`CharonHAPBignum.m`, and that exponentiation is checked against an independent implementation on 72
primes from 32 to 3072 bits. A vendored SRP would be a second, unverified answer to a question the
package can already answer correctly.

## What is missing, and why

**SRP-6a is not implemented, because its group prime could not be read.**

`pair-setup` needs N and g for a 3072-bit group. The group is a 384-byte constant inside a real
HomeKit.framework, and it is not a formula — RFC 5054's 3072-bit group is a specific number whose hex
begins `AC7B…`, and I do not have it from a measurement. I searched the 12.0 arm64 cache for it two
ways: every 384-byte window in HomeKit's `__TEXT`, `__DATA` and `__DATA_CONST` whose top three bytes
are `FF FF FF` (128 windows, none of them a safe prime — the group's prime is not of that shape), and
every window beginning with the `AC 7B D4 91 92 D6 3C 93 6A DB 30 68` I remember the RFC's hex
starting with (no window at all).

A group prime written from memory is a value no release ships. It would parse, it would compute, and
it would make every `pair-setup` fail in a way that reads like a network fault — which is worse than an
honest refusal, because it sends whoever debugs it looking at the network.

**How to finish it.** Two routes, in order of preference:

1. Locate the group in a release. A 3072-bit safe prime in a dyld cache is recognisable: it is prime,
   `(p-1)/2` is prime, and it sits in a framework's data. The 16.0 and 18.0 arm64e HomeKit images were
   not searched (the search above was the 12.0 arm64 one), and HAP's SRP code may well keep the group
   in a different segment than `__DATA_CONST` — the `__TEXT,__const` section of the same image, or a
   `__DATA,__const` view of it. One more pass over those is likely to find it, and the reading is the
   same three steps the constants used.
2. If the group is not where it is looked for, then the group HAP uses is not the one this memory
   holds, and the right move is to read HAP's own documentation for it — which the coordinator can do
   and this port cannot, having no browser.

The rest of `pair-setup` is already in place underneath: `charon_bn_mont_pow` for both sides of the
exponentiation, `charon_hap_sha512` for the hash, `charon_hap_hmac_sha512` for the proofs, and
`charon_hap_equal` for comparing them. What is missing is the group and the four or five lines of
glue that use it.

## `pair-verify` is not blocked

`pair-verify` needs no group: it is X25519 over a per-session ephemeral against the accessory's stored
public key, Ed25519 over the four values, and HKDF-SHA-512 for the session keys. All of that is here
and checked. What is not written is the framing — the HTTP request, the JSON body and the session's
counter — which is ordinary code and is not blocked by anything in this file.

## A note on the seed

Monocypher's `crypto_ed25519_key_pair` **destroys the seed** it is given: it wipes the 32 bytes once
it has hashed them. `charon_hap_ed25519_keypair_from_seed` therefore copies the caller's seed and
hands the library the copy. A caller who passed a string literal straight through would have had the
library write zeroes into read-only memory; the host test found that, and it is why the wrapper is
shaped the way it is rather than as a one-line pass-through.
