// contentunavailable_test.m - the empty-state property bags and the state object, port against host.
//
// The host's own UIKit and the port's in one process: uikit2/run.sh renames the backport's classes, so
// each case asks the two sides the same question and holds the answers to each other. What is compared
// is what facts/UIKit/UIContentUnavailable17.md records, and every default is read from the host rather
// than assumed, so a wrong default in the port is a red run and not a row that claims otherwise.
//
// Both sides are typed: the system side with the SDK's own class, the port side with the renamed
// declaration below, which the SDK has none of on a macCatalyst 15.0 target. That is the point of a
// differential against the port's own objects: the host framework cannot answer for these classes, the
// port can, and the comparison is between the two.
#import <UIKit/UIKit.h>
#import "check.h"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

@interface CharonHostUIContentUnavailableTextProperties : NSObject
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic) NSLineBreakMode lineBreakMode;
@property (nonatomic) NSInteger numberOfLines;
@property (nonatomic) BOOL adjustsFontSizeToFitWidth;
@property (nonatomic) CGFloat minimumScaleFactor;
@property (nonatomic) BOOL allowsDefaultTighteningForTruncation;
@end

@interface CharonHostUIContentUnavailableImageProperties : NSObject
@property (nonatomic, copy, nullable) UIImageSymbolConfiguration *preferredSymbolConfiguration;
@property (nonatomic, strong, nullable) UIColor *tintColor;
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) CGSize maximumSize;
@property (nonatomic) BOOL accessibilityIgnoresInvertColors;
@end

@interface CharonHostUIContentUnavailableButtonProperties : NSObject
@property (nonatomic, copy, nullable) UIAction *primaryAction;
@property (nonatomic, copy, nullable) UIMenu *menu;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic) UIButtonRole role;
@end

@interface CharonHostUIContentUnavailableConfigurationState : NSObject
- (instancetype)initWithTraitCollection:(UITraitCollection *)traitCollection;
@property (nonatomic, strong) UITraitCollection *traitCollection;
@property (nonatomic, strong, nullable) NSString *searchText;
- (nullable id)objectForKeyedSubscript:(id)key;
- (void)setObject:(id)object forKeyedSubscript:(id)key;
- (id)copyWithZone:(NSZone *)zone;
@end

// Each check names the question and takes the two answers already reduced to strings, so a red run says
// which property differed rather than printing two objects.
static void BOTH(NSString *what, NSString *ours, NSString *theirs)
{
    charon_check([ours isEqualToString:theirs], what.UTF8String,
                 [NSString stringWithFormat:@"port %@ != system %@", ours, theirs]);
}

static CharonHostUIContentUnavailableTextProperties *PortTextBag(Class c)
{
    return [[c alloc] init];
}

