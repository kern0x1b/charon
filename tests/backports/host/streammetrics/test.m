#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>
#import "check.h"

/* The four names a stream task's transaction reports about the socket underneath it, against the
   host's own stream task over the same connection.

   The port's classes are compiled under names of their own (uikit2/renames.sh with "*", which renames
   the classes and leaves the selectors), so the two never meet and each answer can be held beside the
   other. The listener is this test's own: a plain TCP socket on the loopback that accepts one
   connection and holds it, so what is compared is what each side *reports* about a socket both of
   them opened to the same place -- the addresses and the ports the descriptor holds, read by the port
   through kCFStreamPropertySocketNativeHandle and by the host through the system's own way.

   No certificate and no TLS: those are the other two rows and another test, because a TLS listener
   the test owns needs a certificate and a trust decision inside the test's own delegate.

   WHERE IT STOPS, and the measurement that says why:

       -[CharonHostNSURLSessionStreamTask _onqueue_resume]: unrecognized selector sent to instance

   Every check before that line passes, and the side this test calls the host's own IS the host's own
   (the check named "the host's own stream task is not the port's" is what says so, and it fails on the
   tree this file was written against: the port's -[NSURLSession streamTaskWithHostName:port:] is a
   category on a class the RELEASE owns and used to be applied by the loader over the release's own
   method of that name, so the task made on the left of the differential was a port task - measured
   2026-10-04: the host's own stream task was a CharonHostNSURLSessionStreamTask).

   What stops it is the port's own -resume, and it is the release's machinery, measured on the host
   2026-10-04 with the runtime and with the held caches:

       the host's own stream task is a __NSCFTCPIOStreamTask: superclass NSURLSessionTask, 54 own
           instance methods of which _onqueue_resume is one, 27 own ivars, instance size 920
       NSURLSessionStreamTask, the class of the RELEASE'S NAME: superclass NSURLSessionTask, 0 own
           instance methods, instance size 728, and _onqueue_resume is in no class of its chain
       __NSCFTCPIOStreamTask is NOT a subclass of NSURLSessionStreamTask

   -[NSURLSessionTask resume] is the release's and sends _onqueue_resume to self, so a task that is to
   be resumed by the release has to inherit that selector from the class the release really makes. On a
   band from 8.0 on the port's task is a subclass of CFNetwork's own NSURLSessionStreamTask and reaches
   it; on this host that reparenting is not available, and attach.c's mechanism cannot be used at all
   here: it writes the superclass word and reads the layout back, and on a host build every compiled
   class is already realized before the first constructor runs - measured by writing the word and
   reading the instance size back (728, the old layout, where the class written in had 16), in the main
   executable and in a dylib alike. So the wall is real and it is the host's, and the run fails with a
   line instead of hanging the host test sweep. The level that can hold the delivery is the 6.1.3
   emulator, where [super resume] is the release's own class. */

void host_attach_prefixed(const char *prefix);

/* The delegate a stream task's metrics arrive through, which is the only way an application sees
   them: the session builds the transaction and calls this. */
@interface CharonMetricsCollector : NSObject
@property NSURLSessionTaskMetrics *metrics;
@end

@implementation CharonMetricsCollector

- (void)URLSession:(NSURLSession *)session
                    task:(NSURLSessionTask *)task
 didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics
{
    self.metrics = metrics;
}

@end

static int failures;
static int checks;
static int divergences;

static int charon_listener(void)
{
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0)
        return -1;
    int reuse = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0; /* the kernel picks a free one, so two runs never collide */
    socklen_t length = sizeof(address);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(listener, 1) != 0 ||
        getsockname(listener, (struct sockaddr *)&address, &length) != 0) {
        close(listener);
        return -1;
    }
    return listener;
}

static NSUInteger charon_port_of(int descriptor)
{
    struct sockaddr_in address;
    socklen_t length = sizeof(address);
    if (getsockname(descriptor, (struct sockaddr *)&address, &length) != 0)
        return 0;
    return ntohs(address.sin_port);
}

static int charon_accepted = -1;

/* The accept runs on its own queue, because it blocks until a connection lands and the connection
   only lands once the task under test is resumed: accepting on the main thread is the second thing
   this test got wrong, and the thirty second bound is what said so. */
static void accept_once(int listener)
{
    if (charon_accepted >= 0)
        return;
    charon_accepted = 0; /* in flight */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int connection = accept(listener, NULL, NULL);
        if (connection < 0) {
            charon_accepted = -1;
            return;
        }
        /* One byte, so the reader on the other end has something to read and the task can finish. The
           first version of this test accepted and said nothing, which left both sides waiting for
           bytes that never came: that is what hung it, and this line is the whole fix. */
        const char greeting = 'k';
        write(connection, &greeting, 1);
    });
}

static void charon_on_alarm(int number)
{
    fprintf(stderr, "\nFAIL the test ran past its thirty second bound\n");
    _exit(1);
}

/* Every wait in this test is bounded, so a run that goes wrong fails instead of hanging: the host
   test sweep runs every one of these run.sh scripts, and a hanging test would hang the sweep for
   every band on the machine. */
static void charon_bound_the_run(void)
{
    signal(SIGALRM, charon_on_alarm);
    alarm(30);
}

/* The one transaction of a task, whichever side built it. */
static id first_transaction(id metrics)
{
    if (![metrics respondsToSelector:NSSelectorFromString(@"transactionMetrics")])
        return nil;
    NSArray *transactions = ((id (*)(id, SEL))objc_msgSend)(metrics, NSSelectorFromString(@"transactionMetrics"));
    return transactions.count ? transactions[0] : nil;
}

