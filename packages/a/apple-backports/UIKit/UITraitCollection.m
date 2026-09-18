#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "CharonTraitStyle.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static NSString *const CharonIdiomKey = @"UITraitCollectionBuiltinTrait-_UITraitNameUserInterfaceIdiom";
static NSString *const CharonScaleKey = @"UITraitCollectionBuiltinTrait-_UITraitNameDisplayScale";
static NSString *const CharonHorizontalKey = @"UITraitCollectionBuiltinTrait-_UITraitNameHorizontalSizeClass";
static NSString *const CharonVerticalKey = @"UITraitCollectionBuiltinTrait-_UITraitNameVerticalSizeClass";
static NSString *const CharonStyleKey = @"UITraitCollectionBuiltinTrait-_UITraitNameUserInterfaceStyle";

static BOOL charon_orientation_forced;
static UIInterfaceOrientation charon_forced_orientation;

static UITraitCollection *charon_make(Class cls, UIUserInterfaceIdiom idiom, CGFloat scale, UIUserInterfaceSizeClass horizontal, UIUserInterfaceSizeClass vertical);

static UIInterfaceOrientation charon_interface_orientation(void)
{
    if (charon_orientation_forced)
        return charon_forced_orientation;
    UIApplication *application = [UIApplication sharedApplication];
    UIInterfaceOrientation orientation = application ? application.statusBarOrientation : UIInterfaceOrientationPortrait;
    return orientation ? orientation : UIInterfaceOrientationPortrait;
}

static UITraitCollection *charon_trait_collection_for(UIUserInterfaceIdiom idiom, CGFloat scale, UIInterfaceOrientation orientation, BOOL external)
{
    UITraitCollection *collection;
    if (external)
        collection = charon_make([UITraitCollection class], UIUserInterfaceIdiomUnspecified, scale, UIUserInterfaceSizeClassRegular, UIUserInterfaceSizeClassRegular);
    else if (idiom == UIUserInterfaceIdiomPad)
        collection = charon_make([UITraitCollection class], idiom, scale, UIUserInterfaceSizeClassRegular, UIUserInterfaceSizeClassRegular);
    else {
        UIUserInterfaceSizeClass vertical = UIInterfaceOrientationIsLandscape(orientation) ? UIUserInterfaceSizeClassCompact : UIUserInterfaceSizeClassRegular;
        collection = charon_make([UITraitCollection class], idiom, scale, UIUserInterfaceSizeClassCompact, vertical);
    }
    charon_set_trait_style(collection, UIUserInterfaceStyleLight);
    return collection;
}

static UITraitCollection *charon_screen_traits(UIScreen *screen)
{
    UIScreen *main = [UIScreen mainScreen];
    if (!screen)
        screen = main;
    UIInterfaceOrientation orientation = charon_interface_orientation();
    if (screen != main)
        return charon_trait_collection_for(UIUserInterfaceIdiomUnspecified, screen.scale, orientation, YES);
    static UITraitCollection *cached[2];
    static CGFloat cachedScale;
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);
    CGFloat scale = screen.scale;
    if (cachedScale != scale) {
        cached[0] = nil;
        cached[1] = nil;
        cachedScale = scale;
    }
    if (!cached[landscape])
        cached[landscape] = charon_trait_collection_for([UIDevice currentDevice].userInterfaceIdiom, scale, orientation, NO);
    return cached[landscape];
}

static void charon_collect_views(UIView *view, NSMutableOrderedSet *found)
{
    UIResponder *next = view.nextResponder;
    if ([next isKindOfClass:[UIViewController class]] && ((UIViewController *)next).view == view)
        [found addObject:next];
    [found addObject:view];
    for (UIView *subview in view.subviews)
        charon_collect_views(subview, found);
}

static void charon_collect_controllers(UIViewController *controller, NSMutableOrderedSet *found)
{
    if (!controller || [found containsObject:controller])
        return;
    [found addObject:controller];
    if (controller.isViewLoaded)
        charon_collect_views(controller.view, found);
    for (UIViewController *child in controller.childViewControllers)
        charon_collect_controllers(child, found);
    UIViewController *presented = controller.presentedViewController;
    if (presented && presented.presentingViewController == controller)
        charon_collect_controllers(presented, found);
}

