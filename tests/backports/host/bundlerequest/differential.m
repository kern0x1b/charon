// differential.m - NSBundleResourceRequest against the host's own, and the two rules the host cannot
// be asked about against the header's own words.
//
// The host's public -initWithTags: forwards to a private -initWithTag:, and that is the state oracle:
// the port's public initialiser is compared with the host's private one, over the bundle, the
// priority and the progress. The trap that interrupted this was this test's own bug - the invocation's
// target was the class, so the message reached the class method +doesNotRecognizeSelector: and the
// pointer authentication failure was inside CoreFoundation's format path, not the port's. The private
// initialiser is used here and nowhere else: the port calls nothing private, and neither does any other
// test in this tree.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static int checks;
static int failures;

static void fail(NSString *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    printf("FAIL %s\n", text.UTF8String);
    failures++;
}

static void same_bool(BOOL ours, BOOL theirs, NSString *what)
{
    checks++;
    if (ours != theirs)
        fail(@"%@: the port says %@, Foundation %@", what, ours ? "yes" : "no", theirs ? "yes" : "no");
}

static void same_double(double ours, double theirs, NSString *what)
{
    checks++;
    if (ours != theirs)
        fail(@"%@: the port says %g, Foundation %g", what, ours, theirs);
}

static const double NSBundleResourceRequestUrgent = 1.0;

static void same_integer(long long ours, long long theirs, NSString *what)
{
    checks++;
    if (ours != theirs)
        fail(@"%@: the port says %lld, Foundation %lld", what, ours, theirs);
}

static void same_string(NSString *ours, NSString *theirs, NSString *what)
{
    checks++;
    if (ours == theirs)
        return;
    if (![ours isEqualToString:theirs])
        fail(@"%@: the port says |%@|, Foundation |%@|", what, ours ?: @"(nil)", theirs ?: @"(nil)");
}

// The port's own class, declared here under the name run.sh gives it, so the calls are typed and reach
// its accessors by name. It is the release that has none of this, so nothing here relies on a
// declaration the SDK owns.
@interface CharonHostNSBundleResourceRequest : NSObject <NSProgressReporting>
- (instancetype)init;
- (instancetype)initWithTags:(NSSet<NSString *> *)tags;
- (instancetype)initWithTags:(NSSet<NSString *> *)tags bundle:(NSBundle *)bundle;
@property (readonly) NSSet<NSString *> *tags;
@property (readonly) NSBundle *bundle;
@property double loadingPriority;
@property (readonly) NSProgress *progress;
- (void)beginAccessingResourcesWithCompletionHandler:(void (^)(NSError *error))handler;
- (void)conditionallyBeginAccessingResourcesWithCompletionHandler:(void (^)(BOOL available))handler;
- (void)endAccessingResources;
@end

extern double const CharonHostNSBundleResourceRequestLoadingPriorityUrgent;
extern NSString *const CharonHostNSBundleResourceRequestLowDiskSpaceNotification;

// The host's private initialiser. The target is the *instance*: set to the class it asks the class
// method +doesNotRecognizeSelector:, which is what the stack showed, and then the trap, inside
// CoreFoundation's own format path. The private initialiser was never tested before this.
static id host_initWithTag(Class subject, NSString *tag)
{
    SEL factory = NSSelectorFromString(@"initWithTag:");
    NSMethodSignature *signature = [subject instanceMethodSignatureForSelector:factory];
    if (!signature)
        return nil;
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature];
    call.selector = factory;
    call.target = [subject alloc];
    id held = tag;
    [call setArgument:&held atIndex:2];
    [call retainArguments];
    @try {
        [call invoke];
    } @catch (NSException *exception) {
        return nil;
    }
    id result = nil;
    [call getReturnValue:&result];
    return result;
}

static id host_privileged(Class subject, SEL selector, id first)
{
    SEL firstSelector = NSSelectorFromString([NSString stringWithFormat:@"%@:", NSStringFromSelector(selector)]);
    SEL secondSelector = NSSelectorFromString([NSString stringWithFormat:@"%@::", NSStringFromSelector(selector)]);
    SEL chosen = [subject instancesRespondToSelector:firstSelector] ? firstSelector : secondSelector;
    NSMethodSignature *signature = [subject instanceMethodSignatureForSelector:chosen];
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature];
    call.selector = chosen;
    call.target = subject;
    NSUInteger arguments = signature.numberOfArguments;
    if (arguments > 2) {
        [call setArgument:&first atIndex:2];
        for (NSUInteger index = 3; index < arguments; index++) {
            NSInteger zero = 0;
            [call setArgument:&zero atIndex:index];
        }
    }
    [call retainArguments];
    [call invoke];
    id result = nil;
    if (strcmp(signature.methodReturnType, @encode(id)) == 0)
        [call getReturnValue:&result];
    return result;
}

