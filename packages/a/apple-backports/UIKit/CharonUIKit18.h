// CharonUIKit18.h - the 18.1-18.4 names UIKit's 18.x bands add, declared because the BUILD SDK does not
// have them.
//
// The build SDK is 16.4, so none of the classes below exist in a header the port compiles against:
// measured, the 16.4 SDK's UIKit.framework/Headers holds 351 headers and @interface UIGlassEffect,
// @interface UIWritingToolsCoordinator and @interface UIConversationEntry are in none of them (the same
// measurement CharonUIKit26.h rests on).  A class is a DYLD SYMBOL - an application that links
// strongly against UIWritingToolsCoordinator names _OBJC_CLASS_$_UIWritingToolsCoordinator and dyld has
// to find it - so for these names the whole honest answer is that the NAME EXISTS AND IS EXPORTED.
//
// So each class here is declared and given an empty implementation, exactly as CharonUIKit26.h's
// twenty-one are.  That is not a stub: a class with no members IS the complete honest answer for a
// name whose only requirement is that dyld resolve it, and a class with invented members would be
// worse than an empty one - it would answer for behaviour nobody measured.  The registry row for each
// says exactly that.
//
// NO SUPERCLASS BUT NSObject AND NO PROTOCOLS, AND THAT IS THE MEASURED CLAIM, NOT A DEFAULT.  Nothing
// in this tree declares what these classes inherit from or conform to: the 26.2 sysroot is not in the
// store (only iPhoneOS16.4.sdk is, at ~/.xmake/packages/i/iphoneos-sdk/16.4/), so there is no
// declaration here to read a superclass or a protocol list out of, and declaring one would be a guess
// with a symbol on it.  NSObject is the minimum that makes the name exist.  A caller that sends one of
// these a message from UIKit gets an unrecognised-selector answer, which is the same answer it gets
// from a class that exists and has no such method - and the row says so rather than implying a
// behaviour the port has not measured.
//
// GUARDED ON THE SDK'S OWN AVAILABILITY MACROS rather than on __has_include, because the header names
// these classes live in are not measurable from this tree.  AvailabilityVersions.h in the 16.4 SDK
// defines __IPHONE_16_4 as its highest and no __IPHONE_17_* or __IPHONE_18_*, so both guards are open
// here; an SDK of 18.2 or later defines __IPHONE_18_2 and the SDK's own declaration is used instead,
// and this file steps aside rather than redefining it.
#ifndef CHARON_UIKIT18_H
#define CHARON_UIKIT18_H

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#if !defined(__IPHONE_18_2)

// Writing Tools, iOS 18.2.  Three objects and nothing else: the coordinator a text view talks to, the
// per-request context it hands back, and the timing parameters a text animation is driven with.
API_AVAILABLE(ios(18.2))
@interface UIWritingToolsCoordinator : NSObject
@end

API_AVAILABLE(ios(18.2))
@interface UIWritingToolsCoordinatorContext : NSObject
@end

API_AVAILABLE(ios(18.2))
@interface UIWritingToolsCoordinatorAnimationParameters : NSObject
@end

#endif   // !defined(__IPHONE_18_2)

#if !defined(__IPHONE_18_4)

// The conversation a suggestion belongs to, and the suggestion itself.  Eight names in three families,
// because that is how the queue names them: the abstract pair (UIConversationContext, UIConversationEntry)
// and the two concrete pairs that specialise it for Mail and Messages.
API_AVAILABLE(ios(18.4))
@interface UIConversationContext : NSObject
@end

API_AVAILABLE(ios(18.4))
@interface UIConversationEntry : NSObject
@end

API_AVAILABLE(ios(18.4))
@interface UIMailConversationContext : NSObject
@end

API_AVAILABLE(ios(18.4))
@interface UIMailConversationEntry : NSObject
@end

API_AVAILABLE(ios(18.4))
@interface UIMessageConversationContext : NSObject
@end

API_AVAILABLE(ios(18.4))
@interface UIMessageConversationEntry : NSObject
@end

// What a text input offers while the user types: one input suggestion, and the smart reply that is one.
API_AVAILABLE(ios(18.4))
@interface UIInputSuggestion : NSObject
@end

API_AVAILABLE(ios(18.4))
@interface UISmartReplySuggestion : NSObject
@end

#endif   // !defined(__IPHONE_18_4)

NS_ASSUME_NONNULL_END

#endif   // CHARON_UIKIT18_H
