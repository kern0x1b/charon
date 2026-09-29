// The twenty-two trait classes of iOS 17, 18 and 26, and the table that says what each of them is.
// A trait class carries no state at all on any release: it is a token, and everything asked of it is asked of the
// class. What the host's own UIKit answers was measured before this was written (facts/UIKit/UITrait17.md, M1):
// +identifier is the class's own name, +name is that name without its UITrait prefix, +defaultValue is the value
// a collection that sets none of this trait has, and +affectsColorAppearance is YES for exactly the seven traits
// that decide how a dynamic colour and a dynamic image resolve. UITraitTypesettingLanguage is the one class the
// host gives no +affectsColorAppearance at all, and this keeps that: the property is @optional in the header and
// an application that asks a trait class for it must be ready for nil. The private +defaultValueRepresentsUnspecified
// and +_isPrivate the host also carries are not in any SDK header, so nothing here answers them.

#import "CharonTraits17.h"
#import "CharonTraitStyle.h"
#import <objc/runtime.h>

#if !__has_include(<UIKit/UITrait.h>)

// The table, in the order UITrait.h and the three environment headers declare the twenty-two, which is the
// order the host lists systemTraitsAffectingColorAppearance in. Its entries are put there by the +load below,
// because a definition names its class with [Class class] and no static initializer may send a message. A
// lookup is a walk of twenty-two entries, which is nothing beside the message a caller has already paid to
// reach it. What a collection that sets none of a trait answers is its class's defaultValue; the two object
// traits the host measured with a nil default keep it, so a collection answers nil for a typesetting language
// as the host does, and the one BOOL trait is the exception UITraitCollection+Traits17.m says more of.
static const CharonTraitDefinition *charon_definitions[22];
static int charon_definition_count;

static void charon_register_trait_definition(CharonTraitDefinition *definition)
{
    if (charon_definition_count == (int)(sizeof(charon_definitions) / sizeof(charon_definitions[0])))
        [NSException raise:NSInternalInconsistencyException format:@"more trait definitions than the table holds"];
    charon_definitions[charon_definition_count++] = definition;
}

const CharonTraitDefinition *charon_trait_definition(Class trait)
{
    if (!trait)
        return NULL;
    for (int i = 0; i < charon_definition_count; i++) {
        if (charon_definitions[i]->trait == trait)
            return charon_definitions[i];
    }
    return NULL;
}

NSArray *charon_trait_classes(void)
{
    static NSArray *classes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *found = [NSMutableArray arrayWithCapacity:(NSUInteger)charon_definition_count];
        for (int i = 0; i < charon_definition_count; i++)
            [found addObject:(id)charon_definitions[i]->trait];
        classes = found;
    });
    return classes;
}

// The table is the one place a trait's identity is written: the class, the name the port stores the value under,
// the kind of value, where that value lives, the default and whether the trait decides appearance. The name is
// the one the older trait collections already use, so one collection holds one value per trait whichever way it
// was set; UITraitLayoutDirection is the one whose stored name is longer than the class's +name, because the
// collection has always keyed that trait as UserInterfaceLayoutDirection and its description says so.

