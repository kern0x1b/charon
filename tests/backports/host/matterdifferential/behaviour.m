// matterdifferential/behaviour.m - what a cluster DOES when there is nothing to reach, the system's class and
// the port's asked the same things in one program.
//
// cases.m compares the two classes' member SETS and one round trip. It never calls a subscribe or a cached
// read, so for a long time nothing said what the port's `subscribeAttribute*` did: it stored the string
// @"subscribed" over the attribute's value (2,441 methods), and nothing noticed. This program is the
// measurement the port's answer is held to.
//
// The system side is Apple's own class on a REAL controller that has been shut down, so every request ends in
// the framework's own "this controller cannot answer" path; no network is opened and no node is reached. The
// port side is the same selectors on the port's own class, compiled with its name aliased (as cases.m does).
//
// Two kinds of line, and only the first decides the exit status:
//
//   assert.*    the port's answer is compared with the system's; a difference is a failure
//   own.*       a property only the port has to keep (its stored value, one instance's table is its own, and
//               nothing races), asserted on the port alone because the system keeps no stored value at all
//
// Usage: behaviour <ClusterClassName> <AttributeName> [stress]
#import <Foundation/Foundation.h>
#import <Matter/Matter.h>
#import <Security/Security.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>

@interface BehaviourStorage : NSObject <MTRStorage>
@property (nonatomic, strong) NSMutableDictionary *table;
@end
@implementation BehaviourStorage
- (instancetype)init { self = [super init]; _table = [NSMutableDictionary dictionary]; return self; }
- (NSData *)storageDataForKey:(NSString *)key { @synchronized (self) { return self.table[key]; } }
- (BOOL)setStorageData:(NSData *)value forKey:(NSString *)key { @synchronized (self) { self.table[key] = value; } return YES; }
- (BOOL)removeStorageDataForKey:(NSString *)key { @synchronized (self) { [self.table removeObjectForKey:key]; } return YES; }
@end

// A software P-256 key: the framework asks the operational signer for a public key and a signature while it
// creates a fabric, and nothing else here signs anything.
@interface BehaviourKeypair : NSObject <MTRKeypair>
@property (nonatomic) SecKeyRef privateKey;
@property (nonatomic) SecKeyRef publicKeyRef;
@end
@implementation BehaviourKeypair
- (instancetype)init
{
    self = [super init];
    NSDictionary *attributes = @{(id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
                                 (id)kSecAttrKeySizeInBits: @256};
    CFErrorRef error = NULL;
    _privateKey = SecKeyCreateRandomKey((CFDictionaryRef)attributes, &error);
    if (!_privateKey) {
        return nil;
    }
    _publicKeyRef = SecKeyCopyPublicKey(_privateKey);
    return self;
}
- (SecKeyRef)copyPublicKey { return (SecKeyRef)CFRetain(_publicKeyRef); }
- (SecKeyRef)publicKey { return _publicKeyRef; }
- (NSData *)signMessageECDSA_DER:(NSData *)message
{
    CFErrorRef error = NULL;
    CFDataRef signature = SecKeyCreateSignature(_privateKey, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                (CFDataRef)message, &error);
    return (__bridge_transfer NSData *)signature;
}
@end

static NSMutableDictionary *sides[2];   // 0 system, 1 port
static const void *queueKey = &queueKey;

// Whether the class carries the selector in its OWN method list. A port class that does not define a member
// inherits the system's, and then the system answers for both sides and the comparison says nothing about the
// port - MTRBaseClusterTestCluster is a deprecated subclass whose current-shape members are the superclass's.
static BOOL definesOwn(Class cls, SEL selector)
{
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int index = 0; index < count && !found; index++) {
        found = sel_isEqual(method_getName(list[index]), selector);
    }
    free(list);
    return found;
}

static NSString *describeError(NSError *error)
{
    return error ? [NSString stringWithFormat:@"%@/%ld \"%@\"", error.domain, (long)error.code,
                    error.localizedDescription] : @"nil";
}

static NSString *describeValue(id value)
{
    return value ? [NSString stringWithFormat:@"%@ (%@)", value, NSStringFromClass([value class])] : @"nil";
}

static void record(int side, NSString *key, NSString *value)
{
    @synchronized ([NSNull null]) {
        sides[side][key] = value;
    }
}

