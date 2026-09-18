# The safe area of a view, iOS 11.0

Introduced in iOS 11.0: the part of a view that nothing of the system covers.

Source: UIKit of the arm64 shared cache of iOS 11.0 (iPod7,1 15A372), read in
full for the path below. There is no differential test against a host for this
one: `UIWindow` cannot be created through Mac Catalyst without a full
application, so the expectations of `tests/backports/device/safearea-tweak.m`
are derived from the algorithm here by hand and checked on the device.

| member | address in 11.0 |
|---|---|
| `-[UIView safeAreaInsets]` | `0x18a285b78` |
| `-[UIView setSafeAreaInsets:]` | `0x18a27d1cc` |
| `-[UIView _updateSafeAreaInsets]` | `0x18a27c9d4` |
| `-[UIView _safeAreaInsetsInSuperview:]` | `0x18a27c720` |
| `-[UIView _safeAreaInsetsForFrame:inSuperview:]` | `0x18a27c7d0` |
| `-[UIView _edgesPropagatingSafeAreaInsetsToDescendants]` | `0x18a27c6d4` |
| `-[UIView _safeAreaInsetsDidChangeFromOldInsets:]` | `0x18a27d178` |
| `-[UIViewController additionalSafeAreaInsets]` | `0x18a329618` |
| `-[UIViewController setAdditionalSafeAreaInsets:]` | `0x18a30d224` |

## How UIKit computes it

The value is **stored**, in the field at offset `0x1b8`; `-safeAreaInsets` only
reads four doubles out of it. UIKit refreshes it at its own moments — during
layout, when a frame changes, when a view changes superview — through
`-_updateSafeAreaInsets`, which is exactly

    [self setSafeAreaInsets:[self _safeAreaInsetsInSuperview:[self superview]]]

and `-_safeAreaInsetsInSuperview:` takes the view's `frame` (or
`_frameIgnoringLayerTransform` when a layer transform is in play) into
`-_safeAreaInsetsForFrame:inSuperview:`, which does three things:

1. If the superview belongs to a view controller, its overlay insets are
   refreshed (`_updateContentOverlayInsetsFromParentIfNecessary`) and read
   (`_contentOverlayInsets`), then joined with the superview's own safe area by
   `_UIEdgeInsetsMax` — the larger of the two on every edge.
2. `_edgesPropagatingSafeAreaInsetsToDescendants` decides which edges travel
   down at all. A plain `UIView` answers `0xf`, all four; subclasses narrow it.
3. `_UIViewInsetsNormalizedToInnerRect` moves the result from the superview's
   bounds to the view's frame: for each edge, `max(0, outer edge − inner edge)`
   — in the code a subtraction followed by `fmaxnm` against zero.

`-setSafeAreaInsets:` compares the four numbers with what is stored and, only
when they differ, calls `_safeAreaInsetsDidChangeFromOldInsets:`, which notifies
**the view first** (`-safeAreaInsetsDidChange`) and the controller second
(`-viewSafeAreaInsetsDidChange`, reached as `_safeAreaInsetsDidChangeForView`).
The whole store is gated on `__UIApplicationLinkedOnOrAfter`, so an application
built against an older SDK sees zeroes.

`-setAdditionalSafeAreaInsets:` compares with what it holds and, on a change,
asks the controller and its children to recompute their overlay insets: the
additional insets are part of the overlay, not something applied to the view
afterwards.

## What the port does, and what it refuses

The geometry carries over unchanged: the port computes the same joins and the
same `max(0, outer − inner)`. Two things differ, both on purpose.

**The value is computed on every read, not stored.** Storing it would need a
refresh at UIKit's moments, and reaching those means replacing `-layoutSubviews`,
`-setFrame:` or `-didMoveToSuperview`, which the port does not do. Computed on
read, the answer is always current, and the recursion up the superview chain is
what UIKit does anyway, once per level.

**The callbacks are not declared at all.** `-safeAreaInsetsDidChange`,
`-viewSafeAreaInsetsDidChange` and `-safeAreaLayoutGuide` would each be a
promise the port cannot keep: the first two are called from the moment of
change, which the port never sees, and the guide's frame is kept live by the
layout engine, which the port is not part of. A declared method that is never
called is the quietest kind of lie, so `respondsToSelector:` answers honestly
instead. They are in the registry as `absent` with that reason, and so is
`insetsLayoutMarginsFromSafeArea`: it would only mean something if it changed
what `-layoutMargins` answers, and that method belongs to the iOS 8 backport,
not to this one. A flag that layout reads and believes, while nothing acts on
it, is worse than no flag.

## Where the insets come from on iOS 6

iOS 11 gets them from the controller's overlay insets, which are built from the
scene, the bars and the presentation chain — machinery iOS 6 does not have. On
iOS 6 the layout does not extend under the bars: the view of a controller is
already laid out below the navigation bar and above the tab bar, and it reaches
under the status bar only when the controller asks for a full screen layout.
So the port measures what is really covered:

- a window is inset by the part of `-[UIApplication statusBarFrame]` that falls
  inside it, when the status bar is not hidden;
- a controller's view is inset by the parts of the status bar, the navigation
  bar, the toolbar and the tab bar that actually overlap it — each converted
  into the view's own coordinates and intersected with its bounds, and only when
  that bar is visible and in the same window;
- `additionalSafeAreaInsets` are **added** to that, edge by edge, as iOS 11 adds
  them into the overlay;
- everything below inherits by the geometry above.

The controller of a view is found through the responder chain: the view of a
controller answers it as its `-nextResponder`.
