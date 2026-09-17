#import <UIKit/UIKit.h>
#import "check.h"

#define NAMED(...) ([NSString stringWithFormat:__VA_ARGS__].UTF8String)

@interface CharonHostUITraitCollection : NSObject <NSCopying, NSSecureCoding>
+ (instancetype)traitCollectionWithTraitsFromCollections:(NSArray *)traitCollections;
+ (instancetype)traitCollectionWithUserInterfaceIdiom:(UIUserInterfaceIdiom)idiom;
+ (instancetype)traitCollectionWithDisplayScale:(CGFloat)scale;
+ (instancetype)traitCollectionWithHorizontalSizeClass:(UIUserInterfaceSizeClass)horizontalSizeClass;
+ (instancetype)traitCollectionWithVerticalSizeClass:(UIUserInterfaceSizeClass)verticalSizeClass;
+ (instancetype)charon_traitCollectionWithIdiom:(UIUserInterfaceIdiom)idiom scale:(CGFloat)scale orientation:(UIInterfaceOrientation)orientation external:(BOOL)external;
- (BOOL)containsTraitsInCollection:(id)trait;
@property (nonatomic, readonly) UIUserInterfaceIdiom userInterfaceIdiom;
@property (nonatomic, readonly) CGFloat displayScale;
@property (nonatomic, readonly) UIUserInterfaceSizeClass horizontalSizeClass;
@property (nonatomic, readonly) UIUserInterfaceSizeClass verticalSizeClass;
@end

static NSString *traits_of(id collection)
{
    NSString *description = [collection description];
    NSRange separator = [description rangeOfString:@"; "];
    return separator.location == NSNotFound ? description : [description substringFromIndex:NSMaxRange(separator)];
}

static NSString *values_of(id collection)
{
    return [NSString stringWithFormat:@"idiom %ld scale %g horizontal %ld vertical %ld",
            (long)[collection userInterfaceIdiom], (double)[collection displayScale],
            (long)[collection horizontalSizeClass], (long)[collection verticalSizeClass]];
}

static void compare(id ours, UITraitCollection *system, const char *name)
{
    charon_check([values_of(ours) isEqualToString:values_of(system)], name, [NSString stringWithFormat:@"%@ != %@", values_of(ours), values_of(system)]);
    if ([ours userInterfaceIdiom] > UIUserInterfaceIdiomPad)
        return;
    charon_check([traits_of(ours) isEqualToString:traits_of(system)], NAMED(@"%s description", name), [NSString stringWithFormat:@"%@ != %@", traits_of(ours), traits_of(system)]);
}

static NSArray *archive_keys(id object)
{
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:YES error:NULL];
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    NSMutableArray *keys = [NSMutableArray array];
    for (id entry in [plist objectForKey:@"$objects"]) {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;
        for (NSString *key in entry) {
            if (![key hasPrefix:@"$"])
                [keys addObject:key];
        }
    }
    [keys sortUsingSelector:@selector(compare:)];
    return keys;
}

