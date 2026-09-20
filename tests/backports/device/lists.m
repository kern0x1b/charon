#import <UIKit/UIKit.h>
#include <dlfcn.h>
#pragma clang diagnostic ignored "-Wnonnull"
#import <objc/runtime.h>
#import "check.h"
#import "lists-cases.h"
#import "lists-expectations.h"

static NSString *const results_folder = @"/private/var/backports";

static void spin(NSTimeInterval seconds)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

static UIImage *square(CGFloat side)
{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 1);
    [[UIColor redColor] setFill];
    UIRectFill(CGRectMake(0, 0, side, side));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static NSString *rgb(UIColor *color)
{
    CGFloat c[4] = {0, 0, 0, 0};
    [color getRed:&c[0] green:&c[1] blue:&c[2] alpha:&c[3]];
    return [NSString stringWithFormat:@"(%.3f,%.3f,%.3f,%.3f)", c[0], c[1], c[2], c[3]];
}

@interface CharonListsSource : NSObject <UICollectionViewDataSource>
@property (nonatomic, copy) void (^configure)(UICollectionViewCell *cell, NSIndexPath *indexPath);
@property (nonatomic, copy) UICollectionReusableView *(^supplementary)(UICollectionView *view, NSString *kind, NSIndexPath *indexPath);
@property (nonatomic) NSInteger count;
@end

@implementation CharonListsSource
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.count;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"c" forIndexPath:indexPath];
    self.configure(cell, indexPath);
    return cell;
}
- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    return self.supplementary(collectionView, kind, indexPath);
}
@end

@interface CharonRegistrationsSource : NSObject <UICollectionViewDataSource>
@property (nonatomic, strong) UICollectionViewCellRegistration *registration;
@property (nonatomic, strong) UICollectionViewSupplementaryRegistration *header;
@end

@implementation CharonRegistrationsSource
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return 3;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [collectionView dequeueConfiguredReusableCellWithRegistration:self.registration forIndexPath:indexPath item:@(indexPath.item)];
}
- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    return [collectionView dequeueConfiguredReusableSupplementaryViewWithRegistration:self.header forIndexPath:indexPath];
}
@end

@interface CharonListsCell : UICollectionViewListCell
@end

static NSMutableArray *update_log;

@implementation CharonListsCell
- (void)updateConfigurationUsingState:(UICellConfigurationState *)state
{
    [update_log addObject:[NSString stringWithFormat:@"update h=%d s=%d e=%d d=%d", state.highlighted, state.selected, state.editing, state.disabled]];
    [super updateConfigurationUsingState:state];
}
- (void)setNeedsUpdateConfiguration
{
    [update_log addObject:@"needsUpdate"];
    [super setNeedsUpdateConfiguration];
}
@end

