#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#pragma clang diagnostic ignored "-Wnonnull"

static const char charon_handler_key;

@implementation UIAccessibilityCustomAction (CharonHandler13)

- (instancetype)initWithName:(NSString *)name actionHandler:(UIAccessibilityCustomActionHandler)actionHandler
{
    if ((self = [self initWithName:name target:nil selector:NULL]))
        [self setActionHandler:actionHandler];   // a send, not a dot-syntax write: a write is renamed by the
    // property name it reads, and a category on a host class has both the accessor and the setter renamed,
    // so only a send keeps the two the same name
    return self;
}

- (UIAccessibilityCustomActionHandler)actionHandler
{
    return objc_getAssociatedObject(self, &charon_handler_key);
}

- (void)setActionHandler:(UIAccessibilityCustomActionHandler)actionHandler
{
    objc_setAssociatedObject(self, &charon_handler_key, actionHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

@end
