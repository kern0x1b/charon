# UITableViewDiffableDataSource, iOS 13.0

Introduced in iOS 13.0: the data source of `UICollectionViewDiffableDataSource.md`, for a table view. It has the same `snapshot`, index path and
identifier lookups, `-applySnapshot:animatingDifferences:` and `-applySnapshot:animatingDifferences:completion:`, and `defaultRowAnimation`.
The 14.0 members are the collection view's alone.

Source and method: as for the collection view, in the `diffabledatasource` group of `tests/backports/host/uikit2` (a third of the trials are
table views) and in `device/diffable.m`.

## What the port does as the system does

- The rows are moved, inserted, deleted and reloaded with `defaultRowAnimation`, which starts as `UITableViewRowAnimationAutomatic`, and
  without animation when `animatingDifferences` is NO.
- A table view cannot move a row out of a section that is deleted or into one that is inserted, so an apply that would has the table `reloadData`,
  and the provider is asked for every row; so it does when more than one section moves.
- The callbacks are `numberOfSectionsInTableView:`, `tableView:numberOfRowsInSection:` (past the end: "Invalid parameter not satisfying: section <
  _impl.numberOfSections"; nil index path: "indexPath") and `tableView:cellForRowAtIndexPath:`, which raises "Invalid parameter not
  satisfying: itemIdentifier" for a path with no item and "UITableViewDiffableDataSource cell provider returned nil for index path ... with item
  identifier '...', which is not allowed. You must always return a cell to the table view: ..." for a cell not returned. It answers no header, footer,
  editing, moving or index title callback: a subclass that wants one adds it, and `respondsToSelector:` is the system's.

## Where the port departs

- The same rule as the collection view's: a batch whose counts the port cannot prove, any move of a row between sections, and a section change
  mixed with row changes are a `reloadData`, so the animation is lost and the provider is asked for every row.

- The rule for when the system falls back to `reloadData` for a table is read from its answers: a row that moves out of a deleted section
  or into an inserted one, or more than one section that moves. In a few batches with several section moves the system does not fall back
  where the port does, and the provider is asked for other cells; the counts and index paths are the same.
- What the table view of iOS 6 accepts inside `beginUpdates` - a section moved with rows inserted into it, a row moved between sections - was not
  read from the release; `device/diffable.m` runs forty random snapshots through a table view and a collection view of the device to say.
