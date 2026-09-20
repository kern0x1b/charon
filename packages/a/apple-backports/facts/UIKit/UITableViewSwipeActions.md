# The swipe actions of a table, iOS 8 and iOS 11

`tableView:editActionsForRowAtIndexPath:` (iOS 8, an array of `UITableViewRowAction`) and
`tableView:leadingSwipeActionsConfigurationForRowAtIndexPath:` /
`tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:` (iOS 11, a `UISwipeActionsConfiguration` of
`UIContextualAction`) are what an application answers to say which buttons a swipe on a row shows.

Source: **there is no oracle for the interaction**. The host's UIKit under Mac Catalyst draws no swipe buttons, so the
values (`UITableViewRowAction`, `UIContextualAction`, `UISwipeActionsConfiguration`) are held against it and the behaviour
below is the port's own, checked by `tests/backports/device/swipeui.m` on an iPhone 4S and an iPad 2 running 6.1.3 with
real touches: the test sends digitizer events to the HID event system, so UIKit's own gesture recognizers see a finger. The looks - the width of a button, its font, the fraction that makes a full
swipe, the duration - are set from what the system's swipe looks like and are not measured.

## What is carried

- The port puts one pan recognizer and one tap recognizer on a table when its delegate is set (`setDelegate:` is
  replaced on `UITableView`, calling the release's own first), on a release whose UIKit lacks `UITableViewRowAction` or
  `UISwipeActionsConfiguration` - the check is that the class comes from the port's library. A release that has the class
  has the behaviour, and the port does nothing there.
- The pan begins for a drag that is more horizontal than vertical, on a row that exists, when the table is not editing, the
  data source does not refuse `canEditRowAtIndexPath:` and `editingStyleForRowAtIndexPath:` is not none, and the delegate
  answers a message for the side of the drag: to the left the trailing configuration, or the row actions; to the right the
  leading configuration. Anything else is left to the release, whose own swipe to delete goes on working.
- The row slides: its content view and accessory move by the drag, and the buttons are laid out in a view behind them at
  the edge, each as wide as it is at rest times the fraction of the way open. The first action is at the edge, and the
  others follow it inward.
- A button is as wide as its title plus 15 points each side and at least 74; its colour is the action's background colour
  (grey for a normal action and red for a destructive one, as the values give); a contextual action's image is drawn
  above the title.
- Letting go opens the row for a drag over half the buttons' width or a flick towards the edge, and closes it otherwise. An
  open row is dragged closed the same way. Only one row is open at a time.
- A tap on a button runs its handler: a row action's with the action and the index path, a contextual action's with the
  action, the button as the source view, and a completion block that closes the row. A row action's row closes after the
  handler returns.
- A drag across more than 65% of the table's width runs the first action when a row action is the source or the
  configuration's `performsFirstActionWithFullSwipe` is YES; otherwise the row stops at its buttons.
- A tap anywhere but on a button closes the open row and is swallowed: nothing is selected. A scroll of the table closes it.
- The delegate is told `willBeginEditingRowAtIndexPath:` when a row starts to open and `didEndEditingRowAtIndexPath:` when
  it has closed.

## When the table changes under an open row

An open row is closed at once, without animation, and the delegate is told `didEndEditingRowAtIndexPath:`, when:

- the table enters editing mode (`setEditing:YES`), and while it is editing no swipe begins;
- the table is reloaded, or rows or sections are inserted, deleted, reloaded or moved;
- the table's width changes, as a rotation makes it change;
- the row is no longer the cell of its index path, which is what a row that scrolled away and was reused looks like.

Each is checked on the devices by `tests/backports/device/swipeui.m`, with a swipe that still opens a row afterwards.

## What is not carried

`backgroundEffect` of a row action, the slide out of a row after a destructive action, the haptics, and right to left layouts
are not carried. An open row is closed by a scroll of the table or a tap, never held open across them.