static void check_text_bag(void)
{
    Class port = NSClassFromString(@"CharonHostUIContentUnavailableTextProperties");
    CharonHostUIContentUnavailableTextProperties *ours = PortTextBag(port);
    UIContentUnavailableTextProperties *system = [[UIContentUnavailableTextProperties alloc] init];
    charon_check(ours != nil && system != nil, "both sides make a text bag", @"one of the two answered nothing");

    // the defaults, read rather than assumed
    BOTH(@"a fresh text bag holds the same line break mode",
         [@(ours.lineBreakMode) stringValue], [@(system.lineBreakMode) stringValue]);
    BOTH(@"a fresh text bag holds the same line count",
         [@(ours.numberOfLines) stringValue], [@(system.numberOfLines) stringValue]);
    BOTH(@"a fresh text bag holds the same font-size-to-fit flag",
         [@(ours.adjustsFontSizeToFitWidth) stringValue], [@(system.adjustsFontSizeToFitWidth) stringValue]);
    BOTH(@"a fresh text bag holds the same minimum scale factor",
         [@(ours.minimumScaleFactor) stringValue], [@(system.minimumScaleFactor) stringValue]);
    BOTH(@"a fresh text bag holds the same default tightening flag",
         [@(ours.allowsDefaultTighteningForTruncation) stringValue],
         [@(system.allowsDefaultTighteningForTruncation) stringValue]);
    // The two releases name their system font differently - the host answers .AppleSystemUIFont, which does not
    // exist on 6.1.3 - so what is compared is the size and the role, and the family names are recorded in the
    // facts rather than held equal, because holding them equal would ask the port to answer a name it has no
    // way to produce.
    charon_check(ours.font != nil && system.font != nil, "a fresh text bag holds a font on both sides",
                 [NSString stringWithFormat:@"port %@ system %@", ours.font, system.font]);
    if (ours.font && system.font) {
        BOTH(@"a fresh text bag's default font is the same size",
             [@(ours.font.pointSize) stringValue], [@(system.font.pointSize) stringValue]);
        // the review measured a fresh bag holding a colour as well as a font; this asks that here rather
        // than assuming it, and it is the check that is red until the port sets one
        // The two sides name their label colour differently - the host's is a dynamic catalog entry called
        // labelColor, the release's is darkTextColor - and neither name is the other's, so what is compared is
        // the role: a colour that is there and is not the clear colour. Both names are in the facts.
        BOTH(@"a fresh text bag holds a labelled colour, not none and not clear",
             (ours.color != nil && ![ours.color isEqual:[UIColor clearColor]]) ? @"labelled" : @"other",
             (system.color != nil && ![system.color isEqual:[UIColor clearColor]]) ? @"labelled" : @"other");
    }

    // the writes, then the reads
    UIFont *font = [UIFont systemFontOfSize:19];
    UIColor *color = [UIColor redColor];
    ours.font = font; system.font = font;
    ours.color = color; system.color = color;
    ours.numberOfLines = 3; system.numberOfLines = 3;
    ours.minimumScaleFactor = 0.75f; system.minimumScaleFactor = 0.75f;
    ours.adjustsFontSizeToFitWidth = YES; system.adjustsFontSizeToFitWidth = YES;
    ours.lineBreakMode = NSLineBreakByTruncatingTail; system.lineBreakMode = NSLineBreakByTruncatingTail;
    ours.allowsDefaultTighteningForTruncation = YES; system.allowsDefaultTighteningForTruncation = YES;

    BOTH(@"a text bag reads back the font it was given, by size",
         [@(ours.font.pointSize) stringValue], [@(system.font.pointSize) stringValue]);
    BOTH(@"a text bag reads back the font object it was given",
         ours.font == font ? @"set" : @"other", system.font == font ? @"set" : @"other");
    BOTH(@"a text bag reads back the line count it was given",
         [@(ours.numberOfLines) stringValue], [@(system.numberOfLines) stringValue]);
    BOTH(@"a text bag reads back the scale factor it was given",
         [@(ours.minimumScaleFactor) stringValue], [@(system.minimumScaleFactor) stringValue]);
    BOTH(@"a text bag reads back the line break mode it was given",
         [@(ours.lineBreakMode) stringValue], [@(system.lineBreakMode) stringValue]);
    BOTH(@"a text bag reads back the font-size-to-fit flag it was given",
         [@(ours.adjustsFontSizeToFitWidth) stringValue], [@(system.adjustsFontSizeToFitWidth) stringValue]);
    BOTH(@"a text bag reads back the default tightening flag it was given",
         [@(ours.allowsDefaultTighteningForTruncation) stringValue],
         [@(system.allowsDefaultTighteningForTruncation) stringValue]);
    CharonHostUIContentUnavailableTextProperties *ourCopy = [ours copy];
    UIContentUnavailableTextProperties *systemCopy = [system copy];
    BOTH(@"a text bag's copy holds the line count",
         [@(ourCopy.numberOfLines) stringValue], [@(systemCopy.numberOfLines) stringValue]);
    BOTH(@"a text bag's copy holds the font",
         ourCopy.font == font ? @"set" : @"other", systemCopy.font == font ? @"set" : @"other");
}

static void check_image_bag(void)
{
    CharonHostUIContentUnavailableImageProperties *ours =
        [[NSClassFromString(@"CharonHostUIContentUnavailableImageProperties") alloc] init];
    UIContentUnavailableImageProperties *system = [[UIContentUnavailableImageProperties alloc] init];
    charon_check(ours != nil && system != nil, "both sides make an image bag", @"one of the two answered nothing");

    BOTH(@"a fresh image bag holds the same corner radius",
         [@(ours.cornerRadius) stringValue], [@(system.cornerRadius) stringValue]);
    BOTH(@"a fresh image bag holds the same maximum width",
         [@(ours.maximumSize.width) stringValue], [@(system.maximumSize.width) stringValue]);
    BOTH(@"a fresh image bag holds the same maximum height",
         [@(ours.maximumSize.height) stringValue], [@(system.maximumSize.height) stringValue]);
    BOTH(@"a fresh image bag holds the same invert-colours flag",
         [@(ours.accessibilityIgnoresInvertColors) stringValue],
         [@(system.accessibilityIgnoresInvertColors) stringValue]);
    BOTH(@"a fresh image bag has no symbol configuration on either side",
         ours.preferredSymbolConfiguration == nil ? @"nil" : @"set",
         system.preferredSymbolConfiguration == nil ? @"nil" : @"set");

    UIColor *green = [UIColor greenColor];
    ours.tintColor = green; system.tintColor = green;
    ours.cornerRadius = 12.5f; system.cornerRadius = 12.5f;
    ours.maximumSize = CGSizeMake(64, 48); system.maximumSize = CGSizeMake(64, 48);
    ours.accessibilityIgnoresInvertColors = YES; system.accessibilityIgnoresInvertColors = YES;

    BOTH(@"an image bag reads back the corner radius",
         [@(ours.cornerRadius) stringValue], [@(system.cornerRadius) stringValue]);
    BOTH(@"an image bag reads back the maximum width",
         [@(ours.maximumSize.width) stringValue], [@(system.maximumSize.width) stringValue]);
    BOTH(@"an image bag reads back the maximum height",
         [@(ours.maximumSize.height) stringValue], [@(system.maximumSize.height) stringValue]);
    BOTH(@"an image bag reads back the invert-colours flag",
         [@(ours.accessibilityIgnoresInvertColors) stringValue],
         [@(system.accessibilityIgnoresInvertColors) stringValue]);
    BOTH(@"an image bag reads back the tint it was given", ours.tintColor == green ? @"set" : @"other",
         system.tintColor == green ? @"set" : @"other");
    CharonHostUIContentUnavailableImageProperties *ourCopy = [ours copy];
    UIContentUnavailableImageProperties *systemCopy = [system copy];
    BOTH(@"an image bag's copy holds the corner radius",
         [@(ourCopy.cornerRadius) stringValue], [@(systemCopy.cornerRadius) stringValue]);
}

