# Key commands, custom accessibility actions and the accessibility settings, iOS 7 to 9

Source: the host's own UIKit, recorded for the constant values, the defaults, the copies and the archive, and held against the
port by the checks of `tests/backports/device/uikit2.m`.

## Key commands (iOS 7)

`UIKeyCommand` is made with `+keyCommandWithInput:modifierFlags:action:` (iOS 9 added a discoverability title, which is
kept) and answers its input, modifier flags and action. A command made with `init` has no input and the action `_nop`, as the
system's does; a copy is another command with the same fields; two commands with the same input, flags and action are equal;
the class supports secure coding. The five arrow and escape inputs (iOS 7) and the page inputs (iOS 8) are the names of
their constants. `UIResponder.keyCommands` answers `nil` unless the application overrides it.

iOS 6 does not ask a responder for its key commands: a hardware keyboard reaches an application as text through the
first responder, and nothing calls a key command. The class and the property are `inert`. The properties iOS 13 added to the
class - the title, the image, the property list, the attributes, the state and the alternates - are carried with the class becoming a
`UICommand` (`UICommand.md`); iOS 15's are in `UIKeyCommandPriority.md`.

## Custom accessibility actions (iOS 8)

`UIAccessibilityCustomAction` keeps its name, target and selector, and `accessibilityCustomActions`,
`accessibilityElements` and `accessibilityNavigationStyle` of any object keep what they are given, with `nil` and the
automatic style as the defaults. VoiceOver of iOS 6 lists no custom actions and does not read the other two, so they are
`inert`.

## Accessibility settings (iOS 8, 9)

iOS 6 has none of bold text, grayscale, reduce motion, reduce transparency, darker system colours, speak screen, speak
selection and switch control, so the functions that ask about them answer `NO`, and the notifications that would say
they changed are carried and never posted. Shake to undo is always on in iOS 6, so `UIAccessibilityIsShakeToUndoEnabled()`
answers `YES`, as the host does; and there is no element with an assistive technology's focus, so
`UIAccessibilityFocusedElement()` answers `nil`. The values of the constants, and of the two numbers that pause and resume
an assistive technology (1033 and 1034), are the host's.

## The URL of the settings of an application (iOS 8)

`UIApplicationOpenSettingsURLString` is `app-settings:`. iOS 6 has no settings page for an application and no handler
for that scheme, so `-openURL:` on it answers `NO`, which an application that checks `-canOpenURL:` first already handles.
