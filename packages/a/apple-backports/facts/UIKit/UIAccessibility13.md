# Accessibility of iOS 13 and 14

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), for the answers and the values, and the `views13` group of
`tests/backports/host/uikit2` for the members that are categories.

## Settings

`UIAccessibilityShouldDifferentiateWithoutColor()`, `UIAccessibilityIsOnOffSwitchLabelsEnabled()`, `UIAccessibilityButtonShapesEnabled()`
and `UIAccessibilityPrefersCrossFadeTransitions()` answer NO: iOS 6 has none of the settings. `UIAccessibilityIsVideoAutoplayEnabled()`
answers YES, as the host does with the setting at its default, and nothing on the release turns video previews off. The
notifications that would say they changed - `...ShouldDifferentiateWithoutColorDidChangeNotification`,
`...OnOffSwitchLabelsDidChangeNotification`, `...VideoAutoplayStatusDidChangeNotification`, `...ButtonShapesEnabledStatusDidChangeNotification`
and `...PrefersCrossFadeTransitionsStatusDidChangeNotification` - are their own names and are never posted.

## Names

`UIAccessibilityTextAttributeContext`, `UIAccessibilitySpeechAttributeSpellOut` and the seven `UIAccessibilityTextualContext...`
values are the strings of their names, as the host has them. VoiceOver of iOS 6 reads no text by them.

## Objects

`accessibilityUserInputLabels` answers an empty array until set, `accessibilityAttributedUserInputLabels` nil; setting one gives the
other: the attributed labels of plain ones are attributed strings with no attributes, the plain ones of attributed labels their
strings. The arrays are copied. `accessibilityTextualContext` and `accessibilityRespondsToUserInteraction` (NO) are kept. There is no
Voice Control or dictation context on the release to read them, so the first one set says so once in the log.

## Custom actions

`UIAccessibilityCustomAction` is inert on this release already: VoiceOver lists none. The handler forms `-initWithName:actionHandler:`
(iOS 13) and `-initWithName:image:actionHandler:` and `-initWithName:image:target:selector:` (iOS 14) are made and keep their handler
and image, with `actionHandler` and `image` as properties; the handler is never called. The forms with an attributed name are absent,
as `initWithAttributedName:target:selector:` of iOS 11 is (`registry/UIKit/ios11.json`).