static BOOL waitFor(dispatch_semaphore_t semaphore, double seconds)
{
    return dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC))) == 0;
}

// What one side answers to a subscribe, in either of the header's two shapes. `invoke` makes the call.
static void observeSubscribe(int side, NSString *shape, dispatch_queue_t queue, NSInteger *calls,
                             void (^invoke)(void (^established)(void), void (^report)(id, NSError *)))
{
    __block int reports = 0, establisheds = 0, onQueue = 0;
    __block id reportedValue = @"unset";
    __block NSError *reportedError = nil;
    dispatch_semaphore_t first = dispatch_semaphore_create(0);
    invoke(^{
                @synchronized ([NSNull null]) {
                    establisheds++;
                }
            },
            ^(id value, NSError *error) {
                @synchronized ([NSNull null]) {
                    reports++;
                    reportedValue = value;
                    reportedError = error;
                    if (dispatch_get_specific(queueKey)) {
                        onQueue++;
                    }
                }
                dispatch_semaphore_signal(first);
            });
    // Whether the handler can run before the call returns is not compared: over 42 recorded runs of this check
    // the framework answered "yes" once and "no" in the rest, and the port answered "no" in all 42. A row that
    // flips between runs on one side is not a fact about either side.
    waitFor(first, 5.0);
    [NSThread sleepForTimeInterval:0.5];   // a second call, or an established call, would land here
    record(side, [NSString stringWithFormat:@"assert.subscribe[%@].reportHandler calls", shape],
           [NSString stringWithFormat:@"%d", reports]);
    record(side, [NSString stringWithFormat:@"assert.subscribe[%@].subscriptionEstablished calls", shape],
           [NSString stringWithFormat:@"%d", establisheds]);
    record(side, [NSString stringWithFormat:@"assert.subscribe[%@].reportHandler value", shape],
           describeValue(reportedValue));
    record(side, [NSString stringWithFormat:@"assert.subscribe[%@].reportHandler error", shape],
           describeError(reportedError));
    record(side, [NSString stringWithFormat:@"assert.subscribe[%@].reportHandler ran on the cluster's queue", shape],
           onQueue == reports && reports > 0 ? @"yes" : @"no");
    if (calls) {
        *calls = reports;
    }
}

enum { StressWorkers = 8, StressRounds = 3000 };

typedef struct {
    __unsafe_unretained id cluster;
    __unsafe_unretained NSString *attribute;
    int rounds;
    int worker;
    int reads;      // what this worker read back, one per round
    int unwritten;  // of those, the reads that are not a value some worker wrote
} Stress;

// A worker writes worker * 100000 + round, for a worker from 1 to StressWorkers and a round below StressRounds. A
// read that is anything else - nil, a string, a number no worker wrote - came from nowhere the test can name.
static BOOL writtenByWorker(id value)
{
    if (![value isKindOfClass:[NSNumber class]]) {
        return NO;
    }
    long number = [value longValue];
    long worker = number / 100000, round = number % 100000;
    return number >= 0 && worker >= 1 && worker <= StressWorkers && round < StressRounds;
}

