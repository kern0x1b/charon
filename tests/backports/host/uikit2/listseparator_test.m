// listseparator_test.m - the list separator configuration of iOS 14.5, port against host.
//
// Same shape as the rest of this suite: the port's class is renamed by uikit2/run.sh and sits beside the
// system's own in one process. The system side is the SDK's own class - the 16.4 SDK this package compiles
// against declares UIListSeparatorConfiguration, and so does the Catalyst SDK this links - so nothing here
// redeclares the system side and this group's other half comes out of a framework.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "check.h"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

@interface CharonHostUIListSeparatorConfiguration : NSObject <NSCopying, NSSecureCoding>
- (instancetype)initWithListAppearance:(UICollectionLayoutListAppearance)listAppearance;
@property (nonatomic) UIListSeparatorVisibility topSeparatorVisibility;
@property (nonatomic) UIListSeparatorVisibility bottomSeparatorVisibility;
@property (nonatomic) NSDirectionalEdgeInsets topSeparatorInsets;
@property (nonatomic) NSDirectionalEdgeInsets bottomSeparatorInsets;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, strong) UIColor *multipleSelectionColor;
@end

typedef id (*zero_init)(id, SEL);
typedef id (*sep_init)(id, SEL, UICollectionLayoutListAppearance);

static void BOTH(NSString *what, NSString *ours, NSString *theirs)
{
    charon_check([ours isEqualToString:theirs], what.UTF8String,
                 [NSString stringWithFormat:@"port %@ != system %@", ours, theirs]);
}

static NSString *insets(NSDirectionalEdgeInsets e)
{
    return [NSString stringWithFormat:@"%g %g %g %g", (double)e.top, (double)e.leading, (double)e.bottom, (double)e.trailing];
}

// The colour ROLE, and why it is the role. The host's separator colour and multiple-selection colour are
// 13.0 dynamic catalog entries with no name on 6.1.3 or 4.3, so neither the name nor the four components
// are shared between the two releases - the host resolves to 0 0 0 0.098 and the port's row is the iOS one.
// What is shared is that a colour is there and is not the clear colour, and that is what this asks.
static NSString *colourRole(UIColor *color)
{
    if (!color)
        return @"none";
    if ([color isEqual:[UIColor clearColor]])
        return @"clear";
    return @"present";
}

