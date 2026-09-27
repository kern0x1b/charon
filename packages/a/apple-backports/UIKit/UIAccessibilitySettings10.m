// The accessibility settings iOS 10 added (facts/UIKit/UIAccessibilitySettings10.md).
//
// One object carries one release: both symbols here are first exported by iOS 10.0, which is the
// first held release that has them.

#import <UIKit/UIKit.h>

BOOL UIAccessibilityIsAssistiveTouchRunning(void)
{
    // "This always returns false if Guided Access is not enabled" (the header of SDK 26.2,
    // UIAccessibility.h:600). iOS 6 has no Guided Access an application can be locked into, and no
    // AssistiveTouch of its own, so there is no preference to read and the answer is NO, as the
    // header's own sentence gives for every release that cannot be in Guided Access.
    return NO;
}

UIAccessibilityHearingDeviceEar UIAccessibilityHearingDevicePairedEar(void)
{
    // "Returns the current pairing status of MFi hearing aids" (the header of SDK 26.2,
    // UIAccessibility.h:628). MFi hearing aids pair with a release that has the MFi audio
    // protocols, and iOS 6 has none of them: no such device can be paired, so no ear is.
    return UIAccessibilityHearingDeviceEarNone;
}