static void *stressMain(void *argument)
{
    Stress *work = (Stress *)argument;
    @autoreleasepool {
        id cluster = work->cluster;
        SEL reader = NSSelectorFromString([NSString stringWithFormat:@"readAttribute%@WithCompletion:", work->attribute]);
        SEL writer = NSSelectorFromString([NSString stringWithFormat:@"writeAttribute%@WithValue:completion:", work->attribute]);
        for (int round = 0; round < work->rounds; round++) {
            @autoreleasepool {
                id value = @(work->worker * 100000 + round);
                void (^status)(NSError *) = ^(NSError *error) {};
                // The port's read completes on the calling thread, so the completion is run before the call returns.
                void (^completion)(id, NSError *) = ^(id read, NSError *error) {
                    work->reads++;
                    if (!writtenByWorker(read)) {
                        work->unwritten++;
                    }
                };
                ((void (*)(id, SEL, id, id))objc_msgSend)(cluster, writer, value, status);
                ((void (*)(id, SEL, id))objc_msgSend)(cluster, reader, completion);
            }
        }
    }
    return NULL;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: behaviour <ClusterClass> <Attribute> [stress]\n");
            return 2;
        }
        NSString *systemName = @(argv[1]);
        NSString *attribute = @(argv[2]);
        BOOL stress = argc > 3 && strcmp(argv[3], "stress") == 0;
        Class systemClass = NSClassFromString(systemName);
        Class portClass = NSClassFromString([@"CharonPort" stringByAppendingString:systemName]);
        if (!systemClass || !portClass) {
            printf("class\t%s\t%s\n", systemName.UTF8String, systemClass ? "found" : "MISSING");
            printf("class\tport\t%s\n", portClass ? "found" : "MISSING");
            return 1;
        }
        sides[0] = [NSMutableDictionary dictionary];
        sides[1] = [NSMutableDictionary dictionary];

        BehaviourStorage *storage = [[BehaviourStorage alloc] init];
        MTRDeviceControllerFactoryParams *factoryParams =
            [[MTRDeviceControllerFactoryParams alloc] initWithStorage:storage];
        NSError *error = nil;
        MTRDeviceControllerFactory *factory = [MTRDeviceControllerFactory sharedInstance];
        if (![factory startControllerFactory:factoryParams error:&error]) {
            printf("factory\tdid not start\t%s\n", [[error description] UTF8String]);
            return 1;
        }
        uint8_t ipk[16] = {0};
        MTRDeviceControllerStartupParams *startup = [[MTRDeviceControllerStartupParams alloc]
            initWithIPK:[NSData dataWithBytes:ipk length:sizeof(ipk)] fabricID:@1
              nocSigner:[[BehaviourKeypair alloc] init]];
        startup.vendorID = @0xFFF1;
        MTRDeviceController *controller = [factory createControllerOnNewFabric:startup error:&error];
        if (!controller) {
            printf("controller\tnot created\t%s\n", [[error description] UTF8String]);
            return 1;
        }
        // Stopped: the system's own "this controller cannot answer" path, which is the nearest thing to
        // a device that has no Matter hardware at all.
        MTRBaseDevice *device = [MTRBaseDevice deviceWithNodeID:@4660 controller:controller];
        [controller shutdown];

        dispatch_queue_t queue = dispatch_queue_create("behaviour", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue, queueKey, (void *)1, NULL);

        Class classes[2] = {systemClass, portClass};
        id firstOf[2] = {nil, nil}, secondOf[2] = {nil, nil};
        for (int side = 0; side < 2; side++) {
            Class cls = classes[side];
            SEL designated = NSSelectorFromString(@"initWithDevice:endpointID:queue:");
            id cluster = ((id (*)(id, SEL, id, id, id))objc_msgSend)([cls alloc], designated, device, @1, queue);
            id other = ((id (*)(id, SEL, id, id, id))objc_msgSend)([cls alloc], designated, device, @1, queue);
            firstOf[side] = cluster;
            secondOf[side] = other;
            record(side, @"assert.instance", cluster ? @"created" : @"nil");

            SEL subscribeParams = NSSelectorFromString([NSString stringWithFormat:
                @"subscribeAttribute%@WithParams:subscriptionEstablished:reportHandler:", attribute]);
            SEL subscribeOld = NSSelectorFromString([NSString stringWithFormat:
                @"subscribeAttribute%@WithMinInterval:maxInterval:params:subscriptionEstablished:reportHandler:", attribute]);
            MTRSubscribeParams *params = [[MTRSubscribeParams alloc] initWithMinInterval:@1 maxInterval:@10];
            record(side, @"observe.subscribe[WithParams] defined by",
                   definesOwn(cls, subscribeParams) ? @"the class itself" : @"its superclass");
            record(side, @"observe.subscribe[WithMinInterval] defined by",
                   definesOwn(cls, subscribeOld) ? @"the class itself" : @"its superclass");
            // Each side is asked for the shapes IT declares, and the declaration is an assert row: a shape only one
            // side declares is a DIFFERENT, not a silence. The system keeps deprecated shapes too, so a port that
            // does not carry one fails here by name.
            BOOL declaresParams = [cluster respondsToSelector:subscribeParams];
            record(side, @"assert.subscribe[WithParams] declared", declaresParams ? @"yes" : @"no");
            if (declaresParams) {
                observeSubscribe(side, @"WithParams", queue, NULL, ^(void (^established)(void), void (^report)(id, NSError *)) {
                    ((void (*)(id, SEL, id, id, id))objc_msgSend)(cluster, subscribeParams, params, established, report);
                });
            }
            BOOL declaresOld = [cluster respondsToSelector:subscribeOld];
            record(side, @"assert.subscribe[WithMinInterval] declared", declaresOld ? @"yes" : @"no");
            if (declaresOld) {
                observeSubscribe(side, @"WithMinInterval", queue, NULL, ^(void (^established)(void), void (^report)(id, NSError *)) {
                    ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(cluster, subscribeOld, @1, @10, params, established, report);
                });
            }

            // The cached read, with a container that has no cache attached: the framework's own "there is
            // nothing to read this from" answer. It is a class method, and it is given the queue to complete on.
            SEL cached = NSSelectorFromString([NSString stringWithFormat:
                @"readAttribute%@WithClusterStateCache:endpoint:queue:completion:", attribute]);
            BOOL declaresCached = [cls respondsToSelector:cached];
            record(side, @"assert.cachedRead declared", declaresCached ? @"yes" : @"no");
            if (declaresCached) {
                __block id cachedValue = @"unset";
                __block NSError *cachedError = nil;
                __block int cachedCalls = 0, cachedOnQueue = 0;
                dispatch_semaphore_t done = dispatch_semaphore_create(0);
                MTRClusterStateCacheContainer *container = [[MTRClusterStateCacheContainer alloc] init];
                void (^completion)(id, NSError *) = ^(id value, NSError *failure) {
                    @synchronized ([NSNull null]) {
                        cachedValue = value;
                        cachedError = failure;
                        cachedCalls++;
                        // The queue the completion ran on, as the queue's own specific key says: the one given.
                        if (dispatch_get_specific(queueKey)) {
                            cachedOnQueue++;
                        }
                    }
                    dispatch_semaphore_signal(done);
                };
                ((void (*)(id, SEL, id, id, id, id))objc_msgSend)(cls, cached, container, @1, queue, completion);
                waitFor(done, 5.0);
                record(side, @"assert.cachedRead.completion calls", [NSString stringWithFormat:@"%d", cachedCalls]);
                record(side, @"assert.cachedRead.value", describeValue(cachedValue));
                record(side, @"assert.cachedRead.error", describeError(cachedError));
                record(side, @"assert.cachedRead.completion ran on the given queue",
                       cachedCalls > 0 && cachedOnQueue == cachedCalls ? @"yes" : @"no");
            }
        }

        // What only the port keeps: a stored value (the system keeps none), that a subscribe leaves it
        // alone, that another instance has its own table, and that concurrent writes and reads hand back
        // values that were written. Each check the port's class is expected to run is named below; one that
        // does not run is a failure, not a silence.
        // The own.* checks the port's class is expected to run, by name. A check that does not run is a failure.
        NSMutableArray *expectedOwn = [NSMutableArray array];
        BOOL stressBroke = NO;
        {
            id cluster = firstOf[1], other = secondOf[1];
            SEL reader = NSSelectorFromString([NSString stringWithFormat:@"readAttribute%@WithCompletion:", attribute]);
            SEL writer = NSSelectorFromString([NSString stringWithFormat:@"writeAttribute%@WithValue:completion:", attribute]);
            SEL subscribeParams = NSSelectorFromString([NSString stringWithFormat:
                @"subscribeAttribute%@WithParams:subscriptionEstablished:reportHandler:", attribute]);
            id (^readOnce)(id) = ^id(id who) {
                __block id got = @"unset";
                void (^completion)(id, NSError *) = ^(id value, NSError *failure) { got = value; };
                ((void (*)(id, SEL, id))objc_msgSend)(who, reader, completion);
                return got;
            };
            // What the PORT class answers, inherited members included: an alias answers its superclass's accessors and
            // keeps its table there, and its own checks have to run. (definesOwn is for the SYSTEM side, where an
            // inherited member is the system's own answer.)
            if ([portClass instancesRespondToSelector:reader] && [portClass instancesRespondToSelector:writer]) {
                [expectedOwn addObject:@"own.write then read"];
                [expectedOwn addObject:@"own.other instance reads"];
                void (^status)(NSError *) = ^(NSError *failure) {};
                ((void (*)(id, SEL, id, id))objc_msgSend)(cluster, writer, @30, status);
                id before = readOnce(cluster);
                record(1, @"own.write then read", describeValue(before));
                if ([portClass instancesRespondToSelector:subscribeParams]) {
                    [expectedOwn addObject:@"own.value after subscribe"];
                    MTRSubscribeParams *params = [[MTRSubscribeParams alloc] initWithMinInterval:@1 maxInterval:@10];
                    dispatch_semaphore_t reported = dispatch_semaphore_create(0);
                    ((void (*)(id, SEL, id, id, id))objc_msgSend)(cluster, subscribeParams, params, ^{},
                        ^(id value, NSError *failure) { dispatch_semaphore_signal(reported); });
                    waitFor(reported, 5.0);
                    id after = readOnce(cluster);
                    record(1, @"own.value after subscribe", describeValue(after));
                }
                record(1, @"own.other instance reads", describeValue(readOnce(other)));
            }
            if (stress && [portClass instancesRespondToSelector:reader] && [portClass instancesRespondToSelector:writer]) {
                [expectedOwn addObject:@"own.stress"];
                pthread_t threads[StressWorkers];
                Stress work[StressWorkers];
                for (int index = 0; index < StressWorkers; index++) {
                    work[index] = (Stress){cluster, attribute, StressRounds, index + 1, 0, 0};
                    pthread_create(&threads[index], NULL, stressMain, &work[index]);
                }
                for (int index = 0; index < StressWorkers; index++) {
                    pthread_join(threads[index], NULL);
                }
                int reads = 0, unwritten = 0;
                for (int index = 0; index < StressWorkers; index++) {
                    reads += work[index].reads;
                    unwritten += work[index].unwritten;
                }
                // Every read must be a value some worker wrote, and every worker must have read back all of its rounds.
                stressBroke = unwritten > 0 || reads != StressWorkers * StressRounds;
                record(1, @"own.stress", [NSString stringWithFormat:@"%d threads x %d write+read: %d reads, %d not a value a worker wrote",
                                          StressWorkers, StressRounds, reads, unwritten]);
            }
        }

        int failures = 0;
        NSArray *keys = [[sides[0].allKeys arrayByAddingObjectsFromArray:sides[1].allKeys]
            valueForKeyPath:@"@distinctUnionOfObjects.self"];
        for (NSString *key in [keys sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *system = sides[0][key] ?: @"(absent)";
            NSString *port = sides[1][key] ?: @"(absent)";
            BOOL same = [system isEqualToString:port];
            BOOL decides = [key hasPrefix:@"assert."];
            printf("%s\t%s\n    system: %s\n    port:   %s\n", same ? "same     " : (decides ? "DIFFERENT" : "own      "),
                   key.UTF8String, system.UTF8String, port.UTF8String);
            if (!same && decides) {
                failures++;
            }
        }
        // the port-only properties: each is a requirement and a failure is a failure
        NSString *written = sides[1][@"own.write then read"];
        if (written && ![written hasPrefix:@"30 "]) {
            printf("DIFFERENT\town.write then read: the port does not hand back the value written\n");
            failures++;
        }
        NSString *afterSubscribe = sides[1][@"own.value after subscribe"];
        if (afterSubscribe && ![afterSubscribe isEqualToString:written]) {
            printf("DIFFERENT\town.value after subscribe: %s, which is not what was stored (%s)\n",
                   afterSubscribe.UTF8String, written.UTF8String);
            failures++;
        }
        NSString *otherInstance = sides[1][@"own.other instance reads"];
        if (otherInstance && ![otherInstance isEqualToString:@"nil"]) {
            printf("DIFFERENT\town.other instance reads: %s - one instance's table is another's\n",
                   otherInstance.UTF8String);
            failures++;
        }
        // An own.* check the port's class is expected to run, and did not, is a failure: nothing else says it ran.
        for (NSString *key in expectedOwn) {
            if (!sides[1][key]) {
                printf("MISSING\t%s: the check did not run on the port\n", key.UTF8String);
                failures++;
            }
        }
        if (stressBroke) {
            printf("DIFFERENT\town.stress: a read was not a value a worker wrote, or a worker lost a round\n");
            failures++;
        }
        printf("checks: %lu, failed: %d\n", (unsigned long)keys.count, failures);
        return failures == 0 ? 0 : 1;
    }
}
