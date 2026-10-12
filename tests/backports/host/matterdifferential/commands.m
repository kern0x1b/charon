// matterdifferential/commands.m - every command and every reader of one Matter class, the system's and the port's,
// called the same way and their answers compared.
//
// The controller is one the framework has shut down (shutdown-controller.h), so every request answers through the
// framework's own "this controller cannot answer" path: no network is opened and no node is reached. Each selector is
// called once on each side with nil in every argument but the last, which is the completion block; the block takes
// the arity the SDK's header declares for it (run commands.sh writes that arity from the compiler's AST).
//
// A call's answer is what the completion received: how many times it ran, the error's domain, code and userInfo keys,
// and whether the data was nil. The two sides must give the same answer. Whether the completion ran on the cluster's
// queue is printed, not compared: the port completes on the caller's thread, the same shape its readers have.
//
// Writes and subscribes are not called here: a write stores a value on the port's side by design and behaviour.m
// asserts that on the port alone, and a subscribe is behaviour.m's. They are counted, so the run says what it skipped.
//
// Usage: commands <ClusterClassName>, with CHARON_DECLARED (class<TAB>selector<TAB>arity, one row per declared
// instance selector; arity 0 when it takes no completion) in the environment.
#import <Foundation/Foundation.h>
#import <Matter/Matter.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "shutdown-controller.h"

#ifdef CHARN_PORT_CLUSTER
#define PORT_CLUSTER CHARN_PORT_CLUSTER
#else
#define PORT_CLUSTER "MTRBaseClusterIdentify"
#endif

static const void *queueKey = &queueKey;

// What one completion received.
@interface Answer : NSObject
@property (nonatomic) int calls;
@property (nonatomic) BOOL onQueue;
@property (nonatomic) BOOL dataWasNil;
@property (nonatomic, strong) NSError *error;
@end
@implementation Answer
@end

// The part of an answer the two sides must agree on, as one line.
static NSString *comparable(Answer *answer, BOOL timedOut)
{
    if (timedOut) {
        return @"no completion within 5 s";
    }
    NSError *e = answer.error;
    NSString *error = e ? [NSString stringWithFormat:@"%@/%ld keys=[%@]", e.domain, (long)e.code,
                           [[[e.userInfo allKeys] sortedArrayUsingSelector:@selector(compare:)]
                               componentsJoinedByString:@","]] : @"no error";
    return [NSString stringWithFormat:@"calls=%d data-nil=%d %@", answer.calls, answer.dataWasNil, error];
}

// One call of `selector` on `target`, whose last argument is a completion of `arity` parameters. Returns nil when the
// selector takes more arguments than this check knows how to pass.
static Answer *call(id target, SEL selector, NSUInteger arguments, int arity, dispatch_queue_t queue, BOOL *timedOut)
{
    Answer *answer = [[Answer alloc] init];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    void (^record)(id, NSError *) = ^(id data, NSError *error) {
        @synchronized (answer) {
            answer.calls++;
            answer.onQueue = dispatch_get_specific(queueKey) != NULL;
            answer.dataWasNil = data == nil;
            answer.error = error;
        }
        dispatch_semaphore_signal(done);
    };
    // A one-parameter completion (MTRStatusCompletion) is called with its error alone; a two-parameter one with data and
    // error. The block is built for the arity the header declares, because a block called with fewer arguments than it
    // takes reads whatever was in the register.
    id completion;
    if (arity == 1) {
        completion = ^(NSError *error) { record(nil, error); };
    } else if (arity == 2) {
        completion = record;
    } else {
        return nil;
    }
    switch (arguments) {
        case 1: ((void (*)(id, SEL, id))objc_msgSend)(target, selector, completion); break;
        case 2: ((void (*)(id, SEL, id, id))objc_msgSend)(target, selector, nil, completion); break;
        case 3: ((void (*)(id, SEL, id, id, id))objc_msgSend)(target, selector, nil, nil, completion); break;
        case 4: ((void (*)(id, SEL, id, id, id, id))objc_msgSend)(target, selector, nil, nil, nil, completion); break;
        case 5: ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(target, selector, nil, nil, nil, nil, completion); break;
        default: return nil;
    }
    *timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0;
    return answer;
}

