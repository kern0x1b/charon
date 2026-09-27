# The accessibility settings of iOS 10

`UIAccessibilityIsAssistiveTouchRunning()` and `UIAccessibilityHearingDevicePairedEar()`, and the
two notification names that go with them (`UIKit/UIAccessibilitySettings10.m`).

Neither function is in the 6.1.3 cache, so there is no release of the port's architecture that
carries them and nothing to differ against. Both answers are the ones the SDK's own header states
for a release that has none of the hardware and none of the setting.

## AssistiveTouch

`UIAccessibilityIsAssistiveTouchRunning()` answers `NO`. Its own header gives the rule
(SDK 26.2, `UIAccessibility.h:600`):

> This always returns false if Guided Access is not enabled.

iOS 6.1.3 cannot be put into Guided Access by an application at all - the request that would do it
is iOS 7's `UIAccessibilityRequestGuidedAccessSession()`, and it needs a supervised,
MDM-whitelisted device (`UIAccessibilityGuidedAccess7.md`) - and has no AssistiveTouch of its own,
so there is no preference to read. `NO` is the header's own answer for every release in that state,
and it is the same answer this package already gives for the other settings iOS 6 does not have
(`UIAccessibility+Settings.m`: switch control, speak screen, bold text and the rest).

`UIAccessibilityAssistiveTouchStatusDidChangeNotification` is carried under its own name and never
posted, as every other status notification of this package is.

## The paired hearing device

`UIAccessibilityHearingDevicePairedEar()` answers `UIAccessibilityHearingDeviceEarNone`, which is 0,
the "no ear" case of the enumeration. Its own header names what it reports (SDK 26.2,
`UIAccessibility.h:628`):

> Returns the current pairing status of MFi hearing aids

MFi hearing aids pair over the MFi audio protocols, which arrived after iOS 6: a device that has
none of them cannot be paired with, and a device that is not paired with has no ear to report. The
enumeration is an options mask (`None` 0, `Left` 1 << 1, `Right` 1 << 2, `Both` the two together), so
`None` is also the right answer for a device that is paired with a device covering both ears and has
no such thing to pair - the same value, for the same reason.

`UIAccessibilityHearingDevicePairedEarDidChangeNotification` is carried under its own name and
never posted.
