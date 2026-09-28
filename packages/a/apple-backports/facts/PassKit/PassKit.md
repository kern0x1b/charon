# PassKit on iOS 6: the measurement pass, and what it decides

`apple.objc.inventory` against the armv7 dyld shared cache of **6.1.3**, and it splits PassKit in two
before a line of code is written:

| class | in the release? | what it has there |
| --- | --- | --- |
| `PKPass` | **yes**, 90 instance methods | `-initWithData:error:`, `-initWithCoder:`, `-encodeWithCoder:`, `passTypeIdentifier`, `serialNumber`, `passNumber`, `organizationName`, `localizedDescription`, `expirationDate`, `activationDate`, `userName`, `deviceName`, `primaryAccountNumberSuffix`, `foregroundColor`, `backgroundColor`, `logoImage`, `-copyWithZone:`, `+supportsSecureCoding` |
| `PKPassLibrary` | **yes**, 34 instance methods | `-containsPass:`, `-passesOfType:`, `-cardAddedWithUniqueID:`, `-cardChangedWithUniqueID:`, `-cardRemovedWithPassTypeIdentifier:serialNumber:`, `+isPassLibraryAvailable` |
| `PKAddPassesViewController` | **yes**, 26 instance methods | `-initWithPass:`, `-initWithPass:orURL:`, `-initWithURL:`, `-setDelegate:`, `delegate`, `+isAvailable` |
| `PKPaymentAuthorizationViewController`, `PKPaymentRequest`, `PKPaymentSummaryItem`, `PKPaymentToken`, `PKPaymentAuthorizationController` | **no** | absent from the release entirely |

`apple.dyld`'s `first_releases` for the 75 classes the SDK 26.2 declares and this port does not
have: 8.0 ×7, 8.1 ×1, 9.0 ×6, 10.0.1 ×1, 10.1.1 ×2, 11.0 ×5, 12.0 ×1, 16.0 ×39, 18.0 ×9, and 3 in
no held release (the 26.x identity-document classes).

## What this decides

**The wallet is the release's own, so the wallet is not a backport.** `PKPass`, `PKPassLibrary` and
`PKAddPassesViewController` are in the ledger as *missing members* of classes the release already
carries -- `PKPassLibrary.lastUpdatedDate`, `PKPassLibrary.isPassLibraryAvailable` and the rest are
iOS 8/9/11 additions -- so they are **categories on the release's own classes**, not new classes.
That is a different shape of work from MapKit's and a much smaller one: no class symbol, no
`initWithData:error:` of our own, just the members over the release's own objects, and the gate's
category check is what proves they attach.

**Apple Pay is the hardware wall, and it is Apple's.** There is no Secure Element on a 4S, no Touch
ID, and no `PKPaymentAuthorizationController` in the release: `PKPaymentAuthorizationViewController`
and the whole payment request/token/summary family are absent, and Apple's own answer on a device
without the hardware is that there is nothing to authorize. So:

- `+[PKPaymentAuthorizationViewController canMakePayments]` and
  `+[PKPaymentRequest canMakePaymentsUsingNetworks:]` answer **NO**, which is the documented answer
  for a device with no Secure Element, and the registry entry says why in those words.
- The payment classes themselves are `absent` at the seam, each with the reason that the class is the
  Secure Element's own surface and the device has none -- **not** "absent because the release lacks
  it", which would be true and useless.
- `PKAddPaymentPassViewController` and `PKAddPaymentPassRequest` are the other half of the same
  wall: they are the screen that *authorizes* a payment pass, so they are `absent` with the same
  reason, while `PKAddPassesViewController` and `PKPass` (the wallet, not the payment) are the
  release's own and stay.

**One thing this pass settles the same way the MapKit `MKMapItem` one did:** the ruling said "PassKit:
`PKPassLibrary`/`PKPass` over the release's own Passbook". The measurement says there is nothing to
port underneath them -- they *are* the release's Passbook, at 90 and 34 methods respectively -- so
the work is the iOS 8-and-later members of those two classes, not a reimplementation of the library.
Writing a `PKPass` here would be a second copy of something the release already has, which
COORDINATION §9 forbids.

