#import <UIKit/UIKit.h>

static inline void charon_menus_say_once(NSString *key, NSString *text)
{
    static NSMutableSet *said;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        said = [[NSMutableSet alloc] init];
    });
    @synchronized (said) {
        if ([said containsObject:key])
            return;
        [said addObject:key];
    }
    NSLog(@"%@", text);
}

static inline NSString *charon_short_description(id object)
{
    return object ? [NSString stringWithFormat:@"<%@: %p>", [object class], object] : @"(null)";
}

static inline UIWindow *charon_window_of(UIView *view)
{
    return [view isKindOfClass:[UIWindow class]] ? (UIWindow *)view : view.window;
}

NSString *charon_menu_attributes_text(NSUInteger attributes);

@interface UIMenuElement (CharonMenus)
- (instancetype)initCharonWithTitle:(NSString *)title image:(UIImage *)image;
- (void)charon_setTitle:(NSString *)title;
- (void)charon_setImage:(UIImage *)image;
@end

@interface UIAction (CharonMenus)
- (instancetype)initCharonWithTitle:(NSString *)title image:(UIImage *)image identifier:(NSString *)identifier handler:(UIActionHandler)handler;
- (void)charon_performWithSender:(id)sender;
@end

@interface UICommand (CharonMenus)
- (instancetype)initCharonWithTitle:(NSString *)title image:(UIImage *)image action:(SEL)action propertyList:(id)propertyList alternates:(NSArray *)alternates;
@end

@interface UIMenu (CharonMenus)
- (instancetype)initCharonWithTitle:(NSString *)title image:(UIImage *)image identifier:(NSString *)identifier options:(UIMenuOptions)options
                            children:(NSArray<UIMenuElement *> *)children;
@end

@interface UIDeferredMenuElement (CharonMenus)
- (void)charon_fulfillWithCompletion:(void (^)(NSArray<UIMenuElement *> *elements))completion;
@end

@interface UIContextMenuConfiguration (CharonMenus)
- (UIContextMenuActionProvider)charon_actionProvider;
@end

@interface UIContextMenuInteraction (CharonMenus)
- (UIMenu *)charon_visibleMenu;
- (void)charon_replaceVisibleMenu:(UIMenu *)menu;
- (void)charon_beginAtLocation:(CGPoint)location;
@end


@interface CharonControlProxy : NSObject
- (instancetype)initWithControl:(UIControl *)control action:(UIAction *)action;
- (void)charon_fire:(id)sender;
@property (nonatomic, weak) UIControl *control;
@property (nonatomic, strong) UIAction *action;
@end

void charon_show_menu(UIMenu *menu);
