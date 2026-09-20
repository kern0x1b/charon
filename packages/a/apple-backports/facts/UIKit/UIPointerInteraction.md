# UIPointerInteraction and the pointer delegate, iOS 13.4

Introduced in iOS 13.4: the interaction a view is given to change the pointer of a trackpad or a mouse over it, and the two
protocols it talks to its delegate through. iOS 6 has no pointing device - no trackpad, no mouse, no hover - so the interaction
is **present and inert**: it can be made, added to a view and removed, and it never asks its delegate for anything.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), held against the backport by `tests/backports/host/uikit2` (the
`pointer` group), and the header of SDK 16.4. The host answers for a Mac pointer; nothing about the pointer itself is read here.

## As UIKit does

- `-initWithDelegate:` keeps the delegate **weakly**; nil is accepted and `-delegate` answers nil once the delegate is gone.
- `enabled` starts as YES and is kept as it is set; `-invalidate` changes nothing that can be read back.
- `view` is nil until the interaction is added to a view (`UIView+Interactions` sends `-willMoveToView:` and `-didMoveToView:`), moves
  with it from one view to another, and is nil again after it is removed.
- `-init` is answered as `-initWithDelegate:nil`, as the host's is although the header marks it unavailable.
- `-description` is `<UIPointerInteraction: 0x...>`, which is what the class inherits.

## What the port does

- Nothing more. No gesture recogniser is added to the view and the delegate is never sent `-pointerInteraction:regionForRequest:defaultRegion:`,
  `-pointerInteraction:styleForRegion:`, `-pointerInteraction:willEnterRegion:animator:` or `-pointerInteraction:willExitRegion:animator:`. The
  first time an interaction is added to a view the port says so in the log, once: "this release has no pointing device, so the interaction is
  attached and its delegate is never called".
- `UIPointerInteractionAnimating` has no carrier: the release never hands an application an animator, so no object of the port adopts it.

## Where it differs

- Everything above about the pointer: nothing is drawn, nothing morphs and nothing is asked. An application that uses the interaction to add
  hover feedback loses only the feedback.