static void charon_deliver_trait_changes(NSArray *environments, void (^change)(void))
{
    NSMutableOrderedSet *found = [NSMutableOrderedSet orderedSet];
    for (id environment in environments) {
        if ([environment isKindOfClass:[UIViewController class]]) {
            charon_collect_controllers(environment, found);
        } else if ([environment isKindOfClass:[UIView class]]) {
            charon_collect_views(environment, found);
            if ([environment isKindOfClass:[UIWindow class]])
                charon_collect_controllers([(UIWindow *)environment rootViewController], found);
        } else {
            [found addObject:environment];
        }
    }
    NSMutableArray *previous = [NSMutableArray arrayWithCapacity:found.count];
    for (id<UITraitEnvironment> environment in found)
        [previous addObject:environment.traitCollection];
    change();
    NSUInteger index = 0;
    for (id<UITraitEnvironment> environment in found) {
        UITraitCollection *before = [previous objectAtIndex:index++];
        if (![before isEqual:environment.traitCollection])
            [environment traitCollectionDidChange:before];
    }
}

static void charon_orientation_changed(NSNotification *notification)
{
    NSNumber *old = [notification.userInfo objectForKey:UIApplicationStatusBarOrientationUserInfoKey];
    UIApplication *application = notification.object;
    if (!old || !application)
        return;
    NSMutableArray *environments = [NSMutableArray arrayWithObject:[UIScreen mainScreen]];
    [environments addObjectsFromArray:application.windows];
    charon_orientation_forced = YES;
    charon_forced_orientation = (UIInterfaceOrientation)old.integerValue;
    charon_deliver_trait_changes(environments, ^{
        charon_orientation_forced = NO;
    });
    charon_orientation_forced = NO;
}

static NSString *charon_idiom_name(UIUserInterfaceIdiom idiom)
{
    switch (idiom) {
    case UIUserInterfaceIdiomPhone:
        return @"Phone";
    case UIUserInterfaceIdiomPad:
        return @"Pad";
    default:
        return [NSString stringWithFormat:@"%ld", (long)idiom];
    }
}

static NSString *charon_size_class_name(UIUserInterfaceSizeClass sizeClass)
{
    switch (sizeClass) {
    case UIUserInterfaceSizeClassCompact:
        return @"Compact";
    case UIUserInterfaceSizeClassRegular:
        return @"Regular";
    default:
        return [NSString stringWithFormat:@"%ld", (long)sizeClass];
    }
}

@implementation UITraitCollection {
    UIUserInterfaceIdiom _userInterfaceIdiom;
    CGFloat _displayScale;
    UIUserInterfaceSizeClass _horizontalSizeClass;
    UIUserInterfaceSizeClass _verticalSizeClass;
}

+ (void)load
{
    if (objc_getClass("UITraitCollection") != self)
        return;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidChangeStatusBarOrientationNotification object:nil queue:nil usingBlock:^(NSNotification *notification) {
        charon_orientation_changed(notification);
    }];
}

+ (UITraitCollection *)charon_traitCollectionForScreen:(UIScreen *)screen
{
    return charon_screen_traits(screen);
}

+ (UITraitCollection *)charon_traitCollectionWithIdiom:(UIUserInterfaceIdiom)idiom scale:(CGFloat)scale orientation:(UIInterfaceOrientation)orientation external:(BOOL)external
{
    return charon_trait_collection_for(idiom, scale, orientation, external);
}

+ (void)charon_deliverChangesInEnvironments:(NSArray *)environments change:(void (^)(void))change
{
    charon_deliver_trait_changes(environments, change);
}

@dynamic layoutDirection;
@dynamic preferredContentSizeCategory;
@dynamic displayGamut;
@dynamic userInterfaceStyle;
@dynamic accessibilityContrast;
@dynamic userInterfaceLevel;
@dynamic legibilityWeight;
@dynamic activeAppearance;
@dynamic toolbarItemPresentationSize;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

