# CarPlay on iOS 6: the measurement pass, and what it decides

`apple.objc.inventory` against the armv7 dyld shared cache of **6.1.3**: **no CarPlay class is in
this release -- with one exception that matters, which the first measurement pass got wrong.**
`CPInterfaceController`, `CPWindow` and every template class are absent; the framework is not here at
all. But a class **named** `CPListItem` is, and it is not CarPlay's: its own eleven methods are
`-addParagraph:`, `-paragraphAtIndex:`, `-paragraphCount`, `-list`, `-number`, `-setList:` and
`-setNumber:` -- some other framework's private list item, with no `text`, no `image`, no
`accessoryType` and no `handler`.

So Apple's CarPlay `CPListItem` is iOS 12 and absent, and its *name* is taken, which is the case
`charon_alias.h` exists for. (Note what this is and is not: the release has no `CPWindow`,
`CPTemplate` or any other CarPlay class, but it does have this one *name*, and a name the release
exports cannot be replaced by a second class of the same name.) `CarPlay/CPListItem.m` carries the name as an **alias**: it defines
`CharonCPListItem`, exports the release's name to it, and records the pair in
`__DATA,__charon_alias` for the library's loader. A subclass an application writes of `CPListItem`
inherits the release's class and is laid out after it; sent to `CharonCPListItem` itself, the class
introspection answers as the release's class does, so `[CPListItem class]`, what `[CPListItem alloc]`
makes and what the release hands out are one class. This is exactly how the port already handles a
name the release carries and Apple did not add -- `UIKit`'s `NSTextList` and `NSTextTab`, whose rows
in `registry/UIKit/base.json` say the same thing. The gate's `duplicated()` check is what found it
and it is the check working.

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

## What is carried, and what is the wall

**24 classes implemented, in four objects by the release that first exports them, and 7 classes
`absent` at the seam.** The numbers are the registry's own, counted from
`registry/CarPlay/ios12.json`; they are the only count in this file. The implemented ones:

| object | classes |
| --- | --- |
| 12.0 | `CPWindow`, `CPTemplate`, `CPBarButton`, `CPGridButton`, `CPMapButton`, `CPTravelEstimates`, `CPManeuver`, `CPAlertAction`, `CPNavigationAlert` |
| 12.0 | `CPListItem`, `CPListSection`, `CPListTemplate`, `CPGridTemplate`, `CPMapTemplate`, `CPInterfaceController` |
| 12.0 | `CPActionSheetTemplate`, `CPAlertTemplate`, `CPImageSet`, `CPSearchTemplate`, `CPTrip`, `CPRouteChoice`, `CPTripPreviewTextConfiguration` |
| 16.0 | `CPButton`, `CPTextButton` |

The remaining 48 of the corpus have **no registry entry at all** and their ledger rows stay `missing`:
they are not `absent` (they draw in-app like these do and nothing about them needs a car, so calling
them absent would be a false claim), they are simply not written yet. The objects they go in,
measured:

| object | classes |
| --- | --- |
| 14.0 | `CPContactCallButton`, `CPContactDirectionsButton`, `CPContactMessageButton`, `CPMessageListItemLeadingConfiguration`, `CPMessageListItemTrailingConfiguration`, `CPNowPlayingAddToLibraryButton`, `CPNowPlayingImageButton`, `CPNowPlayingMoreButton`, `CPNowPlayingPlaybackRateButton`, `CPNowPlayingRepeatButton`, `CPNowPlayingShuffleButton` -- none of them is in the SDK 16.4 headers, so the registry's `introduced` is what places them |
| 15.0 | `CPAssistantCellConfiguration` |
| 16.0 | `CPContact`, `CPContactTemplate`, `CPDashboardButton`, `CPDashboardController`, `CPInformationItem`, `CPInformationRatingItem`, `CPInformationTemplate`, `CPInstrumentClusterController`, `CPListImageRowItem`, `CPMessageComposeBarButton`, `CPMessageListItem`, `CPNowPlayingButton`, `CPNowPlayingTemplate`, `CPPointOfInterest`, `CPPointOfInterestTemplate`, `CPTabBarTemplate` -- all in the 16.4 headers, all first exported at 16.0 |
| 17.4 | `CPLane`, `CPLaneGuidance`, `CPRouteInformation` |
| 18.0 | `CPNowPlayingMode`, `CPNowPlayingModeSports`, `CPNowPlayingSportsClock`, `CPNowPlayingSportsEventStatus`, `CPNowPlayingSportsTeam`, `CPNowPlayingSportsTeamLogo` -- members of `CPNowPlayingTemplate`, so a category on the 16.0 class in the 18.0 object |
| 26.0 | `CPListImageRowItemElement` and its five subclasses, `CPMessageGridItemConfiguration` |

