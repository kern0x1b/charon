// UIContentUnavailableConfiguration.h - the configuration of the empty-state API of iOS 17.0 and the
// content view that draws it, declared because the BUILD SDK does not declare them.
//
// The build SDK is 16.4 and neither class is in a header under its UIKit.framework/Headers, which is the
// same position UIContentUnavailableProperties.h states for the three property bags and the state, so
// this sits beside that header and takes its guard from the same place: __has_include, so a future build
// SDK that ships these names uses the system's own declaration and this file steps aside.
//
// The transcription is read from the SDK that declares these names, charon/.agent-work/sdk-26.2's
// iPhoneOS26.2.sdk/System/Library/Frameworks/UIKit.framework/Headers, and every default the
// implementation sets is what the host measured first
// (facts/UIKit/UIContentUnavailable17.md, M4) - the header states none of them.
//
// A class is a DYLD SYMBOL before it is anything else, so an application that links strongly against
// UIContentUnavailableConfiguration names _OBJC_CLASS_$_UIContentUnavailableConfiguration and dyld has to
// find it.  That is why these two are declared and implemented rather than left to a missing-header error:
// the name must resolve on 6.1.3 and on 4.3.

#ifndef CHARON_UIKIT_CONTENTUNAVAILABLECONFIGURATION_H
#define CHARON_UIKIT_CONTENTUNAVAILABLECONFIGURATION_H

#import <UIKit/UIKit.h>
#import "UIContentUnavailableProperties.h"

NS_ASSUME_NONNULL_BEGIN

#if !__has_include(<UIKit/UIContentUnavailableConfiguration.h>)

typedef NS_ENUM(NSInteger, UIContentUnavailableAlignment) {
    UIContentUnavailableAlignmentCenter,
    UIContentUnavailableAlignmentNatural
} API_AVAILABLE(ios(17.0), tvos(17.0)) API_UNAVAILABLE(watchos);

API_AVAILABLE(ios(17.0), tvos(17.0)) API_UNAVAILABLE(watchos)
@interface UIContentUnavailableConfiguration : NSObject <UIContentConfiguration, NSSecureCoding>

/// Returns the default configuration for unavailable content.
+ (instancetype)emptyConfiguration;
/// Returns the default configuration for content which is loading.
+ (instancetype)loadingConfiguration;
/// Returns the default configuration for searches which return no results.
+ (instancetype)searchConfiguration;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

/// The image to display.
@property (nonatomic, strong, nullable) UIImage *image;
/// Additional properties to configure the image.
@property (nonatomic, readonly) UIContentUnavailableImageProperties *imageProperties;

/// The primary text.
@property (nonatomic, copy, nullable) NSString *text;
/// An attributed variant of the primary text.
@property (nonatomic, copy, nullable) NSAttributedString *attributedText;
/// Additional properties to configure the primary text.
@property (nonatomic, readonly) UIContentUnavailableTextProperties *textProperties;

/// The secondary text.
@property (nonatomic, copy, nullable) NSString *secondaryText;
/// An attributed variant of the secondary text.
@property (nonatomic, copy, nullable) NSAttributedString *secondaryAttributedText;
/// Additional properties to configure the secondary text.
@property (nonatomic, readonly) UIContentUnavailableTextProperties *secondaryTextProperties;

/// The primary button.
@property (nonatomic, strong) UIButtonConfiguration *button;
/// Additional properties to configure the primary button.
@property (nonatomic, readonly) UIContentUnavailableButtonProperties *buttonProperties;

/// The secondary button.
@property (nonatomic, strong) UIButtonConfiguration *secondaryButton;
/// Additional properties to configure the secondary button.
@property (nonatomic, readonly) UIContentUnavailableButtonProperties *secondaryButtonProperties;

/// The alignment of the image, text and buttons.
@property (nonatomic) UIContentUnavailableAlignment alignment;
/// Whether the content view preserves inherited layout margins from its superview on each axis.
@property (nonatomic) UIAxis axesPreservingSuperviewLayoutMargins;
/// The margins for the content to the edges of the content view.
@property (nonatomic) NSDirectionalEdgeInsets directionalLayoutMargins;

/// Padding between the image and text.
@property (nonatomic) CGFloat imageToTextPadding;
/// Padding between the text and secondary text.
@property (nonatomic) CGFloat textToSecondaryTextPadding;
/// Padding between the button and text.
@property (nonatomic) CGFloat textToButtonPadding;
/// Padding between the button and secondary button.
@property (nonatomic) CGFloat buttonToSecondaryButtonPadding;

/// The background configuration.
@property (nonatomic, strong) UIBackgroundConfiguration *background;

@end

API_AVAILABLE(ios(17.0), tvos(17.0)) API_UNAVAILABLE(watchos)
@interface UIContentUnavailableView : UIView <UIContentView>

- (instancetype)initWithConfiguration:(UIContentUnavailableConfiguration *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The content unavailable configuration.
@property (nonatomic, copy) UIContentUnavailableConfiguration *configuration;

/// Whether the content can scroll.  Default is NO.
@property (nonatomic, getter=isScrollEnabled) BOOL scrollEnabled;

@end

#endif   // !__has_include(<UIKit/UIContentUnavailableConfiguration.h>)

NS_ASSUME_NONNULL_END

#endif   // CHARON_UIKIT_CONTENTUNAVAILABLECONFIGURATION_H