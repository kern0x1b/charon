#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

static const char charon_target_key;

@implementation NSUserActivity (CharonTargetContent)

- (NSString *)targetContentIdentifier
{
    return objc_getAssociatedObject(self, &charon_target_key);
}

- (void)setTargetContentIdentifier:(NSString *)targetContentIdentifier
{
    objc_setAssociatedObject(self, &charon_target_key, [targetContentIdentifier copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