// A trait definition is written by a function, not by a static initializer, because a definition names its
// class with [Class class] and no initializer may send a message. The function fills the one static of its
// class and puts its address in the table; +load calls them in the order the headers declare the twenty-two.
#define CHARON_TRAIT(ClassName, StoredName, ValueKind, Home, Default, Appearance)                                                        \
    static CharonTraitDefinition charon_held_##ClassName;                                                                               \
    static void charon_define_##ClassName(void)                                                                                        \
    {                                                                                                                                   \
        charon_held_##ClassName.trait = [ClassName class];                                                                             \
        charon_held_##ClassName.name = StoredName;                                                                                     \
        charon_held_##ClassName.kind = ValueKind;                                                                                      \
        charon_held_##ClassName.home = Home;                                                                                           \
        charon_held_##ClassName.defaultValue = Default;                                                                                \
        charon_held_##ClassName.affectsColorAppearance = Appearance;                                                                   \
        charon_register_trait_definition(&charon_held_##ClassName);                                                                    \
    }

CHARON_TRAIT(UITraitUserInterfaceIdiom, @"UserInterfaceIdiom", CharonTraitValueNSInteger, CharonTraitHomeIvar, @(-1), YES)
CHARON_TRAIT(UITraitUserInterfaceStyle, @"UserInterfaceStyle", CharonTraitValueNSInteger, CharonTraitHomeStyle, @(0), YES)
CHARON_TRAIT(UITraitLayoutDirection, @"UserInterfaceLayoutDirection", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(-1), NO)
CHARON_TRAIT(UITraitDisplayScale, @"DisplayScale", CharonTraitValueCGFloat, CharonTraitHomeIvar, @(0), NO)
CHARON_TRAIT(UITraitHorizontalSizeClass, @"HorizontalSizeClass", CharonTraitValueNSInteger, CharonTraitHomeIvar, @(0), NO)
CHARON_TRAIT(UITraitVerticalSizeClass, @"VerticalSizeClass", CharonTraitValueNSInteger, CharonTraitHomeIvar, @(0), NO)
CHARON_TRAIT(UITraitForceTouchCapability, @"ForceTouchCapability", CharonTraitValueNSInteger, CharonTraitHomeForceTouch, @(0), NO)
CHARON_TRAIT(UITraitPreferredContentSizeCategory, @"PreferredContentSizeCategory", CharonTraitValueObject, CharonTraitHomeExtras, nil, NO)
CHARON_TRAIT(UITraitDisplayGamut, @"DisplayGamut", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(-1), YES)
CHARON_TRAIT(UITraitAccessibilityContrast, @"AccessibilityContrast", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(-1), YES)
CHARON_TRAIT(UITraitUserInterfaceLevel, @"UserInterfaceLevel", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(-1), YES)
CHARON_TRAIT(UITraitLegibilityWeight, @"LegibilityWeight", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(-1), NO)
CHARON_TRAIT(UITraitActiveAppearance, @"ActiveAppearance", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(-1), YES)
CHARON_TRAIT(UITraitToolbarItemPresentationSize, @"ToolbarItemPresentationSize", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(-1), NO)
CHARON_TRAIT(UITraitImageDynamicRange, @"ImageDynamicRange", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(-1), NO)
CHARON_TRAIT(UITraitTypesettingLanguage, @"TypesettingLanguage", CharonTraitValueObject, CharonTraitHomeExtras, nil, NO)
CHARON_TRAIT(UITraitSceneCaptureState, @"SceneCaptureState", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(-1), NO)
CHARON_TRAIT(UITraitHDRHeadroomUsageLimit, @"HDRHeadroomUsageLimit", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(-1), NO)
CHARON_TRAIT(UITraitResolvesNaturalAlignmentWithBaseWritingDirection, @"ResolvesNaturalAlignmentWithBaseWritingDirection", CharonTraitValueObject, CharonTraitHomeExtras, nil, NO)
CHARON_TRAIT(UITraitListEnvironment, @"ListEnvironment", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(0), YES)
CHARON_TRAIT(UITraitTabAccessoryEnvironment, @"TabAccessoryEnvironment", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(0), NO)
CHARON_TRAIT(UITraitSplitViewControllerLayoutEnvironment, @"SplitViewControllerLayoutEnvironment", CharonTraitValueNSInteger, CharonTraitHomeExtras, @(0), NO)

@interface CharonTraitDefinitions17 : NSObject
@end

@implementation CharonTraitDefinitions17

+ (void)load
{
    charon_define_UITraitUserInterfaceIdiom();
    charon_define_UITraitUserInterfaceStyle();
    charon_define_UITraitLayoutDirection();
    charon_define_UITraitDisplayScale();
    charon_define_UITraitHorizontalSizeClass();
    charon_define_UITraitVerticalSizeClass();
    charon_define_UITraitForceTouchCapability();
    charon_define_UITraitPreferredContentSizeCategory();
    charon_define_UITraitDisplayGamut();
    charon_define_UITraitAccessibilityContrast();
    charon_define_UITraitUserInterfaceLevel();
    charon_define_UITraitLegibilityWeight();
    charon_define_UITraitActiveAppearance();
    charon_define_UITraitToolbarItemPresentationSize();
    charon_define_UITraitImageDynamicRange();
    charon_define_UITraitTypesettingLanguage();
    charon_define_UITraitSceneCaptureState();
    charon_define_UITraitHDRHeadroomUsageLimit();
    charon_define_UITraitResolvesNaturalAlignmentWithBaseWritingDirection();
    charon_define_UITraitListEnvironment();
    charon_define_UITraitTabAccessoryEnvironment();
    charon_define_UITraitSplitViewControllerLayoutEnvironment();

    // The traits the older collections never had are named and described here, so a collection that holds one
    // prints it as the host prints it and codes it under the name the host's coder uses. The traits that
    // already had a description keep the one they have: charon_register_trait_kind refuses a second entry for a
    // name, so nothing carried changes.
    charon_register_trait_kind((CharonTraitKind){@"ImageDynamicRange", 0, YES, @"Standard", @"High"});
    charon_register_trait_kind((CharonTraitKind){@"SceneCaptureState", 0, YES, @"Inactive", @"Active"});
    charon_register_trait_kind((CharonTraitKind){@"HDRHeadroomUsageLimit", 0, YES, @"Active", @"Inactive"});
    charon_register_trait_kind((CharonTraitKind){@"ListEnvironment", 0, 2,
                                                   @"None,Plain,Grouped,InsetGrouped,Sidebar,SidebarPlain", nil});
    charon_register_trait_kind((CharonTraitKind){@"TabAccessoryEnvironment", 0, 2, @"None,Regular,Inline", nil});
    charon_register_trait_kind((CharonTraitKind){@"SplitViewControllerLayoutEnvironment", 0, 2, @"Expanded,Collapsed", nil});
    charon_register_trait_kind((CharonTraitKind){@"ToolbarItemPresentationSize", 0, 2, @"Small,Medium,Large", nil});
    // The two object traits and the one BOOL trait have no pair of names to print, so code 3 prints what is
    // held: the typesetting language a collection carries, and whether it resolves natural alignment from the
    // base writing direction rather than from the user's language.
    charon_register_trait_kind((CharonTraitKind){@"TypesettingLanguage", 0, 3, nil, nil});
    charon_register_trait_kind((CharonTraitKind){@"ResolvesNaturalAlignmentWithBaseWritingDirection", 0, 3, nil, nil});
}

@end

// One implementation for all twenty-two: the class property a caller names decides what the table holds for it.
static NSString *charon_identifier(Class self)
{
    return NSStringFromClass(self);
}

// +name is the class's own name without its UITrait prefix on every one of the twenty-two, measured; it is not
// the name the port stores the value under, which for UITraitLayoutDirection is the longer
// UserInterfaceLayoutDirection the collection has always printed. The two are separate on purpose, and
// charon_trait_public_name in the header is the one place the rule is written.
static NSString *charon_trait_name(Class self)
{
    const CharonTraitDefinition *definition = charon_trait_definition(self);
    return definition ? charon_trait_public_name(definition) : NSStringFromClass(self);
}

static BOOL charon_affects_color_appearance(Class self)
{
    const CharonTraitDefinition *definition = charon_trait_definition(self);
    return definition ? definition->affectsColorAppearance : NO;
}

static id charon_object_default(Class self)
{
    const CharonTraitDefinition *definition = charon_trait_definition(self);
    return definition ? definition->defaultValue : nil;
}

static NSInteger charon_integer_default(Class self)
{
    const CharonTraitDefinition *definition = charon_trait_definition(self);
    if (!definition)
        return -1;
    return definition->defaultValue ? [definition->defaultValue integerValue] : -1;
}

static CGFloat charon_cgfloat_default(Class self)
{
    const CharonTraitDefinition *definition = charon_trait_definition(self);
    return definition && definition->defaultValue ? (CGFloat)[definition->defaultValue doubleValue] : 0;
}

@implementation UITraitUserInterfaceIdiom
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitUserInterfaceStyle
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitLayoutDirection
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitDisplayScale
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (CGFloat)defaultValue { return charon_cgfloat_default(self); }
@end

@implementation UITraitHorizontalSizeClass
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitVerticalSizeClass
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitForceTouchCapability
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitPreferredContentSizeCategory
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (id)defaultValue { return charon_object_default(self); }
@end

@implementation UITraitDisplayGamut
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitAccessibilityContrast
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitUserInterfaceLevel
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitLegibilityWeight
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitActiveAppearance
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitToolbarItemPresentationSize
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitImageDynamicRange
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitTypesettingLanguage
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (id)defaultValue { return charon_object_default(self); }
@end

@implementation UITraitSceneCaptureState
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitHDRHeadroomUsageLimit
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitResolvesNaturalAlignmentWithBaseWritingDirection
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (id)defaultValue { return charon_object_default(self); }
@end

@implementation UITraitListEnvironment
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitTabAccessoryEnvironment
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

@implementation UITraitSplitViewControllerLayoutEnvironment
+ (NSString *)identifier { return charon_identifier(self); }
+ (NSString *)name { return charon_trait_name(self); }
+ (BOOL)affectsColorAppearance { return charon_affects_color_appearance(self); }
+ (NSInteger)defaultValue { return charon_integer_default(self); }
@end

#endif
