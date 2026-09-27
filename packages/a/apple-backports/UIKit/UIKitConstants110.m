// The UIKit constants first exported by iOS 11.0
// (facts/UIKit/UIKitConstants110.md).
//
// One object carries one release: every symbol here is first exported by the oldest
// held release that has it, so a band from 11.0 on re-exports the release's own and the
// bands below keep this one.
//
// Every value below was read out of a real dyld shared cache, /System/Library/PrivateFrameworks/UIFoundation.framework/UIFoundation,
// never from a header and never from a host framework.

#import <UIKit/UIKit.h>

const NSTextListMarkerFormat NSTextListMarkerBox = @"{box}";
const NSTextListMarkerFormat NSTextListMarkerCheck = @"{check}";
const NSTextListMarkerFormat NSTextListMarkerCircle = @"{circle}";
const NSTextListMarkerFormat NSTextListMarkerDecimal = @"{decimal}";
const NSTextListMarkerFormat NSTextListMarkerDiamond = @"{diamond}";
const NSTextListMarkerFormat NSTextListMarkerDisc = @"{disc}";
const NSTextListMarkerFormat NSTextListMarkerHyphen = @"{hyphen}";
const NSTextListMarkerFormat NSTextListMarkerLowercaseAlpha = @"{lower-alpha}";
const NSTextListMarkerFormat NSTextListMarkerLowercaseHexadecimal = @"{lower-hexadecimal}";
const NSTextListMarkerFormat NSTextListMarkerLowercaseLatin = @"{lower-latin}";
const NSTextListMarkerFormat NSTextListMarkerLowercaseRoman = @"{lower-roman}";
const NSTextListMarkerFormat NSTextListMarkerOctal = @"{octal}";
const NSTextListMarkerFormat NSTextListMarkerSquare = @"{square}";
const NSTextListMarkerFormat NSTextListMarkerUppercaseAlpha = @"{upper-alpha}";
const NSTextListMarkerFormat NSTextListMarkerUppercaseHexadecimal = @"{upper-hexadecimal}";
const NSTextListMarkerFormat NSTextListMarkerUppercaseLatin = @"{upper-latin}";
const NSTextListMarkerFormat NSTextListMarkerUppercaseRoman = @"{upper-roman}";
const NSErrorDomain UIDocumentBrowserErrorDomain = @"com.apple.DocumentManager";
const NSNotificationName UIFocusDidUpdateNotification = @"UIFocusDidUpdateNotification";
const NSNotificationName UIFocusMovementDidFailNotification = @"UIFocusMovementDidFailNotification";
NSString *const UIFocusUpdateAnimationCoordinatorKey = @"UIFocusUpdateAnimationCoordinatorKey";
NSString *const UIFocusUpdateContextKey = @"UIFocusUpdateContextKey";
