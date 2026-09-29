#ifndef CHARON_TRAITS17_H
#define CHARON_TRAITS17_H

// The traits of iOS 17, 18 and 26, declared where the SDK a backport builds against does not have them.
// UITrait.h and the three environment headers reached UIKit in 17.0 and 26.0, and the build SDK (16.4) stops
// before both, so the surface is written here from the 26.2 headers, in Apple's own idiom: the whole file is
// empty where the SDK's own UITrait.h is there, so a build against a newer SDK takes its declarations from the
// SDK and this file adds nothing. What the port implements is in UITrait17.m, UITraitCollection+Traits17.m and
// UITraitOverrides17.m; the values live in the store the older trait collections already keep, under the same
// names (facts/UIKit/UITrait17.md has the measurements and the routing table).

#import <UIKit/UIKit.h>
#import "../CharonSayOnce.h"

#if !__has_include(<UIKit/UITrait.h>)

#pragma clang diagnostic ignored "-Wobjc-protocol-qualifiers"

typedef NS_ENUM(NSInteger, UIImageDynamicRange) {
    UIImageDynamicRangeUnspecified = -1,
    UIImageDynamicRangeStandard = 0,
    UIImageDynamicRangeConstrainedHigh = 1,
    UIImageDynamicRangeHigh = 2
};

typedef NS_ENUM(NSInteger, UISceneCaptureState) {
    UISceneCaptureStateUnspecified = -1,
    UISceneCaptureStateInactive = 0,
    UISceneCaptureStateActive = 1
};

typedef NS_ENUM(NSInteger, UIHDRHeadroomUsageLimit) {
    UIHDRHeadroomUsageLimitUnspecified = -1,
    UIHDRHeadroomUsageLimitActive = 0,
    UIHDRHeadroomUsageLimitInactive = 1
};

typedef NS_ENUM(NSInteger, UIListEnvironment) {
    UIListEnvironmentUnspecified = 0,
    UIListEnvironmentNone = 1,
    UIListEnvironmentPlain = 2,
    UIListEnvironmentGrouped = 3,
    UIListEnvironmentInsetGrouped = 4,
    UIListEnvironmentSidebar = 5,
    UIListEnvironmentSidebarPlain = 6
};

typedef NS_ENUM(NSInteger, UITabAccessoryEnvironment) {
    UITabAccessoryEnvironmentUnspecified = 0,
    UITabAccessoryEnvironmentNone = 1,
    UITabAccessoryEnvironmentRegular = 2,
    UITabAccessoryEnvironmentInline = 3
};

typedef NS_ENUM(NSInteger, UISplitViewControllerLayoutEnvironment) {
    UISplitViewControllerLayoutEnvironmentNone = 0,
    UISplitViewControllerLayoutEnvironmentExpanded = 1,
    UISplitViewControllerLayoutEnvironmentCollapsed = 2
};

@protocol UITraitDefinition <NSObject>
@optional
@property (nonatomic, class, readonly) NSString *identifier;
@property (nonatomic, class, readonly) NSString *name;
@property (nonatomic, class, readonly) BOOL affectsColorAppearance;
@end
typedef Class<UITraitDefinition> UITrait;

@protocol UICGFloatTraitDefinition <UITraitDefinition>
@property (nonatomic, class, readonly) CGFloat defaultValue;
@end
typedef Class<UICGFloatTraitDefinition> UICGFloatTrait;

@protocol UINSIntegerTraitDefinition <UITraitDefinition>
@property (nonatomic, class, readonly) NSInteger defaultValue;
@end
typedef Class<UINSIntegerTraitDefinition> UINSIntegerTrait;

@protocol UIObjectTraitDefinition <UITraitDefinition>
@property (nonatomic, class, readonly, nullable) __kindof id<NSObject> defaultValue;
@end
typedef Class<UIObjectTraitDefinition> UIObjectTrait;