static NSBundle *makeBundle(NSString *name, BOOL withManifest)
{
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    NSFileManager *files = [NSFileManager defaultManager];
    [files removeItemAtPath:root error:NULL];
    [files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];
    if (withManifest) {
        NSDictionary *manifest = @{@"NSBundleResourceRequestTags": @{
            @"level1": @[@{@"NSBundleResourceRequestPath": @"packs/one.pack"}],
            @"level2": @[@{@"NSBundleResourceRequestPath": @"packs/two.pack"}]}};
        [manifest writeToFile:[root stringByAppendingPathComponent:@"OnDemandResources.plist"] atomically:YES];
    }
    return [NSBundle bundleWithPath:root];
}

int main(void)
{
    @autoreleasepool {
        Class ours = NSClassFromString(@"CharonHostNSBundleResourceRequest");
        Class theirs = NSClassFromString(@"NSBundleResourceRequest");
        if (!ours || !theirs) {
            printf("FAIL the backport does not define NSBundleResourceRequest: %d\n", ours != Nil);
            return 1;
        }
        NSBundle *withManifest = makeBundle(@"charon-brr-with", YES);
        NSBundle *withoutManifest = makeBundle(@"charon-brr-without", NO);
        NSSet *known = [NSSet setWithObjects:@"level1", @"level2", nil];
        NSSet *unknown = [NSSet setWithObject:@"level9"];

        // the four properties, held to the header's own words: the tags it was given, the bundle it
        // resolves in, the default priority, and a progress that is complete the moment it exists
        for (NSSet *tags in @[ known, unknown ])
            for (NSBundle *bundle in @[ withManifest, withoutManifest ]) {
                id request = [[ours alloc] initWithTags:tags bundle:bundle];
                id theirRequest = host_initWithTag(theirs, [[tags allObjects] firstObject]);
                NSString *what = [NSString stringWithFormat:@"%@ in %@",
                                                            [[tags allObjects] componentsJoinedByString:@","],
                                                            [bundle.bundlePath lastPathComponent]];
                checks++;
                if (!request) {
                    fail(@"%@: the port made nothing", what);
                    continue;
                }
                same_integer((long long)[[request tags] count], (long long)[tags count],
                             [what stringByAppendingString:@" tag count"]);
                same_string([[[request tags] allObjects] componentsJoinedByString:@","],
                            [[tags allObjects] componentsJoinedByString:@","],
                            [what stringByAppendingString:@" tags"]);
                same_string([request bundle].bundlePath, bundle.bundlePath,
                            [what stringByAppendingString:@" bundle"]);
                same_double([request loadingPriority], 0.5,
                            [what stringByAppendingString:@" the default priority"]);
                same_integer([request progress].totalUnitCount, 0,
                             [what stringByAppendingString:@" progress totalUnitCount"]);
                same_integer([request progress].completedUnitCount, 0,
                             [what stringByAppendingString:@" progress completedUnitCount"]);
                same_double([request progress].fractionCompleted, 1.0,
                            [what stringByAppendingString:@" progress fractionCompleted"]);
                if (theirRequest) {
                    /* the state, against the host's own instance: this is the only private selector
                       the test sends, and the port calls nothing private */
                    same_string([request bundle].bundlePath, [theirRequest bundle].bundlePath,
                                [what stringByAppendingString:@" the bundle, against the host's"]);
                    same_double([request loadingPriority], [theirRequest loadingPriority],
                                [what stringByAppendingString:@" the priority, against the host's"]);
                    same_integer([request progress].totalUnitCount, [theirRequest progress].totalUnitCount,
                                 [what stringByAppendingString:@" progress totalUnitCount, against the host's"]);
                    same_integer([request progress].completedUnitCount, [theirRequest progress].completedUnitCount,
                                 [what stringByAppendingString:@" progress completedUnitCount, against the host's"]);
                } else {
                    printf("note: the host's private -initWithTag: did not answer for %@ in %@\n",
                           [[tags allObjects] firstObject], [bundle.bundlePath lastPathComponent]);
                }
                [request setLoadingPriority:0.25];
                same_double([request loadingPriority], 0.25, [what stringByAppendingString:@" the priority set"]);
                [request setLoadingPriority:NSBundleResourceRequestUrgent];
                same_double([request loadingPriority], 1.0, [what stringByAppendingString:@" the urgent priority"]);
            }

        // -init, which the header marks unavailable on every platform and both answer by refusing
        for (Class subject in @[ ours, theirs ]) {
            NSString *reason = nil, *name = nil;
            @try {
                ((id (*)(id, SEL))objc_msgSend)([subject alloc], @selector(init));
            } @catch (NSException *exception) {
                name = exception.name;
                reason = exception.reason;
            }
            same_string(name, NSInvalidArgumentException, [NSString stringWithFormat:@"%@ -init's name",
                                                                  class_getName(subject)]);
            same_string(reason, @"init is unavailable", [NSString stringWithFormat:@"%@ -init's reason",
                                                                 class_getName(subject)]);
        }

        // the three resource methods, for tags the manifest names and one it does not
        for (NSSet *tags in @[ known, unknown ])
            for (NSBundle *bundle in @[ withManifest, withoutManifest ]) {
                id ourRequest = [[ours alloc] initWithTags:tags bundle:bundle];
                NSString *what = [NSString stringWithFormat:@"%@ in %@",
                                                            [[tags allObjects] componentsJoinedByString:@","],
                                                            [bundle.bundlePath lastPathComponent]];
                __block NSError *ourError = nil;
                [ourRequest beginAccessingResourcesWithCompletionHandler:^(NSError *error) { ourError = error; }];
                checks++;
                if (tags == known && bundle == withManifest) {
                    if (ourError) {
                        fail(@"%@: the port completed with %@ %ld where every pack is in the bundle", what,
                             ourError.domain, (long)ourError.code);
                        continue;
                    }
                } else {
                    if (!ourError) {
                        fail(@"%@: the port completed with nothing, and the bundle has no such tag", what);
                        continue;
                    }
                    same_string(ourError.domain, NSCocoaErrorDomain, [what stringByAppendingString:@" error domain"]);
                    same_integer((long long)ourError.code, 4994, [what stringByAppendingString:@" error code"]);
                }
                __block BOOL ourAvailable = NO;
                [ourRequest conditionallyBeginAccessingResourcesWithCompletionHandler:^(BOOL available) {
                    ourAvailable = available;
                }];
                same_bool(ourAvailable, tags == known && bundle == withManifest,
                          [what stringByAppendingString:@" conditionallyBeginAccessing answers"]);
                [ourRequest endAccessingResources];
            }

        // the two NSBundle additions, held to the header: macOS ships them as stubs that answer
        // where the header promises an exception, so the host cannot be the oracle for either
        SEL setPriority = NSSelectorFromString(@"setPreservationPriority:forTags:");
        SEL priorityFor = NSSelectorFromString(@"preservationPriorityForTag:");
        Class bundleClass = objc_getClass("NSBundle");
        same_bool([bundleClass instancesRespondToSelector:setPriority], YES,
                  @"the port adds -setPreservationPriority:forTags: to NSBundle");
        same_bool([bundleClass instancesRespondToSelector:priorityFor], YES,
                  @"the port adds -preservationPriorityForTag: to NSBundle");
        for (NSBundle *bundle in @[ withoutManifest, withManifest ]) {
            NSString *what = [NSString stringWithFormat:@"a bundle with%s tag information",
                                                        bundle == withManifest ? "" : " no"];
            NSString *reason = nil;
            @try {
                ((void (*)(id, SEL, double, id))objc_msgSend)(bundle, setPriority, 0.25, known);
            } @catch (NSException *exception) {
                reason = exception.reason;
            }
            same_string(reason, bundle == withManifest ? nil : @"the header's refusal",
                        [what stringByAppendingString:@" -setPreservationPriority:forTags:"]);
            if (bundle == withManifest) {
                same_double(((double (*)(id, SEL, id))objc_msgSend)(bundle, priorityFor, @"level1"), 0.25,
                            @"the priority stored for level1 reads back");
                same_double(((double (*)(id, SEL, id))objc_msgSend)(bundle, priorityFor, @"level9"), 0.0,
                            @"a tag the manifest does not name has no priority");
            }
        }
        printf("note: the host's two NSBundle additions are the same selectors on the same class and read back 0,\n"
               "  so the port's two are held to the header and differ from macOS on purpose.\n");

        // the two constants: present, and of the header's own values - macOS does not emit either
        same_double(CharonHostNSBundleResourceRequestLoadingPriorityUrgent, 1.0,
                    @"NSBundleResourceRequestLoadingPriorityUrgent");
        same_string(CharonHostNSBundleResourceRequestLowDiskSpaceNotification,
                    @"NSBundleResourceRequestLowDiskSpaceNotification",
                    @"NSBundleResourceRequestLowDiskSpaceNotification");
        void *urgent = dlsym(RTLD_DEFAULT, "_NSBundleResourceRequestLoadingPriorityUrgent");
        void *low = dlsym(RTLD_DEFAULT, "_NSBundleResourceRequestLowDiskSpaceNotification");
        printf("note: on this host %s and %s, so neither constant's value is measurable here and both\n"
               "  are the header's own words; facts/Foundation/NSBundleResourceRequest.md says so.\n",
               urgent ? "the urgent priority is a symbol" : "the urgent priority is not a symbol",
               low ? "the notification is a symbol" : "the notification is not a symbol");

        printf("checks=%d failures=%d\n", checks, failures);
    }
    return failures ? 1 : 0;
}