static void check_one_appearance(NSInteger appearance, NSString *label)
{
    CharonHostUIListSeparatorConfiguration *ours = [[CharonHostUIListSeparatorConfiguration alloc] initWithListAppearance:(UICollectionLayoutListAppearance)appearance];
    UIListSeparatorConfiguration *theirs = [[UIListSeparatorConfiguration alloc] initWithListAppearance:(UICollectionLayoutListAppearance)appearance];
    charon_check(ours != nil && theirs != nil, "both sides build a separator configuration", @"one side answered nothing");

    BOTH([NSString stringWithFormat:@"the %@ top visibility", label],
         [NSString stringWithFormat:@"%ld", (long)ours.topSeparatorVisibility],
         [NSString stringWithFormat:@"%ld", (long)theirs.topSeparatorVisibility]);
    BOTH([NSString stringWithFormat:@"the %@ bottom visibility", label],
         [NSString stringWithFormat:@"%ld", (long)ours.bottomSeparatorVisibility],
         [NSString stringWithFormat:@"%ld", (long)theirs.bottomSeparatorVisibility]);
    BOTH([NSString stringWithFormat:@"the %@ top insets are the automatic ones", label],
         insets(ours.topSeparatorInsets), insets(theirs.topSeparatorInsets));
    BOTH([NSString stringWithFormat:@"the %@ bottom insets are the automatic ones", label],
         insets(ours.bottomSeparatorInsets), insets(theirs.bottomSeparatorInsets));
    BOTH([NSString stringWithFormat:@"the %@ insets are the shared constant", label],
         [NSString stringWithFormat:@"%d", (int)(ours.topSeparatorInsets.leading == UIListSeparatorAutomaticInsets.leading)],
         [NSString stringWithFormat:@"%d", (int)(theirs.topSeparatorInsets.leading == UIListSeparatorAutomaticInsets.leading)]);
    BOTH([NSString stringWithFormat:@"the %@ colour is a colour", label], colourRole(ours.color), colourRole(theirs.color));
    BOTH([NSString stringWithFormat:@"the %@ multiple-selection colour is a colour", label],
         colourRole(ours.multipleSelectionColor), colourRole(theirs.multipleSelectionColor));

    // Every write, read back on both sides.
    ours.topSeparatorVisibility = 2; theirs.topSeparatorVisibility = 2;
    ours.bottomSeparatorVisibility = 1; theirs.bottomSeparatorVisibility = 1;
    ours.topSeparatorInsets = NSDirectionalEdgeInsetsMake(1, 2, 3, 4);
    theirs.topSeparatorInsets = NSDirectionalEdgeInsetsMake(1, 2, 3, 4);
    ours.bottomSeparatorInsets = NSDirectionalEdgeInsetsMake(5, 6, 7, 8);
    theirs.bottomSeparatorInsets = NSDirectionalEdgeInsetsMake(5, 6, 7, 8);
    ours.color = [UIColor redColor]; theirs.color = [UIColor redColor];
    ours.multipleSelectionColor = [UIColor greenColor]; theirs.multipleSelectionColor = [UIColor greenColor];
    BOTH([NSString stringWithFormat:@"a written %@ top visibility reads back", label],
         [NSString stringWithFormat:@"%ld", (long)ours.topSeparatorVisibility],
         [NSString stringWithFormat:@"%ld", (long)theirs.topSeparatorVisibility]);
    BOTH([NSString stringWithFormat:@"a written %@ bottom visibility reads back", label],
         [NSString stringWithFormat:@"%ld", (long)ours.bottomSeparatorVisibility],
         [NSString stringWithFormat:@"%ld", (long)theirs.bottomSeparatorVisibility]);
    BOTH([NSString stringWithFormat:@"a written %@ top insets read back", label],
         insets(ours.topSeparatorInsets), insets(theirs.topSeparatorInsets));
    BOTH([NSString stringWithFormat:@"a written %@ bottom insets read back", label],
         insets(ours.bottomSeparatorInsets), insets(theirs.bottomSeparatorInsets));
    BOTH([NSString stringWithFormat:@"a written %@ colour reads back by identity", label],
         ours.color == [UIColor redColor] ? @"same" : @"copied", theirs.color == [UIColor redColor] ? @"same" : @"copied");
    BOTH([NSString stringWithFormat:@"a written %@ multiple-selection colour reads back by identity", label],
         ours.multipleSelectionColor == [UIColor greenColor] ? @"same" : @"copied",
         theirs.multipleSelectionColor == [UIColor greenColor] ? @"same" : @"copied");

    // The copy: measured on the host, a DIFFERENT object that holds every written value, including the same
    // colour instances. Asking for both is what tells a copy from a hand-over of the receiver.
    CharonHostUIListSeparatorConfiguration *ourCopy = [ours copy];
    UIListSeparatorConfiguration *theirCopy = [theirs copy];
    BOTH([NSString stringWithFormat:@"a %@ copy is not its receiver", label], ourCopy == ours ? @"same" : @"other",
         theirCopy == theirs ? @"same" : @"other");
    BOTH([NSString stringWithFormat:@"a %@ copy keeps the top visibility", label],
         [NSString stringWithFormat:@"%ld", (long)ourCopy.topSeparatorVisibility],
         [NSString stringWithFormat:@"%ld", (long)theirCopy.topSeparatorVisibility]);
    BOTH([NSString stringWithFormat:@"a %@ copy keeps the bottom insets", label],
         insets(ourCopy.bottomSeparatorInsets), insets(theirCopy.bottomSeparatorInsets));
    BOTH([NSString stringWithFormat:@"a %@ copy keeps the colour instance", label],
         ourCopy.color == ours.color ? @"same" : @"other", theirCopy.color == theirs.color ? @"same" : @"other");

    // The archive. The keys are the host's own, read out of the host's archive plist, so this compares the
    // round trip rather than the bytes: both sides encode through a secure-coding archiver and read back.
    // One NSError per call, and the lengths as integers.  The first version of this section shared one
    // `error` across four calls and printed `ourArchive.length` - an NSUInteger - through a `%@`: CFString
    // called -respondsToSelector: on the number, and the whole group died with SIGSEGV inside
    // objc_opt_respondsToSelector before it could report anything.  That is the harness's own format string,
    // not the archive round trip: the crash was in the string built on the way to reporting a failure, and
    // it fired whether or not there was one.  Measured under AddressSanitizer, the stack was
    // objc_opt_respondsToSelector <- __CFSTRING_IS_CALLING_OUT_TO_AN_OBJECT_FORMAT_ARGUMENT_WITH_CONTEXT__ <-
    // +[NSString stringWithFormat:] <- check_one_appearance at this line.
    NSError *ourError = nil, *theirError = nil, *ourReadError = nil, *theirReadError = nil;
    NSData *ourArchive = [NSKeyedArchiver archivedDataWithRootObject:ours requiringSecureCoding:YES error:&ourError];
    NSData *theirArchive = [NSKeyedArchiver archivedDataWithRootObject:theirs requiringSecureCoding:YES error:&theirError];
    charon_check(ourArchive != nil && theirArchive != nil, [[NSString stringWithFormat:@"the %@ archives", label] UTF8String],
                 [NSString stringWithFormat:@"port %@ (%lu bytes) system %@ (%lu bytes)", ourError,
                  (unsigned long)ourArchive.length, theirError, (unsigned long)theirArchive.length]);
    if (ourArchive && theirArchive) {
        CharonHostUIListSeparatorConfiguration *ourBack =
            [NSKeyedUnarchiver unarchivedObjectOfClass:[CharonHostUIListSeparatorConfiguration class] fromData:ourArchive error:&ourReadError];
        UIListSeparatorConfiguration *theirBack =
            [NSKeyedUnarchiver unarchivedObjectOfClass:[UIListSeparatorConfiguration class] fromData:theirArchive error:&theirReadError];
        charon_check(ourBack != nil && theirBack != nil, [[NSString stringWithFormat:@"the %@ archive reads back", label] UTF8String],
                     [NSString stringWithFormat:@"port %@ system %@", ourBack ? @"an object" : ourReadError,
                      theirBack ? @"an object" : theirReadError]);
        if (ourBack && theirBack) {
            BOTH([NSString stringWithFormat:@"the %@ archived top visibility comes back", label],
                 [NSString stringWithFormat:@"%ld", (long)ourBack.topSeparatorVisibility],
                 [NSString stringWithFormat:@"%ld", (long)theirBack.topSeparatorVisibility]);
            BOTH([NSString stringWithFormat:@"the %@ archived bottom visibility comes back", label],
                 [NSString stringWithFormat:@"%ld", (long)ourBack.bottomSeparatorVisibility],
                 [NSString stringWithFormat:@"%ld", (long)theirBack.bottomSeparatorVisibility]);
            BOTH([NSString stringWithFormat:@"the %@ archived top insets come back", label],
                 insets(ourBack.topSeparatorInsets), insets(theirBack.topSeparatorInsets));
            BOTH([NSString stringWithFormat:@"the %@ archived bottom insets come back", label],
                 insets(ourBack.bottomSeparatorInsets), insets(theirBack.bottomSeparatorInsets));
            BOTH([NSString stringWithFormat:@"the %@ archived colour comes back", label],
                 colourRole(ourBack.color), colourRole(theirBack.color));
        }
    }
}