## The check for each family

- The wallet members: a host differential is impossible (macOS has no iOS Passbook), so the emulator
  call test at 6.1.3 is the check, plus the gate's own category check, which proves the members
  attach to the release's classes.
- `canMakePayments`: a straight read, and the emulator call test asks it and records the answer.

## The Secure Element and the wallet: what each member answers, and the measurement behind it

A 4S has no NFC and no Secure Element, so every member below is **answered**, not left out — a
missing symbol crashes an application on a selector, and these are selectors Apple's headers declare.
By kind, and the kind is the rule:

| kind | the answer | why |
| --- | --- | --- |
| a capability question | `NO` | Apple's own documentation gives `NO` where the hardware cannot do it |
| an operation | a completion carrying `PKPassKitErrorDomain` | the release's own domain, first exported at 6.0 |
| `presentSecureElementPass:` | `NO` | its own signature has no completion, so the return value is the answer |

**`PKPassKitErrorDomain` is linked, not defined.** First exported at **6.0** (the gate's own
`first_releases` over the armv7 cache of 6.1.3), so the release owns the string and the package only
names it. The host probe measures it at **20 bytes** and the host framework's own value.

**`PKUnsupportedVersionError` is 2** and is the nearest the header's own enumeration comes to "this
device cannot do that": `PKUnknownError = -1`, `PKInvalidDataError = 1`, `PKUnsupportedVersionError
= 2`, `PKInvalidSignature = 3`, `PKNotEntitledError = 4`. There is no "unsupported hardware" beside
them, and the reason is written down rather than left as an unexplained code.

**Three answers that are the measured one rather than the safe one**, each of which could be
otherwise and was not:

- `+isSuppressingAutomaticPassPresentation` says `NO`. It could say `YES`, which looks conservative.
  It does not: reporting a suppression that does not exist makes a caller restore a presentation that
  was never stopped.
- `-authorizationStatusForCapability:` says `NotDetermined`, **not** `Restricted`. `Restricted` claims
  the hardware was refused, and nothing was asked.
- `+passesOfType:` returns the **empty set, not `nil`**. `nil` says "we do not know", which is a
  different thing to say from "there are none".

## The 26.0 pair, and a correction

**An earlier revision of this file was wrong and said so twice.** It claimed that
`-authorizationStatusForCapability:` and `-requestAuthorizationForCapability:completion:` are in no
held SDK, and it wrote that `PKPaymentCapability` is declared nowhere. Measured in the **SDK 26.2** —
whose root is a *developer folder*, not a bare `.sdk`, which is why an earlier search under
`i/iphoneos-sdk/26.2/` found nothing:

```
$ grep -n "authorizationStatusForCapability\|requestAuthorizationForCapability" \
    .../iPhoneOS26.2.sdk/System/Library/Frameworks/PassKit.framework/Headers/PKPassLibrary.h
121:- (PKPassLibraryAuthorizationStatus)authorizationStatusForCapability:(PKPassLibraryCapability)capability API_AVAILABLE(ios(26.0), watchos(26.0));
124:- (void)requestAuthorizationForCapability:(PKPassLibraryCapability)capability completion:(void (^)(PKPassLibraryAuthorizationStatus status))completion API_AVAILABLE(ios(26.0), watchos(26.0));