@interface UITraitUserInterfaceIdiom : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitUserInterfaceStyle : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitLayoutDirection : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitDisplayScale : NSObject <UICGFloatTraitDefinition>
@end
@interface UITraitHorizontalSizeClass : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitVerticalSizeClass : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitForceTouchCapability : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitPreferredContentSizeCategory : NSObject <UIObjectTraitDefinition>
@end
@interface UITraitDisplayGamut : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitAccessibilityContrast : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitUserInterfaceLevel : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitLegibilityWeight : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitActiveAppearance : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitToolbarItemPresentationSize : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitImageDynamicRange : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitTypesettingLanguage : NSObject <UIObjectTraitDefinition>
@end
@interface UITraitSceneCaptureState : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitHDRHeadroomUsageLimit : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitResolvesNaturalAlignmentWithBaseWritingDirection : NSObject <UIObjectTraitDefinition>
@end
@interface UITraitListEnvironment : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitTabAccessoryEnvironment : NSObject <UINSIntegerTraitDefinition>
@end
@interface UITraitSplitViewControllerLayoutEnvironment : NSObject <UINSIntegerTraitDefinition>
@end

@protocol UIMutableTraits <NSObject>
- (void)setCGFloatValue:(CGFloat)value forTrait:(UICGFloatTrait)trait;
- (CGFloat)valueForCGFloatTrait:(UICGFloatTrait)trait;
- (void)setNSIntegerValue:(NSInteger)value forTrait:(UINSIntegerTrait)trait;
- (NSInteger)valueForNSIntegerTrait:(UINSIntegerTrait)trait;
- (void)setObject:(nullable id<NSObject>)object forTrait:(UIObjectTrait)trait;
- (nullable __kindof id<NSObject>)objectForTrait:(UIObjectTrait)trait;
@property (nonatomic) UIUserInterfaceIdiom userInterfaceIdiom;
@property (nonatomic) UIUserInterfaceStyle userInterfaceStyle;
@property (nonatomic) UITraitEnvironmentLayoutDirection layoutDirection;
@property (nonatomic) CGFloat displayScale;
@property (nonatomic) UIUserInterfaceSizeClass horizontalSizeClass;
@property (nonatomic) UIUserInterfaceSizeClass verticalSizeClass;
@property (nonatomic) UIForceTouchCapability forceTouchCapability;
@property (nonatomic, copy) UIContentSizeCategory preferredContentSizeCategory;
@property (nonatomic) UIDisplayGamut displayGamut;
@property (nonatomic) UIAccessibilityContrast accessibilityContrast;
@property (nonatomic) UIUserInterfaceLevel userInterfaceLevel;
@property (nonatomic) UILegibilityWeight legibilityWeight;
@property (nonatomic) UIUserInterfaceActiveAppearance activeAppearance;
@property (nonatomic) UINSToolbarItemPresentationSize toolbarItemPresentationSize;
@property (nonatomic) UIImageDynamicRange imageDynamicRange;
@property (nonatomic) UISceneCaptureState sceneCaptureState;
@property (nonatomic, copy) NSString *typesettingLanguage;
@property (nonatomic) UIListEnvironment listEnvironment;
@property (nonatomic) UITabAccessoryEnvironment tabAccessoryEnvironment;
@property (nonatomic) UISplitViewControllerLayoutEnvironment splitViewControllerLayoutEnvironment;
@property (nonatomic) BOOL resolvesNaturalAlignmentWithBaseWritingDirection;
@end

typedef void (^UITraitMutations)(id<UIMutableTraits> mutableTraits);

@protocol UITraitOverrides <UIMutableTraits>
- (BOOL)containsTrait:(UITrait)trait;
- (void)removeTrait:(UITrait)trait;
@end

@protocol UITraitChangeRegistration <NSObject, NSCopying>
@end

typedef void (^UITraitChangeHandler)(__kindof id<UITraitEnvironment> traitEnvironment, UITraitCollection *previousCollection);

