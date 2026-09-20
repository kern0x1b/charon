#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@implementation UITextInputAssistantItem {
    BOOL _allowsHidingShortcuts;
    NSArray<UIBarButtonItemGroup *> *_leadingBarButtonGroups;
    NSArray<UIBarButtonItemGroup *> *_trailingBarButtonGroups;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _allowsHidingShortcuts = YES;
        _leadingBarButtonGroups = @[];
        _trailingBarButtonGroups = @[];
    }
    return self;
}

- (BOOL)allowsHidingShortcuts
{
    return _allowsHidingShortcuts;
}

- (void)setAllowsHidingShortcuts:(BOOL)allows
{
    _allowsHidingShortcuts = allows;
}

- (NSArray<UIBarButtonItemGroup *> *)leadingBarButtonGroups
{
    return _leadingBarButtonGroups;
}

- (void)setLeadingBarButtonGroups:(NSArray<UIBarButtonItemGroup *> *)groups
{
    _leadingBarButtonGroups = [groups copy];
}

- (NSArray<UIBarButtonItemGroup *> *)trailingBarButtonGroups
{
    return _trailingBarButtonGroups;
}

- (void)setTrailingBarButtonGroups:(NSArray<UIBarButtonItemGroup *> *)groups
{
    _trailingBarButtonGroups = [groups copy];
}

@end

static const void *CharonAssistantItemKey = &CharonAssistantItemKey;

@implementation UIResponder (CharonInputAssistantItem)

- (UITextInputAssistantItem *)inputAssistantItem
{
    UITextInputAssistantItem *item = objc_getAssociatedObject(self, CharonAssistantItemKey);
    if (!item) {
        item = [[UITextInputAssistantItem alloc] init];
        objc_setAssociatedObject(self, CharonAssistantItemKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return item;
}

@end
