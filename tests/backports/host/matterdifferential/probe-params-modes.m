// matterdifferential/probe-params-modes.m - what the framework answers for a command that takes a params object, on a
// controller that has been shut down, when the params object is built three ways: the default initialiser, every
// settable NSNumber, NSString, NSData and NSArray field set to zero or empty, and every such field set to one.
//
// commands.m passes nil for the params and finds 28 selectors where the framework answers MTRInteractionErrorDomain/135
// and the port MTRErrorDomain/6. This program says whether the answer changes with the parameters, for every command of
// one class, so the answer can be matched by a rule and not by a list of selectors.
//
// Usage: probe-params-modes <ClusterClassName>, with CHARON_DECLARED (class<TAB>selector<TAB>arity) in the environment,
// as commands.m reads it. One line per selector and mode: selector, mode, then the answer in commands.m's form.
//
// Modes: default (every property nil), zeros, ones, objones (struct properties filled with ones), zero:<p> and one:<p>
// (that property zero or one, the others the other value), nil:<p> (that property nil, the others one), and path:<s>.<f>
// (struct s filled with ones except field f, which is zero). zero: and one: leave the other properties set, so a refusal
// can be the other properties' and not the named one's: the nil: and path: modes are the ones that separate the two.
// The nil: and path: modes are only run for the selectors PROBE_NIL_SELECTORS and PROBE_PATH_SELECTORS name.
#import <Foundation/Foundation.h>
#import <Matter/Matter.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "shutdown-controller.h"

static const void *queueKey = &queueKey;

@interface ProbeAnswer : NSObject
@property (nonatomic) int calls;
@property (nonatomic) BOOL dataWasNil;
@property (nonatomic, strong) NSError *error;
@end
@implementation ProbeAnswer
@end

// The answer as commands.m prints it: the count, whether the data was nil, and the error's domain, code and keys.
static NSString *answerLine(ProbeAnswer *answer, BOOL timedOut)
{
    if (timedOut) {
        return @"no completion within 5 s";
    }
    NSError *e = answer.error;
    NSString *error = e ? [NSString stringWithFormat:@"%@/%ld keys=[%@] described=\"%@\"", e.domain, (long)e.code,
                           [[[e.userInfo allKeys] sortedArrayUsingSelector:@selector(compare:)]
                               componentsJoinedByString:@","], e.localizedDescription] : @"no error";
    return [NSString stringWithFormat:@"calls=%d data-nil=%d %@", answer.calls, answer.dataWasNil, error];
}

// The properties every params class has that are about the transport of the command, not its fields: a timed invoke
// or a server-side timeout would change the path the call takes, so the probe leaves them alone.
static BOOL isTransportProperty(NSString *name)
{
    return [name isEqualToString:@"timedInvokeTimeout"] || [name isEqualToString:@"timedInvokeTimeoutMs"] ||
           [name isEqualToString:@"serverSideProcessingTimeout"];
}

// Sets every settable NSNumber, NSString, NSData and NSArray property to zero or empty (zeros) or to one (not zeros).
// With zeroField set, that one property takes its zero value and every other property takes one. With oneField set,
// that one property takes one and every other takes its zero value.
// Set for the "objones" mode: a struct field takes a default-initialised object of its class instead of nil.
static BOOL fillObjects = NO;
static int fillDepth = 0;
// Set for a "path:" mode: "struct.field", the one field of one struct that is zero while everything else is one.
static NSString *zeroPath = nil;
// Set for a "nil:" mode: the one top-level property that is left nil while every other property is one.
static NSString *nilField = nil;

static void fillParams(id params, BOOL zeros, NSString *zeroField, NSString *oneField)
{
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList([params class], &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = @(property_getName(props[i]));
        NSString *attribute = @(property_getAttributes(props[i]));
        if (isTransportProperty(name)) {
            continue;
        }
        if (fillDepth == 0 && nilField && [name isEqualToString:nilField]) {
            continue;
        }
        BOOL zero = oneField ? ![name isEqualToString:oneField] : (zeros || [name isEqualToString:zeroField]);
        id value = nil;
        if ([attribute hasPrefix:@"T@\"NSNumber\""]) {
            value = zero ? @0 : @1;
        } else if ([attribute hasPrefix:@"T@\"NSString\""]) {
            value = zero ? @"" : @"x";
        } else if ([attribute hasPrefix:@"T@\"NSData\""]) {
            uint8_t byte = zero ? 0 : 1;
            value = [NSData dataWithBytes:&byte length:1];
        } else if ([attribute hasPrefix:@"T@\"NSArray\""]) {
            value = @[];
        } else if (fillObjects && [attribute hasPrefix:@"T@\""]) {
            // A struct field: a default-initialised object of its own class, when the mode asks for objects.
            Class objectClass = NSClassFromString([[attribute substringFromIndex:3] componentsSeparatedByString:@"\""].firstObject);
            if (objectClass) {
                value = [[objectClass alloc] init];
                // The struct's own fields are set the same way, to a depth of three, so a refusal inside a struct is seen.
                if (fillDepth < 3) {
                    // zeroPath, when set as "struct.field" by a path mode, makes that one field of that one struct zero.
                    NSString *inner = nil;
                    if (zeroPath && [zeroPath hasPrefix:[name stringByAppendingString:@"."]]) {
                        inner = [zeroPath substringFromIndex:name.length + 1];
                    }
                    fillDepth++;
                    fillParams(value, NO, inner, nil);
                    fillDepth--;
                }
            }
        }
        if (!value) {
            continue;
        }
        NSString *setterName = [NSString stringWithFormat:@"set%@%@:", [[name substringToIndex:1] uppercaseString],
                                                          [name substringFromIndex:1]];
        SEL setter = NSSelectorFromString(setterName);
        if ([params respondsToSelector:setter]) {
            ((void (*)(id, SEL, id))objc_msgSend)(params, setter, value);
        }
    }
    free(props);
}

