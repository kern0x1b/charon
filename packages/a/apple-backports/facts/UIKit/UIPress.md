# UIPress, UIPressesEvent, the responder messages of presses and UICollectionViewTransitionLayout

Source: the host's own UIKit under Mac Catalyst, in an application with a window, asked for each answer below and held
against the backport by `tests/backports/host/presses/run.sh`, eight records that the app `tests/backports/device/presses.m`
compares on a device running 6.1.3.

## UIPress and UIPressesEvent, iOS 9.0

A press is a button of a remote, a game controller or a hardware keyboard. The release has none of them and sends no such
event, so both classes only exist.

- A press made by `-init` has phase began (0), type up arrow (0), no window, no responder, no recognizers and force 0. The
  superclass is NSObject. The values of the types (up, down, left, right arrows, select, menu, play/pause: 0 to 6) and of the
  five phases (0 to 4) are those of the header.
- `UIPressesEvent` is a `UIEvent` of type presses (3) whose `allPresses` and `pressesForGestureRecognizer:` are empty sets.
- `UIPress.key`, an iOS 13.4 property, is not carried.
- `-[UIResponder pressesBegan:withEvent:]`, `pressesChanged:`, `pressesEnded:` and `pressesCancelled:` hand a **non-empty** set
  to the next responder and do nothing for an empty one, so an override that calls `super` reaches the responder after it.
  The release never sends the messages; an application that calls them, or an override that calls `super`, is safe.

## UICollectionViewTransitionLayout, iOS 7.0

The layout a collection view puts in place while it animates from one layout to another, with the two layouts and a
progress from 0 to 1. The release's collection view has no such animation, so it never makes one.

- `-initWithCurrentLayout:nextLayout:` keeps the two layouts as they are given; the progress is 0 and can be set.
- The superclass is `UICollectionViewLayout`.
- `-updateValue:forAnimatedKey:` and `-valueForAnimatedKey:` keep nothing outside a running transition: the host answers 0
  after an update, and so does the port.
- The layout produces no attributes of its own on the release: the host interpolates between the two layouts, the port
  does not.
