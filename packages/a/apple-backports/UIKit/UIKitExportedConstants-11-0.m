#import <UIKit/UIKit.h>

// The exported constants that arrived in iOS 11.0, and no others: an object carries the API of one
// release, so each release's worth of them is its own file. Every value was read, not chosen -- out
// of a real dyld shared cache with tools/cfconst.py and out of the host's own UIKit, which agree on
// every one both could give; tests/backports/host/uikitconst holds the backport to the host's.

NSString * const NSTextListMarkerBox = @"{box}";
NSString * const NSTextListMarkerCheck = @"{check}";
NSString * const NSTextListMarkerCircle = @"{circle}";
NSString * const NSTextListMarkerDecimal = @"{decimal}";
NSString * const NSTextListMarkerDiamond = @"{diamond}";
NSString * const NSTextListMarkerDisc = @"{disc}";
NSString * const NSTextListMarkerHyphen = @"{hyphen}";
NSString * const NSTextListMarkerLowercaseAlpha = @"{lower-alpha}";
NSString * const NSTextListMarkerLowercaseHexadecimal = @"{lower-hexadecimal}";
NSString * const NSTextListMarkerLowercaseLatin = @"{lower-latin}";
NSString * const NSTextListMarkerLowercaseRoman = @"{lower-roman}";
NSString * const NSTextListMarkerOctal = @"{octal}";
NSString * const NSTextListMarkerSquare = @"{square}";
NSString * const NSTextListMarkerUppercaseAlpha = @"{upper-alpha}";
NSString * const NSTextListMarkerUppercaseHexadecimal = @"{upper-hexadecimal}";
NSString * const NSTextListMarkerUppercaseLatin = @"{upper-latin}";
NSString * const NSTextListMarkerUppercaseRoman = @"{upper-roman}";
NSString * const UIDocumentBrowserErrorDomain = @"com.apple.DocumentManager";
NSString * const UIFocusDidUpdateNotification = @"UIFocusDidUpdateNotification";
NSString * const UIFocusMovementDidFailNotification = @"UIFocusMovementDidFailNotification";
NSString * const UIFocusUpdateAnimationCoordinatorKey = @"UIFocusUpdateAnimationCoordinatorKey";
NSString * const UIFocusUpdateContextKey = @"UIFocusUpdateContextKey";
