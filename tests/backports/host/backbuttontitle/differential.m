#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "check.h"

static BOOL ours;

static SEL named(NSString *selector)
{
    if (!ours)
        return NSSelectorFromString(selector);
    if ([selector hasPrefix:@"set"])
        return NSSelectorFromString([@"setCharonHost" stringByAppendingString:[selector substringFromIndex:3]]);
    return NSSelectorFromString([@"charonHost" stringByAppendingFormat:@"%@%@",
                                 [[selector substringToIndex:1] uppercaseString], [selector substringFromIndex:1]]);
}

static NSString *title_of(UINavigationItem *item)
{
    return ((id (*)(id, SEL))objc_msgSend)(item, named(@"backButtonTitle"));
}

static void set_title(UINavigationItem *item, NSString *title)
{
    ((void (*)(id, SEL, id))objc_msgSend)(item, named(@"setBackButtonTitle:"), title);
}

static UIBarButtonItem *plain(NSString *title)
{
    return [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStylePlain target:nil action:NULL];
}

static void record(NSMutableArray *into, const char *step, NSString *value)
{
    [into addObject:@[@(step), value ?: @"nothing"]];
}

static void script(NSMutableArray *into)
{
    UINavigationItem *fresh = [[UINavigationItem alloc] initWithTitle:@"Root"];
    record(into, "a fresh item has no back button title", title_of(fresh));

    UINavigationItem *titled = [[UINavigationItem alloc] initWithTitle:@"Root"];
    set_title(titled, @"Up");
    record(into, "the title it was given", title_of(titled));

    UINavigationItem *itemed = [[UINavigationItem alloc] initWithTitle:@"Root"];
    itemed.backBarButtonItem = plain(@"Item");
    record(into, "an item of its own is not a title", title_of(itemed));

    UINavigationItem *both = [[UINavigationItem alloc] initWithTitle:@"Root"];
    set_title(both, @"First");
    both.backBarButtonItem = plain(@"Second");
    record(into, "a title set before an item stays", title_of(both));
    record(into, "and the item stays too", both.backBarButtonItem.title);

    UINavigationItem *other = [[UINavigationItem alloc] initWithTitle:@"Root"];
    other.backBarButtonItem = plain(@"Second");
    set_title(other, @"First");
    record(into, "a title set after an item stays", title_of(other));
    record(into, "and the item the application set is left alone", other.backBarButtonItem.title);

    UINavigationItem *cleared = [[UINavigationItem alloc] initWithTitle:@"Root"];
    set_title(cleared, @"Gone");
    set_title(cleared, nil);
    record(into, "a title set to nil is gone", title_of(cleared));

    NSMutableString *mutable = [NSMutableString stringWithString:@"Mut"];
    UINavigationItem *copied = [[UINavigationItem alloc] initWithTitle:@"Root"];
    set_title(copied, mutable);
    [mutable appendString:@"ated"];
    record(into, "the title is copied on the way in", title_of(copied));

    UINavigationItem *twice = [[UINavigationItem alloc] initWithTitle:@"Root"];
    set_title(twice, @"One");
    set_title(twice, @"Two");
    record(into, "the last title wins", title_of(twice));
}

int main(void)
{
    @autoreleasepool {
        NSMutableArray *system = [NSMutableArray array], *port = [NSMutableArray array];
        ours = NO;
        script(system);
        ours = YES;
        BOOL carried = [UINavigationItem instancesRespondToSelector:named(@"backButtonTitle")];
        CHECK(carried, "the port carries the back button title of a navigation item");
        if (carried)
            script(port);
        for (NSUInteger index = 0; index < system.count; index++) {
            NSArray *mine = index < port.count ? port[index] : nil;
            NSString *expected = system[index][1], *actual = mine ? mine[1] : @"nothing";
            printf("  %s: %s\n", [system[index][0] UTF8String], expected.UTF8String);
            charon_check([expected isEqual:actual], [system[index][0] UTF8String],
                         [NSString stringWithFormat:@"%@ != %@", actual, expected]);
        }
        if (carried) {
            UINavigationItem *shown = [[UINavigationItem alloc] initWithTitle:@"Root"];
            set_title(shown, @"Shown");
            CHECK([shown.backBarButtonItem.title isEqual:@"Shown"],
                  "the port puts the title where this release draws the back button from");
            UINavigationItem *kept = [[UINavigationItem alloc] initWithTitle:@"Root"];
            kept.backBarButtonItem = plain(@"Mine");
            set_title(kept, @"Ignored");
            CHECK([kept.backBarButtonItem.title isEqual:@"Mine"],
                  "and leaves an item the application set alone, which is the order UIKit resolves in");
            UINavigationItem *undone = [[UINavigationItem alloc] initWithTitle:@"Root"];
            set_title(undone, @"Gone");
            set_title(undone, nil);
            CHECK(undone.backBarButtonItem == nil, "and takes its own item away again with the title");
        }
    }
    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    return charon_failures;
}
