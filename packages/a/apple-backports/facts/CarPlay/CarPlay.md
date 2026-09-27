# CarPlay on iOS 6: the measurement pass, and what it decides

`apple.objc.inventory` against the armv7 dyld shared cache of **6.1.3**: **no CarPlay class of any
name is in the release.** `CPInterfaceController`, `CPInterfaceControllerDelegate`,
`CPWindow` and every template class are absent -- the framework is not in this release at all, as the
ledger's own reasons already say for all 74 of its classes.

`apple.dyld`'s `first_releases` over the held cache ladder, for the 74 classes the SDK 26.2 declares
and this port does not have:

| first held release that exports it | classes |
| --- | --- |
| 12.0 | 25 |
| 16.0 | 35 |
| 18.0 | 1 |
| not in any held release | 13 |

So the CarPlay surface splits into three objects by measured release, and nothing here is a copy of
anything: the framework is Apple's and there is no open implementation of it to port.

## What the wall is, and where it is

**The wall is the head unit, and it is Apple's, not this port's.** A CarPlay scene is a connection to
a car: without a car there is no scene, which is Apple's own behaviour without a car and not a
limitation of the port. That is the honest seam, and it is one seam with two halves:

- **Everything the templates need is implementable in-app.** The ruling and this file agree: the
  list, grid, map and now-playing templates are ordinary view controllers, and a
  `CPInterfaceController` equivalent is an object with a content window of the port's own that pushes
  and pops template view controllers, keeps the tab bar and the now-playing bar, and answers the
  delegate. None of that needs a car. So the templates and the interface controller are `implemented`
  and run in an application.
- **The scene connection is not implementable.** `CPScene`/`CPInterfaceController`'s connection to a
  car is a system service no program on this device can stand in for, so the scene is refused exactly
  as Apple refuses it without a car, and every CarPlay-specific affordance that depends on the car
  (the templates' car-specific layout, the car's input, the vehicle status) answers the way Apple
  answers it. That half is `documented-absent` at the seam, per COORDINATION §2: the API surface
  exists, everything not depending on the wall is implemented, and the refusal happens only where the
  wall is.

## What this decides, per family

- **`CPInterfaceController` and the four templates** (list, grid, map, now-playing) plus the
  supporting classes: `implemented`, as in-app view controllers over the port's own content window.
  A host differential is impossible for most of it (macOS has no CarPlay templates), so the emulator
  call test at 6.1.3 is the check, as it is for the MapKit renderers.
- **The car-dependent surface**: `inert` or `absent` per class, each with the measurement that the
  release has no CarPlay at all and the reason the class depends on a car that is not there.
- **The scene**: the connection refused, and `status` `absent` for the classes that *are* the
  connection, with the effect naming what a caller gets.

One thing this pass settles before any code is written, and it is the same shape as the MapKit
`MKMapItem` correction: **the wallet half of PassKit is the release's own**, so that half is not a
backport at all. See `facts/PassKit/PassKit.md`.

## The SDK shapes this has to be written against, read from the SDK 16.4

CarPlay's classes are not shaped the way a surface list suggests, and writing against the shapes
rather than against the list is the difference between working and a compile error per member. What
the SDK the port compiles against actually declares:

- `CPButton`, `CPBarButton`, `CPGridButton`, `CPMapButton` and `CPTextButton` are **`NSObject`
  subclasses, not views**. A `CPButton` has `-initWithImage:handler:` and a `title`; a `CPBarButton`
  has `-initWithImage:handler:` and `-initWithTitle:handler:`; a `CPGridButton` has
  `-initWithTitleVariants:image:handler:`; a `CPMapButton` has `-initWithHandler:`. So none of them
  can be drawn by being a view: each one is drawn by the template that holds it, and that is the real
  work — a grid button drawn in a collection view cell, a map button drawn over the map, a bar button
  drawn in a bar.
- `CPTemplate` declares `userInfo`, `tabTitle`, `tabImage`, `tabSystemItem` and `showsTabBadge`, and
  **no `title`** — so `CPTemplate.title` is this port's own member, declared under Apple's name.
- `CPListItem` conforms to **`CPSelectableListItem`**, so every member that protocol requires is
  required here; its own members are `text` (readonly), `detailText`, `image`, `accessoryImage`,
  `accessoryType`, `handler` (iOS 14, taking the item and a completion block), `explicitContent` (a
  **BOOL**, not a string), `playbackProgress` (a **CGFloat**), `playing`,
  `playingIndicatorLocation`, `enabled` and the class property `maximumImageSize`.
- `CPListSection` has `init` marked `NS_UNAVAILABLE` and `-initWithItems:` as the way in, and its
  `header`, `headerSubtitle`, `headerButton` and `items` are **readonly**, with `-updateSections:` on
  the template for the rest.
- `CPListTemplate` and `CPGridTemplate` also mark `init`/`new` `NS_UNAVAILABLE`, take
  `-initWithTitle:sections:` / `-initWithTitle:gridButtons:`, and expose `maximumItemCount` and
  `maximumSectionCount` as **class** properties.
- `CPTravelEstimates` takes `-initWithDistanceRemaining:timeRemaining:` with
  `NSMeasurement<NSUnitLength *> *` and answers `distanceRemaining` in the same type.

### The one that needs a decision

`NSMeasurement` and `NSUnitLength` are **absent from the release**: the 6.1.3 selector list has no
`measurementFormatter`, no `initWithUnit`-style initialiser for a unit, and
`-initWithDistance:time:` (measured absent), so there is no `NSMeasurement` class to put a
`CPTravelEstimates` distance into. `CPTravelEstimates` is the only CarPlay member the port cannot reach
for a reason that is **not** "the release has no CarPlay": a class the release has no counterpart of
would have to be carried here, which is Foundation's type in a CarPlay signature.

The two ways that can go, and the port has to pick one:

1. **Carry `NSMeasurement` and `NSUnitLength`** in the Foundation backport, as classes, and
   `CPTravelEstimates` is then real. This is Foundation's API, it belongs in `libFoundationBackports`,
   and the measure system behind it (a unit, a converter, a formatter) is a few hundred lines.
2. **`CPTravelEstimates` answers `distanceRemaining` as nil** and `timeRemaining` as the time, with the
   registry saying the distance is nil because the release has no measurement type to hold it. That is
   a quiet-different answer and COORDINATION §2 does not allow it.

**This is the question to put to the owner**: option 1 is the honest one and it is Foundation's
work rather than CarPlay's, so it belongs in whichever band owns Foundation, and this port would then
link `FoundationBackports` for it. Everything else in the 12.0 template family has no such question --
the list, grid, map and now-playing templates, the interface controller, the window and the alert
actions are all writable against the release and against UIKit.