@interface CharonListsDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation CharonListsDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    charon_log_to([results_folder stringByAppendingPathComponent:@"lists.log"]);
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
    [summary writeToFile:[results_folder stringByAppendingPathComponent:@"lists.done"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (UICollectionViewCell *)buildCase:(const ListCase *)c view:(UICollectionView **)outView
{
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(c->width, c->height);
    layout.minimumLineSpacing = 0;
    UICollectionView *view = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, c->width, 480) collectionViewLayout:layout];
    [view registerClass:[UICollectionViewListCell class] forCellWithReuseIdentifier:@"c"];
    [self.window.rootViewController.view addSubview:view];
    CharonListsSource *source = [[CharonListsSource alloc] init];
    source.count = 1;
    NSString *factory = @(c->factory);
    source.configure = ^(UICollectionViewCell *cell, NSIndexPath *indexPath) {
        UIListContentConfiguration *configuration = [[UIListContentConfiguration performSelector:NSSelectorFromString(factory)] copy];
        if (c->text)
            configuration.text = @"Title";
        if (c->secondary)
            configuration.secondaryText = @"Secondary";
        if (c->image)
            configuration.image = square(29);
        cell.contentConfiguration = configuration;
        NSMutableArray *accessories = [NSMutableArray array];
        for (int slot = 0; slot < 3; slot++) {
            int kind = c->accessories[slot];
            if (kind < 0)
                continue;
            NSString *name = @(list_accessory_names[kind]);
            if ([name hasPrefix:@"custom"])
                [accessories addObject:[[UICellAccessoryCustomView alloc] initWithCustomView:[[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 20)]
                                                                                    placement:[name hasSuffix:@"leading"] ? UICellAccessoryPlacementLeading : UICellAccessoryPlacementTrailing]];
            else
                [accessories addObject:[[NSClassFromString(name) alloc] init]];
        }
        [(UICollectionViewListCell *)cell setAccessories:accessories];
        [(UICollectionViewListCell *)cell setIndentationLevel:c->indentation];
    };
    view.dataSource = source;
    objc_setAssociatedObject(view, "source", source, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.editing = c->editing;
    [view reloadData];
    [view layoutIfNeeded];
    spin(0.1);
    [view layoutIfNeeded];
    *outView = view;
    return [view cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
}

- (void)collect:(UIView *)view root:(UIView *)root labels:(NSMutableArray *)labels images:(NSMutableArray *)images
{
    for (UIView *sub in view.subviews) {
        CGRect frame = [sub.superview convertRect:sub.frame toView:root];
        if ([sub isKindOfClass:[UILabel class]])
            [labels addObject:[NSValue valueWithCGRect:frame]];
        else if ([sub isKindOfClass:[UIImageView class]])
            [images addObject:[NSValue valueWithCGRect:frame]];
        [self collect:sub root:root labels:labels images:images];
    }
}

- (BOOL)close:(double)actual to:(double)expected
{
    return fabs(actual - expected) <= 0.51;
}

- (void)run
{
    Dl_info info;
    CHECK(dladdr((__bridge const void *)[UIListContentConfiguration class], &info) && !strcmp(strrchr(info.dli_fname, '/') + 1, "libUIKitBackports.dylib"), "UIListContentConfiguration comes from the backports library");
    CHECK(dladdr((__bridge const void *)[UICollectionViewListCell class], &info) && !strcmp(strrchr(info.dli_fname, '/') + 1, "libUIKitBackports.dylib"), "UICollectionViewListCell comes from the backports library");
    [self checkValues];
    [self checkGeometry];
    [self checkListLayout];
    [self checkStates];
    [self checkHonesty];
}

- (void)checkValues
{
    NSArray *factories = @[@"cellConfiguration", @"subtitleCellConfiguration", @"valueCellConfiguration", @"plainHeaderConfiguration", @"plainFooterConfiguration", @"groupedHeaderConfiguration", @"groupedFooterConfiguration",
                           @"sidebarCellConfiguration", @"sidebarSubtitleCellConfiguration", @"accompaniedSidebarCellConfiguration", @"accompaniedSidebarSubtitleCellConfiguration", @"sidebarHeaderConfiguration"];
    CHECK(factories.count == sizeof lists_values / sizeof lists_values[0], "there is a recorded line for every content configuration style");
    for (NSUInteger index = 0; index < factories.count; index++) {
        NSString *actual = list_value_line(factories[index], [UIListContentConfiguration performSelector:NSSelectorFromString(factories[index])]);
        charon_check(list_text_agrees(actual, @(lists_values[index]), 0.001), [NSString stringWithFormat:@"the %@ has the recorded values", factories[index]].UTF8String, [NSString stringWithFormat:@"\n  actual   %@\n  recorded %s", actual, lists_values[index]]);
    }
    NSArray *backgrounds = @[@"clearConfiguration", @"listPlainCellConfiguration", @"listPlainHeaderFooterConfiguration", @"listGroupedCellConfiguration", @"listGroupedHeaderFooterConfiguration", @"listSidebarHeaderConfiguration",
                             @"listSidebarCellConfiguration", @"listAccompaniedSidebarCellConfiguration"];
    for (NSUInteger index = 0; index < backgrounds.count; index++) {
        NSString *actual = list_background_line(backgrounds[index], [UIBackgroundConfiguration performSelector:NSSelectorFromString(backgrounds[index])]);
        charon_check(list_text_agrees(actual, @(lists_backgrounds[index]), 0.001), [NSString stringWithFormat:@"the %@ has the recorded values", backgrounds[index]].UTF8String, [NSString stringWithFormat:@"\n  actual   %@\n  recorded %s", actual, lists_backgrounds[index]]);
    }
    UIListContentConfiguration *configuration = [UIListContentConfiguration cellConfiguration];
    configuration.text = @"Hello";
    configuration.textProperties.numberOfLines = 2;
    UIListContentConfiguration *copy = [configuration copy];
    CHECK([copy isEqual:configuration] && copy.textProperties != configuration.textProperties && copy.hash == configuration.hash, "a copy is equal and holds its own properties");
    copy.textProperties.numberOfLines = 3;
    CHECK(![copy isEqual:configuration] && configuration.textProperties.numberOfLines == 2, "changing the copy leaves the original alone");
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:configuration];
    UIListContentConfiguration *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    CHECK([decoded isEqual:configuration], "a configuration survives archiving");
    UICellConfigurationState *state = [[UICellConfigurationState alloc] initWithTraitCollection:[[UITraitCollection alloc] init]];
    state.selected = YES;
    state[@"key"] = @"value";
    UICellConfigurationState *stateCopy = [state copy];
    CHECK([stateCopy isEqual:state] && stateCopy[@"key"] && stateCopy.selected && ![stateCopy isEditing], "a state copies with its flags and custom states");
    BOOL raised = NO;
    @try {
        (void)[[UIViewConfigurationState alloc] initWithTraitCollection:nil];
    } @catch (NSException *exception) {
        raised = [exception.name isEqual:NSInternalInconsistencyException] && [exception.reason isEqual:@"Invalid parameter not satisfying: traitCollection != nil"];
    }
    CHECK(raised, "a state with no trait collection raises as the system's does");
    NSArray *sections = @[];
    (void)sections;
}

- (void)checkGeometry
{
    CHECK(list_case_count() == sizeof lists_geometry / sizeof lists_geometry[0], "there is a recorded answer for every list case");
    for (size_t index = 0; index < list_case_count(); index++) {
        const ListCase *c = &list_cases[index];
        UICollectionView *view = nil;
        UICollectionViewCell *cell = [self buildCase:c view:&view];
        NSMutableArray *labels = [NSMutableArray array], *images = [NSMutableArray array];
        [self collect:cell.contentView root:cell labels:labels images:images];
        const double *expected = lists_geometry[index];
        NSMutableArray *accessories = [NSMutableArray array];
        for (UIView *sub in cell.subviews) {
            NSString *name = NSStringFromClass([sub class]);
            if (sub == cell.contentView || [name hasSuffix:@"BackgroundView"] || [name hasSuffix:@"RowSeparatorView"] || sub.hidden)
                continue;
            [accessories addObject:[NSValue valueWithCGRect:sub.frame]];
        }
        [accessories sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
            return [@(a.CGRectValue.origin.x) compare:@(b.CGRectValue.origin.x)];
        }];
        CGRect content = cell.contentView.frame;
        CGRect image = images.count ? [images[0] CGRectValue] : CGRectMake(-1, -1, -1, -1);
        double textX = labels.count ? [labels[0] CGRectValue].origin.x : -1;
        BOOL match = [self close:content.origin.x to:expected[0]] && [self close:content.size.width to:expected[1]] && [self close:image.origin.x to:expected[2]] && [self close:image.origin.y to:expected[3]] &&
                     [self close:image.size.width to:expected[4]] && [self close:image.size.height to:expected[5]] && [self close:textX to:expected[6]] && accessories.count == (NSUInteger)expected[7];
        for (NSUInteger slot = 0; match && slot < accessories.count && slot < 3; slot++) {
            CGRect frame = [accessories[slot] CGRectValue];
            match = [self close:frame.origin.x to:expected[8 + 4 * slot]] && [self close:frame.origin.y to:expected[9 + 4 * slot]] && [self close:frame.size.width to:expected[10 + 4 * slot]] && [self close:frame.size.height to:expected[11 + 4 * slot]];
        }
        NSString *detail = [NSString stringWithFormat:@"editing %d superview %@ content %g %g image %@ text x %g accessories %lu\n  recorded %g %g image %g %g %g %g text x %g accessories %g", view.editing, NSStringFromClass([cell.superview class]), content.origin.x, content.size.width, NSStringFromCGRect(image), textX, (unsigned long)accessories.count, expected[0],
                                                     expected[1], expected[2], expected[3], expected[4], expected[5], expected[6], expected[7]];
        charon_check(match, [NSString stringWithFormat:@"list case %zu (%s) is laid out as the recorded one", index, c->factory].UTF8String, detail);
        [view removeFromSuperview];
    }
}

