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

## The two payment controllers are carried as CLASSES, not absent

**The finding that changed this**, from the 6.1.3 gate over the first real library build:

```
categories whose class neither iOS 6.1.3 nor the package exports ...
  PKPaymentAuthorizationController(CharonSecureElement: ...) and
  PKPaymentAuthorizationViewController(CharonSecureElement: ...)
```

A category on a class nobody carries is dead code: the loader has nothing to attach it to. Both
classes are measured absent from the armv7 cache of 6.1.3, and the registry said the CLASS was
`absent` (10.0 and 8.0) while its six members said `implemented` — a contradiction the gate found
and the registry did not.

**The class exists on a device without a Secure Element.** That is the whole of the correction, and
it is the standing rule: `absent` is for absent *hardware*, and the Secure Element is hardware, but
its absence is not why the class is missing. A 4S-era iPod answers `+canMakePayments` **NO** — it does
not lack the class, it answers the question. So:

| class | release | base | what it answers |
| --- | --- | --- | --- |
| `PKPaymentAuthorizationController` | 10.0 | `NSObject` | three capability questions, all `NO` |
| `PKPaymentAuthorizationViewController` | 8.0 | `UIViewController` | two capability questions, all `NO` |

**One object per release**, which is the release-split gate's own rule and not tidiness: the class is
8.0 and `+canMakePaymentsUsingNetworks:capabilities:` is 9.0, so that member is in
`PKPaymentAuthorizationViewController9.m` and the class and its 8.0 members are in
`PKPaymentAuthorizationViewController8.m`. An object carrying API of two releases is what that gate
refuses. The 9.0 member is a category on the port's own class and the 8.0 object implements that
class, so together they are one class in two objects.

**What stays absent, and it is the hardware and not the backlog**: `-initWithRequest:` takes a
`PKPaymentPass`, and **there is no `PKPaymentPass` in this release at all** (measured absent from the
armv7 cache of 6.1.3), so a payment sheet over a pass that cannot exist is a sheet with nothing in it.
The delegate callbacks are the same: they would report a presentation that cannot happen.

**The stand-in**, following `CHARON_MEDIAPLAYER_STANDIN` / `MPMediaItemStandin.h` in MediaPlayer: a
host that already has Apple's `PKPaymentAuthorizationController` gives a second `@implementation` of
the name as a duplicate symbol, and the probe would then measure Apple's class. `CharonPassKitStandin.h`
declares both classes as the SDK declares them and carries `PKMerchantCapability`, which the release's
own headers do not declare and which the members are spelled with.

**The probe asks whether the class is there, not only whether a member answers**: 86 check lines over
54 member cases, 0 failures, all four mutants red. Six of the lines are the two controllers, and one of
them checks the *superclass* — a renamed subclass of the host's class would answer all five questions
correctly while being a class the release never had. The five value classes below add their own class,
superclass and member cases, and the fourth mutant is theirs (the update's default status,
`PKPaymentAuthorizationStatusSuccess` → `Failure`, which turns exactly the three status cases red and
leaves a reworded comment in the same file green).

## The five value classes of iOS 11, and why they are carried rather than absent

`PKPaymentAuthorizationResult`, `PKPaymentRequestUpdate`, `PKPaymentRequestShippingContactUpdate`,
`PKPaymentRequestShippingMethodUpdate` and `PKPaymentRequestPaymentMethodUpdate` were `absent` with the
Secure Element's reason, which is the reason this page already overturned for the two controllers:
**`absent` is for absent _hardware_, and the Secure Element's absence is not why a class is missing.**
These five are further from the hardware than the controllers were -- none of them touches a Secure
Element, a card, a pass or a sheet. What decides them is that they are the **value types of the delegate
completion blocks**, and this port already exports the two classes those blocks belong to:

| the port exports | the header's method over it | the class the handler takes |
| --- | --- | --- |
| `PKPaymentAuthorizationViewController` (8.0, `PKPaymentAuthorizationViewController8.m`) | `-paymentAuthorizationViewController:didAuthorizePayment:handler:` (`PKPaymentAuthorizationViewControllerDelegate.h:60`) | `PKPaymentAuthorizationResult` |
| the same | `-paymentAuthorizationViewController:didSelectShippingContact:handler:` (`:88`) | `PKPaymentRequestShippingContactUpdate` |
| the same | `-paymentAuthorizationViewController:didSelectShippingMethod:handler:` (`:74`) | `PKPaymentRequestShippingMethodUpdate` |
| the same | `-paymentAuthorizationViewController:didSelectPaymentMethod:handler:` (`:98`) | `PKPaymentRequestPaymentMethodUpdate` |
| `PKPaymentAuthorizationController` (10.0, `PKPaymentAuthorizationController10.m`) | the same four on `PKPaymentAuthorizationController.h:64, :97, :92, :108` | the same four |

