# NSCollectionLayoutSection content insets reference, iOS 14.0

Introduced in iOS 14.0: which edges of the collection view a section, or a layout, keeps its content clear of.
`NSCollectionLayoutSection.contentInsetsReference` and `UICollectionViewCompositionalLayoutConfiguration.contentInsetsReference`
take one of five values: automatic, none, safe area, layout margins, readable content. The classes are those of
`NSCollectionLayoutItem.md` and `UICollectionViewCompositionalLayout.md`; only the two properties are of this release.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), with a collection view whose layout margins were set to
top 10, left 20, bottom 30, right 40, asked for each of the five values on the section and on the layout in both scroll
directions, and the header of SDK 16.4. The differential test is `tests/backports/host/uikit2` (the `compositionallayout`
group, ten of its layouts).

## What the port does as UIKit does

- The defaults are the header's: a layout refers to the safe area, a section to automatic, which follows the layout.
- The reference clears the section of edges **across** the scroll direction only: the left and right edges when scrolling
  down, the top and bottom when scrolling sideways. None and automatic clear nothing at all; layout margins clear the
  collection view's `layoutMargins`; readable content does the same, since the port has no readable content guide, and on
  a phone the host's own answer is the layout margins too; the safe area clears the collection view's `safeAreaInsets` (the port
  carries them from iOS 11, see `UIViewSafeArea.md`).
- What is cleared is taken off the size the section's groups are laid out in, and the section is moved by it; the content
  size is not made smaller. The size given to a section provider is the collection view's, cleared of nothing.
- The boundary supplementary items of the **layout** are not cleared by it.
- Both properties are copied with their object.

## What the port cannot do

- The host was measured with a safe area of zero, since the host has no status bar, so the values that come from the safe area
  are the port's own reading of it and are not held against the host.