- (void)checkListLayout
{
    UICollectionLayoutListConfiguration *configuration = [[UICollectionLayoutListConfiguration alloc] initWithAppearance:UICollectionLayoutListAppearancePlain];
    configuration.headerMode = UICollectionLayoutListHeaderModeSupplementary;
    UICollectionViewCompositionalLayout *layout = [UICollectionViewCompositionalLayout layoutWithListConfiguration:configuration];
    UICollectionView *view = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 320, 480) collectionViewLayout:layout];
    [self.window.rootViewController.view addSubview:view];
    CharonRegistrationsSource *source = [[CharonRegistrationsSource alloc] init];
    source.registration = [UICollectionViewCellRegistration registrationWithCellClass:[CharonListsCell class] configurationHandler:^(UICollectionViewListCell *cell, NSIndexPath *indexPath, id item) {
        UIListContentConfiguration *content = [cell defaultContentConfiguration];
        content.text = [NSString stringWithFormat:@"Row %@", item];
        cell.contentConfiguration = content;
        cell.accessories = indexPath.item == 0 ? @[[[UICellAccessoryDisclosureIndicator alloc] init]] : @[];
    }];
    source.header = [UICollectionViewSupplementaryRegistration registrationWithSupplementaryClass:[UICollectionReusableView class] elementKind:UICollectionElementKindSectionHeader
                                                                              configurationHandler:^(UICollectionReusableView *headerView, NSString *kind, NSIndexPath *indexPath) {
        headerView.backgroundColor = [UIColor lightGrayColor];
    }];
    view.dataSource = source;
    update_log = [NSMutableArray array];
    [view reloadData];
    [view layoutIfNeeded];
    spin(0.15);
    [view layoutIfNeeded];
    CGSize size = view.collectionViewLayout.collectionViewContentSize;
    CHECK(size.width == 320 && fabs(size.height - (28 + 3 * 44)) < 0.51, "the list is the width of the view and a header and three rows of the estimated height tall");
    for (NSInteger row = 0; row < 3; row++) {
        UICollectionViewCell *cell = [view cellForItemAtIndexPath:[NSIndexPath indexPathForItem:row inSection:0]];
        CHECK([cell isKindOfClass:[CharonListsCell class]], "the registration dequeues its own cell class");
        CGRect frame = cell.frame;
        CHECK(fabs(frame.origin.y - (28 + 44 * row)) < 0.51 && frame.size.width == 320 && fabs(frame.size.height - 44) < 0.51 && frame.origin.x == 0, "each row is a full width row of 44 points below the header");
        NSMutableArray *labels = [NSMutableArray array], *images = [NSMutableArray array];
        [self collect:cell.contentView root:cell labels:labels images:images];
        UILabel *label = nil;
        for (UIView *sub in [cell.contentView.subviews.firstObject subviews])
            if ([sub isKindOfClass:[UILabel class]])
                label = (UILabel *)sub;
        CHECK((labels.count == 1 && [label.text isEqual:[NSString stringWithFormat:@"Row %ld", (long)row]]), "the row shows the text the handler gave");
    }
    UICollectionViewListCell *first = (UICollectionViewListCell *)[view cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    CHECK([first.contentView.subviews.firstObject isKindOfClass:[UIListContentView class]] && first.accessories.count == 1, "the content view of the configuration is inside the cell's content view, beside the accessory");
    UIView *disclosure = nil;
    for (UIView *sub in first.subviews)
        if (sub != first.contentView && !sub.hidden && ![NSStringFromClass([sub class]) hasSuffix:@"BackgroundView"] && ![NSStringFromClass([sub class]) hasSuffix:@"RowSeparatorView"])
            disclosure = sub;
    CHECK(disclosure && fabs(disclosure.frame.origin.x - 290) < 0.51 && disclosure.frame.size.width == 14, "the disclosure indicator sits 16 points from the trailing edge, in a list");
    CHECK(fabs(first.contentView.frame.size.width - 290) < 0.51, "and the content stops where it begins");
    UICollectionViewLayoutAttributes *attributes = [view.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader atIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    CHECK(attributes && fabs(attributes.frame.size.height - 28) < 0.51 && attributes.frame.size.width == 320, "the header is 28 points high");
    CHECK(configuration.showsSeparators && [[first.subviews.lastObject class] isSubclassOfClass:[UIView class]], "a list draws its separators by default");

    [update_log removeAllObjects];
    [view selectItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0] animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    spin(0.1);
    [view layoutIfNeeded];
    CharonListsCell *second = (CharonListsCell *)[view cellForItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]];
    CHECK([update_log containsObject:@"needsUpdate"] && [update_log containsObject:@"update h=0 s=1 e=0 d=0"], "selecting a row asks the cell for an update, then hands it the state it is in");
    CHECK([rgb(second.backgroundConfiguration.backgroundColor) isEqual:rgb([UIColor colorWithWhite:220.0 / 255 alpha:1])], "the default background configuration of a selected list cell takes the selected colour");
    [view deselectItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0] animated:NO];
    spin(0.1);
    [view layoutIfNeeded];
    CHECK([rgb(second.backgroundConfiguration.backgroundColor) isEqual:rgb([UIColor whiteColor])], "and gives it back when the row is deselected");

    [update_log removeAllObjects];
    view.editing = YES;
    spin(0.1);
    [view layoutIfNeeded];
    charon_check([update_log containsObject:@"update h=0 s=0 e=1 d=0"], "putting the collection view into editing puts its cells into the editing state",
                 [NSString stringWithFormat:@"editing %d cells %lu superview %@ log %@", view.editing, (unsigned long)view.visibleCells.count, NSStringFromClass([[view.visibleCells.firstObject superview] class]), update_log]);
    view.editing = NO;
    [view removeFromSuperview];
}