Every one of those methods is `API_AVAILABLE(macos(11.0), ios(11.0), watchos(4.0))` and every one of the
five classes is `API_AVAILABLE(macos(11.0), ios(11.0), watchos(4.0))` in the same header file,
`PKPaymentRequestStatus.h`. They replaced the 8.0 `-completion:(void (^)(PKPaymentAuthorizationStatus))`
(the 8.0 method is `API_DEPRECATED(..., ios(8.0, 11.0))` in the same header). So without this object the
port exports a payment controller whose delegate **cannot be written at all**: the SDK's own header names
a type the port has not got. That, and not the hardware, is what makes these five the port's to carry.

### The measurement, at both band ends, with the control

```
$ CHARON_ROOT=<worktree> xmake l tools/corpus/cache-census.lua PKPayment
6.1.3     ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7
         images 524, of which naming PKPayment 0
         classes 11378, of which PKPayment* 0
         protocols 1171, of which PKPayment* 0
4.3       ~/.charon/dyld/4.3/dyld_shared_cache_armv7
         images 354, of which naming PKPayment 0
         classes 7187, of which PKPayment* 0
         protocols 564, of which PKPayment* 0
11.0      ~/.charon/dyld/11.0/dyld_shared_cache_arm64
         images 1258, of which naming PKPayment 0
         classes 52768, of which PKPayment* 267 (PKPayment PKPaymentActivationResponse ...)
control: 307 name(s) beginning PKPayment found in this run, so a zero on another rung is the release's and not the reader's
```

6.1.3 and 4.3 are the two rungs the package deploys on and the two ends of the absence, and 11.0 is in the
run as the control that makes their zeros mean something: the same reader, the same command, one rung
where the name is there. Transcript: `.agent-work/runs/d10-passkit-r11/census-payment.txt`.

Which release the name is real in, over the whole held ladder:

```
$ python3 tools/cache-index/first-rung.py --rungs _OBJC_CLASS_\$_PKPaymentAuthorizationResult
first-rung.py: read 50 per-release index(es) in 30.44s
_OBJC_CLASS_$_PKPaymentAuthorizationResult	11.0,12.0,16.0,18.0
```

all five answer **11.0**, and `PKPaymentAuthorizationStatus` answers `NONE` -- which is what an
enumeration is: it has no symbol at all, so it is the SDK's declaration and not a release's.

### What Apple's own 11.0 has, measured class by class

```
$ CHARON_ROOT=<worktree> xmake l tools/corpus/objc-inventory.lua \
    ~/.charon/dyld/11.0/dyld_shared_cache_arm64
```

| class | superclass | image | Apple's own instance selectors |
| --- | --- | --- | --- |
| `PKPaymentAuthorizationResult` | `NSObject` | PassKitCore | `-errors`, `-initWithStatus:errors:`, `-setErrors:`, `-setStatus:`, `-status` |
| `PKPaymentRequestUpdate` | `NSObject` | PassKitCore | `-initWithPaymentSummaryItems:`, `-paymentSummaryItems`, `-setPaymentSummaryItems:`, `-setStatus:`, `-status` |
| `PKPaymentRequestShippingContactUpdate` | `PKPaymentRequestUpdate` | PassKitCore | `-errors`, `-initWithErrors:paymentSummaryItems:shippingMethods:`, `-setErrors:`, `-setShippingMethods:`, `-shippingMethods` |
| `PKPaymentRequestShippingMethodUpdate` | `PKPaymentRequestUpdate` | PassKitCore | **none** |
| `PKPaymentRequestPaymentMethodUpdate` | `PKPaymentRequestUpdate` | PassKitCore | `-errors`, `-initWithErrors:paymentSummaryItems:`, `-setErrors:` |

Three things in that table are what the port's object is built from. The superclass chain is Apple's own,
which is why the three updates are subclasses of `PKPaymentRequestUpdate` and not of `NSObject`. And
`PKPaymentRequestShippingMethodUpdate` has **no instance selector of its own at all** -- measured, not
inferred from the header -- so what the port adds for it is the class, and its storage is the base
class's reached through it.

