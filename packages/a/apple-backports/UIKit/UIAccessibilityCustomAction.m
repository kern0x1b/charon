#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <string.h>

@implementation UIAccessibilityCustomAction {
    NSString *_name;
    __weak id _target;
    SEL _selector;
}

@dynamic attributedName, image, actionHandler;

- (instancetype)initWithName:(NSString *)name target:(id)target selector:(SEL)selector
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _target = target;
        _selector = selector;
    }
    return self;
}

- (NSString *)name
{
    return _name;
}

- (void)setName:(NSString *)name
{
    _name = [name copy];
}

- (id)target
{
    return _target;
}

- (void)setTarget:(id)target
{
    _target = target;
}

- (SEL)selector
{
    return _selector;
}

- (void)setSelector:(SEL)selector
{
    _selector = selector;
}

@end

static const void *CharonCustomActionsKey = &CharonCustomActionsKey;
static const void *CharonElementsKey = &CharonElementsKey;
static const void *CharonNavigationStyleKey = &CharonNavigationStyleKey;

// The port's own accessors of accessibilityCustomActions, taken when this image starts, before any framework is opened.
// They are put back in front of the release's by the setter, see CharonReassertCustomActions.
static IMP CharonCustomActionsGetter;
static IMP CharonCustomActionsSetter;
static BOOL CharonCustomActionsArmed;

static void CharonReassertCustomActions(void);

@implementation NSObject (CharonAccessibilityElements)

- (NSArray<UIAccessibilityCustomAction *> *)accessibilityCustomActions
{
    return objc_getAssociatedObject(self, CharonCustomActionsKey);
}

- (void)setAccessibilityCustomActions:(NSArray<UIAccessibilityCustomAction *> *)actions
{
    CharonReassertCustomActions();
    objc_setAssociatedObject(self, CharonCustomActionsKey, [actions copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSArray *)accessibilityElements
{
    return objc_getAssociatedObject(self, CharonElementsKey);
}

- (void)setAccessibilityElements:(NSArray *)elements
{
    objc_setAssociatedObject(self, CharonElementsKey, [elements copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIAccessibilityNavigationStyle)accessibilityNavigationStyle
{
    return (UIAccessibilityNavigationStyle)[objc_getAssociatedObject(self, CharonNavigationStyleKey) integerValue];
}

- (void)setAccessibilityNavigationStyle:(UIAccessibilityNavigationStyle)style
{
    objc_setAssociatedObject(self, CharonNavigationStyleKey, @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

static BOOL CharonInThisImage(const void *address)
{
    Dl_info here, there;
    if (dladdr(address, &there) == 0 || there.dli_fname == NULL || dladdr((const void *)CharonInThisImage, &here) == 0
        || here.dli_fname == NULL) {
        return NO;
    }
    return strcmp(here.dli_fname, there.dli_fname) == 0;
}

// The release's UIAccessibility.framework attaches its own accessibilityCustomActions getter to NSObject when it is
// opened, and that getter then answers in front of the port's: set then get reads nil (measured on the 6.1.3 guest by
// tests/backports/emulate/nsobject-custom-actions). A dyld add-image hook runs before objc attaches that category, and
// 6.1.3 has no hook after the attach, so the port cannot put its accessors back from there. The setter does it instead:
// whenever the visible getter is not the port's, it puts both accessors back in front, and then stores. A value stored
// before the framework is opened is still read as nil by the release's getter; that residual is open in
// coordination/crutches.md. If the release's getter was already on NSObject when this image started, the captured IMPs
// are not the port's, and nothing is put back.
static void CharonReassertCustomActions(void)
{
    if (!CharonCustomActionsArmed) {
        return;
    }
    Method visible = class_getInstanceMethod([NSObject class], @selector(accessibilityCustomActions));
    if (visible != NULL && method_getImplementation(visible) == CharonCustomActionsGetter) {
        return;
    }
    class_replaceMethod([NSObject class], @selector(accessibilityCustomActions), CharonCustomActionsGetter, "@@:");
    class_replaceMethod([NSObject class], @selector(setAccessibilityCustomActions:), CharonCustomActionsSetter, "v@:@");
}

__attribute__((constructor)) static void CharonArmCustomActions(void)
{
    CharonCustomActionsGetter = class_getMethodImplementation([NSObject class], @selector(accessibilityCustomActions));
    CharonCustomActionsSetter = class_getMethodImplementation([NSObject class], @selector(setAccessibilityCustomActions:));
    CharonCustomActionsArmed = CharonInThisImage((const void *)CharonCustomActionsGetter)
        && CharonInThisImage((const void *)CharonCustomActionsSetter);
}
