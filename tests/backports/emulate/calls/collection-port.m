//
//  collection-port.m
//  The resolution results' collection factories, run on the port.
//
//  The same table the host run prints, read out of **this** process: on the device there is no
//  Intents.framework of the system's own, so the classes looked up by name are libIntentsBackports'
//  and nothing has to be renamed. What the port must answer is the host's measured answer:
//
//      two items  -> count 2, one result per item, each the class asked
//      one item   -> count 1
//      empty      -> count 0, an array
//      nil        -> count 0, an array
//
//  and the same program is built a second time against a **mutant** of the generated factory - one
//  that returns an element fewer - so the table is shown going red on the device and not argued
//  about. The mutant is a source swap in the tree, restored afterwards and checked with git status.
//

#import <Foundation/Foundation.h>
#import <Intents/Intents.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSArray *items(void)
{
    Class item = NSClassFromString(@"INMediaItem");
    if (!item) {
        return nil;
    }
    SEL build = NSSelectorFromString(@"initWithIdentifier:title:type:artwork:artist:");
    if (![item instancesRespondToSelector:build]) {
        return nil;
    }
    id one = [[item alloc] initWithIdentifier:@"one" title:@"One" type:0 artwork:nil artist:nil];
    id two = [[item alloc] initWithIdentifier:@"two" title:@"Two" type:0 artwork:nil artist:nil];
    return @[one, two];
}

static void probe(NSString *name, NSArray *input)
{
    Class cls = NSClassFromString(name);
    if (!cls) {
        printf("  %-42s not in this build\n", [name UTF8String]);
        return;
    }
    SEL factory = NSSelectorFromString(@"successesWithResolvedMediaItems:");
    if (![cls respondsToSelector:factory]) {
        printf("  %-42s has no successesWithResolvedMediaItems:\n", [name UTF8String]);
        return;
    }
    id results = ((id (*)(id, SEL, id))objc_msgSend)(cls, factory, input);
    printf("  %-42s count=%lu %s\n", [name UTF8String], (unsigned long)[results count],
           input ? "" : "(nil input)");
    for (id element in results) {
        id value = [element valueForKey:@"resolvedValue"];
        printf("      element %-38s resolvedValue %s\n", class_getName([element class]),
               value ? [[value description] UTF8String] : "(nil)");
    }
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        const char *title = argc > 1 ? argv[1] : "the port's own body";
        NSArray *both = items();
        if (!both) {
            printf("%s: this build has no INMediaItem to hand the factories\n", title);
            return 2;
        }
        const char *classes[] = {"INMediaItemResolutionResult", "INPlayMediaMediaItemResolutionResult",
                                 "INAddMediaMediaItemResolutionResult",
                                 "INSearchForMediaMediaItemResolutionResult",
                                 "INUpdateMediaAffinityMediaItemResolutionResult"};
        printf("%s:\n", title);
        for (unsigned index = 0; index < sizeof(classes) / sizeof(*classes); index++) {
            probe([NSString stringWithUTF8String:classes[index]], @[both[0], both[1]]);
        }
        // And the three other inputs on the base class, which is where the empty and nil answers
        // are the interesting ones: a caller counts what it is given, so nil must be an array.
        NSString *base = @"INMediaItemResolutionResult";
        probe(base, @[both[0]]);
        probe(base, @[]);
        probe(base, nil);
        return 0;
    }
}