- (void)checkStates
{
    UICollectionViewListCell *cell = [[UICollectionViewListCell alloc] initWithFrame:CGRectMake(0, 0, 320, 60)];
    [self.window.rootViewController.view addSubview:cell];
    UIListContentConfiguration *configuration = [UIListContentConfiguration sidebarCellConfiguration];
    configuration.text = @"Sidebar";
    cell.contentConfiguration = configuration;
    UIListContentConfiguration *read = (UIListContentConfiguration *)cell.contentConfiguration;
    CHECK(read != configuration && [read isEqual:configuration], "the configuration a cell reports is a copy of the one it was given");
    cell.highlighted = YES;
    [cell layoutIfNeeded];
    spin(0.05);
    UIListContentConfiguration *updated = (UIListContentConfiguration *)cell.contentConfiguration;
    CHECK(![updated isEqual:configuration], "a sidebar configuration is updated for the highlighted state");
    cell.automaticallyUpdatesContentConfiguration = NO;
    cell.selected = NO;
    spin(0.05);
    [cell layoutIfNeeded];
    CHECK([cell.contentConfiguration isEqual:updated], "with automatic updates off the cell keeps the configuration it has");
    cell.contentConfiguration = nil;
    CHECK(cell.contentConfiguration == nil, "a nil configuration is nil");
    UIBackgroundConfiguration *background = [UIBackgroundConfiguration listGroupedCellConfiguration];
    background.backgroundInsets = NSDirectionalEdgeInsetsMake(3, 4, 5, 6);
    cell.backgroundConfiguration = background;
    [cell layoutIfNeeded];
    UIView *drawn = nil;
    for (UIView *sub in cell.subviews)
        if ([NSStringFromClass([sub class]) hasSuffix:@"BackgroundView"])
            drawn = sub;
    CHECK(drawn && CGRectEqualToRect(drawn.frame, CGRectMake(4, 3, 310, 52)), "a background configuration is drawn behind the content, inside its insets");
    UICellConfigurationState *state = cell.configurationState;
    CHECK([state isKindOfClass:[UICellConfigurationState class]] && !state.selected && !state.disabled, "the configuration state reports the cell's flags");
    cell.userInteractionEnabled = NO;
    CHECK(cell.configurationState.disabled, "a cell that takes no touches is disabled");
    [cell removeFromSuperview];

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 300) style:UITableViewStylePlain];
    [self.window.rootViewController.view addSubview:table];
    UITableViewCell *subtitle = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *tableConfiguration = [subtitle defaultContentConfiguration];
    CHECK(tableConfiguration.textToSecondaryTextVerticalPadding == 0 && !tableConfiguration.prefersSideBySideTextAndSecondaryText, "a subtitle table cell starts from the subtitle configuration");
    UITableViewCell *value = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    CHECK([value defaultContentConfiguration].prefersSideBySideTextAndSecondaryText, "a value table cell starts from the value configuration");
    tableConfiguration.text = @"Row";
    subtitle.contentConfiguration = tableConfiguration;
    [table addSubview:subtitle];
    subtitle.frame = CGRectMake(0, 0, 320, 60);
    [subtitle layoutIfNeeded];
    CHECK(subtitle.textLabel == nil && [subtitle.contentView.subviews.firstObject isKindOfClass:[UIListContentView class]], "a table cell with a content configuration has no text label, and shows the configuration");
    UITableViewHeaderFooterView *header = [[UITableViewHeaderFooterView alloc] initWithReuseIdentifier:@"h"];
    CHECK([header defaultContentConfiguration].directionalLayoutMargins.leading == 8 && ![header.configurationState isKindOfClass:[UICellConfigurationState class]], "a header view has a header configuration and a plain view state");
    table.delegate = nil;
    [table removeFromSuperview];
}

