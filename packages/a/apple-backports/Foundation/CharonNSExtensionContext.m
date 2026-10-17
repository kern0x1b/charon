//
//  CharonNSExtensionContext.m
//  Foundation
//
//  NSExtensionContext, for a release that has no extension host. NSExtensionContext is iOS 8's class, so iOS 6 has none,
//  and the members that IntentsUI and NotificationCenter add to it need a context to be sent to. The class here answers
//  what an application's own context answers, and no more: no input items, and a completion that calls back.
//
//  The host's answers for a fresh context, measured on Catalyst by tests/backports/host/nsextension-context: inputItems
//  empty (class __NSArrayM). Its completeRequestReturningItems:completionHandler: does not call back on a context that no
//  extension host has started. This class calls back, once, with expired NO, because the request is complete when the
//  application asks for it: that is the ruling, and facts/IntentsUI/IntentsUI.md records it as the one difference.
//  cancelRequestWithError: and openURL:completionHandler: are declared by the header and are in no row of this package,
//  so they are not defined here.
//
//  The members of the category IntentsUI adds are in IntentsUI/, and the widget members NotificationCenter adds are in
//  NotificationCenter/; each category is in the library that declares its framework.
//

#import <Foundation/Foundation.h>

@implementation NSExtensionContext

// The host answers a mutable array that is empty, and so does this: a new one each time, so no caller can change it.
- (NSArray *)inputItems
{
    return [NSMutableArray array];
}

- (void)completeRequestReturningItems:(NSArray *)items completionHandler:(void (^)(BOOL expired))completionHandler
{
    if (completionHandler) {
        completionHandler(NO);
    }
}

@end
