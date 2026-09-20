# UICollectionViewCompositionalLayout, iOS 13.0

Introduced in iOS 13.0: a collection view layout that is described, not computed by the application - a section is a
group, a group holds items, and the layout works out where every cell, supplementary view and decoration view goes.
`UICollectionViewCompositionalLayout` is a `UICollectionViewLayout` subclass, and iOS 6 has `UICollectionViewLayout` since
6.0, so the port writes the whole thing: the frames come from the description, and the collection view of the release asks
for them through the calls it has always made (`-prepareLayout`, `-collectionViewContentSize`,
`-layoutAttributesForElementsInRect:`, the three `-layoutAttributesFor...AtIndexPath:` ones and
`-shouldInvalidateLayoutForBoundsChange:`).

Source: the host's own UIKit under Mac Catalyst (macOS 27.0). Nothing of UIKit's code or bytes is read: every rule below was
**measured** - the same description was given to the host's layout and to the port's, in a collection view in a real window, and
the frames, content sizes, element lists and index paths were compared - and the port was made to agree. The differential is
`tests/backports/host/uikit2/compositionallayout_test.m` (the `compositionallayout` group): 182 fixed layouts compared exactly,
whose answers become `tests/backports/device/compositional-expectations.h`, and random ones. The device test is
`tests/backports/device/compositional.m`, run at the scale the numbers were recorded at (2).

## What the port does as UIKit does

Sizes and rounding.

- A layout is solved for the size of the collection view's bounds. A fraction is a fraction of the width, or of the height, of
  the box its item is laid out in, and the answer is rounded **down** to a pixel of the screen (half a point at scale 2), where
  a value that is a hair below a pixel counts as on it. Positions are rounded to the **nearest** pixel. An absolute length is
  kept as it is and an estimated one is its estimate.
- A section is laid out in the size of the collection view less its content insets. A group of a section is sized in the
  section's width less the insets and the **whole** height when the layout scrolls down, and in the whole width and the height
  less the insets when it scrolls sideways: the size along the scroll axis is not cleared of the insets. A group of a group is
  sized in the inner size of its parent, less the group's own content insets. A fraction of the width used for a height is a
  fraction of the width all the same.
- An item's frame is its slot less its content insets. An inset larger than the slot makes a frame of the difference, taken
  positive, so an item 9.5 wide with 7 points on each side is 4.5 wide.

What a group holds.

- A horizontal group puts its subitems in a row, and a vertical one in a column, repeating the list from the start for as many
  items as the section has, and starts a new group when the next one does not fit. **How many fit** is decided against the
  size less the spacing between the items, so the fractions are not fractions of the whole size but of what is left of it once the
  spacings are taken off. When the items of a row take their height as a fraction of the height (or as a length), the count *n*
  is the largest for which *n* items, sized in the size less *n - 1* spacings, and the spacings between them, still fit. When
  some item takes its height as a fraction of the width, the count is first the number of items that fit in the whole size with no
  spacing at all, the fractions are resolved in the size less one spacing fewer than that count, and the row takes as many items
  as then fit with the spacing between them. A group made for a count takes exactly that many, each one over the count of the size
  less the spacings. (Both rules were fitted to a few hundred rows; the second was found by reading the heights of the items.)
- The spacing between items is fixed, or flexible, which is a minimum: what is left of the row is shared out between the
  flexible spacings, the ones between items and the flexible edge spacings of items alike. The share is allowed to be negative, so
  a group wider than its section with a flexible leading edge is pushed left by the difference. An item smaller than its row across
  sits at the start of it, unless its edge spacing is flexible.
- An item's edge spacing lies outside the item: a fixed edge takes room, and a flexible one takes what is left over, the way the
  flexible spacing between items does. A group's own edge spacing does the same in its section, and its top and bottom (leading and
  trailing when scrolling sideways) are room between groups.
- A group of which even the first item is larger than the group along the group's own axis lays out **nothing**: the section
  behaves as one with no items, and has no size unless it has boundary items. The port says so once in the log. An item larger across
  the axis is placed and sticks out.
