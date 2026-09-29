# The SecKey functions of iOS 10

iOS 10 replaced the old key API with five functions that take a CFError instead of an OSStatus and name an algorithm
instead of a padding. A program built against them and run on iOS 6 does not fail politely: the weak reference is NULL
and the call goes to address zero on the path that makes its keys, which is usually the path that starts the program.
None of the five needs anything iOS 6 has not got.

Read from: the armv7 shared cache of iOS 6.1.3, for what Security exports and for the armv7 code of the private entry
points, disassembled; the caches of iOS 6.0, 6.1.6, 7.0, 7.1.2, 8.0, 8.4.1, 9.0, 9.3.6 and the armv7s cache of 10.3.4,
which all export the same private entry points, so no band of the package loses them; `SecKey.h` and `SecItem.h` of SDK
16.4 for the signatures, the padding values and the algorithm names; the host's own Security for the shape of the
CFError and of the two external representations.

## What iOS 6 already has

Security of iOS 6.1.3 exports `SecKeyGeneratePair`, `SecKeyEncrypt`, `SecKeyDecrypt`, `SecKeyRawSign`,
`SecKeyRawVerify` and `SecKeyGetBlockSize` as public API, and these private entry points, which are the ones that make
the difference:

- `SecKeyCopyPublicBytes(SecKeyRef, CFDataRef *)` at 0x32e90511. It asks the key's own class for its public bytes and
  answers `errSecUnimplemented` for a class that has none.
- `SecKeyCreateFromPublicData(CFAllocatorRef, CFIndex algorithmID, CFDataRef)` at 0x32e90545, which reads the data's
  bytes and length and hands them to `SecKeyCreateFromPublicBytes` at 0x32e90525; that one divides the algorithm
  identifier - 1 is RSA and 3 is elliptic curve - and calls `SecKeyCreateRSAPublicKey` or `SecKeyCreateECPublicKey`
  with the encoding those two want. The port never names that encoding itself: the release's own function knows it.
- `SecKeyGetAlgorithmID(SecKeyRef)` at 0x32e904fd, which asks the key's class and answers 1 where the class does not
  say, so an RSA key of the release answers 1.
- `SecKeyCopyAttributeDictionary(SecKeyRef)`, the dictionary a key hands to `SecItemAdd`.

## The five functions

`SecKeyCreateRandomKey` hands the parameters to `SecKeyGeneratePair` untouched, releases the public half and answers
the private key, which is what iOS 10 answers. `kSecAttrIsPermanent`, `kSecAttrKeyType`, `kSecAttrKeySizeInBits`,
`kSecPrivateKeyAttrs` and `kSecPublicKeyAttrs` are all names iOS 6 exports and reads itself, so the meaning of the
dictionary is the release's, not the port's. A key type the release's generator will not make - and it has RSA and
elliptic curve - comes back as NULL and a CFError holding its OSStatus.

`SecKeyCopyPublicKey` is `SecKeyCopyPublicBytes` followed by `SecKeyCreateFromPublicData` with the key's own algorithm
identifier. Where the release cannot serialise a public half it answers NULL, which the header states is the answer
when no public key is available.

`SecKeyCreateEncryptedData` and `SecKeyCreateDecryptedData` turn the algorithm into the padding of the release's own
`SecKeyEncrypt` and `SecKeyDecrypt`, in a buffer of `SecKeyGetBlockSize` bytes cut to the length the release wrote:

| algorithm | padding of iOS 6 |
| --- | --- |
| `kSecKeyAlgorithmRSAEncryptionRaw` | `kSecPaddingNone` |
| `kSecKeyAlgorithmRSAEncryptionPKCS1` | `kSecPaddingPKCS1` |
| `kSecKeyAlgorithmRSAEncryptionOAEPSHA1` | `kSecPaddingOAEP` |

`SecKeyCopyExternalRepresentation` answers the PKCS#1 bytes of the key it is given: 270 of them for the public half of
a 2048-bit RSA key, a `SEQUENCE` of the modulus and the exponent, and 1193 for the private key, a `SEQUENCE` that
starts with a version of zero and holds nine integers. The port takes the data out of the key's attribute dictionary
and parses it before it trusts it: nine integers starting at zero is a private key and is answered as it stands.
Otherwise it asks for the public bytes and answers them only where the key is proven to be a public one - either its
attribute dictionary holds exactly those bytes, which a private key's does not, or the dictionary names the key class
as public. Where neither holds, the answer is NULL and a CFError.

