#import <Foundation/Foundation.h>

NSString *const NSExtensionItemsAndErrorsKey = @"NSExtensionItemsAndErrorsKey";

@implementation NSExtensionContext

@synthesize inputItems;

- (NSArray *)inputItems
{
    return inputItems ?: @[];
}

- (void)completeRequestReturningItems:(NSArray *)items completionHandler:(void (^)(BOOL expired))completionHandler
{
}

- (void)cancelRequestWithError:(NSError *)error
{
}

- (void)openURL:(NSURL *)URL completionHandler:(void (^)(BOOL success))completionHandler
{
}

@end
