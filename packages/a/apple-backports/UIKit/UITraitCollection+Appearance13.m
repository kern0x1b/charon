#import "CharonTraitStyle.h"
#import "CharonSymbols.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

static NSString *const CharonContrast = @"AccessibilityContrast";
static NSString *const CharonLevel = @"UserInterfaceLevel";
static NSString *const CharonLegibility = @"LegibilityWeight";

static char charon_extras_key;

static NSMutableArray *charon_kinds(void)
{
    static NSMutableArray *kinds;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kinds = [[NSMutableArray alloc] init];
    });
    return kinds;
}

void charon_register_trait_kind(CharonTraitKind kind)
{
    NSMutableArray *kinds = charon_kinds();
    @synchronized (kinds) {
        for (NSValue *held in kinds) {
            CharonTraitKind other;
            [held getValue:&other];
            if ([other.name isEqualToString:kind.name])
                return;
        }
        [kinds addObject:[NSValue valueWithBytes:&kind objCType:@encode(CharonTraitKind)]];
    }
}

static void charon_each_kind(void (^visit)(CharonTraitKind kind))
{
    NSMutableArray *kinds = charon_kinds();
    NSArray *copy;
    @synchronized (kinds) {
        copy = [kinds copy];
    }
    for (NSValue *held in copy) {
        CharonTraitKind kind;
        [held getValue:&kind];
        visit(kind);
    }
}

NSDictionary *charon_trait_extras(UITraitCollection *collection)
{
    return objc_getAssociatedObject(collection, &charon_extras_key);
}

NSInteger charon_trait_extra(UITraitCollection *collection, NSString *name)
{
    NSNumber *held = charon_trait_extras(collection)[name];
    return held ? held.integerValue : -1;
}