## What it refuses, and why it refuses rather than guesses

- Every algorithm outside the three above - `RSAEncryptionOAEPSHA224` and the rest of the digests,
  the `AESGCM` variants, and everything elliptic-curve - is refused with NULL and a CFError of
  `errSecParam` whose message names the algorithm and the key, the way the system refuses an algorithm a key cannot
  perform. iOS 6's `kSecPaddingOAEP` carries no choice of digest and is SHA-1, so answering an OAEP-SHA256 call with
  SHA-1 padding would be a different cipher text under the name of the one that was asked for.
- A private key whose external representation the release does not keep is refused rather than answered with its public
  half. A caller that asks for a key's representation and is handed the public half sends the wrong thing and never
  learns of it, which is the failure this package exists to avoid.
- Every CFError is domain `NSOSStatusErrorDomain`, code the OSStatus, `userInfo` with `NSDescription`, which is the
  shape the host's own Security produces; a caller that reads `error.code` reads the release's own status.

## What is not carried

**Nothing about `SecKeyCreateWithData` is claimed, in either direction.** It is **owed**: the release
*could* carry it, since `SecItemAdd` and the key classes are there, but no entry point has been written.
`DecisionTable.md` marks the row **owed** for that reason, and the registry carries **no row for it at
all** - not `absent`, because `absent` is for API only the hardware lacks and this is unfinished work,
and not `implemented`, because there is no function. A caller building a key from raw bytes on 6.1.3 gets
a NULL weak reference, and that is unrecorded on purpose until the entry point exists.

### Owed, in full

- **`SecKeyCreateWithData`** - the entry point itself, then its row.
- **The guest measurement** of the keychain halves: `SecKeyCopyAttributes`'s shaping, the key lookup
  inside `SecKeyIsAlgorithmSupported`, and an actual `SecKeyRawSign` / `SecKeyRawVerify` round trip
  through the padding mapping. Every host case so far has driven the **pure** half with no key and no
  keychain, so the padding mapping is checked and the signing is not. The slot is the coordinator's to
  give; nothing is owed to a run that has not happened.
- The 11 `SecTrust*`, 4 `SecCertificate*`, 2 `SecPolicy*` and 1 `SecAccessControl*` rows.
- The 59 inert rows, and the export.

The other five are carried, and their rows are in `registry/Security/ios10keys.json`:

| API | What it does on the release |
| --- | --- |
| `SecKeyCopyAttributes` | the key's own keychain entry, asked with two-argument `SecItemCopyMatching` (`kSecKey.h:1162`) |
| `SecKeyIsAlgorithmSupported` | the key's class against the table: four RSA PKCS1 digest algorithms for sign and verify, two RSA encryption ones, EC and key exchange refused |
| `SecKeyCreateSignature` | `SecKeyRawSign` with the padding the algorithm names, `0x8002` and `0x8003`-`0x8006` (`kSecKey.h:198-218`) |
| `SecKeyVerifySignature` | `SecKeyRawVerify` with the same padding, so its PKCS1 padding is *checked* (`kSecKey.h:684-690`) |
| `SecKeyCopyKeyExchangeResult` | **inert**: always NULL, with the `CFError` left NULL. iOS 6.1.3 has **no EC key type at all** - `kSecAttrKeyTypeECSECPrimeRandom` is `API_AVAILABLE(macos(10.12), ios(10.0))` (`SecItem.h:804-805`) against `kSecAttrKeyTypeRSA`'s `ios(2.0)` (`SecItem.h:784-785`) - so no `SecKeyRef` can hold an EC private key and there is no peer to exchange with. No secret is invented |

A refusal on the first four is NULL or `false` **with no `CFError` set**, because each signature's
documentation names no domain or code for it, and the port does not manufacture one a caller would
handle as though the SDK had promised it.

### A disagreement this file had with itself

An earlier revision of this file listed all six as "stay absent ... nothing has asked for them yet",
while `DecisionTable.md` marked all six **implemented**. Both were wrong about the same five rows in
opposite directions, and neither matched the tree: five entry points existed and one did not. The
registry is what is state, so it now carries five rows in `ios10keys.json` (four implemented, one
inert) and one in `absent_Security.json`. The table's middle column is a **decision** - whether the port
*could* act - and its count line is a count of decisions, which is how a row marked implemented there
came to be a function that was never written.