static NSString *property(id object, const char *name)
{
    SEL selector = NSSelectorFromString([NSString stringWithFormat:@"%s", name]);
    if (![object respondsToSelector:selector])
        return @"(no such property)";
    id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
    if (!value)
        return @"(nil)";
    return [value description];
}

static void compare(const char *label, id system, id ours)
{
    checks++;
    NSString *left = [system description] ?: @"(nil)";
    NSString *right = [ours description] ?: @"(nil)";
    if ([left isEqualToString:right]) {
        printf("ok   %s: %s\n", label, [left UTF8String]);
    } else {
        failures++;
        printf("FAIL %s: the system answers %s, the backport answers %s\n", label, [left UTF8String], [right UTF8String]);
    }
}

int main(void)
{
    @autoreleasepool {
        charon_bound_the_run();
        host_attach_prefixed("");

        int listener = charon_listener();
        charon_check(listener >= 0, "the test opens its own listener", @"no socket");
        if (listener < 0)
            return 1;
        NSUInteger port = charon_port_of(listener);
        printf("note the listener is on the loopback at port %lu\n", (unsigned long)port);

        /* ---- the host's own stream task, and the transaction it reports ---- */
        /* The port's class, named first: the check below is the red control for the harness's own
           defect, that the port's factory answered the release's and the left side of this differential
           was the port. */
        Class ourTaskClass = NSClassFromString(@"CharonHostNSURLSessionStreamTask");
        charon_check(ourTaskClass != Nil, "the port defines a stream task", @"no such class");
        CharonMetricsCollector *systemDelegate = [[CharonMetricsCollector alloc] init];
        Class systemSessionClass = [NSURLSession class];
        NSURLSession *systemSession = [systemSessionClass sessionWithConfiguration:
            [NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                                     delegate:systemDelegate
                                                                delegateQueue:nil];
        NSURLSessionTask *systemTask = [systemSession streamTaskWithHostName:@"127.0.0.1" port:(NSInteger)port];
        charon_check(systemTask != nil, "the host makes a stream task", @"nil");
        charon_check(systemTask && ourTaskClass && ![systemTask isKindOfClass:ourTaskClass],
                     "the host's own stream task is not the port's", @"the port's factory answered it");
        accept_once(listener);
        [systemTask resume];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        id systemTransaction = first_transaction(systemDelegate.metrics);
        for (NSString *name in @[@"closeRead", @"closeWrite"]) {
            SEL selector = NSSelectorFromString(name);
            if ([systemTask respondsToSelector:selector])
                ((void (*)(id, SEL))objc_msgSend)(systemTask, selector);
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        /* ---- the port's, the same way, and the transaction its delegate is handed ---- */
        /* The class under test here is the *task*: +streamTaskWithHostName:port: is a category on
           NSURLSession, and the port's own session is two thousand lines that this build does not
           need. The task is made through that category, renamed, on the host's own session, which is
           the shape a differential has when the port adds to a class the release already has. */
        SEL ourFactory = NSSelectorFromString(@"charonHost_streamTaskWithHostName:port:");
        charon_check([NSURLSession instancesRespondToSelector:ourFactory],
                     "the port's factory is attached to the session", @"the category is not attached");
        if (!ourTaskClass)
            return 1;

        CharonMetricsCollector *ourDelegate = [[CharonMetricsCollector alloc] init];
        NSURLSession *ourSession = [systemSessionClass sessionWithConfiguration:
            [NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                                     delegate:ourDelegate
                                                                delegateQueue:nil];
        charon_check(ourSession != nil, "a session with the collecting delegate", @"nil");
        NSURLSessionTask *ourTask = ((id (*)(id, SEL, id, NSInteger))objc_msgSend)(ourSession,
            ourFactory, @"127.0.0.1", (NSInteger)port);
        charon_check(ourTask != nil, "and a stream task to the same port", @"nil");
        accept_once(listener);
        ((void (*)(id, SEL))objc_msgSend)(ourTask, @selector(resume));
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        ((void (*)(id, SEL))objc_msgSend)(ourTask, @selector(closeRead));
        ((void (*)(id, SEL))objc_msgSend)(ourTask, @selector(closeWrite));
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];

        id ourTransaction = first_transaction(ourDelegate.metrics);
        if (!ourTransaction) {
            failures++;
            printf("FAIL the port handed no transaction to its delegate\n");
        }

        /* ---- the four names, each side's own ---- */
        printf("note the host's transaction: %s\n", systemTransaction ? "yes" : "none");
        for (NSString *name in @[@"localAddress", @"localPort", @"remoteAddress", @"remotePort"]) {
            compare([name UTF8String], property(systemTransaction, [name UTF8String]),
                    property(ourTransaction, [name UTF8String]));
        }
        /* The two negotiated TLS values are the other two rows: there is no TLS on this connection and
           both sides say so, which is the answer rather than a gap. */
        for (NSString *name in @[@"negotiatedTLSProtocolVersion", @"negotiatedTLSCipherSuite"]) {
            compare([name UTF8String], property(systemTransaction, [name UTF8String]),
                    property(ourTransaction, [name UTF8String]));
        }

        printf("checks=%d failures=%d divergences=%d\n", checks, failures, divergences);
    }
    return failures ? 1 : 0;
}