static NSArray *argumentsOf(NSString *selector)
{
    return [selector componentsSeparatedByString:@":"];
}

int main(int argc, const char *argv[])
{
    int failures = 0;
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: commands <real class name>\n");
            return 2;
        }
        NSString *real = @(argv[1]);
        Class systemClass = NSClassFromString(real);
        Class portClass = NSClassFromString(@PORT_CLUSTER);
        if (!systemClass || !portClass) {
            printf("class\t%s\t%s\n", real.UTF8String, systemClass ? "found" : "MISSING");
            printf("class\tport\t%s\t%s\n", PORT_CLUSTER, portClass ? "found" : "MISSING");
            return 1;
        }

        // The declared instance selectors of this class and the arity of each one's completion.
        NSMutableDictionary *arity = [NSMutableDictionary dictionary];
        const char *declaredPath = getenv("CHARON_DECLARED");
        if (!declaredPath) {
            printf("RED not read: CHARON_DECLARED is unset, so there is nothing to call\n");
            return 1;
        }
        NSString *text = [NSString stringWithContentsOfFile:@(declaredPath) encoding:NSUTF8StringEncoding error:NULL];
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            NSArray *cells = [line componentsSeparatedByString:@"\t"];
            if (cells.count == 3 && [cells[0] isEqualToString:real]) {
                arity[cells[1]] = @([cells[2] intValue]);
            }
        }

        NSError *error = nil;
        MTRDeviceController *controller = StartControllerOnNewFabric(&error);
        if (!controller) {
            printf("controller\tnot started\t%s\n", [[error description] UTF8String]);
            return 1;
        }
        // A base cluster takes the base device and the other kind takes the device object, as each SDK declares.
        BOOL base = [real hasPrefix:@"MTRBaseCluster"];
        id device = base ? [MTRBaseDevice deviceWithNodeID:@4660 controller:controller]
                         : [MTRDevice deviceWithNodeID:@4660 controller:controller];
        [controller shutdown];

        dispatch_queue_t queue = dispatch_queue_create("commands", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue, queueKey, (void *)1, NULL);
        id systemCluster = ((id (*)(id, SEL, id, id, id))objc_msgSend)([systemClass alloc],
            NSSelectorFromString(@"initWithDevice:endpointID:queue:"), device, @1, queue);
        id portCluster = ((id (*)(id, SEL, id, id, id))objc_msgSend)([portClass alloc],
            NSSelectorFromString(@"initWithDevice:endpointID:queue:"), device, @1, queue);
        if (!systemCluster || !portCluster) {
            printf("cluster\tnot created\tsystem %s, port %s\n", systemCluster ? "yes" : "no", portCluster ? "yes" : "no");
            return 1;
        }

        int commands = 0, readers = 0, synchronousReaders = 0, writes = 0, subscribes = 0, initialisers = 0;
        int withoutCompletion = 0, notCarried = 0, differing = 0;
        int onQueueSystem = 0, onQueuePort = 0;
        for (NSString *selector in [[arity allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            SEL name = NSSelectorFromString(selector);
            int completionArity = [arity[selector] intValue];
            NSUInteger arguments = argumentsOf(selector).count - 1;
            if ([selector hasPrefix:@"writeAttribute"]) { writes++; continue; }
            if ([selector hasPrefix:@"subscribe"]) { subscribes++; continue; }
            if ([selector hasPrefix:@"init"] || [selector isEqualToString:@"new"]) { initialisers++; continue; }
            if (completionArity == 0 && [selector hasPrefix:@"readAttribute"]) {
                // The synchronous reader (the generator's read_sync): it returns the value, or nil with no node.
                if (![portCluster respondsToSelector:name]) {
                    printf("DIFFERENT\t%s\t%s\tnot answered by the port\n", real.UTF8String, selector.UTF8String);
                    differing++;
                    continue;
                }
                if (![systemCluster respondsToSelector:name]) {
                    // The SDK 26.2 declares it and this host's framework does not: a later release, not a defect.
                    printf("not-carried\t%s\t%s\n", real.UTF8String, selector.UTF8String);
                    notCarried++;
                    continue;
                }
                if (arguments > 1) {
                    printf("DIFFERENT\t%s\t%s\tnot called: %lu arguments\n", real.UTF8String, selector.UTF8String,
                           (unsigned long)arguments);
                    differing++;
                    continue;
                }
                id system = arguments == 1 ? ((id (*)(id, SEL, id))objc_msgSend)(systemCluster, name, nil)
                                           : ((id (*)(id, SEL))objc_msgSend)(systemCluster, name);
                id port = arguments == 1 ? ((id (*)(id, SEL, id))objc_msgSend)(portCluster, name, nil)
                                         : ((id (*)(id, SEL))objc_msgSend)(portCluster, name);
                NSString *systemAnswer = system ? NSStringFromClass([system class]) : @"nil";
                NSString *portAnswer = port ? NSStringFromClass([port class]) : @"nil";
                synchronousReaders++;
                if ([systemAnswer isEqualToString:portAnswer]) {
                    printf("same\t%s\t%s\treturns %s\n", real.UTF8String, selector.UTF8String, systemAnswer.UTF8String);
                } else {
                    printf("DIFFERENT\t%s\t%s\tsystem returns %s\n\t\t\t\tport:   returns %s\n", real.UTF8String,
                           selector.UTF8String, systemAnswer.UTF8String, portAnswer.UTF8String);
                    differing++;
                }
                continue;
            }
            if (completionArity == 0) {
                withoutCompletion++;
                printf("nocompletion\t%s\t%s\n", real.UTF8String, selector.UTF8String);
                continue;
            }
            BOOL systemTimedOut = NO, portTimedOut = NO;
            if (![portCluster respondsToSelector:name]) {
                printf("DIFFERENT\t%s\t%s\tnot answered by the port\n", real.UTF8String, selector.UTF8String);
                differing++;
                continue;
            }
            if (![systemCluster respondsToSelector:name]) {
                printf("not-carried\t%s\t%s\n", real.UTF8String, selector.UTF8String);
                notCarried++;
                continue;
            }
            Answer *system = call(systemCluster, name, arguments, completionArity, queue, &systemTimedOut);
            Answer *port = call(portCluster, name, arguments, completionArity, queue, &portTimedOut);
            if (!system || !port) {
                printf("DIFFERENT\t%s\t%s\tnot called: %lu arguments, arity %d\n", real.UTF8String, selector.UTF8String,
                       (unsigned long)arguments, completionArity);
                differing++;
                continue;
            }
            NSString *systemAnswer = comparable(system, systemTimedOut);
            NSString *portAnswer = comparable(port, portTimedOut);
            onQueueSystem += system.onQueue;
            onQueuePort += port.onQueue;
            // A reader is named as one, so the summary counts the two kinds apart; both are compared the same way.
            BOOL reader = [selector hasPrefix:@"readAttribute"] || [selector hasPrefix:@"readEvent"];
            if (reader) { readers++; } else { commands++; }
            if ([systemAnswer isEqualToString:portAnswer]) {
                printf("same\t%s\t%s\t%s\n", real.UTF8String, selector.UTF8String, systemAnswer.UTF8String);
            } else {
                printf("DIFFERENT\t%s\t%s\tsystem: %s\n\t\t\t\tport:   %s\n", real.UTF8String, selector.UTF8String,
                       systemAnswer.UTF8String, portAnswer.UTF8String);
                differing++;
            }
        }
        printf("%s\tcommands compared %d, readers compared %d, synchronous readers compared %d, writes not called %d, "
               "subscribes not called %d, initialisers not called %d, without a completion %d, not carried by the host %d\n",
               real.UTF8String, commands, readers, synchronousReaders, writes, subscribes, initialisers, withoutCompletion,
               notCarried);
        printf("%s\tcompletion on the cluster's queue: system %d, port %d\n", real.UTF8String, onQueueSystem, onQueuePort);
        failures = differing;
        printf("checks run: %d, failed: %d\n", commands + readers, failures);
    }
    return failures == 0 ? 0 : 1;
}
