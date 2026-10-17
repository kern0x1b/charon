//
//  CharonNSExtensionContext.m
//  IntentsUI
//
//  NSExtensionContext, for a release that has no extension host. NSExtensionContext is iOS 8's class, so iOS 6 has none,
//  and the three members IntentsUI adds to it (hostedViewMinimumAllowedSize, hostedViewMaximumAllowedSize and
//  interfaceParametersDescription) need a context to be sent to. The class here answers what an application's own
//  context answers, and no more: no input items, the zero sizes, and no interface parameters.
//
//  The host's answers for a fresh context, measured on Catalyst by tests/backports/host/nsextension-context: inputItems
//  empty, both sizes zero, interfaceParametersDescription nil. Its completeRequestReturningItems:completionHandler:
//  does not call back on a context that no extension host has started. This class calls back, once, with expired NO,
//  because the request is complete when the application asks for it; that difference from the host is the one the
//  ruling made, and facts/IntentsUI/IntentsUI.md says so. cancelRequestWithError: and openURL:completionHandler: are
//  declared by the header and are not in any row of this package, so they are not defined here.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@implementation NSExtensionContext

// The host answers a mutable array that is empty, and so does this: a new one each time, so no caller can change the context.
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

// The three members of the category IntentsUI declares on NSExtensionContext (INUIHostedViewControlling.h). A context
// with no host has no size to be shown in and no parameters to describe, so the answers are the host's, measured.
- (CGSize)hostedViewMinimumAllowedSize
{
    return CGSizeZero;
}

- (CGSize)hostedViewMaximumAllowedSize
{
    return CGSizeZero;
}

- (NSString *)interfaceParametersDescription
{
    return nil;
}

@end
