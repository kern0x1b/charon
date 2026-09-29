#import "uirest.h"
#import <objc/message.h>
#import <dlfcn.h>

// A control made of actions, on whichever side this binary is.
//
// The port's -insertSegmentWithAction:atIndex:animated: is a carried selector on a host class, so the harness
// renames it and the port's side answers -charonHostInsertSegmentWithAction:atIndex:animated:. Calling the
// public one on the port's side would reach the **host's own** method, and a host method handing a port action
// to the host's label machinery is a mix no device ever has: on 6.x there is no host method of that name at
// all, so the port's own is what runs there. The recorder has no prefixed method and takes the public one,
// which is the host's own - the right answer on that side.
// Whether the class has a method of that name, asked through the class's method list and **not** through
// -respondsToSelector:. NSSelectorFromString on a name that exists nowhere produces a selector that is
// registered by no class and no category, and the runtime's optimised -respondsToSelector: traps on one - which
// is the `brk #0xc472` an lldb run of the recorder stopped in, with a one-frame backtrace because the trap is
// inside a tail call from the host's own -setAction:forSegmentAtIndex:. So the test asks the method list.
static BOOL charon_has_method(Class cls, const char *name)
{
    if (!cls)
        return NO;
    // `sel_registerName` first, and that is the whole of it: NSSelectorFromString on a name nobody registers
    // produces an **unregistered** selector, and the runtime's optimised -respondsToSelector: traps on one -
    // the recorder's exit 133, whose crash report put the trap under
    // _NSDescriptionWithStringProxyFunc and the frame in this file's own block. Registering is a no-op for a
    // name that is already registered, and it makes the question safe to ask for one that is not.
    SEL selector = sel_registerName(name);
    for (Class c = cls; c; c = class_getSuperclass(c))
        if (class_getInstanceMethod(c, selector))
            return YES;
    return NO;
}

static void charon_insert_action(UISegmentedControl *control, UIAction *action, NSUInteger index)
{
    const char *renamed = "charonHostInsertSegmentWithAction:atIndex:animated:";
    const char *published = "insertSegmentWithAction:atIndex:animated:";
    SEL chosen = NSSelectorFromString(@(charon_has_method([control class], renamed) ? renamed : published));
    ((void (*)(id, SEL, UIAction *, NSUInteger, BOOL))objc_msgSend)(control, chosen, action, index, NO);
}

static UISegmentedControl *charon_control_with_actions(CGRect frame, NSArray *actions)
{
    // The port publishes its own implementation as a name of its own, and this is what a differential calls: the
    // public initialiser is the **host's** on the port's side, because the port's is a carried selector the
    // harness renamed, and a host initialiser given a port action builds a segment from the action and hands it
    // to the host's label - a mix of classes that never happens on a device. The recorder has no such symbol and
    // takes the public initialiser, which is the host's own and the right answer on that side.
    typedef UISegmentedControl *(*CharonControlWithActions)(UISegmentedControl *, CGRect, NSArray *);
    static CharonControlWithActions entry = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        entry = (CharonControlWithActions)dlsym(dlopen(NULL, RTLD_NOW), "charon_control_init_with_actions");
    });
    if (entry)
        return entry([UISegmentedControl alloc], frame, actions);
    SEL published = NSSelectorFromString(@"initWithFrame:actions:");
    return ((id (*)(id, SEL, CGRect, NSArray *))objc_msgSend)([UISegmentedControl alloc], published, frame, actions);
}

static NSString *charon_insert_action_name(UISegmentedControl *control)
{
    return charon_has_method([control class], "charonHostInsertSegmentWithAction:atIndex:animated:") ? @"the port's own"
                                                                                                   : @"the host's own";
}

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
    UISegmentedControl *sg = charon_control_with_actions(CGRectMake(0, 0, 200, 30), @[ a, b1 ]);
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
    // The two action classes side by side in one window. `UIAction` is the host's own on both sides of a
    // differential - the port's is renamed to CharonHostUIAction - so the first pair is the same class in both
    // binaries and the second is the one this binary carries, and the host's comes first so that a side which
    // cannot take the second one has printed the first one's answer before it stops. Which of the two the
    // segment takes is the whole of the difference the -[CharonHostUIAction length] fault turns on.
    for (NSArray *pair in @[ @[ @"the host's", NSClassFromString(@"UIAction") ], @[ @"this binary's", actionClass ] ]) {
        UIAction *one = [pair[1] actionWithTitle:@"AT" image:nil
                                       identifier:[NSString stringWithFormat:@"id-%@", pair[0]]
                                          handler:^(id x) {}];
        UISegmentedControl *own = [[UISegmentedControl alloc] initWithItems:@[ @"seed" ]];
        NSString *outcome = ur_raised(^id {
            charon_insert_action(own, one, 0);
            return [NSString stringWithFormat:@"via=%@ segments=%ld title=%@ back=%@", charon_insert_action_name(own),
                                              (long)own.numberOfSegments, [own titleForSegmentAtIndex:0] ?: @"nil",
                                              [own actionForSegmentAtIndex:0].title ?: @"nil"];
        });
        [lines addObject:ur_line([@"an action from " stringByAppendingString:pair[0]], @[outcome])];
    }
    NSMutableArray *flat = [NSMutableArray array];
    for (NSString *entry in lines)
        [flat addObject:[entry stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    return flat;
}
