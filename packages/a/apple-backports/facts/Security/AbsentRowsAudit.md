# Every `absent` row in the files this series touches, and whether `absent` is the right word

The policy: **`absent` is only for what the release truly cannot carry.** Unfinished work is **owed**,
recorded in the decision table and in a report, and it must not sit in the registry as an `absent` row —
because a reader scanning the registry for unreachable API finds it there and cannot tell it from a row
that describes a real absence.

**This series did not add any of the rows below.** Every one of them predates it: the series only ever
*removed* rows from `absent_Security.json` and `ios11.json`, and *added* rows to `ios13.json`. So per the
rule they are **left in place and listed as crutches with a fix path**, not deleted.

## The nine wrapper rows, and the "Network.framework" reason

| api | file | why `absent` is the wrong word |
| --- | --- | --- |
| `sec_identity_access_certificates()` | `absent_Security.json:10` | carryable: the port supplies the class |
| `sec_certificate_create()` | `ios11.json:26` | carryable: the port supplies the class |
| `sec_certificate_copy_ref()` | `ios11.json:25` | carryable: the port supplies the class |
| `sec_identity_create()` | `ios11.json:29` | carryable: the port supplies the class |
| `sec_identity_create_with_certificates()` | `ios11.json:30` | carryable: the port supplies the class |
| `sec_identity_copy_ref()` | `ios11.json:28` | carryable: the port supplies the class |
| `sec_identity_copy_certificates_ref()` | `ios11.json:27` | carryable: the port supplies the class |
| `sec_trust_create()` | `ios11.json:32` | carryable: the port supplies the class |
| `sec_trust_copy_ref()` | `ios11.json:31` | carryable: the port supplies the class |

**Is the reason a real fact?** *Directionally yes, and one line short of proven.* Eight of the nine carry
the reason *"the security types Network.framework hands its TLS callbacks, and this release has no
Network.framework"*, and that is the right shape: `SecProtocolTypes.h` declares the three types with
`SEC_OBJECT_DECL` and every function on them `API_AVAILABLE(ios(13.0))`, and they exist to hand
`SecTrustRef`/`SecIdentityRef`/`SecCertificateRef` to a TLS callback. **But the greps I ran for
Network.framework's own availability line returned nothing**, so the one line that reason rests on — that
Network.framework post-dates 6.1.3 — is **not independently verified here**, and this file says so rather
than repeating the claim as a fact.

**Where the carrier is.** None. That is the finding: the release carries no such call, and the port does
not either. The carrier is *owed*, and the design is settled — the port's own class implementing
`OS_sec_trust` / `OS_sec_identity` / `OS_sec_certificate`, holding the `CFTypeRef` in its own ivar, as
`clang -E` shows the type is `NSObject<OS_sec_*> *`.

**Fix path:** write them with a **real conformance compile** — `-Werror=protocol`, the `OS_object` shape
checked by `clang -E`, and a negative control — then flip the nine to `implemented`. The ninth row
(`sec_identity_access_certificates`) carries the generic *"arrived in iOS 13, and nothing in iOS 6 has
what it names"* reason instead, which is the same boilerplate as every arrival row and says nothing about
whether the release could carry it. **It could: the design above is the port's own.**

## The other `absent` rows in `absent_Security.json`, all predating this series

`SecPolicyCopyProperties`, `SecPolicyCreateWithProperties`, `SecTrustCopyCustomAnchorCertificates`,
`SecTrustCopyPolicies`, `SecTrustCopyResult`, `SecTrustEvaluateAsync`, `SecTrustSetOCSPResponse`,
`SecTrustEvaluateAsyncWithError`, `SecTrustCopyCertificateChain`, `SecAccessControlGetTypeID`,
`kSecUseDataProtectionKeychain`, `sec_identity_access_certificates` — every one carries the same generic
*"the X arrived in iOS N, and nothing in iOS 6 has what it names"*. That is an **arrival** statement, not
a hardware-absence statement, so `absent` overstates it for any of them the port could carry. None is
added by this series; all are **crutches with a fix path** (the decision table already decides most of
them `inert` with an effect stated, and the registry row should follow the decision).

Two rows in `ios11.json` state a *release* fact rather than an arrival one — `SecTrustSetSignedCertificateTimestamps`
("the release evaluates no certificate transparency") and the two `kSecAttrPersistentReference` spellings
("the keychain of iOS 6 was not read for this attribute"). Those are honest reasons and the spelling pair
is deliberate, but "not read" is a measurement that was never taken, so they are owed measurements rather
than absences.
