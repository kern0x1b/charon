# UISearchController, iOS 8

Introduced in iOS 8: the controller that replaces `UISearchDisplayController`. An application gives it a controller
that shows the results, an object that updates them, and puts its search bar in its own view, in iOS 11 in the
navigation item. iOS 9.1 renamed the dimming flag, iOS 13 added `automaticallyShowsCancelButton` and the two
properties that decide when the results show.

Source: UIKit of iOS 10.0.1 armv7s, read for the presentation flow, the order of the delegate's messages and the
dimming; and the host's own UIKit, recorded by `tests/backports/host/searchcontroller/run.sh` from an application
under Mac Catalyst for the cases of `tests/backports/device/searchcontroller-cases.m`, which the device test
`tests/backports/device/searchcontroller.m` holds the port to on the emulated iOS 6.0 and an iPad 2. The host is a Mac,
whose search bar has no cancel button and whose defaults are a Mac's, so nine of its records differ for a stated
reason and are named in the test; the rest are held.

## What the port does

- The search bar is a `UISearchBar` with the placeholder "Search", and answers an empty string, not `nil`, for its
  text. Its delegate is the application's; the controller listens to the bar through a delegate of its own and passes
  every message on, so the application's delegate hears a change of text before the results are updated.
- `active = YES`, or a search bar that begins editing, presents the controller: `willPresentSearchController:`, an
  update of the results with the text of the bar, `didPresentSearchController:` when the animation has finished. A
  delegate that implements `presentSearchController:` is asked to present the controller itself, hears no will-present
  and no did-present, and the results are updated.
- Presenting puts the controller's view over the view of the controller that defines the presentation context, or the
  top of the hierarchy when none does, dims what lies under it (`obscuresBackgroundDuringPresentation`, whose
  deprecated name `dimsBackgroundDuringPresentation` is the same flag), hides the navigation bar
  (`hidesNavigationBarDuringPresentation`), moves the search bar to the top with a cancel button
  (`automaticallyShowsCancelButton`), and shows the results controller's view once there is text
  (`automaticallyShowsSearchResultsController`, or as `showsSearchResultsController` says).
- A change of text, from the keyboard, updates the results; emptying the text hides them.
- Cancelling, or `active = NO`, sets `active` off first, then sends `willDismissSearchController:`, clears the text,
  updates the results with an empty text, restores the search bar where it was, the navigation bar and the cancel
  button, and sends `didDismissSearchController:` when that is done. Making an inactive controller inactive sends
  nothing.
- `UINavigationItem.searchController` puts the search bar in the title of the navigation bar, and taking the
  controller away takes it out; `hidesSearchBarWhenScrolling` and `preferredSearchBarPlacement` (iOS 16) are kept
  and change nothing - there is one placement, the title view, not the automatic/inline/stacked choice the system's
  layout reads it for. `searchBarPlacement` (iOS 16), the placement realised, answers that one placement: inline -
  in the row of the bar, where the system's inline bar sits too - while the controller's bar is the item's title
  view, and automatic, which names no placement, while the item has no controller or the application has put
  another title view in its place (the header calls the value valid only with a controller assigned).

## What it cannot do as the system does

- The system presents the controller modally over its context: `presentingViewController` is the controller that
  defines the presentation context. The port adds its view to that controller's view and makes itself a child, so
  `parentViewController` is set and `presentingViewController` is `nil`, and the presenting controller's
  `presentedViewController` is `nil` unless the application presented the search controller itself.
- The search bar of a navigation item sits in the title of the bar, where the release's navigation bar can hold it,
  not under a large title, which the release does not have. The stacked placement of iOS 16 is not carried, and
  its inline bar sits in the title rather than on the trailing edge; the scope bar is not shown by the controller whatever
  its activation says, and the suggestions are not carried. `searchControllerObservedScrollView` is not declared: the 16.4 header marks it
  `API_UNAVAILABLE(ios)`, so the release has no such property on iOS.
- The results are updated when the text changes and when the search starts and ends; the number of extra updates the
  system makes while a dismissal finishes is not reproduced.

## On a device, iOS 6.1.3

On an iPad 2 of iOS 6.1.3 (2026-09-23), a process of the band's own (`.agent-work/runs/b1314-live/main.m`, output `run4-all.txt` beside it) loaded the gate's `libUIKitBackports.dylib` and checked `UINavigationItem.searchBarPlacement`: automatic for an item with no search controller; the inline case was not run.

## The iOS 16 properties and the scope bar flag

Measured by `tests/backports/host/search-controller` (15 checks, the port's classes and the host's print the same values), in a process with no
application, so the windows and the application are not in play. The host is a Mac under Mac Catalyst.

- `searchBarPlacement` answers stacked (2) for a controller no navigation item holds, and inline (1) while one holds it, and stacked again once the
  item lets it go. It is read-only. The port answers the same: inline while a navigation item's `searchController` setter has the controller (the
  setter tells the controller, through a weak reference, which item holds it), stacked otherwise. A presented controller's placement is not
  measured.
- `scopeBarActivation` is kept as given: Automatic (0), Manual (1) and OnTextEntry (2) read back as set.
- `automaticallyShowsScopeBar` is the activation's flag: YES is Automatic and NO is Manual; after OnTextEntry it reads YES, and setting NO from
  OnTextEntry makes the activation Manual. The port keeps the activation and the flag as one setting, in the controller's storage and the category
  `UISearchController+ScopeBar.m`.
- `ignoresSearchSuggestionsForSearchBarPlacementStacked` is kept as given, and starts NO.
- The defaults are not in the differential. A Mac starts the activation at Manual and the flag at NO; the port starts the activation at Automatic and
  the flag at YES, where the header puts them and where the port has always started the flag. The tests that hold the port to the header (uikit2's
  `searchcategories`, and the device's `pointer` test) check that start.
- `searchSuggestions` is not built. A process with no application reads back an empty array whatever is set (the host's and the port's alike would
  need a running application to answer), so the release's answer is not measured here and the row stays owed.
- The planted controls in `tests/backports/host/search-controller/run.sh` (placement always stacked, the item not registering, the flag not linked,
  the ignored flag not stored, the activation not stored) each fail the differential.
