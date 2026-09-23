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

## `UIButton.hovered`, iOS 15

`-[UIButton isHovered]` answers NO, always (`UIKit/UIButton+Hover15.m`). A button is hovered only while a pointer rests over it, and the
release delivers no hover event at all - the port's `UIHoverGestureRecognizer` never leaves the possible state for the same reason - so NO
is the answer any device without a pointer gives, not a placeholder. The registry lists the getter, `-[UIButton isHovered]`, since the
property is readonly and has no setter to spell it. Ladder, by `objc.inventory` on each cache with `initWithBarButtonSystemItem:menu:` of
iOS 14 as the positive control and an invented selector as the negative one: `isHovered` is not in `UIButton`'s methods in 6.1.3 or 12.0
and is in 16.0 and 18.0; the ladder has no 13-15 cache, so it bounds the release to 12.0-16.0 and `introduced` stays the header's 15.0.
Not measured on a device.

## On a device, iOS 6.1.3

On an iPad 2 of iOS 6.1.3 (2026-09-23), a process of the band's own (`.agent-work/runs/b1314-live/main.m`, output `run4-all.txt` beside it) loaded the gate's `libUIKitBackports.dylib` and checked `-[UIButton isHovered]`: NO.
