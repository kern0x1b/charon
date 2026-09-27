# NotificationCenter, on a release that has none

iOS 8 brought the Today widget and with it `NotificationCenter.framework`, whose whole purpose is to
be the panel the widget is drawn in. iOS 6.1.3 has no Notification Center, no Today widgets and no
widget host: there is nothing in its armv7 6.1.3 cache that could hold one, and the release's SpringBoard
has no such surface. What is left is the *application's* half of the API, and that is what this
delivery carries.

## `NCWidgetController`: a real record, no consumer

`-[NCWidgetController setHasContent:forWidgetWithBundleIdentifier:]` tells the system that a widget
has content worth reloading, so the system can decide whether to ask the widget to refresh. The flag
is the application's own statement, so the port keeps it - under a namespaced `NSUserDefaults` key,
the same convention `UIApplication+UserNotificationSettings.m` already uses for its registered-types
record and `NCWidgetController` uses for nothing else - and the application reads back exactly what
it wrote. What cannot happen on this release is the reaction: nothing polls the record, because there
is no panel to poll it for. That is said once in the log, at construction, so a process holding the
controller knows why its flags change nothing.

This is the shape the registry's README already allows for MediaPlayer's
`MPRemoteCommandCenter` (`registry/MediaPlayer`, "real, addressable command objects that never fire,
honestly, not fabricated ones").

## The three display-mode members, none of them carried

`NCWidgetDisplayMode` is two cases, and `NCWidgetTypes.h` documents the first as the fixed height and
the second as the variable one. All three members that speak it -
`NSExtensionContext.widgetLargestAvailableDisplayMode`, `-widgetActiveDisplayMode` and
`-widgetMaximumSizeForDisplayMode:` - are registry entries with status `absent`, and the port carries
no code for any of them.

All three are about a widget being shown in a panel, and there is no panel: no Notification Center,
no Today widget, no widget host. A previous pass of this file had the active mode answer the declared
mode and the maximum size answer `CGSizeMake(0, 0)`, and both of those were wrong in the same way -
one derived a number from a declaration nothing would honour, the other produced a size the port made
up. A `CGSizeZero` here also would not have been the honest zero: the constant is an exported symbol
in a modern CoreGraphics that the release's cache does not resolve, which this delivery's first gate
run found for `_CGRectZero` and `_CGRectGetWidth`. What the port does instead is carry none of the
three, so the application is told by `respondsToSelector:` that a release with no panel cannot answer
them.

## The four vibrancy factories, and what is *not* measured

The port's `UIVibrancyEffect` is a real effect: `UIKit/UIVisualEffect.m` keeps the blur style it was
made with, implements `isEqual:`, `hash`, `-description` and `NSCoding` over it, and
`UIKit/UIVibrancyEffect+Style13.m` adds `+effectForBlurEffect:style:` for the vibrancy style itself.
So each factory builds a real effect and the answer compares, archives and describes as the system's
does. The blur style values are read from `UIBlurEffect.h` of SDK 26.2: ExtraLight 0, Light 1,
Dark 2.

**The mapping of a widget style to a material is reasoned from the header's own wording, not
measured.** `widgetPrimaryVibrancyEffect` is documented "for use with select supporting text and
glyphs" and is given `UIBlurEffectStyleLight`; `widgetSecondaryVibrancyEffect` is documented "where
further diminution is required" and is given `UIBlurEffectStyleExtraLight`, the next lighter
material; `notificationCenterVibrancyEffect` is given Light, which is what iOS 10 replaced it with.
There is no host to hold this to, and the reason was measured rather than assumed: compiling a call
to any of the four for `arm64-apple-ios15.0-macabi` against the Command Line Tools' `iOSSupport` fails
with "no known class method for selector 'notificationCenterVibrancyEffect'", because the
deprecation is `ios(13.0, 14.0)` and the host's UIKit no longer declares them. The port's own
`UIVisualEffect` differential (`tests/backports/host/uikit2`, the visualeffect group) is what covers
the effect these factories return.

## `NCWidgetProviding`, and why the protocol is `absent`

All three of its members are messages the *system* sends to the widget's own view controller, and all
three depend on the panel: ask it to refresh, tell it the mode changed, ask it for the insets it
would use. Nothing in the port sends them and nothing in the port reads them, so no class of ours
could conform and the protocol is not carried. An application that writes
`@interface MyWidget : UIViewController <NCWidgetProviding>` gets the protocol emitted in its own
translation unit, with its own implementations on it, which is the whole of what a protocol is for.

`widgetMarginInsetsForProposedMarginInsets:` also carries `maximum: "10.0"`, because the header
itself stops calling it on widgets linked against iOS 10 and later - the port is not going to carry
an API a current release has withdrawn, and the registry's own README gives `removed`/`maximum` as
the way to say so.