+ (UITraitCollection *)traitCollectionWithTraitsFromCollections:(NSArray *)traitCollections
{
    UIUserInterfaceIdiom idiom = UIUserInterfaceIdiomUnspecified;
    CGFloat scale = 0;
    UIUserInterfaceSizeClass horizontal = UIUserInterfaceSizeClassUnspecified;
    UIUserInterfaceSizeClass vertical = UIUserInterfaceSizeClassUnspecified;
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
    for (UITraitCollection *collection in traitCollections) {
        if (![collection isKindOfClass:[UITraitCollection class]])
            continue;
        if (collection->_userInterfaceIdiom != UIUserInterfaceIdiomUnspecified)
            idiom = collection->_userInterfaceIdiom;
        if (collection->_displayScale != 0)
            scale = collection->_displayScale;
        if (collection->_horizontalSizeClass != UIUserInterfaceSizeClassUnspecified)
            horizontal = collection->_horizontalSizeClass;
        if (collection->_verticalSizeClass != UIUserInterfaceSizeClassUnspecified)
            vertical = collection->_verticalSizeClass;
        if (charon_trait_style(collection) != UIUserInterfaceStyleUnspecified)
            style = charon_trait_style(collection);
    }
    UITraitCollection *merged = charon_make(self, idiom, scale, horizontal, vertical);
    charon_set_trait_style(merged, style);
    return merged;
}

+ (UITraitCollection *)traitCollectionWithUserInterfaceIdiom:(UIUserInterfaceIdiom)idiom
{
    return charon_make(self, idiom, 0, UIUserInterfaceSizeClassUnspecified, UIUserInterfaceSizeClassUnspecified);
}

+ (UITraitCollection *)traitCollectionWithDisplayScale:(CGFloat)scale
{
    return charon_make(self, UIUserInterfaceIdiomUnspecified, scale, UIUserInterfaceSizeClassUnspecified, UIUserInterfaceSizeClassUnspecified);
}

+ (UITraitCollection *)traitCollectionWithHorizontalSizeClass:(UIUserInterfaceSizeClass)horizontalSizeClass
{
    return charon_make(self, UIUserInterfaceIdiomUnspecified, 0, horizontalSizeClass, UIUserInterfaceSizeClassUnspecified);
}

+ (UITraitCollection *)traitCollectionWithVerticalSizeClass:(UIUserInterfaceSizeClass)verticalSizeClass
{
    return charon_make(self, UIUserInterfaceIdiomUnspecified, 0, UIUserInterfaceSizeClassUnspecified, verticalSizeClass);
}

static UITraitCollection *charon_make(Class cls, UIUserInterfaceIdiom idiom, CGFloat scale, UIUserInterfaceSizeClass horizontal, UIUserInterfaceSizeClass vertical)
{
    UITraitCollection *collection = [[cls alloc] init];
    collection->_userInterfaceIdiom = idiom;
    collection->_displayScale = scale;
    collection->_horizontalSizeClass = horizontal;
    collection->_verticalSizeClass = vertical;
    return collection;
}