$ grep -rc "PKPaymentCapability" .../Headers
count=0
```

**Both methods are real, and both types are real** — but the types are `PKPassLibraryCapability` and
`PKPassLibraryAuthorizationStatus`, **not** `PKPaymentCapability`, which is in no header at all. So the
selector was right and the type name in the row was invented.

**And the value was wrong, which is the worse half.** The same file claimed
`NotDetermined` is `0`. The 26.2 header (`PKPassLibrary.h:34-39`) says:

| enumerator | value |
| --- | --- |
| `PKPassLibraryAuthorizationStatusNotDetermined` | **−1** |
| `PKPassLibraryAuthorizationStatusDenied` | **0** |
| `PKPassLibraryAuthorizationStatusAuthorized` | 1 |
| `PKPassLibraryAuthorizationStatusRestricted` | 2 |

The port returned `0` and the row said `0` is `NotDetermined`. **`0` is `Denied`** — the answer that
says the hardware refused, the exact opposite of "nothing has been asked". Both are now
`PKPassLibraryAuthorizationStatusNotDetermined` (−1), by the header's own enumerator, and the probe
holds them to **−1**.

`PKLibraryCapability` has one case, `PKPassLibraryCapabilityBackgroundAddPasses`. Both enumerations
are declared in `CharonPassKit.h` **only when the build's SDK lacks them** (`#if !defined(__IPHONE_26_0)`),
because a second typedef of the same enum is a hard error and an SDK that has them must keep its own.
The 16.4 SDK this package is built against does not have them; the 26.2 SDK does.

## Two types the first pass of the objects named, and no SDK has

`PKPaymentNetworkCapabilities` and `PKPaymentActivationData` are in no PassKit header in 16.4. The
headers' own types are `PKMerchantCapability` and `NSData`. Both objects compiled clean against the
SDK anyway, so these were wrong in a way the build does not see; the probe's build is what found them.
`-signData:withSecureElementPass:completion:` takes **three** block arguments (signedData, signature,
error) and `-encryptedServiceProviderDataForSecureElementPass:completion:` passes an **`NSDictionary`**
— both from the headers, and both now matching them.

## Every selector in the registry, checked against the SDK 26.2's own headers

`tools/check-passkit-selectors.py` walks every method row of `registry/PassKit/` and asks the SDK 26.2
whether it spells that selector. A dotted name like `PKPassLibrary.addPassesWithCompletionHandler` is
not a selector, and a name no header declares is not real API — that is what r3 found, in eight rows,
and this is the check that keeps it from coming back.

The check is deliberately strict, because each of three weaker versions passed a name the review
rejected:

- grepping the joined selector fails on **every real** one — a header writes each keyword with its
  parameter's type and name between, so `addPasses:withCompletionHandler:` is never contiguous text;
- requiring only that each keyword occurs in the file passes the **joined** invented names, because
  `addPasses:` and `withCompletionHandler:` are both there, on *different* lines;
- requiring class and keyword on one line fails on Apple's real headers, which name the class once at
  its `@interface` and never again.

So the check takes the selector's keywords, requires them **all on one line with their colons**, and
requires that line to sit under the `@interface` of the class the row names. A zero-colon selector is
matched bare, because a method taking no argument is written `- (void)openPaymentSetup
API_AVAILABLE(ios(8.3))` with no colon after the name at all.

**31 method rows, 0 misses.** The negative control, which is the part that matters: the eleven invented
spellings r3 found, injected at once, give **9 misses and exit 1** — the two that survive are the 26.0
pair, which are real.

## The probe

`tests/backports/host/passkit/run.sh` compiles the objects onto **renamed** classes
(`charonHost_PKPassLibrary` and the rest, in `port-classes.m`) so the runner reaches the port through
the runtime and never the host's PassKit. **43 check lines over 33 member cases, 0 failures**, and
**two** mutants, because one kind of mutation going red is not evidence that another would:

| mutant | the line | what turns red |
| --- | --- | --- |
| 1 | `+canMakePayments` returns `YES` | exactly one case, `PAC.canMakePayments` |
| 2 | the shared error's code, `PKUnsupportedVersionError` → `PKInvalidSignature` | nine cases — the error's **value**, not just its presence |

The second mutant is the one the transcript was not checking before: an operation's error was written
on a continuation line indented four spaces, and the body filter wanted a letter after two spaces, so
**nine error checks were running and being diffed without appearing in either transcript**. The host
is the oracle for the error domain alone. Build and transcripts: `.agent-work/runs/passkit/`.
