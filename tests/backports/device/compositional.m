#import <UIKit/UIKit.h>
#include <dlfcn.h>
#import "check.h"
#import "compositional-cases.m"
#import "compositional-expectations.h"

static NSString *const results_folder = @"/private/var/backports";

@interface CharonCompositionalDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation CharonCompositionalDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    charon_log_to([results_folder stringByAppendingPathComponent:@"compositional.log"]);
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UIViewController alloc] init];
    [self.window makeKeyAndVisible];
    [self performSelector:@selector(runAndReport) withObject:nil afterDelay:0];
    return YES;
}

- (void)runAndReport
{
    @try {
        [self run];
    } @catch (NSException *exception) {
        charon_check(NO, "the checks raise no exception", [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]);
    }
    NSString *summary = [NSString stringWithFormat:@"%@ checks=%d failures=%d\n", charon_failures ? @"FAIL" : @"ok", charon_checks, charon_failures];
    [summary writeToFile:[results_folder stringByAppendingPathComponent:@"compositional.done"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)run
{
    Dl_info info;
    CHECK(dladdr((__bridge const void *)[NSCollectionLayoutSection class], &info) && !strcmp(strrchr(info.dli_fname, '/') + 1, "libUIKitBackports.dylib"), "NSCollectionLayoutSection comes from the backports library");
    CHECK(dladdr((__bridge const void *)[UICollectionViewCompositionalLayout class], &info) && !strcmp(strrchr(info.dli_fname, '/') + 1, "libUIKitBackports.dylib"),
          "UICollectionViewCompositionalLayout comes from the backports library");
    CHECK(sizeof compositional_expectations / sizeof compositional_expectations[0] == compositional_case_count(), "there is one recorded answer for every layout");
    CompositionalKit kit = compositional_kit(@"");
    size_t wrong = 0;
    UIView *probe = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    [self.window.rootViewController.view addSubview:probe];
    UIEdgeInsets safe = [probe respondsToSelector:@selector(safeAreaInsets)] ? probe.safeAreaInsets : UIEdgeInsetsZero;
    [probe removeFromSuperview];
    BOOL recorded = [UIScreen mainScreen].scale == 2 && UIEdgeInsetsEqualToEdgeInsets(safe, UIEdgeInsetsZero);
    CHECK(recorded || YES, recorded ? "the screen is the scale the layouts were recorded at, with no safe area" : "the screen is not at scale 2 with a safe area of zero, where the layouts were recorded, so they are not compared");
    for (NSUInteger index = 0; recorded && index < compositional_case_count(); index++) {
        NSString *actual = compositional_case_dump(kit, index, self.window);
        NSString *expected = @(compositional_expectations[index]);
        if ([actual isEqualToString:expected])
            continue;
        wrong++;
        NSArray *a = [actual componentsSeparatedByString:@"\n"], *b = [expected componentsSeparatedByString:@"\n"];
        NSMutableString *detail = [NSMutableString string];
        for (NSUInteger line = 0; line < MAX(a.count, b.count) && line < 12; line++) {
            NSString *left = line < a.count ? a[line] : @"<none>", *right = line < b.count ? b[line] : @"<none>";
            if (![left isEqual:right])
                [detail appendFormat:@"\n    device %@\n    system %@", left, right];
        }
        NSString *name = [NSString stringWithFormat:@"layout %@ lays out as the system does", compositional_case_name(index)];
        charon_check(NO, name.UTF8String, detail);
    }
    CHECK(wrong == 0, "all recorded layouts are laid out as the system does");
    [self checkEnvironments];
    [self checkHonesty];
}

- (void)checkEnvironments
{
    NSMutableArray *seen = [NSMutableArray array];
    NSCollectionLayoutDimension *(^whole)(void) = ^{ return [NSCollectionLayoutDimension fractionalWidthDimension:1]; };
    NSCollectionLayoutSize *(^size)(NSCollectionLayoutDimension *, NSCollectionLayoutDimension *) = ^(NSCollectionLayoutDimension *w, NSCollectionLayoutDimension *h) {
        return [NSCollectionLayoutSize sizeWithWidthDimension:w heightDimension:h];
    };
    __block NSString *customSeen = nil;
    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger index, id<NSCollectionLayoutEnvironment> environment) {
        id<NSCollectionLayoutContainer> container = environment.container;
        [seen addObject:[NSString stringWithFormat:@"%ld %g %g %g %g %d", (long)index, container.contentSize.width, container.contentSize.height, container.effectiveContentSize.width, container.effectiveContentSize.height,
                                                   environment.traitCollection != nil]];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:size([NSCollectionLayoutDimension fractionalWidthDimension:0.5], [NSCollectionLayoutDimension fractionalHeightDimension:1])];
        NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup customGroupWithLayoutSize:size(whole(), [NSCollectionLayoutDimension absoluteDimension:80]) itemProvider:^NSArray *(id<NSCollectionLayoutEnvironment> inner) {
            id<NSCollectionLayoutContainer> box = inner.container;
            customSeen = [NSString stringWithFormat:@"%g %g %g %g %g %g", box.contentSize.width, box.contentSize.height, box.effectiveContentSize.width, box.effectiveContentSize.height, box.contentInsets.leading, box.effectiveContentInsets.top];
            return @[[NSCollectionLayoutGroupCustomItem customItemWithFrame:CGRectMake(1, 2, 30, 40)]];
        }];
        group.contentInsets = NSDirectionalEdgeInsetsMake(1, 2, 3, 4);
        (void)item;
        return [NSCollectionLayoutSection sectionWithGroup:group];
    }];
    CompositionalCase *built = [[CompositionalCase alloc] init];
    built.layout = layout;
    built.counts = @[@2, @1];
    built.kinds = @[];
    built.decorations = @[];
    built.size = CGSizeMake(320, 480);
    NSString *dump = compositional_dump(built, self.window);
    CHECK_EQUAL(seen.count == 2 ? seen[0] : nil, @"0 320 480 320 480 1", "the section provider is given the size of the collection view and its trait collection");
    CHECK_EQUAL(seen.count == 2 ? seen[1] : nil, @"1 320 480 320 480 1", "the section provider is called once for each section");
    CHECK_EQUAL(customSeen, @"320 80 314 76 2 1", "the custom group's provider is given the group's size, less the group's insets");
    CHECK([dump rangeOfString:@"0 - 0.0 1 2 30 40"].location != NSNotFound, "a custom item is placed from the group's own corner");

    __block int handled = 0;
    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:[NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size(whole(), [NSCollectionLayoutDimension absoluteDimension:40])
                                                                                                                                  subitems:@[[NSCollectionLayoutItem itemWithLayoutSize:size([NSCollectionLayoutDimension fractionalWidthDimension:0.5], [NSCollectionLayoutDimension fractionalHeightDimension:1])]]]];
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorPaging;
    section.visibleItemsInvalidationHandler = ^(NSArray *items, CGPoint offset, id<NSCollectionLayoutEnvironment> environment) {
        handled++;
    };
    CompositionalCase *orthogonal = [[CompositionalCase alloc] init];
    orthogonal.layout = [[UICollectionViewCompositionalLayout alloc] initWithSection:section];
    orthogonal.counts = @[@3];
    orthogonal.kinds = @[];
    orthogonal.decorations = @[];
    orthogonal.size = CGSizeMake(320, 480);
    NSString *flat = compositional_dump(orthogonal, self.window);
    CHECK([flat rangeOfString:@"0 - 0.2 0 40 160 40"].location != NSNotFound, "a section that scrolls the other way is laid out as an ordinary section");
    CHECK(handled == 0 && section.visibleItemsInvalidationHandler != nil && section.orthogonalScrollingBehavior == UICollectionLayoutSectionOrthogonalScrollingBehaviorPaging,
          "its behavior and its handler are kept, and the handler is never called");
}

