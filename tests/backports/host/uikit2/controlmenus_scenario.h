#import "uirest.h"

@interface MenuTarget : NSObject
@end

@implementation MenuTarget
@end

static NSString *bar_line(UIBarButtonItem *item)
{
    return [NSString stringWithFormat:@"title=%@ image=%d menu=%d pa=%d width=%g style=%ld system=%@", item.title ?: @"nil", item.image != nil, item.menu != nil, item.primaryAction != nil, item.width, (long)item.style, @""];
}

static NSArray *menu_scenario(Class actionClass, Class menuClass)
{
    NSMutableArray *lines = [NSMutableArray array];
    UIImage *image = [[UIImage alloc] init];
    __block int fired = 0;
    UIAction *a = [actionClass actionWithTitle:@"AT" image:image identifier:@"idx" handler:^(id x) { fired++; }];
    UIMenu *m = [menuClass menuWithTitle:@"M" children:@[a]];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [lines addObject:ur_line(@"button", @[b.menu ?: @"nil", ur_yes(b.showsMenuAsPrimaryAction), ur_yes(b.contextMenuInteractionEnabled), @(b.role)])];
    b.menu = m;
    [lines addObject:ur_line(@"menu set", @[ur_yes([b.menu isEqual:m]), ur_yes(b.menu != m), ur_yes(b.showsMenuAsPrimaryAction), ur_yes(b.contextMenuInteractionEnabled), ur_yes(b.contextMenuInteraction != nil)])];
    b.showsMenuAsPrimaryAction = YES;
    [lines addObject:ur_line(@"primary", @[ur_yes(b.showsMenuAsPrimaryAction), ur_yes(b.contextMenuInteractionEnabled)])];
    b.menu = nil;
    [lines addObject:ur_line(@"menu nil", @[ur_yes(b.contextMenuInteractionEnabled), ur_yes(b.showsMenuAsPrimaryAction), b.menu ?: @"nil"])];
    UIButton *c = [UIButton buttonWithType:UIButtonTypeCustom];
    c.contextMenuInteractionEnabled = YES;
    [lines addObject:ur_line(@"enabled", @[ur_yes(c.contextMenuInteractionEnabled), ur_yes(c.contextMenuInteraction != nil), ur_yes(c.contextMenuInteraction.delegate == c)])];
    UIContextMenuConfiguration *cf = [c contextMenuInteraction:c.contextMenuInteraction configurationForMenuAtLocation:CGPointZero];
    [lines addObject:ur_line(@"configuration without a menu", @[ur_yes(cf != nil), cf.identifier ? @"identifier" : @"nil"])];
    c.menu = m;
    cf = [c contextMenuInteraction:c.contextMenuInteraction configurationForMenuAtLocation:CGPointZero];
    [lines addObject:ur_line(@"configuration with a menu", @[ur_yes(cf != nil)])];
    [lines addObject:ur_line(@"previews", @[[c contextMenuInteraction:nil previewForHighlightingMenuWithConfiguration:cf] ?: @"nil", [c contextMenuInteraction:nil previewForDismissingMenuWithConfiguration:cf] ?: @"nil"])];
    [lines addObject:ur_line(@"answers", @[ur_yes([c respondsToSelector:@selector(contextMenuInteraction:willDisplayMenuForConfiguration:animator:)]), ur_yes([c respondsToSelector:@selector(contextMenuInteraction:willEndForConfiguration:animator:)]),
                                           ur_yes([c respondsToSelector:@selector(contextMenuInteraction:willPerformPreviewActionForMenuWithConfiguration:animator:)]), ur_yes([c respondsToSelector:@selector(contextMenuInteraction:previewForHighlightingMenuWithConfiguration:)])])];
    b.role = UIButtonRoleDestructive;
    [lines addObject:ur_line(@"role", @(b.role))];

    UIButton *d2 = [UIButton buttonWithType:UIButtonTypeSystem primaryAction:a];
    [lines addObject:ur_line(@"button with type and action", @[[d2 titleForState:UIControlStateNormal] ?: @"nil", ur_yes([d2 imageForState:UIControlStateNormal] != nil), @(d2.buttonType)])];
    UIButton *d3 = [UIButton systemButtonWithPrimaryAction:a];
    [lines addObject:ur_line(@"system button", @[@(d3.buttonType), [d3 titleForState:UIControlStateNormal] ?: @"nil"])];
    UIButton *d4 = [UIButton systemButtonWithImage:image target:nil action:NULL];
    [lines addObject:ur_line(@"system button with image", @[@(d4.buttonType), ur_yes([d4 imageForState:UIControlStateNormal] != nil)])];
    UIButton *d5 = [UIButton buttonWithType:UIButtonTypeCustom primaryAction:nil];
    [lines addObject:ur_line(@"button with no action", @[@(d5.buttonType), [d5 titleForState:UIControlStateNormal] ?: @"nil"])];

    UIBarButtonItem *i1 = [[UIBarButtonItem alloc] initWithPrimaryAction:a];
    [lines addObject:ur_line(@"item with an action", @[bar_line(i1), ur_yes(i1.primaryAction != a), ur_yes([i1.primaryAction isEqual:a])])];
    UIBarButtonItem *i2 = [[UIBarButtonItem alloc] initWithTitle:@"T" menu:m];
    [lines addObject:ur_line(@"item with a menu", @[bar_line(i2), ur_yes([i2.menu isEqual:m])])];
    UIBarButtonItem *i3 = [[UIBarButtonItem alloc] initWithImage:image menu:m];
    [lines addObject:ur_line(@"item with an image and a menu", @[bar_line(i3)])];
    UIBarButtonItem *i4 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd menu:m];
    [lines addObject:ur_line(@"item with a system item and a menu", @[ur_yes(i4.menu != nil), ur_yes(i4.primaryAction == nil)])];
    UIBarButtonItem *i5 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd primaryAction:a];
    [lines addObject:ur_line(@"item with a system item and an action", @[ur_yes(i5.primaryAction != nil), i5.title ?: @"nil", ur_yes(i5.image != nil)])];
    i2.menu = nil;
    [lines addObject:ur_line(@"item without a menu", i2.menu ?: @"nil")];
    i2.primaryAction = a;
    [lines addObject:ur_line(@"item given an action", @[i2.title ?: @"nil", ur_yes(i2.image != nil)])];
    i2.primaryAction = nil;
    [lines addObject:ur_line(@"item without an action", @[i2.title ?: @"nil", ur_yes(i2.image != nil), i2.primaryAction ?: @"nil"])];
    i1.title = @"changed";
    [lines addObject:ur_line(@"item title changed", @[i1.title, i1.primaryAction.title])];
    [lines addObject:ur_line(@"item with nil", ur_raised(^id { return [[UIBarButtonItem alloc] initWithPrimaryAction:nil]; }))];
    UIBarButtonItem *fixed = [UIBarButtonItem fixedSpaceItemOfWidth:10], *flexible = [UIBarButtonItem flexibleSpaceItem];
    [lines addObject:ur_line(@"spaces", @[@(fixed.width), fixed.menu ?: @"nil", flexible.primaryAction ?: @"nil", ur_yes(fixed != flexible)])];

    UIAction *b1 = [actionClass actionWithTitle:@"B" image:nil identifier:@"idy" handler:^(id x) {}];
    UISegmentedControl *sg = [[UISegmentedControl alloc] initWithFrame:CGRectMake(0, 0, 200, 30) actions:@[a, b1]];
    [lines addObject:ur_line(@"segments", @[@(sg.numberOfSegments), @(sg.selectedSegmentIndex), [sg titleForSegmentAtIndex:0] ?: @"nil", [sg titleForSegmentAtIndex:1] ?: @"nil", ur_yes([sg imageForSegmentAtIndex:0] != nil),
                                           ur_yes([sg actionForSegmentAtIndex:0] != a), ur_yes([[sg actionForSegmentAtIndex:0] isEqual:a]), @([sg segmentIndexForActionIdentifier:@"idy"]), @([sg segmentIndexForActionIdentifier:@"nope"])])];
    UIAction *cc = [actionClass actionWithTitle:@"C" image:nil identifier:@"idz" handler:^(id x) {}];
    [sg insertSegmentWithAction:cc atIndex:1 animated:NO];
    [lines addObject:ur_line(@"inserted", @[@(sg.numberOfSegments), [sg titleForSegmentAtIndex:1], @([sg segmentIndexForActionIdentifier:@"idz"]), @([sg segmentIndexForActionIdentifier:@"idy"])])];
    [lines addObject:ur_line(@"set a taken identifier", ur_raised(^id { [sg setAction:a forSegmentAtIndex:1]; return @"no"; }))];
    UIAction *n9 = [actionClass actionWithTitle:@"N9" image:nil identifier:@"id9" handler:^(id x) {}];
    [sg setAction:n9 forSegmentAtIndex:1];
    [lines addObject:ur_line(@"set an action", @[[sg titleForSegmentAtIndex:1], ur_yes([sg imageForSegmentAtIndex:1] != nil)])];
    [sg insertSegmentWithTitle:@"plain" atIndex:0 animated:NO];
    [lines addObject:ur_line(@"a plain segment", @[[sg actionForSegmentAtIndex:0] ?: @"nil", @([sg segmentIndexForActionIdentifier:@"idx"]), @([sg segmentIndexForActionIdentifier:@"id9"])])];
    [sg removeSegmentAtIndex:0 animated:NO];
    [lines addObject:ur_line(@"segment removed", @[@([sg segmentIndexForActionIdentifier:@"idx"]), @([sg segmentIndexForActionIdentifier:@"id9"])])];
    [lines addObject:ur_line(@"no action", @[[sg actionForSegmentAtIndex:9] ?: @"nil", [[[UISegmentedControl alloc] initWithItems:@[@"q"]] actionForSegmentAtIndex:0] ?: @"nil"])];
    [lines addObject:ur_line(@"unique on insert", ur_raised(^id { [sg insertSegmentWithAction:cc atIndex:0 animated:NO]; return @"no"; }))];
    NSMutableArray *flat = [NSMutableArray array];
    for (NSString *entry in lines)
        [flat addObject:[entry stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    return flat;
}