**And one thing in that table is deliberately NOT carried.** Apple's own binary also has, on all five,
`-init`, `-initWithCoder:`, `-encodeWithCoder:`, `+supportsSecureCoding` and the `NSSecureCoding`
conformance, plus the private initializers `-initWithStatus:paymentSummaryItems:`,
`-initWithStatus:errors:paymentSummaryItems:shippingMethods:` and, on the payment-method update, a
private `-peerPaymentQuote`. **No SDK header declares any of them**: `rg -c NSSecureCoding` over
`PKPaymentRequestStatus.h` answers **0** in the SDK 26.2 and **0** in the SDK 16.4 the package is built
against. A name no header declares is not API this package carries -- that is the rule
`tools/check-passkit-selectors.py` enforces on the method rows, and the reason the 26.2 surface TSV has
no row for a coding method of these classes.

### What a caller gets on this release, which is the honest half

The object stores what the delegate put in it and hands the same values back. `-initWithStatus:errors:`
keeps a **copy** of the errors in the order they were passed -- the header says they are ordered most
serious first (`PKPaymentRequestStatus.h:31-33`) -- and the status is the one the delegate passed,
because that initializer takes it. The one `status` this port CHOOSES is the update's:
`-initWithPaymentSummaryItems:` sets `PKPaymentAuthorizationStatusSuccess`, which is the header's own
stated default for that property (`PKPaymentRequestStatus.h:49-51`, "PKPaymentAuthorizationStatusSuccess
by default") and the enumeration's own zero, since `PKConstants.h:65` declares
`PKPaymentAuthorizationStatus` with no explicit values. The three `null_resettable` error properties
answer the **empty list**, never `nil`, because `null_resettable` is Apple's own promise that the getter
does not.

What a caller **cannot** fill on this device is the other two lists, and the object does not paper over
it: there is no `PKPaymentSummaryItem` in 6.1.3 at all (registry row, 8.0, absent) and no
`PKShippingMethod` either. Both are measured rather than assumed --
`python3 tools/cache-index/first-rung.py` with `_OBJC_CLASS_$_PKPaymentSummaryItem` and
`_OBJC_CLASS_$_PKShippingMethod` answers **8.0** for each, which is above 6.1.3 and below the 11.0 the
census found them on. So in practice `paymentSummaryItems` and `shippingMethods` answer the **empty
array** here, which is what the release's own missing classes leave and not a value this port invents. Both properties copy, so a delegate that mutates the array it passed
cannot change what it already reported.

### One object, and what keeps the later releases out of it

`PKPaymentRequestStatus11.m` is the only object, and all five classes first export at 11.0 together
(measured above), which is what `tools/release-split.lua` reads. The SDK the package compiles against is
16.4, and its `PKPaymentRequestStatus.h` declares every property of these classes up to 16.4 --
`orderDetails` (16.0), `shippingMethods` (15.0), `multiTokenContexts`, `recurringPaymentRequest`,
`automaticReloadPaymentRequest` (16.0), `deferredPaymentRequest` (16.4). Auto-synthesis would put all
six accessors in an 11.0 object, so each is `@dynamic`, which is what the tree uses for a property this
release's object does not own (`PDFAnnotation11.m`'s `-bounds`, `MPSImageThreshold13.m`). The built
object's own member list is the check that they stayed out:

```
$ xmake l tools/corpus/objc-inventory.lua PKPaymentRequestStatus11.o armv7
class | PKPaymentAuthorizationResult          |                     | -.cxx_destruct,-errors,-initWithStatus:errors:,-setErrors:,-setStatus:,-status
class | PKPaymentRequestPaymentMethodUpdate    | PKPaymentRequestUpdate | -.cxx_destruct,-errors,-initWithErrors:paymentSummaryItems:,-setErrors:
class | PKPaymentRequestUpdate                 |                     | -.cxx_destruct,-initWithPaymentSummaryItems:,-paymentSummaryItems,-setPaymentSummaryItems:,-setStatus:,-status
class | PKPaymentRequestShippingMethodUpdate   | PKPaymentRequestUpdate |
class | PKPaymentRequestShippingContactUpdate  | PKPaymentRequestUpdate | -.cxx_destruct,-errors,-initWithErrors:paymentSummaryItems:shippingMethods:,-setErrors:,-setShippingMethods:,-shippingMethods
```