// All five appearances the 27.0 header declares. Measured: the host gives the same six values for every one
// of them, and the case asks all five so that a port which switched on the appearance would be red.
static void check_every_appearance(void)
{
    NSArray *names = @[@"plain", @"grouped", @"inset grouped", @"sidebar", @"sidebar plain"];
    for (NSInteger i = 0; i < (NSInteger)names.count; i++)
        check_one_appearance(i, names[(NSUInteger)i]);
}

// -init and +new are NS_UNAVAILABLE and neither refuses; what they answer is NOT the initialiser's shape.
// The insets are ZERO where the initialiser gives the automatic ones, and both colours are nil. That is
// measured and it is the whole of what these two rows are.
static void check_the_unavailable_pair(void)
{
    CharonHostUIListSeparatorConfiguration *ours = ((zero_init)objc_msgSend)((id)((zero_init)objc_msgSend)((id)[CharonHostUIListSeparatorConfiguration class], @selector(alloc)), @selector(init));
    UIListSeparatorConfiguration *theirs = ((zero_init)objc_msgSend)((id)((zero_init)objc_msgSend)((id)[UIListSeparatorConfiguration class], @selector(alloc)), @selector(init));
    charon_check(ours != nil && theirs != nil, "both sides answer an unavailable -init", @"one side raised");
    BOTH(@"the unavailable -init gives zero top visibility",
         [NSString stringWithFormat:@"%ld", (long)ours.topSeparatorVisibility],
         [NSString stringWithFormat:@"%ld", (long)theirs.topSeparatorVisibility]);
    BOTH(@"the unavailable -init gives zero top insets", insets(ours.topSeparatorInsets), insets(theirs.topSeparatorInsets));
    BOTH(@"the unavailable -init gives zero bottom insets", insets(ours.bottomSeparatorInsets), insets(theirs.bottomSeparatorInsets));
    BOTH(@"the unavailable -init gives no colour", colourRole(ours.color), colourRole(theirs.color));
    BOTH(@"the unavailable -init gives no multiple-selection colour", colourRole(ours.multipleSelectionColor),
         colourRole(theirs.multipleSelectionColor));

    CharonHostUIListSeparatorConfiguration *ourNew = ((zero_init)objc_msgSend)((id)[CharonHostUIListSeparatorConfiguration class], @selector(new));
    UIListSeparatorConfiguration *theirNew = ((zero_init)objc_msgSend)((id)[UIListSeparatorConfiguration class], @selector(new));
    charon_check(ourNew != nil && theirNew != nil, "both sides answer an unavailable +new", @"one side raised");
    BOTH(@"the unavailable +new gives zero bottom visibility",
         [NSString stringWithFormat:@"%ld", (long)ourNew.bottomSeparatorVisibility],
         [NSString stringWithFormat:@"%ld", (long)theirNew.bottomSeparatorVisibility]);
    BOTH(@"the unavailable +new gives zero bottom insets", insets(ourNew.bottomSeparatorInsets), insets(theirNew.bottomSeparatorInsets));
    BOTH(@"the unavailable +new gives no colour", colourRole(ourNew.color), colourRole(theirNew.color));
    BOTH(@"+supportsSecureCoding", [NSString stringWithFormat:@"%d", (int)[CharonHostUIListSeparatorConfiguration supportsSecureCoding]],
         [NSString stringWithFormat:@"%d", (int)[UIListSeparatorConfiguration supportsSecureCoding]]);
}

int main(void)
{
    @autoreleasepool {
        check_every_appearance();
        check_the_unavailable_pair();
        printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    }
    return charon_failures;
}