int main(void)
{
    @autoreleasepool {
        UIUserInterfaceIdiom idioms[] = {UIUserInterfaceIdiomUnspecified, UIUserInterfaceIdiomPhone, UIUserInterfaceIdiomPad, (UIUserInterfaceIdiom)9};
        CGFloat scales[] = {0, 1, 2, 2.5};
        UIUserInterfaceSizeClass classes[] = {UIUserInterfaceSizeClassUnspecified, UIUserInterfaceSizeClassCompact, UIUserInterfaceSizeClassRegular, (UIUserInterfaceSizeClass)5};
        for (int index = 0; index < 4; index++) {
            compare([CharonHostUITraitCollection traitCollectionWithUserInterfaceIdiom:idioms[index]],
                    [UITraitCollection traitCollectionWithUserInterfaceIdiom:idioms[index]], NAMED(@"idiom %ld", (long)idioms[index]));
            compare([CharonHostUITraitCollection traitCollectionWithDisplayScale:scales[index]],
                    [UITraitCollection traitCollectionWithDisplayScale:scales[index]], NAMED(@"scale %g", (double)scales[index]));
            compare([CharonHostUITraitCollection traitCollectionWithHorizontalSizeClass:classes[index]],
                    [UITraitCollection traitCollectionWithHorizontalSizeClass:classes[index]], NAMED(@"horizontal %ld", (long)classes[index]));
            compare([CharonHostUITraitCollection traitCollectionWithVerticalSizeClass:classes[index]],
                    [UITraitCollection traitCollectionWithVerticalSizeClass:classes[index]], NAMED(@"vertical %ld", (long)classes[index]));
        }
        compare([[CharonHostUITraitCollection alloc] init], [[UITraitCollection alloc] init], "empty collection");

        NSArray *ourParts = @[[CharonHostUITraitCollection traitCollectionWithUserInterfaceIdiom:UIUserInterfaceIdiomPhone],
                              [CharonHostUITraitCollection traitCollectionWithDisplayScale:2],
                              [CharonHostUITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassCompact],
                              [CharonHostUITraitCollection traitCollectionWithVerticalSizeClass:UIUserInterfaceSizeClassRegular],
                              [CharonHostUITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassRegular],
                              [CharonHostUITraitCollection traitCollectionWithUserInterfaceIdiom:UIUserInterfaceIdiomUnspecified],
                              [CharonHostUITraitCollection traitCollectionWithDisplayScale:0],
                              [[CharonHostUITraitCollection alloc] init]];
        NSArray *systemParts = @[[UITraitCollection traitCollectionWithUserInterfaceIdiom:UIUserInterfaceIdiomPhone],
                                 [UITraitCollection traitCollectionWithDisplayScale:2],
                                 [UITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassCompact],
                                 [UITraitCollection traitCollectionWithVerticalSizeClass:UIUserInterfaceSizeClassRegular],
                                 [UITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassRegular],
                                 [UITraitCollection traitCollectionWithUserInterfaceIdiom:UIUserInterfaceIdiomUnspecified],
                                 [UITraitCollection traitCollectionWithDisplayScale:0],
                                 [[UITraitCollection alloc] init]];
        compare([CharonHostUITraitCollection traitCollectionWithTraitsFromCollections:@[]],
                [UITraitCollection traitCollectionWithTraitsFromCollections:@[]], "merge of nothing");
        for (NSUInteger first = 0; first < ourParts.count; first++) {
            for (NSUInteger second = 0; second < ourParts.count; second++) {
                NSArray *ours = @[[ourParts objectAtIndex:first], [ourParts objectAtIndex:second]];
                NSArray *system = @[[systemParts objectAtIndex:first], [systemParts objectAtIndex:second]];
                compare([CharonHostUITraitCollection traitCollectionWithTraitsFromCollections:ours],
                        [UITraitCollection traitCollectionWithTraitsFromCollections:system], NAMED(@"merge %lu %lu", (unsigned long)first, (unsigned long)second));
            }
        }
        compare([CharonHostUITraitCollection traitCollectionWithTraitsFromCollections:ourParts],
                [UITraitCollection traitCollectionWithTraitsFromCollections:systemParts], "merge of every part");

        for (NSUInteger first = 0; first < ourParts.count; first++) {
            for (NSUInteger second = 0; second < ourParts.count; second++) {
                BOOL ours = [[ourParts objectAtIndex:first] containsTraitsInCollection:[ourParts objectAtIndex:second]];
                BOOL system = [[systemParts objectAtIndex:first] containsTraitsInCollection:[systemParts objectAtIndex:second]];
                charon_check(ours == system, NAMED(@"contains %lu %lu", (unsigned long)first, (unsigned long)second), [NSString stringWithFormat:@"%d != %d", ours, system]);
                BOOL equalOurs = [[ourParts objectAtIndex:first] isEqual:[ourParts objectAtIndex:second]];
                BOOL equalSystem = [[systemParts objectAtIndex:first] isEqual:[systemParts objectAtIndex:second]];
                charon_check(equalOurs == equalSystem, NAMED(@"equal %lu %lu", (unsigned long)first, (unsigned long)second), [NSString stringWithFormat:@"%d != %d", equalOurs, equalSystem]);
                if (equalOurs)
                    charon_check([[ourParts objectAtIndex:first] hash] == [[ourParts objectAtIndex:second] hash], NAMED(@"hash %lu %lu", (unsigned long)first, (unsigned long)second), @"equal collections hash differently");
            }
        }
        id merged = [CharonHostUITraitCollection traitCollectionWithTraitsFromCollections:ourParts];
        UITraitCollection *systemMerged = [UITraitCollection traitCollectionWithTraitsFromCollections:systemParts];
        charon_check([merged containsTraitsInCollection:nil] == [systemMerged containsTraitsInCollection:nil], "contains nil", @"a nil collection is contained");
        charon_check([merged copy] == merged, "copy returns the same object", @"copy allocated a new collection");
        charon_check([[merged class] supportsSecureCoding] == [[systemMerged class] supportsSecureCoding], "supports secure coding", @"secure coding differs");
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:merged requiringSecureCoding:YES error:NULL];
        id decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[merged class] fromData:data error:NULL];
        charon_check([values_of(decoded) isEqualToString:values_of(merged)], "coding round trip", [NSString stringWithFormat:@"%@ != %@", values_of(decoded), values_of(merged)]);
        charon_check([archive_keys(merged) isEqual:archive_keys(systemMerged)], "archive keys", [NSString stringWithFormat:@"%@ != %@", archive_keys(merged), archive_keys(systemMerged)]);

        struct { UIUserInterfaceIdiom idiom; CGFloat scale; UIInterfaceOrientation orientation; BOOL external; const char *expected; } rules[] = {
            {UIUserInterfaceIdiomPhone, 2, UIInterfaceOrientationPortrait, NO, "idiom 0 scale 2 horizontal 1 vertical 2"},
            {UIUserInterfaceIdiomPhone, 2, UIInterfaceOrientationPortraitUpsideDown, NO, "idiom 0 scale 2 horizontal 1 vertical 2"},
            {UIUserInterfaceIdiomPhone, 2, UIInterfaceOrientationLandscapeLeft, NO, "idiom 0 scale 2 horizontal 1 vertical 1"},
            {UIUserInterfaceIdiomPhone, 1, UIInterfaceOrientationLandscapeRight, NO, "idiom 0 scale 1 horizontal 1 vertical 1"},
            {UIUserInterfaceIdiomPad, 2, UIInterfaceOrientationPortrait, NO, "idiom 1 scale 2 horizontal 2 vertical 2"},
            {UIUserInterfaceIdiomPad, 1, UIInterfaceOrientationLandscapeLeft, NO, "idiom 1 scale 1 horizontal 2 vertical 2"},
            {UIUserInterfaceIdiomPhone, 1, UIInterfaceOrientationPortrait, YES, "idiom -1 scale 1 horizontal 2 vertical 2"},
        };
        for (NSUInteger index = 0; index < sizeof(rules) / sizeof(*rules); index++) {
            id collection = [CharonHostUITraitCollection charon_traitCollectionWithIdiom:rules[index].idiom scale:rules[index].scale orientation:rules[index].orientation external:rules[index].external];
            NSString *expected = [NSString stringWithUTF8String:rules[index].expected];
            charon_check([values_of(collection) isEqualToString:expected], NAMED(@"iOS 8 rule %lu", (unsigned long)index), [NSString stringWithFormat:@"%@ != %@", values_of(collection), expected]);
        }
        printf("checks=%d failures=%d\n", charon_checks, charon_failures);
        return charon_failures;
    }
}