- (instancetype)init
{
    if ((self = [super init]))
        _userInterfaceIdiom = UIUserInterfaceIdiomUnspecified;
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        _userInterfaceIdiom = [coder containsValueForKey:CharonIdiomKey] ? (UIUserInterfaceIdiom)[coder decodeIntegerForKey:CharonIdiomKey] : UIUserInterfaceIdiomUnspecified;
        _displayScale = (CGFloat)[coder decodeDoubleForKey:CharonScaleKey];
        _horizontalSizeClass = (UIUserInterfaceSizeClass)[coder decodeIntegerForKey:CharonHorizontalKey];
        _verticalSizeClass = (UIUserInterfaceSizeClass)[coder decodeIntegerForKey:CharonVerticalKey];
        charon_set_trait_style(self, (UIUserInterfaceStyle)[coder decodeIntegerForKey:CharonStyleKey]);
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    if (_userInterfaceIdiom != UIUserInterfaceIdiomUnspecified)
        [coder encodeInteger:_userInterfaceIdiom forKey:CharonIdiomKey];
    if (_displayScale != 0)
        [coder encodeDouble:_displayScale forKey:CharonScaleKey];
    if (_horizontalSizeClass != UIUserInterfaceSizeClassUnspecified)
        [coder encodeInteger:_horizontalSizeClass forKey:CharonHorizontalKey];
    if (_verticalSizeClass != UIUserInterfaceSizeClassUnspecified)
        [coder encodeInteger:_verticalSizeClass forKey:CharonVerticalKey];
    if (charon_trait_style(self) != UIUserInterfaceStyleUnspecified)
        [coder encodeInteger:charon_trait_style(self) forKey:CharonStyleKey];
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (UIUserInterfaceIdiom)userInterfaceIdiom
{
    return _userInterfaceIdiom;
}

- (CGFloat)displayScale
{
    return _displayScale;
}

- (UIUserInterfaceSizeClass)horizontalSizeClass
{
    return _horizontalSizeClass;
}

- (UIUserInterfaceSizeClass)verticalSizeClass
{
    return _verticalSizeClass;
}

- (BOOL)containsTraitsInCollection:(UITraitCollection *)trait
{
    if (![trait isKindOfClass:[UITraitCollection class]])
        return YES;
    if (trait->_userInterfaceIdiom != UIUserInterfaceIdiomUnspecified && trait->_userInterfaceIdiom != _userInterfaceIdiom)
        return NO;
    if (trait->_displayScale != 0 && trait->_displayScale != _displayScale)
        return NO;
    if (trait->_horizontalSizeClass != UIUserInterfaceSizeClassUnspecified && trait->_horizontalSizeClass != _horizontalSizeClass)
        return NO;
    if (charon_trait_style(trait) != UIUserInterfaceStyleUnspecified && charon_trait_style(trait) != charon_trait_style(self))
        return NO;
    return trait->_verticalSizeClass == UIUserInterfaceSizeClassUnspecified || trait->_verticalSizeClass == _verticalSizeClass;
}

- (BOOL)isEqual:(id)object
{
    if (object == self)
        return YES;
    if (![object isKindOfClass:[UITraitCollection class]])
        return NO;
    UITraitCollection *other = object;
    return other->_userInterfaceIdiom == _userInterfaceIdiom && other->_displayScale == _displayScale &&
           other->_horizontalSizeClass == _horizontalSizeClass && other->_verticalSizeClass == _verticalSizeClass &&
           charon_trait_style(other) == charon_trait_style(self);
}

- (NSUInteger)hash
{
    NSUInteger scale = (NSUInteger)(_displayScale * 100);
    return ((NSUInteger)(_userInterfaceIdiom + 1) << 24) ^ (scale << 8) ^ ((NSUInteger)_horizontalSizeClass << 4) ^ (NSUInteger)_verticalSizeClass ^
           ((NSUInteger)charon_trait_style(self) << 20);
}

- (NSString *)description
{
    NSMutableArray *traits = [NSMutableArray array];
    if (_userInterfaceIdiom != UIUserInterfaceIdiomUnspecified)
        [traits addObject:[@"UserInterfaceIdiom = " stringByAppendingString:charon_idiom_name(_userInterfaceIdiom)]];
    if (_displayScale != 0)
        [traits addObject:[NSString stringWithFormat:@"DisplayScale = %g", (double)_displayScale]];
    if (_horizontalSizeClass != UIUserInterfaceSizeClassUnspecified)
        [traits addObject:[@"HorizontalSizeClass = " stringByAppendingString:charon_size_class_name(_horizontalSizeClass)]];
    if (_verticalSizeClass != UIUserInterfaceSizeClassUnspecified)
        [traits addObject:[@"VerticalSizeClass = " stringByAppendingString:charon_size_class_name(_verticalSizeClass)]];
    if (charon_trait_style(self) != UIUserInterfaceStyleUnspecified)
        [traits addObject:[@"UserInterfaceStyle = " stringByAppendingString:charon_trait_style(self) == UIUserInterfaceStyleDark ? @"Dark" : @"Light"]];
    return [NSString stringWithFormat:@"<%@: %p; %@>", [self class], self, [traits componentsJoinedByString:@", "]];
}

@end