- (void)checkHonesty
{
    CHECK(![NSCollectionLayoutGroup instancesRespondToSelector:NSSelectorFromString(@"visualDescription")], "the group's visual description is absent");
    CHECK(![NSCollectionLayoutGroup respondsToSelector:NSSelectorFromString(@"horizontalGroupWithLayoutSize:repeatingSubitem:count:")], "the repeating group of iOS 16 is absent");
    CHECK(![NSCollectionLayoutSection instancesRespondToSelector:NSSelectorFromString(@"supplementaryContentInsetsReference")], "the supplementary content insets reference of iOS 16 is absent");
    CHECK(![NSCollectionLayoutSection instancesRespondToSelector:NSSelectorFromString(@"orthogonalScrollingProperties")], "the orthogonal scrolling properties of iOS 17 are absent");
    CHECK(![NSCollectionLayoutItem instancesRespondToSelector:NSSelectorFromString(@"setSupplementaryItems:")], "an item's supplementary items are read-only");
    CHECK([NSCollectionLayoutGroup instancesRespondToSelector:NSSelectorFromString(@"setSupplementaryItems:")], "a group's supplementary items are settable");
    CHECK([NSCollectionLayoutSection instancesRespondToSelector:NSSelectorFromString(@"contentInsetsReference")] && [UICollectionViewCompositionalLayoutConfiguration instancesRespondToSelector:NSSelectorFromString(@"contentInsetsReference")],
          "the content insets reference of iOS 14 is there");
    UICollectionViewCompositionalLayoutConfiguration *configuration = [[UICollectionViewCompositionalLayoutConfiguration alloc] init];
    CHECK(configuration.contentInsetsReference == UIContentInsetsReferenceSafeArea && [NSCollectionLayoutSection sectionWithGroup:[NSCollectionLayoutGroup horizontalGroupWithLayoutSize:[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1] heightDimension:[NSCollectionLayoutDimension absoluteDimension:1]] subitems:@[[NSCollectionLayoutItem itemWithLayoutSize:[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1] heightDimension:[NSCollectionLayoutDimension absoluteDimension:1]]]]]].contentInsetsReference == UIContentInsetsReferenceAutomatic,
          "the layout refers to the safe area and a section to automatic, as the header says");
    CHECK([[NSCollectionLayoutDimension fractionalWidthDimension:0.5] isEqual:[NSCollectionLayoutDimension fractionalWidthDimension:0.5]] && ![[NSCollectionLayoutDimension fractionalWidthDimension:0.5] isEqual:[NSCollectionLayoutDimension absoluteDimension:0.5]],
          "dimensions are equal by kind and value");
    BOOL raised = NO;
    @try {
        [NSCollectionLayoutDimension fractionalWidthDimension:NAN];
    } @catch (NSException *exception) {
        raised = [exception.name isEqual:NSInternalInconsistencyException] && [exception.reason hasPrefix:@"Invalid fractional width: nan."];
    }
    CHECK(raised, "a dimension that is not finite raises as the system's does");
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        [[NSFileManager defaultManager] createDirectoryAtPath:results_folder withIntermediateDirectories:YES attributes:nil error:NULL];
        return UIApplicationMain(argc, argv, nil, @"CharonCompositionalDelegate");
    }
}