- (void)checkHonesty
{
    CHECK(![UIViewConfigurationState instancesRespondToSelector:NSSelectorFromString(@"isPinned")], "the pinned state of iOS 15 is absent");
    CHECK(![UICollectionViewCell instancesRespondToSelector:NSSelectorFromString(@"configurationUpdateHandler")] && ![UITableViewCell instancesRespondToSelector:NSSelectorFromString(@"configurationUpdateHandler")],
          "the update handler of iOS 15 is absent");
    CHECK(![UICollectionViewCell instancesRespondToSelector:NSSelectorFromString(@"defaultBackgroundConfiguration")], "the default background configuration of iOS 16 is absent");
    CHECK(![UIBackgroundConfiguration instancesRespondToSelector:NSSelectorFromString(@"image")] && ![UICollectionLayoutListConfiguration instancesRespondToSelector:NSSelectorFromString(@"headerTopPadding")],
          "the image of a background and the header padding of a list, both iOS 15, are absent");
    CHECK(![UICollectionLayoutListConfiguration instancesRespondToSelector:NSSelectorFromString(@"separatorConfiguration")], "the separator configuration of iOS 14.5 is absent");
    CHECK(![UIListContentTextProperties instancesRespondToSelector:NSSelectorFromString(@"showsExpansionTextWhenTruncated")], "the expansion text property is absent");
    CHECK(![UICollectionView instancesRespondToSelector:NSSelectorFromString(@"selectionFollowsFocus")], "selection that follows focus is absent");
    CHECK(![UICollectionViewCell instancesRespondToSelector:NSSelectorFromString(@"defaultContentConfiguration")] && [UICollectionViewListCell instancesRespondToSelector:NSSelectorFromString(@"defaultContentConfiguration")],
          "only the list cell has a default content configuration");
    CHECK([UICollectionView instancesRespondToSelector:NSSelectorFromString(@"setEditing:")] && [UICollectionView instancesRespondToSelector:NSSelectorFromString(@"allowsMultipleSelectionDuringEditing")], "the editing state of a collection view is there");
    UICollectionLayoutListConfiguration *configuration = [[UICollectionLayoutListConfiguration alloc] initWithAppearance:UICollectionLayoutListAppearanceInsetGrouped];
    configuration.leadingSwipeActionsConfigurationProvider = ^UISwipeActionsConfiguration *(NSIndexPath *indexPath) { return nil; };
    CHECK(configuration.leadingSwipeActionsConfigurationProvider != nil && ![UICollectionLayoutListConfiguration instancesRespondToSelector:NSSelectorFromString(@"itemSeparatorHandler")], "a swipe actions provider is kept and never asked");
    BOOL raised = NO;
    @try {
        (void)[[UICellAccessoryLabel alloc] initWithText:nil];
    } @catch (NSException *exception) {
        raised = [exception.name isEqual:NSInternalInconsistencyException] && [exception.reason isEqual:@"Invalid parameter not satisfying: text != nil"];
    }
    CHECK(raised, "a label accessory with no text raises as the system's does");
    UICollectionViewListCell *cell = [[UICollectionViewListCell alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    raised = NO;
    @try {
        cell.accessories = @[[[UICellAccessoryCheckmark alloc] init], [[UICellAccessoryCheckmark alloc] init]];
    } @catch (NSException *exception) {
        raised = [exception.name isEqual:NSInternalInconsistencyException] && [exception.reason hasPrefix:@"Accessories array contains more than one system accessory of the same type."];
    }
    CHECK(raised, "two accessories of one system type are refused");
    NSArray *accessories = @[[[UICellAccessoryLabel alloc] initWithText:@"a"], [[UICellAccessoryCheckmark alloc] init]];
    CHECK(UICellAccessoryPositionBeforeAccessoryOfClass([UICellAccessoryCheckmark class])(accessories) == 1 && UICellAccessoryPositionAfterAccessoryOfClass([UICellAccessoryLabel class])(accessories) == 1 &&
              UICellAccessoryPositionAfterAccessoryOfClass([UICellAccessoryDelete class])(accessories) == 2 && UICellAccessoryPositionBeforeAccessoryOfClass([UICellAccessoryDelete class])(accessories) == 0,
          "the position blocks answer where an accessory would go");
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        [[NSFileManager defaultManager] createDirectoryAtPath:results_folder withIntermediateDirectories:YES attributes:nil error:NULL];
        return UIApplicationMain(argc, argv, nil, @"CharonListsDelegate");
    }
}
