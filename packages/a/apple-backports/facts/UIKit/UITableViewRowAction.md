# UITableViewRowAction, iOS 8

Source: the host's own UIKit, under Mac Catalyst, asked for each answer below and held against the backport by the
`rowaction` group of `tests/backports/host/uikit2/run.sh`; and iOS 6.0 and 6.1.3 on the emulator, an iPhone 4S and an
iPad 2, through `tests/backports/device/uikit2.m`.

## The value

An action is a style, a title, a background colour, a background effect and the handler it was made with, made by
`+rowActionWithStyle:title:handler:`. Style is read-only: destructive and default are the same value, 0, and normal is 1.
The title, the colour and the effect are settable and copied on the way in; a title of nil and a handler of nil are
accepted, and `-init` makes an action of style 0 with no title, no colour and no handler.

A colour is given to every action made by the factory: a destructive one is the system red, a normal one is the grey
0.78, 0.78, 0.8; the host's red is that of its own release and the port gives iOS 7's system red. Setting it to nil clears it.

The class adopts `NSCopying` and nothing else: it is not archived. A copy is another object with the same style, title,
colour and handler, and it does not carry the effect; nothing is equal to a copy of itself, since the class keeps the
identity `isEqual:` of `NSObject`.

## What iOS 6 does with them

The release's table asks its delegate for a delete confirmation only, and nothing in it sends
`tableView:editActionsForRowAtIndexPath:`, so the actions an application builds are never shown: a swipe on a row
offers the release's own delete button when the delegate lets the row be deleted, and nothing when it does not. The class is
carried so that an application that builds and returns actions runs; the swipe buttons are not.