Every name in that list is one the SDK's own header declares for **11.0**, and `PKPaymentRequestShippingMethodUpdate`
is empty in the same way Apple's own is.

And the gate's own check, run over that object compiled to a scratch folder beside a record of the SDK it
was compiled against (`.agent-work/runs/d10-passkit-r11/objects/`), which is what release-split reads:

```
$ xmake l tools/release-split.lua .agent-work/runs/d10-passkit-r11/objects
release-split: clean, every object file's symbols first-appear in one release (1 files, 10 symbols, 50 releases checked)
PKPaymentRequestStatus11.o	_OBJC_CLASS_$_PKPaymentAuthorizationResult	11.0
PKPaymentRequestStatus11.o	_OBJC_CLASS_$_PKPaymentRequestPaymentMethodUpdate	11.0
PKPaymentRequestStatus11.o	_OBJC_CLASS_$_PKPaymentRequestShippingContactUpdate	11.0
PKPaymentRequestStatus11.o	_OBJC_CLASS_$_PKPaymentRequestShippingMethodUpdate	11.0
PKPaymentRequestStatus11.o	_OBJC_CLASS_$_PKPaymentRequestUpdate	11.0
PKPaymentRequestStatus11.o	_OBJC_METACLASS_$_PKPaymentAuthorizationResult	11.0
PKPaymentRequestStatus11.o	_OBJC_METACLASS_$_PKPaymentRequestPaymentMethodUpdate	11.0
PKPaymentRequestStatus11.o	_OBJC_METACLASS_$_PKPaymentRequestShippingContactUpdate	11.0
PKPaymentRequestStatus11.o	_OBJC_METACLASS_$_PKPaymentRequestShippingMethodUpdate	11.0
PKPaymentRequestStatus11.o	_OBJC_METACLASS_$_PKPaymentRequestUpdate	11.0
```

Ten symbols, every one of them 11.0, and no `@dynamic` property among them -- which is the mixed-release
defect this file's shape exists to prevent, measured rather than asserted.

### The probe, and two things it found

`tests/backports/host/passkit/run.sh`, transcript in `.agent-work/runs/d10-passkit-r11/probe-run.txt`:

```
ok every transcript reached the runner's own summary line
--- the real run made 54 member case(s) over 86 check line(s):
ok the real run's every case matches the row it checks
ok the mutant differs, so the comparison does see the value it is checking
ok the second mutant differs too, so the error's code is checked and not just its presence
ok the third mutant differs, so PKSecureElement8.m's answers are read
ok the third mutant's difference is the case it names
ok the third mutant's transcript says which case is wrong, not merely that it is
ok the fourth mutant differs, so PKPaymentRequestStatus11.m's answers are read
ok the fourth mutant's difference is the case it names
ok the fourth mutant's transcript says which case is wrong, not merely that it is
    PKPaymentRequestUpdate.status defaults to Success        1                          FAIL
      ... and PKPaymentRequestPaymentMethodUpdate inherits Success for status 1    FAIL
      ... and PKPaymentRequestShippingContactUpdate inherits Success for status 1   FAIL
```

**Two defects the probe found, both in the probe, and both worth naming because either would have read
as a pass.** The first run's `errors:` case passed an `NSError` where the SDK declares an `NSArray` of
them: `[NSError copy]` answers the error, not a list of one, so the case measured nothing. And a runner
that dies mid-transcript leaves **no** `FAIL` in it, because the cases after the crash never ran -- the
first run of that defect ended in an exception, and the only reason it was not green is that the fourth
mutant still differed. So `run.sh` now checks that **every** transcript ends with the runner's own
`# N check(s), N failure(s)` line, before it compares anything.

What the cases measure, and where each answer comes from: the five classes exist (the host has all five,
so a member answering would prove nothing on its own), the superclass chain is Apple's own as 11.0
measures it, `status` reads back what was passed and the update's own default is `Success`, the error
lists keep the order they were given and are **copies** -- proved by emptying the array the delegate
passed and reading the count again -- and the three `null_resettable` lists answer a list, never `nil`.
The last three cases are the negative ones: `PKPaymentRequestUpdate` must carry **no** `shippingMethods`
(15.0), **no** `multiTokenContexts` (16.0) and `PKPaymentAuthorizationResult` **no** `orderDetails`
(16.0), because `@dynamic` is what keeps an 11.0 object from shipping a later release's member.
