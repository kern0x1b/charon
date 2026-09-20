#import <UIKit/UIKit.h>
#import <objc/runtime.h>

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

@implementation NSObject (CharonAccessibilityElements)

- (NSArray<UIAccessibilityCustomAction *> *)accessibilityCustomActions
{
    return objc_getAssociatedObject(self, CharonCustomActionsKey);
}

- (void)setAccessibilityCustomActions:(NSArray<UIAccessibilityCustomAction *> *)actions
{
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
