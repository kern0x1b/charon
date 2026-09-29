//
//  CharonAXSettings.h
//  Accessibility
//
//  The settings functions of 18.0, 17.0 and 26.1, and the Settings-section enumeration of 18.0, under
//  the names an application writes. AXSettings.h is not in the SDK this package compiles against - it
//  arrived after 16.4 - so these are transcribed: the names, the kinds, the parameter and return types
//  and the availability, and nothing else. No line of Apple's prose is reproduced here and no body of
//  Apple's is copied; every body is in CharonAXSettings17.m, CharonAXSettings18.m or
//  CharonAXSettings26.m and is the port's own.
//
//  Why each answer is what it is, and the measurement behind it, is in
//  facts/Accessibility/Accessibility.md. In one line each, and the same line appears above every body:
//  this release carries no accessibility preference of any of these five kinds, so the value is NO and
//  cannot change, so the notification that announces the change is never posted.
//
//  Three of these are the framework's own C surface with no device behind them at all -
//  AXAssistiveAccessEnabled, AXOpenSettingsFeature and the Settings-section enumeration - and the port
//  answers them as a release with no assistive-access mode and no such Settings sections answers them.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(17.0))
FOUNDATION_EXPORT BOOL AXPrefersHorizontalTextLayout(void);

API_AVAILABLE(ios(17.0))
FOUNDATION_EXPORT NSNotificationName const _Nonnull AXPrefersHorizontalTextLayoutDidChangeNotification;

API_AVAILABLE(ios(17.0))
FOUNDATION_EXPORT BOOL AXAnimatedImagesEnabled(void);

API_AVAILABLE(ios(17.0))
FOUNDATION_EXPORT NSNotificationName const _Nonnull AXAnimatedImagesEnabledDidChangeNotification;

API_AVAILABLE(ios(18.0))
FOUNDATION_EXPORT BOOL AXAssistiveAccessEnabled(void);

API_AVAILABLE(ios(18.0))
FOUNDATION_EXPORT BOOL AXPrefersNonBlinkingTextInsertionIndicator(void);

API_AVAILABLE(ios(18.0))
FOUNDATION_EXPORT NSNotificationName const _Nonnull AXPrefersNonBlinkingTextInsertionIndicatorDidChangeNotification;

// The sections the Settings app of 18.0 opens at. The cases are names and numbers from the header, and
// they are here because AXOpenSettingsFeature takes one: a caller on this release has nothing to open
// whatever it asks for, and the case is what the caller's switch matched.
typedef NS_ENUM(NSInteger, AXSettingsFeature) {
    AXSettingsFeaturePersonalVoiceAllowAppsToRequestToUse = 1,
    AXSettingsFeatureAllowAppsToAddAudioToCalls = 2,
    AXSettingsFeatureAssistiveTouch = 3,
    AXSettingsFeatureAssistiveTouchDevices = 4,
    AXSettingsFeatureDwellControl = 5,
} API_AVAILABLE(ios(18.0));

API_AVAILABLE(ios(18.0))
FOUNDATION_EXPORT void AXOpenSettingsFeature(AXSettingsFeature feature,
                                             void (^_Nullable completionHandler)(NSError *_Nullable error));

NS_ASSUME_NONNULL_END

API_AVAILABLE(ios(26.1))
FOUNDATION_EXPORT BOOL AXPrefersActionSliderAlternative(void);

API_AVAILABLE(ios(26.1))
FOUNDATION_EXPORT NSNotificationName const _Nonnull AXPrefersActionSliderAlternativeDidChangeNotification;

API_AVAILABLE(ios(26.1))
FOUNDATION_EXPORT BOOL AXShowBordersEnabled(void);

API_AVAILABLE(ios(26.1))
FOUNDATION_EXPORT NSNotificationName const _Nonnull AXShowBordersEnabledStatusDidChangeNotification;