- The last group of a section that has fewer items than a whole group is **trimmed** along the scroll axis: measured from the group's
  inner corner, it is as long as the items in it reach (to the far edge of their frames, the item's own insets taken off) plus what
  a whole group leaves over after its last item. The group's own insets are not added back. A group trimmed to less than nothing
  makes a section of no height, which is left out of every list of elements. A group that holds a nested group that is partly
  filled is trimmed by the nested group's items in the same way.
- A custom group asks its item provider once for each section, with a container the size of the group resolved in the
  **whole** size of the collection view (not in the section's), its content insets and the size less them; the frames it answers are
  relative to the group's own outer corner, and the group is repeated for the items that are left. An estimated size in a custom
  group says no content insets, as UIKit's does.
- When a group's height is estimated and its items are not, the group is as tall as its tallest item.

Sections and the layout.

- Sections are stacked along the scroll axis, with the layout's inter-section spacing between every two, empty ones included. A
  section with no items has no size unless it has boundary supplementary items, and then it is the size of its two content insets
  and what its boundary items need. The content size is the sum along the axis, and across it the width of the collection view or
  of the widest group if that is wider.
- Boundary supplementary items sit at an edge of a section (of the layout, for the layout's). The item takes the size of its
  `layoutSize` in the section's width, cleared of the insets when the section follows them, and the whole height; the alignment
  names the corner or edge, the item is centred on the axis it does not name, and the offset moves it. An item that extends the
  boundary lies *outside* the section along the scroll axis and the section grows to hold it, on either side it sticks out on; one
  that does not lies inside. An item aligned to the sides of a section that scrolls down (top and bottom when scrolling sideways) is
  centred along the section; when it extends the boundary and is taller than the section, the section grows to it and the item is
  placed at its start, and when it does not extend it, the item is centred and sticks out on both sides. Items of the same side do
  not stack: each is placed against the section's edge. A section with no items is as large as what its extending items need.
- Pinned boundary items stay in the visible bounds (less the adjusted content inset) while their section is in view, and are stopped
  at the far edge of the section or of the layout, the room the extending items took not counted for the far side. They have a z
  index of a billion plus their own while they are in the visible bounds. A change of the bounds invalidates the layout only when
  there is a pinned item; the port then keeps the solved frames and re-pins.
- Supplementary items tied to an item are placed from its frame, those tied to a group from the group's frame, resolved in the size
  the group is laid out in. The container anchor names a point of the frame; the item anchor, which defaults to the same edges, a
  point of the view; the view is put where its point falls on the container's, and offsets add: an absolute offset in points, a
  fractional one in fractions of **the supplementary view's** own size.
- Decoration items are the size of their section, boundary items included, less their insets, and are not made for a section with no
  size. Cells of a section that has decoration items have z index 1.
- Index paths. A cell is its item's, in the section. A boundary item is item 0 of its section, the layout's is item `NSIntegerMax` of
  section 0. Supplementary items tied to items and to groups count from 0 for each element kind **in each section**, in the order
  they are laid out; a decoration item is its number in the section's array.
- Asking. `-layoutAttributesForElementsInRect:` clips the rectangle to the content: nothing comes back outside it, and a rectangle
  with no area gets the decoration views alone. What belongs to a group is handed out only when the **group** meets the rectangle
  (an item that sticks out of its group is answered for the part of it in the group, and one wholly outside its group is never
  answered, though `-layoutAttributesForItemAtIndexPath:` gives its frame), and decoration views by whether their section's frame
  meets or touches it. A section with no size answers nothing.
- The section provider is called once for each section on every solve, with an environment whose container is the size of the
  collection view (no insets), and the view's trait collection. A nil section for a section with items raises
  `Invalid section definition. Please specify a valid section definition when content is to be rendered for a section.
  This is a client error.`

## What the port cannot do

- **No nested scrolling.** `orthogonalScrollingBehavior` is kept, and every value but none is laid out as a plain section: the
  groups run along the scroll axis of the layout and are not a scroll view of their own. The first such section says so in the
  log. `visibleItemsInvalidationHandler` is kept and never called, since UIKit calls it only for such sections, and
  `NSCollectionLayoutVisibleItem`, which it receives, is never made.
- **No self-sizing.** iOS 6 asks a cell nothing about its size. An estimated dimension is laid out at its estimate; the first one
  says so in the log.
- The layout runs left to right: leading is left, and `flipsHorizontallyInOtherLayoutDirection` is not carried.
- iOS 6's collection view has no invalidation contexts, so a bounds change is answered by `-shouldInvalidateLayoutForBoundsChange:`
  and `-invalidateLayout` only.
- The port does not supply the attributes for appearing and disappearing items that the host's layout does; the base class answers.
- `visualDescription`, and the members of later releases, are absent (`NSCollectionLayoutItem.md`).

## Where the port differs, measured

The random layouts of the differential test (`CHARON_FUZZ_ROUNDS`) put a description together from the features above and compare the
two answers. With one feature at a time, from about one layout in twenty to none differs; with all of them at once about three in ten
do, nearly all in the situations below, which the fixed layouts do not reach:

- A row that mixes lengths and fractions of the width, while some item takes its height as a fraction of the width, can be packed by
  one item differently, and a row whose items disagree about the axis they are measured along in the direction of the row is not held
  to the host.
- A nested group whose first item does not fit in it: the port leaves the nested group empty; the host's answer varies.
- A layout with boundary items whose sections are all empty, and boundary items given offsets in a section with no room.
- An item whose insets exceed its slot on both sides in a very narrow slot.
- An estimated size on the axis a group runs along is laid out at its estimate; the host's answer for a vertical group with an
  estimated height is one group holding every item, and for a horizontal group with an estimated width a group of one item, as it
  grows the group to its content.
- The host keeps the pinned positions of sections that are out of sight from the last time they were in sight; the port computes
  them all. Nothing in sight differs, and the differential test only compares what is in sight.
