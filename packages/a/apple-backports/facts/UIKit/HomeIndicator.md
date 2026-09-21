# The home indicator and the edge gestures of a view controller

`-prefersHomeIndicatorAutoHidden`, `-preferredScreenEdgesDeferringSystemGestures`, `-childViewControllerForHomeIndicatorAutoHidden`,
`-childViewControllerForScreenEdgesDeferringSystemGestures` and the two `-setNeedsUpdateOf…` requests are what a controller of the release
overrides or sends to say that the indicator is to hide, or which screen edges are to leave the system gestures alone. This device has a home button and
no indicator, and the gestures from the edges do not exist on it, so nothing reads the answers.

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