## `CPTemplate.title` is not a name this port carries

Measured against the SDK 26.2 the port does not compile against but does target: 26.2's
`CPTemplate.h` mentions "the template's title" in a `@note` and **declares no such property**, and the
templates that do have one -- `CPListTemplate`, `CPGridTemplate`, `CPMapTemplate` -- declare `title` on
themselves. An earlier version of this library gave `CPTemplate` a `title`; that name no header
declares, so it is removed (rule R4, and the lift sets that go with a registered name), and the tab's
own name is now `tabTitle`, which the header does declare.

**The buttons are NSObjects, and the templates draw them.** That is the SDK's own shape -- `CPButton`,
`CPBarButton`, `CPGridButton`, `CPMapButton` and `CPTextButton` are all `NSObject` subclasses in the
16.4 headers, and none of them is a view. So each carries a `charon_drawInRect:` (and `alpha:` where it
is drawn in a bar), and each template asks its buttons to draw themselves: the list and grid and map
templates put the bar buttons in a bar the template owns, the grid template asks each grid button to
draw into the collection view cell it is in, and the map template asks each map button to draw over
its map inside the map view's own insets. Each button's own handler is called
when the drawn mark is tapped. The header's own rule that a navigation bar shows at most two leading
buttons is honoured by the bar.

**`CPTravelEstimates` takes the port's own `NSMeasurement`.** `libFoundationBackports` carries
`NSUnit`, `NSUnitLength` and `NSMeasurement` (all three registered `implemented`, `minimum: "6.0"`, with
real implementations: the unit ladder, the linear and reciprocal converters, the measurement and its
arithmetic), which is exactly what the release lacking them is for. `CPTravelEstimates` is the member
that needs them, and it gets a real `NSMeasurement<NSUnitLength *> *` back.

**The map template uses the release's own map.** `CPMapTemplate`'s view controller is the release's
`MKMapView` -- the only map this port has -- with this port's own renderers on it, the map buttons over
it, and the navigation alert drawn as a guidance card out of its own title and subtitle variants. The
car-specific part of a map template (the car's own map rendering, the vehicle status, the car's input)
is the wall and is the registry's.

**`CPInterfaceController` owns a `CPWindow` of the port's own** -- a car's window is a window, and on
this port it is a window the application owns. It keeps the root template, the tab templates and the
pushed stack, implements the header's own completion forms and its deprecated forms of the six
operations, sends the delegate the four template lifecycle messages, and answers `carTraitCollection`
with **this device's own screen trait collection**, because the car is this device. `prefersDarkUser
UserInterfaceStyle` is `inert`: the release has no dark mode, and there is nothing for it to change.

**`CPWindow.mapButtonSafeAreaLayoutGuide` has no registry row at all, and that is the accurate
state.** Measured three ways: a layout guide is iOS 9; the release's 6.1.3 inventory has **no
`CPWindow` of any name** (CarPlay is not in this release, which is the whole of this file's
premise); and the gate's own imports stage named `_OBJC_CLASS_$_UILayoutGuide` as the one symbol
`libCarPlayBackports.dylib` imported that the device's iOS 6.1.3 does not export. So neither the
release nor this port answers the property, there is nothing for a row to describe, and the
ledger's row stays `missing` -- which is the honest word for a member nobody carries. The map
template's own buttons are laid out inside the map view's own insets, so the picture does not
depend on it either way.

**The wall, per class, as `absent` (7 of them):** `CPTemplateApplicationScene` (13.0),
`CPTemplateApplicationDashboardScene` (13.4), `CPTemplateApplicationInstrumentClusterScene` (15.4),
`CPNavigationSession`, `CPSessionConfiguration`, `CPVoiceControlState` and `CPVoiceControlTemplate`.
`CPRouteChoice` is **not** among them: a route choice is a choice of route between two places, which
is arithmetic, and it is built and registered implemented. Each one's own reason is in its entry, and `NSClassFromString` answers nil
for all of them, which is what `absent` means.

## What is not carried, and why that is not `absent`

The 48 classes named in the table above -- `CPNowPlayingTemplate` and the now-playing buttons, `CPTabBarTemplate`,
`CPInformationTemplate`, `CPContactTemplate`, `CPSearchTemplate`, `CPActionSheetTemplate`,
`CPAlertTemplate`, `CPTrip`, `CPSearchTemplateDelegate` and the rest -- have **no registry entry at
all**, on purpose. They are not `absent`: they draw in-app like the seventeen do, and nothing about
them needs a car, so calling them absent would be a false claim. They are simply not written yet, and
the ledger's rows for them stay `missing`, which is the honest state. They are the next CarPlay round,
and they follow the shapes read here.
