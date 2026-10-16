# The home indicator and the edge gestures of a view controller

`-prefersHomeIndicatorAutoHidden`, `-preferredScreenEdgesDeferringSystemGestures`, `-childViewControllerForHomeIndicatorAutoHidden`,
`-childViewControllerForScreenEdgesDeferringSystemGestures` and the two `-setNeedsUpdateOf…` requests are what a controller of the release
overrides or sends to say that the indicator is to hide, or which screen edges are to leave the system gestures alone. This device has a home button and
no indicator, so nothing reads the indicator's answers. Whether the edges of this device carry system gestures for a controller to defer is not
measured here, and the edge rows are not part of this change.

Source: UIKit of iOS 12.0 arm64 (each method read at its address in the cache), and the host's own UIKit under Mac Catalyst, recorded by
`tests/backports/host/homeindicator/run.sh` and held against the port on the iPad 2 by `tests/backports/device/homeindicator.m`.

## What the port does

- The four getters of `UIViewController` answer what the release's default answers: NO, no edge, and no child.
- `UINavigationController` answers its top view controller and `UITabBarController` its selected view controller for the two child properties, as the
  release's overrides do.
- `-setNeedsUpdateOfHomeIndicatorAutoHidden` and `-setNeedsUpdateOfScreenEdgesDeferringSystemGestures` go to the parent view controller, or to the
  presenting one when there is no parent, and stop at the root, where the release hands the request to the application. A controller in the chain that
  overrides the method sees it once, as on the release.

Not carried: the update itself, which asks the application to redraw an indicator or to defer a system gesture, neither of which this device has.
The indicator half is a part this device does not have, so the answers above are the release's own for a device without one. The edge half is not
settled: the top edge of iOS 6 is believed to carry the pull-down of Notification Center, which a deferral would have to reach, and that is not
measured here. `-preferredScreenEdgesDeferringSystemGestures`, the two edge children and `-setNeedsUpdateOfScreenEdgesDeferringSystemGestures` stay
`inert` until it is measured, and then either deferred or refused in the registry.
