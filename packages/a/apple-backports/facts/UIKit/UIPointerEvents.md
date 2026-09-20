# Pointer members of UIEvent, UIGestureRecognizer, UITapGestureRecognizer and UIButton, iOS 13.4

Introduced in iOS 13.4: which buttons and modifier keys an event came with, the button a tap needs, a recogniser's hook to leave an event out,
and a button's built-in pointer interaction. iOS 6 delivers touches only, so the events carry nothing to report.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), held against the backport by `tests/backports/host/uikit2` (the
`pointercategories` group), and the header of SDK 16.4.

## As UIKit does

- `UIEventButtonMaskForButtonNumber(n)` is 1 for `n` of 0 or 1, `1 << (n - 1)` up to the largest bit the type keeps but two, and 0 for a
  negative number or a larger one: 62 gives 2^61 and 63 gives 0 on a 64-bit host.
- `UITapGestureRecognizer.buttonMaskRequired` starts as `UIEventButtonMaskPrimary`, keeps any positive value, and raises
  `NSInternalInconsistencyException` "buttonMaskRequired must be greater than 0" for zero or less.
- `-[UIGestureRecognizer shouldReceiveEvent:]` answers YES.
- `UIButton.pointerInteractionEnabled` is NO at first. Setting `pointerStyleProvider` to a block turns it on; the getter answers the block that was
  set. The first turn-on adds one `UIPointerInteraction` to the button's `interactions`; turning it off keeps the interaction and the provider,
  and turning it on again adds no second.

## What the port answers

- `UIEvent.modifierFlags`, `UIEvent.buttonMask`, `UIGestureRecognizer.modifierFlags` and `UIGestureRecognizer.buttonMask` are 0 always: no modifier
  is held and no button is pressed, since every event is a touch. Nothing was read from a release for the button mask of a finger; the
  header says the tap's mask is only evaluated for indirect input devices.
- The interaction the button adds is the port's `UIPointerInteraction`, and never asks the provider for a style.
- `-gestureRecognizer:shouldReceiveEvent:` of a recogniser's delegate is never sent.
