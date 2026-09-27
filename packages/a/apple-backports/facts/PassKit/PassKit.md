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