static void check_button_bag(void)
{
    CharonHostUIContentUnavailableButtonProperties *ours =
        [[NSClassFromString(@"CharonHostUIContentUnavailableButtonProperties") alloc] init];
    UIContentUnavailableButtonProperties *system = [[UIContentUnavailableButtonProperties alloc] init];
    charon_check(ours != nil && system != nil, "both sides make a button bag", @"one of the two answered nothing");

    BOTH(@"a fresh button bag answers enabled the same way",
         [@(ours.isEnabled) stringValue], [@(system.isEnabled) stringValue]);
    BOTH(@"a fresh button bag holds the same role", [@(ours.role) stringValue], [@(system.role) stringValue]);
    BOTH(@"a fresh button bag has no action on either side",
         ours.primaryAction == nil ? @"nil" : @"set", system.primaryAction == nil ? @"nil" : @"set");
    BOTH(@"a fresh button bag has no menu on either side",
         ours.menu == nil ? @"nil" : @"set", system.menu == nil ? @"nil" : @"set");

    ours.enabled = NO; system.enabled = NO;
    ours.role = UIButtonRolePrimary; system.role = UIButtonRolePrimary;
    BOTH(@"a button bag reads back the enabled flag",
         [@(ours.isEnabled) stringValue], [@(system.isEnabled) stringValue]);
    BOTH(@"a button bag reads back the role", [@(ours.role) stringValue], [@(system.role) stringValue]);
    CharonHostUIContentUnavailableButtonProperties *ourCopy = [ours copy];
    UIContentUnavailableButtonProperties *systemCopy = [system copy];
    BOTH(@"a button bag's copy holds the enabled flag",
         [@(ourCopy.isEnabled) stringValue], [@(systemCopy.isEnabled) stringValue]);
}

static void check_state(void)
{
    CharonHostUIContentUnavailableConfigurationState *ours =
        [[NSClassFromString(@"CharonHostUIContentUnavailableConfigurationState") alloc]
            initWithTraitCollection:[UITraitCollection currentTraitCollection]];
    UIContentUnavailableConfigurationState *system =
        [[UIContentUnavailableConfigurationState alloc] initWithTraitCollection:[UITraitCollection currentTraitCollection]];
    charon_check(ours != nil && system != nil, "both sides make a state over a trait collection",
                 @"one of the two answered nothing");
    BOTH(@"a fresh state has no search text on either side",
         ours.searchText == nil ? @"nil" : @"set", system.searchText == nil ? @"nil" : @"set");

    ours.searchText = @"a search"; system.searchText = @"a search";
    BOTH(@"a state reads back the search text it was given", ours.searchText, system.searchText);

    // the keyed pair UIConfigurationState declares
    [ours setObject:@"held" forKeyedSubscript:@"k"];
    [system setObject:@"held" forKeyedSubscript:@"k"];
    BOTH(@"a state holds what was keyed into it", [ours objectForKeyedSubscript:@"k"], [system objectForKeyedSubscript:@"k"]);
    BOTH(@"a state holds nothing at a key nobody keyed",
         [ours objectForKeyedSubscript:@"absent"] == nil ? @"nil" : @"other",
         [system objectForKeyedSubscript:@"absent"] == nil ? @"nil" : @"other");
    CharonHostUIContentUnavailableConfigurationState *ourCopy = [ours copy];
    UIContentUnavailableConfigurationState *systemCopy = [system copy];
    BOTH(@"a state's copy keeps the keyed value",
         [ourCopy objectForKeyedSubscript:@"k"], [systemCopy objectForKeyedSubscript:@"k"]);
    BOTH(@"a state's copy keeps the search text", ourCopy.searchText, systemCopy.searchText);
}

int main(void)
{
    @autoreleasepool {
        check_text_bag();
        check_image_bag();
        check_button_bag();
        check_state();
        printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    }
    return charon_failures;
}
