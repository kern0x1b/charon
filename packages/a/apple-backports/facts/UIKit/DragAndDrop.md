# Drag and drop, iOS 11.0

iOS 11 let a view offer what it shows to be dragged and accept what is dropped on
it, across applications on an iPad and inside one on an iPhone. The whole of it
rides on a system service that iOS 6 does not have, so what this package carries
is the surface an application configures, held, and the answer that no drag ever
begins.

Source: UIKitCore of the arm64 shared cache of iOS 12.0 - `+[UIDragInteraction
isEnabledByDefault]` at `0x1acc2f9d0` and the function it continues into at
`0x1acc3a3c4`, `-[UIDragInteraction isEnabled]` at `0x1acc2f9d4` and
`-setEnabled:` at `0x1acc2fad4`, `-[UIDragItem initWithItemProvider:]` at
`0x1acc30654`, `-[UIDropProposal initWithDropOperation:]` at `0x1acc4f658` and
`-copyWithZone:` at `0x1acc4f850`, `-[UIDropInteraction initWithDelegate:]` at
`0x1acc4f95c`, the accessors of `UITableView` and `UICollectionView`. The host's
UIKit through Mac Catalyst, side by side with the renamed classes, for what the
accessors answer (`tests/backports/host/dragdrop`), and an iPad 2 running 6.1.3.

## What each class holds

- `UIDropProposal`: made with a drop operation. A new proposal is not precise and
  prefers a full size preview - the release sets the second one to YES when it
  makes the proposal, so the default of the property is YES. A copy is a new
  object of the same class with the same operation, `precise` and
  `prefersFullSizePreview`.
- `UIDragItem`: made with an item provider and asks nothing of it, a `nil`
  provider included. The provider and the local object are kept by identity, the
  preview provider is a copied block, and all of them are `nil` until set.
- `UIDragInteraction`: made with a delegate, held weakly. The view is held weakly
  as well, and is set when a view adds the interaction and cleared when it lets
  it go. `enabled` answers what was set once something was set; before that it
  answers the class value `+isEnabledByDefault`.
- `UIDropInteraction`: the same, with `allowsSimultaneousDropSessions`, NO until
  set.
- `UITableView` and `UICollectionView`: a drag delegate and a drop delegate, held
  weakly, `dragInteractionEnabled`, which answers what was set and the class
  value of the drag interaction before that, and `hasActiveDrag` and
  `hasActiveDrop`, which answer whether a drag or a drop is going on.
- `UITableViewCell.userInteractionEnabledWhileDragging`, NO until set, and the
  hook `dragStateDidChange:` of both kinds of cell, which does nothing until a
  subclass overrides it.

## Where iOS 6 differs

`+[UIDragInteraction isEnabledByDefault]` answers YES on an iPad and NO on an
iPhone in iOS 12. There is no drag session on this release, on any device, so the
package answers NO everywhere, and an application that asks before it draws a
handle on its rows draws none. This is the one departure, and it is the reason
`dragInteractionEnabled` of a table or a collection view starts as NO here.

No drag ever begins and no drop ever enters a view, so no delegate is asked
anything, `hasActiveDrag` and `hasActiveDrop` are NO, and the state of a cell does
not change. `UITableViewDragDelegate` and its kin are protocols the application
adopts; the package has nothing to do with them. The sessions, the previews and
the coordinators that a delegate is handed are not carried: they are only ever
made by the system while a drag is going on. The registry lists most of them as
absent.

## The two session selectors that must not crash a caller

`-[UIDragDropSession canLoadObjectsOfClass:]` and `-[UIDropSession
loadObjectsOfClass:completion:]` are the exception: no session object is ever
made by this release, but a caller holding one must never hit an unrecognized
selector for asking it. `CharonDragDropSession` in `UIDragDropSession.m` is a
concrete, private conformer of both protocols that answers honestly instead of
crashing - `canLoadObjectsOfClass:` is NO and `loadObjectsOfClass:completion:`
calls its completion with an empty array and returns a finished `NSProgress` -
the same answer a session that never had anything to offer would give. Nothing
in this package vends an instance of it yet, since no drag or drop ever begins
to need one; it exists so the surface is safe to use the day something does.