@protocol UITraitChangeObservable <NSObject>
- (id<UITraitChangeRegistration>)registerForTraitChanges:(NSArray<UITrait> *)traits withHandler:(UITraitChangeHandler)handler;
- (id<UITraitChangeRegistration>)registerForTraitChanges:(NSArray<UITrait> *)traits withTarget:(id)target action:(SEL)action;
- (id<UITraitChangeRegistration>)registerForTraitChanges:(NSArray<UITrait> *)traits withAction:(SEL)action;
- (void)unregisterForTraitChanges:(id<UITraitChangeRegistration>)registration;
@end

@interface UITraitCollection (CharonTraits17)
+ (UITraitCollection *)traitCollectionWithTraits:(UITraitMutations NS_NOESCAPE)mutations;
- (UITraitCollection *)traitCollectionByModifyingTraits:(UITraitMutations NS_NOESCAPE)mutations;
+ (UITraitCollection *)traitCollectionWithCGFloatValue:(CGFloat)value forTrait:(UICGFloatTrait)trait;
- (UITraitCollection *)traitCollectionByReplacingCGFloatValue:(CGFloat)value forTrait:(UICGFloatTrait)trait;
- (CGFloat)valueForCGFloatTrait:(UICGFloatTrait)trait;
+ (UITraitCollection *)traitCollectionWithNSIntegerValue:(NSInteger)value forTrait:(UINSIntegerTrait)trait;
- (UITraitCollection *)traitCollectionByReplacingNSIntegerValue:(NSInteger)value forTrait:(UINSIntegerTrait)trait;
- (NSInteger)valueForNSIntegerTrait:(UINSIntegerTrait)trait;
+ (UITraitCollection *)traitCollectionWithObject:(nullable id<NSObject>)object forTrait:(UIObjectTrait)trait;
- (UITraitCollection *)traitCollectionByReplacingObject:(nullable id<NSObject>)object forTrait:(UIObjectTrait)trait;
- (nullable __kindof id<NSObject>)objectForTrait:(UIObjectTrait)trait;
- (NSSet<UITrait> *)changedTraitsFromTraitCollection:(nullable UITraitCollection *)traitCollection;
@property (nonatomic, readonly, class) NSArray<UITrait> *systemTraitsAffectingColorAppearance;
@property (nonatomic, readonly, class) NSArray<UITrait> *systemTraitsAffectingImageLookup;
@end

// The trait a class stands for, and where this port keeps the value of it. kind is the protocol the class adopts,
// which is also the type forTrait: is given it by: a trait class asked through the wrong one is refused, as
// UIKitCore 26.2 refuses it (facts/UIKit/UITrait17.md, M4).
typedef NS_ENUM(NSInteger, CharonTraitValue) {
    CharonTraitValueCGFloat = 0,
    CharonTraitValueNSInteger = 1,
    CharonTraitValueObject = 2
};

// A trait definition, one per class: which class, the name this port stores the value under, what kind of value
// it takes, the value a collection that sets none has (the class property defaultValue, measured), and whether a
// change of it is a change of a dynamic colour's appearance. home says where the value lives: HOME_EXTRAS is the
// dictionary the older trait collections keep, HOME_IVAR the five traits UITraitCollection.m holds in its own
// storage, HOME_STYLE charon_trait_style and HOME_FORCE_TOUCH the two that keep theirs beside.
typedef NS_ENUM(NSInteger, CharonTraitHome) {
    CharonTraitHomeExtras = 0,
    CharonTraitHomeIvar = 1,
    CharonTraitHomeStyle = 2,
    CharonTraitHomeForceTouch = 3
};

typedef struct {
    __unsafe_unretained Class trait;
    __unsafe_unretained NSString *name;
    CharonTraitValue kind;
    CharonTraitHome home;
    __unsafe_unretained id defaultValue;
    BOOL affectsColorAppearance;
} CharonTraitDefinition;

// The definition of a trait class, or NULL when the class is not one this port carries. The twenty-two are
// registered by UITrait17.m's +load, so a lookup before the runtime has run its +load calls answers NULL and the
// caller raises the way UIKitCore does.
const CharonTraitDefinition *charon_trait_definition(Class trait);

