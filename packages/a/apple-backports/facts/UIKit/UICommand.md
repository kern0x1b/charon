# UICommand, UICommandAlternate and the key command that is one, iOS 13

Introduced in iOS 13: a menu element that names an action by selector and sends it down the responder chain, where `UIAction` holds a
handler. `UIKeyCommand` became a `UICommand` in the same release.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), asked for every default, every equality, every exception and the
archive, and held against the backport by the `commands` group of `tests/backports/host/uikit2`; `tests/backports/device/uirest.m`
runs the same statements on a device.

## What the host answers

- `+commandWithTitle:image:action:propertyList:` and its `alternates:` form make the command. `+new` and `-init` are marked unavailable
  in the header and work: they answer a command with no title and no action.
- The property list is checked and deep copied: a value that is not a property list of the binary format - a dictionary with a number
  as a key, an `NSNull`, an `NSURL`, an array holding a plain object - raises `NSInternalInconsistencyException`, "Invalid parameter
  not satisfying: propertyListCopy". A mutable string or array that goes in is immutable when it comes out. The port checks with
  `CFPropertyListIsValid` for the binary format and copies with `CFPropertyListCreateDeepCopy`.
- Alternates are checked one by one: a modifier flags value of 0, or two alternates with the same flags, raises "Invalid parameter not
  satisfying: alternateModifierFlags != 0 && ![allAlternateModifierFlags containsIndex:alternateModifierFlags]"; something that is not
  an alternate raises the unrecognised selector `modifierFlags`. The array is copied.
- `-isEqual:` compares the action and the property list only; the title, the image, the attributes and the state do not count. `-hash` is
  the action's. `-copy` is another command, equal to the first and with the same attributes, state, discoverability title and title.
- A `UICommandAlternate` is equal to another of the same modifier flags, is its own copy, and prints as `<UICommandAlternate: 0x...>`.
- `-description` is `<UICommand: 0x...; title = T; action: foo:>`, the title left out when empty.
- The archive holds `title`, `preferredDisplayMode`, `action` (as a string), `propertyList` and `alternates` when there are any, and
  `discoverabilityTitle`, `attributes` and `states` when they are set. The system adds an internal identifier and an accessibility
  identifier that the port has no use for and does not write.
- `UICommandTagShare` is `com.apple.command-tag.share`.

## UIKeyCommand

A key command is a command with an input and modifier flags, and `-init` gives it the action `_nop`, no input and the title "". It is
equal to another of the same input and the same modifier flags and to no other - the action, the title and the property list do not
count - and its hash follows. Its description is `<UIKeyCommand: 0x...; action: foo:; input: a; modifierFlags: Cmd>`: the action left
out when there is none, `<none>` for no input, the flags left out when 0 and named `AlphaShift`, `NumPad`, `Ctrl`, `Opt`, `Shift`,
`Cmd` in that order and joined with hyphens. `+keyCommandWithInput:modifierFlags:action:discoverabilityTitle:` gives the command that
title as its title too. The key command holds no more than it did: iOS 6 sends nothing to a key command (see
`KeyboardAndAccessibility.md`); the three members iOS 15 added are held in `UIKeyCommandPriority.md`.

## In a menu

A `UICommand` is a menu element like an action. The action sheet of the context menu interaction lists it, and when it is chosen the
sheet sends its action down the responder chain with `sendAction:to:from:forEvent:` and the command as the sender, where an action runs
its handler. A command with the destructive attribute is the destructive button; a disabled or hidden one is left out.

## What differs from the host

The members of iOS 16 and later of the menu leaf protocol - `subtitle`, `selectedImage`, `repeatBehavior`, `sender`,
`performWithSender:target:` - are not answered.