void charon_set_trait_extra(UITraitCollection *collection, NSString *name, NSInteger value)
{
    NSMutableDictionary *extras = [charon_trait_extras(collection) mutableCopy] ?: [NSMutableDictionary dictionary];
    if (value == -1)
        [extras removeObjectForKey:name];
    else
        extras[name] = @(value);
    objc_setAssociatedObject(collection, &charon_extras_key, extras.count ? extras : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

NSDictionary *charon_merge_trait_extras(NSArray *collections)
{
    NSMutableDictionary *merged = [NSMutableDictionary dictionary];
    for (UITraitCollection *collection in collections)
        [merged addEntriesFromDictionary:charon_trait_extras(collection) ?: @{}];
    return merged;
}

void charon_apply_trait_extras(UITraitCollection *collection, NSDictionary *extras)
{
    objc_setAssociatedObject(collection, &charon_extras_key, extras.count ? [extras copy] : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void charon_apply_screen_trait_extras(UITraitCollection *collection)
{
    charon_each_kind(^(CharonTraitKind kind) {
        charon_set_trait_extra(collection, kind.name, kind.screenDefault);
    });
}

BOOL charon_trait_extras_contained(UITraitCollection *collection, UITraitCollection *wanted)
{
    for (NSString *name in charon_trait_extras(wanted)) {
        if (charon_trait_extra(wanted, name) != charon_trait_extra(collection, name))
            return NO;
    }
    return YES;
}

BOOL charon_trait_extras_equal(UITraitCollection *a, UITraitCollection *b)
{
    NSDictionary *first = charon_trait_extras(a), *second = charon_trait_extras(b);
    return first == second || (!first.count && !second.count) || [first isEqualToDictionary:second];
}

NSUInteger charon_trait_extras_hash(UITraitCollection *collection)
{
    NSUInteger hash = 0;
    NSDictionary *extras = charon_trait_extras(collection);
    for (NSString *name in extras)
        hash ^= name.hash + [extras[name] unsignedIntegerValue] * 2654435761u;
    return hash;
}

void charon_add_trait_extras_description(UITraitCollection *collection, NSMutableArray *traits)
{
    charon_each_kind(^(CharonTraitKind kind) {
        if (!kind.described)
            return;
        NSInteger value = charon_trait_extra(collection, kind.name);
        if (kind.described == 2) {
            NSArray *names = [kind.first componentsSeparatedByString:@","];
            if (value >= 0 && value < (NSInteger)names.count)
                [traits addObject:[NSString stringWithFormat:@"%@ = %@", kind.name, names[value]]];
        } else if (value == 0 || value == 1)
            [traits addObject:[NSString stringWithFormat:@"%@ = %@", kind.name, value ? kind.second : kind.first]];
    });
}

void charon_encode_trait_extras(UITraitCollection *collection, NSCoder *coder)
{
    NSDictionary *extras = charon_trait_extras(collection);
    for (NSString *name in extras)
        [coder encodeInteger:[extras[name] integerValue] forKey:[@"UITraitCollectionBuiltinTrait-_UITraitName" stringByAppendingString:name]];
}

void charon_decode_trait_extras(UITraitCollection *collection, NSCoder *coder)
{
    charon_each_kind(^(CharonTraitKind kind) {
        NSString *key = [@"UITraitCollectionBuiltinTrait-_UITraitName" stringByAppendingString:kind.name];
        if ([coder containsValueForKey:key])
            charon_set_trait_extra(collection, kind.name, [coder decodeIntegerForKey:key]);
    });
}

static void charon_register_thirteen(void)
{
    charon_register_trait_kind((CharonTraitKind){CharonContrast, 0, YES, @"Normal", @"High"});
    charon_register_trait_kind((CharonTraitKind){CharonLevel, 0, YES, @"Base", @"Elevated"});
    charon_register_trait_kind((CharonTraitKind){CharonLegibility, 0, NO, @"Default", @"Bold"});
}

static UITraitCollection *charon_with(NSString *name, NSInteger value)
{
    charon_register_thirteen();
    UITraitCollection *collection = [UITraitCollection traitCollectionWithTraitsFromCollections:@[]];
    charon_set_trait_extra(collection, name, value);
    return collection;
}

static NSMutableArray *charon_current_stack(void)
{
    NSMutableDictionary *dictionary = [NSThread currentThread].threadDictionary;
    NSMutableArray *stack = dictionary[@"CharonCurrentTraits"];
    if (!stack) {
        stack = [NSMutableArray array];
        dictionary[@"CharonCurrentTraits"] = stack;
    }
    return stack;
}

static UITraitCollection *charon_current_base(void)
{
    UITraitCollection *screen = [UIScreen mainScreen].traitCollection;
    return screen ? screen : [UITraitCollection traitCollectionWithTraitsFromCollections:@[]];
}

@interface CharonTraitKinds13 : NSObject
@end

@implementation CharonTraitKinds13

+ (void)load
{
    charon_register_thirteen();
}

@end

@implementation UITraitCollection (CharonAppearance13)

+ (UITraitCollection *)traitCollectionWithAccessibilityContrast:(UIAccessibilityContrast)accessibilityContrast
{
    return charon_with(CharonContrast, accessibilityContrast);
}

+ (UITraitCollection *)traitCollectionWithLegibilityWeight:(UILegibilityWeight)legibilityWeight
{
    return charon_with(CharonLegibility, legibilityWeight);
}

+ (UITraitCollection *)traitCollectionWithUserInterfaceLevel:(UIUserInterfaceLevel)userInterfaceLevel
{
    return charon_with(CharonLevel, userInterfaceLevel);
}

- (UIAccessibilityContrast)accessibilityContrast
{
    return (UIAccessibilityContrast)charon_trait_extra(self, CharonContrast);
}

- (UILegibilityWeight)legibilityWeight
{
    return (UILegibilityWeight)charon_trait_extra(self, CharonLegibility);
}

- (UIUserInterfaceLevel)userInterfaceLevel
{
    return (UIUserInterfaceLevel)charon_trait_extra(self, CharonLevel);
}

- (BOOL)hasDifferentColorAppearanceComparedToTraitCollection:(UITraitCollection *)traitCollection
{
    return self.userInterfaceStyle != traitCollection.userInterfaceStyle || self.accessibilityContrast != traitCollection.accessibilityContrast ||
           self.userInterfaceLevel != traitCollection.userInterfaceLevel ||
           charon_trait_extra(self, @"ActiveAppearance") != (traitCollection ? charon_trait_extra(traitCollection, @"ActiveAppearance") : 0);
}

- (UIImageConfiguration *)imageConfiguration
{
    return [[UIImageConfiguration alloc] initCharonWithTraitCollection:self];
}

+ (UITraitCollection *)currentTraitCollection
{
    UITraitCollection *held = [charon_current_stack() lastObject];
    return held ? held : charon_current_base();
}

+ (void)setCurrentTraitCollection:(UITraitCollection *)currentTraitCollection
{
    NSMutableArray *stack = charon_current_stack();
    [stack removeAllObjects];
    if (currentTraitCollection)
        [stack addObject:[UITraitCollection traitCollectionWithTraitsFromCollections:@[charon_current_base(), currentTraitCollection]]];
}

- (void)performAsCurrentTraitCollection:(void (NS_NOESCAPE ^)(void))actions
{
    NSMutableArray *stack = charon_current_stack();
    [stack addObject:[UITraitCollection traitCollectionWithTraitsFromCollections:@[charon_current_base(), self]]];
    @try {
        actions();
    } @finally {
        [stack removeLastObject];
    }
}

@end