// The twenty-two classes, in the order UITrait.h and the three environment headers declare them, which is the
// order the host lists systemTraitsAffectingColorAppearance in. A class is read with the runtime rather than
// named, so nothing here depends on a link-time reference that a release might not answer.
NSArray *charon_trait_classes(void);

// +name on every one of the twenty-two is the class's own name without its UITrait prefix, measured on the host
// (M1). It is not the name the port stores a value under, which for UITraitLayoutDirection is the longer
// UserInterfaceLayoutDirection the collection has always printed; the two are separate on purpose.
static inline NSString *charon_trait_public_name(const CharonTraitDefinition *definition)
{
    NSString *identifier = NSStringFromClass(definition->trait);
    return [identifier hasPrefix:@"UITrait"] ? [identifier substringFromIndex:7] : identifier;
}

// Whether a collection says nothing about a trait, which is what makes an absent value the trait's default
// rather than a value of its own. The one BOOL trait is not asked this question: M2 measured a collection that
// sets none of it answering true, so it reads true whether or not anything was set.
BOOL charon_trait_is_default(UITraitCollection *collection, const CharonTraitDefinition *definition);

// The value this port holds for a trait in a collection: an NSNumber for a CGFloat or an NSInteger trait, the
// object itself for an object trait, and nil where the collection sets none. Not a copy: a caller may hold it.
id charon_trait_value(UITraitCollection *collection, const CharonTraitDefinition *definition);

// A copy of the collection with the trait set to a value of its own kind. A value of the wrong kind for the
// trait is refused here, as UIKitCore 26.2 refuses it at the trait's own boundary.
UITraitCollection *charon_trait_collection_with(UITraitCollection *collection, const CharonTraitDefinition *definition, id value);

// The dictionary that holds the extras, read and written for a trait whose value is not one of the five ivars.
// An object trait's value is stored as the object; a numeric one as an NSNumber, which is what the older traits
// already store, so one dictionary holds every trait of a collection and equality, hashing, coding, merging and
// the description all reach the new ones without a store of their own.
id charon_trait_extra_object(UITraitCollection *collection, NSString *name);
void charon_set_trait_extra_object(UITraitCollection *collection, NSString *name, id value);

// The force touch capability's own storage, beside the file that reads it.
void charon_set_trait_force_touch(UITraitCollection *collection, UIForceTouchCapability capability);

// The five traits UITraitCollection.m holds in its own storage, written from here; the header declares them
// readonly, so these are the port's own, not the SDK's.
@interface UITraitCollection (CharonTraitStorage)
- (void)charon_setUserInterfaceIdiom:(UIUserInterfaceIdiom)idiom;
- (void)charon_setDisplayScale:(CGFloat)scale;
- (void)charon_setHorizontalSizeClass:(UIUserInterfaceSizeClass)sizeClass;
- (void)charon_setVerticalSizeClass:(UIUserInterfaceSizeClass)sizeClass;
@end

// A mutable view of a collection's traits, which is what traitCollectionWithTraits: and
// traitCollectionByModifyingTraits: run their block against, and what a trait overrides object is.
@interface CharonTraitMutations : NSObject <UIMutableTraits> {
    UITraitCollection *_collection;
}
- (instancetype)initWithCollection:(UITraitCollection *)collection;
- (UITraitCollection *)charon_collection;
- (void)setCGFloatValue:(CGFloat)value forTrait:(UICGFloatTrait)trait;
- (CGFloat)valueForCGFloatTrait:(UICGFloatTrait)trait;
- (void)setNSIntegerValue:(NSInteger)value forTrait:(UINSIntegerTrait)trait;
- (NSInteger)valueForNSIntegerTrait:(UINSIntegerTrait)trait;
- (void)setObject:(nullable id<NSObject>)object forTrait:(UIObjectTrait)trait;
- (nullable __kindof id<NSObject>)objectForTrait:(UIObjectTrait)trait;
@end

static inline void charon_traits_say_once(NSString *key, NSString *text)
{
    charon_say_once_for(key, text);
}

#endif

#endif