// One call with the params as the first argument and the completion as the last; the arguments between are nil.
static ProbeAnswer *callWithParams(id target, SEL selector, id params, NSUInteger arguments, int arity,
                                   dispatch_queue_t queue, BOOL *timedOut)
{
    ProbeAnswer *answer = [[ProbeAnswer alloc] init];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    void (^record)(id, NSError *) = ^(id data, NSError *error) {
        @synchronized (answer) {
            answer.calls++;
            answer.dataWasNil = data == nil;
            answer.error = error;
        }
        dispatch_semaphore_signal(done);
    };
    id completion;
    if (arity == 1) {
        completion = ^(NSError *error) { record(nil, error); };
    } else if (arity == 2) {
        completion = record;
    } else {
        return nil;
    }
    switch (arguments) {
        case 2: ((void (*)(id, SEL, id, id))objc_msgSend)(target, selector, params, completion); break;
        case 3: ((void (*)(id, SEL, id, id, id))objc_msgSend)(target, selector, params, nil, completion); break;
        case 4: ((void (*)(id, SEL, id, id, id, id))objc_msgSend)(target, selector, params, nil, nil, completion); break;
        default: return nil;
    }
    *timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0;
    return answer;
}

// The params class a selector takes: the cluster's name, the command's name with its first letter capitalised, and
// Params, as the generator and the SDK name them (MTRColorControlClusterStepHueParams for stepHueWithParams:).
static Class paramsClassFor(NSString *clusterName, NSString *selector)
{
    NSString *verb = [[selector componentsSeparatedByString:@"WithParams"] firstObject];
    if (verb.length == 0 || [verb isEqualToString:selector]) {
        return nil;
    }
    NSString *name = [NSString stringWithFormat:@"MTR%@Cluster%@%@Params", clusterName,
                      [[verb substringToIndex:1] uppercaseString], [verb substringFromIndex:1]];
    return NSClassFromString(name);
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        if (argc < 2) {
            fprintf(stderr, "usage: probe-params-modes <real class name>\n");
            return 2;
        }
        NSString *real = @(argv[1]);
        Class systemClass = NSClassFromString(real);
        if (!systemClass) {
            printf("class\t%s\tMISSING\n", real.UTF8String);
            return 1;
        }
        // The cluster's name: the class name without its MTRBaseCluster or MTRCluster prefix.
        NSString *clusterName = [real hasPrefix:@"MTRBaseCluster"] ? [real substringFromIndex:@"MTRBaseCluster".length]
                                                                    : [real substringFromIndex:@"MTRCluster".length];
        NSMutableDictionary *arity = [NSMutableDictionary dictionary];
        const char *declaredPath = getenv("CHARON_DECLARED");
        if (!declaredPath) {
            printf("RED not read: CHARON_DECLARED is unset\n");
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
        BOOL base = [real hasPrefix:@"MTRBaseCluster"];
        id device = base ? [MTRBaseDevice deviceWithNodeID:@4660 controller:controller]
                         : [MTRDevice deviceWithNodeID:@4660 controller:controller];
        [controller shutdown];

        dispatch_queue_t queue = dispatch_queue_create("probe-params-modes", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue, queueKey, (void *)1, NULL);
        id cluster = ((id (*)(id, SEL, id, id, id))objc_msgSend)([systemClass alloc],
            NSSelectorFromString(@"initWithDevice:endpointID:queue:"), device, @1, queue);
        if (!cluster) {
            printf("cluster\tnot created\t%s\n", real.UTF8String);
            return 1;
        }

        for (NSString *selector in [[arity allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            int completionArity = [arity[selector] intValue];
            NSUInteger arguments = [selector componentsSeparatedByString:@":"].count - 1;
            if (![selector containsString:@"WithParams"] || arguments < 2 || completionArity == 0) {
                continue;
            }
            Class paramsClass = paramsClassFor(clusterName, selector);
            if (!paramsClass) {
                printf("noparams\t%s\t%s\n", real.UTF8String, selector.UTF8String);
                continue;
            }
            SEL name = NSSelectorFromString(selector);
            if (![cluster respondsToSelector:name]) {
                printf("notcarried\t%s\t%s\n", real.UTF8String, selector.UTF8String);
                continue;
            }
            // The modes: the default initialiser; every field zero; every field one; and, for each field, two kinds:
            // that field zero with the others one ("zero:"), and that field one with the others zero ("one:"). A kind
            // names the field whose zero or one value the framework refuses, if any.
            NSMutableArray *modes = [NSMutableArray arrayWithObjects:@"default", @"zeros", @"ones", @"objones", nil];
            unsigned int propertyCount = 0;
            objc_property_t *props = class_copyPropertyList(paramsClass, &propertyCount);
            for (unsigned int i = 0; i < propertyCount; i++) {
                NSString *name = @(property_getName(props[i]));
                if (!isTransportProperty(name)) {
                    [modes addObject:[NSString stringWithFormat:@"zero:%@", name]];
                    [modes addObject:[NSString stringWithFormat:@"one:%@", name]];
                }
            }
            free(props);
            // Path modes, only for the selectors PROBE_PATH_SELECTORS names (comma-separated substrings): each field of
            // each Matter struct field, zero on its own while everything else is one.
            BOOL pathsWanted = NO;
            const char *filterText = getenv("PROBE_PATH_SELECTORS");
            if (filterText) {
                for (NSString *token in [@(filterText) componentsSeparatedByString:@","]) {
                    if (token.length && [selector containsString:token]) {
                        pathsWanted = YES;
                    }
                }
            }
            if (pathsWanted) {
                objc_property_t *topProps = class_copyPropertyList(paramsClass, &propertyCount);
                for (unsigned int i = 0; i < propertyCount; i++) {
                    NSString *top = @(property_getName(topProps[i]));
                    NSString *attribute = @(property_getAttributes(topProps[i]));
                    if (![attribute hasPrefix:@"T@\"MTR"]) {
                        continue;
                    }
                    Class childClass = NSClassFromString([[attribute substringFromIndex:3] componentsSeparatedByString:@"\""].firstObject);
                    if (!childClass) {
                        continue;
                    }
                    unsigned int childCount = 0;
                    objc_property_t *childProps = class_copyPropertyList(childClass, &childCount);
                    for (unsigned int j = 0; j < childCount; j++) {
                        NSString *child = @(property_getName(childProps[j]));
                        if (!isTransportProperty(child)) {
                            [modes addObject:[NSString stringWithFormat:@"path:%@.%@", top, child]];
                        }
                    }
                    free(childProps);
                }
                free(topProps);
            }
            // Nil modes, only for the selectors PROBE_NIL_SELECTORS names (same matching): each top-level field nil on its
            // own while everything else is one. Unlike "zero:", no other field is zero, so a refusal is the nil field's.
            const char *nilText = getenv("PROBE_NIL_SELECTORS");
            BOOL nilsWanted = NO;
            if (nilText) {
                for (NSString *token in [@(nilText) componentsSeparatedByString:@","]) {
                    if (token.length && [selector containsString:token]) {
                        nilsWanted = YES;
                    }
                }
            }
            if (nilsWanted) {
                objc_property_t *nilProps = class_copyPropertyList(paramsClass, &propertyCount);
                for (unsigned int i = 0; i < propertyCount; i++) {
                    NSString *name = @(property_getName(nilProps[i]));
                    if (!isTransportProperty(name)) {
                        [modes addObject:[NSString stringWithFormat:@"nil:%@", name]];
                    }
                }
                free(nilProps);
            }
            for (NSString *mode in modes) {
                id params = [[paramsClass alloc] init];
                if ([mode isEqualToString:@"zeros"]) {
                    fillParams(params, YES, nil, nil);
                } else if ([mode isEqualToString:@"ones"]) {
                    fillParams(params, NO, nil, nil);
                } else if ([mode hasPrefix:@"zero:"]) {
                    fillParams(params, NO, [mode substringFromIndex:@"zero:".length], nil);
                } else if ([mode hasPrefix:@"one:"]) {
                    fillParams(params, NO, nil, [mode substringFromIndex:@"one:".length]);
                } else if ([mode hasPrefix:@"nil:"]) {
                    nilField = [mode substringFromIndex:@"nil:".length];
                    fillParams(params, NO, nil, nil);
                    nilField = nil;
                } else if ([mode isEqualToString:@"objones"]) {
                    fillObjects = YES;
                    fillParams(params, NO, nil, nil);
                    fillObjects = NO;
                } else if ([mode hasPrefix:@"path:"]) {
                    fillObjects = YES;
                    zeroPath = [mode substringFromIndex:@"path:".length];
                    fillParams(params, NO, nil, nil);
                    zeroPath = nil;
                    fillObjects = NO;
                }
                BOOL timedOut = NO;
                ProbeAnswer *answer = callWithParams(cluster, name, params, arguments, completionArity, queue, &timedOut);
                printf("%s\t%s\t%s\t%s\n", selector.UTF8String, mode.UTF8String, NSStringFromClass(paramsClass).UTF8String,
                       answer ? answerLine(answer, timedOut).UTF8String : "not called");
            }
        }
    }
    return 0;
}
