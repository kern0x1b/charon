# Appearances on the bars of iOS 6, iOS 13

Source: the public SDK headers of iOS 13 to 27; the host's own UIKit, under Mac Catalyst, for what a bar hands back
(`tests/backports/host/uikit2/appearances_test.m`: the defaults, the copies, clearing, and, through the legacy
accessors of the host's bars, what the port sets); and the iOS 6 calls the port maps them onto, which the device test
cannot exercise, since it makes no views.

## The four properties

`UINavigationBar` and `UIToolbar` answer `standardAppearance` and `compactAppearance`, `UITabBar` answers
`standardAppearance`, and all are applied. The rest are kept and applied to nothing: `scrollEdgeAppearance` of the
navigation bar, `scrollEdgeAppearance` and `compactScrollEdgeAppearance` of the toolbar, `scrollEdgeAppearance` of the
tab bar and `compactScrollEdgeAppearance` of the navigation bar, and the four of a `UINavigationItem` and the two of a
`UITabBarItem`. They are `inert`: each keeps a copy, hands it back, and says once in the log that iOS 6 has no scroll
position and no per-item look to choose one by. A bar that is not at a scroll edge in iOS 13 uses the standard
appearance, and so does this one, always.

What the host answers, and the backport answers as well:

- `standardAppearance` is never nil: a bar that was never given one answers a new appearance of its own kind, the same
  object every time. Setting nil brings that default back. The others answer nil until set.
- A setter keeps a copy of what it is given, and the getter answers that copy, so a change to the object handed in
  changes nothing and a change to the object handed back is a change to the bar.
- An object of the wrong kind is kept and applied to nothing, where the host raises nothing either.
- A tab bar answers no compact appearance.

## When an appearance is applied

The setters apply at once. A change made later to the appearance a bar keeps, through the object the getter
handed back, is applied on the next turn of the run loop, once for any number of changes. The default appearance
a bar hands back is applied only when it is changed, so reading it changes nothing. Setting nil takes back what an
earlier appearance applied.

The bar's legacy calls are the ones the appearance is mapped onto. An application that uses both has the
appearance win, as in iOS 13, since the appearance is applied whole: what it does not set is cleared.

## The map

| appearance | iOS 6 |
|---|---|
| `backgroundImage` | `setBackgroundImage:forBarMetrics:` of the bar, as it is; the content mode is kept and ignored |
| `backgroundColor`, no image | a one point image of the colour, stretched, through the same call |
| no image, no colour, no effect (the transparent and the new navigation bar look) | an empty image, so the bar is clear |
| the default effect, no image, no colour | nothing: the bar keeps the look iOS 6 gives it; the blur is ignored |
| `shadowImage` | `shadowImage` of the bar; with a background image or colour applied only, since iOS 6 draws no shadow otherwise |
| `shadowColor`, no image | a hairline of the colour, one pixel tall, as the shadow; nil is an empty image, no shadow |
| `titleTextAttributes` (navigation) | `titleTextAttributes` of the bar, the font and colour and the shadow of an `NSShadow` turned into the `UITextAttribute` keys of iOS 6; every other key is dropped |
| `titlePositionAdjustment` (navigation) | `setTitleVerticalPositionAdjustment:forBarMetrics:`; the horizontal part has no counterpart |
| `compactAppearance` | the same, for `UIBarMetricsLandscapePhone`; without one the metrics are cleared and the standard image shows |
| `buttonAppearance` | on `UIBarButtonItem appearanceWhenContainedIn:` the bar's class: the title text attributes of the normal, highlighted and disabled states when they differ from the defaults, the title offset of the normal state, the plain background image of each state |
| `doneButtonAppearance`, `prominentButtonAppearance` | the background images of the done style; its text attributes are not applied, since iOS 6 has one set per state for both styles |
| `backButtonAppearance` | `setBackButtonBackgroundImage:forState:barMetrics:` and the back button's title offset; its title attributes are those of the plain button |
| tab bar `selectionIndicatorImage` | `selectionIndicatorImage` of the tab bar |
| tab bar stacked `selected.iconColor` | `selectedImageTintColor` |
| tab bar stacked `normal` and `selected` title attributes, and the normal title offset | `UITabBarItem appearanceWhenContainedIn:` the tab bar, states normal and selected |

The buttons are set on the appearance proxy of a bar's class, since iOS 6 has no button setting for one bar: they reach
every bar of that class in the application, and only views that come into a window afterwards. A program that sets an appearance
on one navigation bar of several gets the button look on all of them.

## Kept in the object and not applied

- `backgroundEffect` blur, of any style; `backgroundImageContentMode`; the compact shadow, since iOS 6 has one shadow
  for a bar.
- `largeTitleTextAttributes` (says once in the log), the horizontal title offset, the back indicator images
  (`inert`, as on the bar itself since iOS 7's `backIndicatorImage`), the focused state of every button, the position
  adjustments of a background image, and the text attributes of the prominent button.
- On a tab bar (says once in the log): the icon colour of an unselected tab, the badge appearance, the inline and
  compact inline layouts, `selectionIndicatorTintColor` and the positioning, width and spacing of the items.
- `barTintColor`, which the port carries for iOS 7, is not touched.

## Unsure, to be proved on a device

The legacy proxies of iOS 6 are checked for when a view enters a window, so an appearance set after a bar is on
screen may not reach the buttons already there until they leave and return. Reading the proxy back, the host's UIKit
answers what was set; that iOS 6's answers the same has not been read.
