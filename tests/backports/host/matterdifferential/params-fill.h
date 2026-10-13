// matterdifferential/params-fill.h - the params objects the matterdifferential programs call the framework and the port
// with, and the call that reads the completion's answer. probe-params-modes.m and commands.m both include it, so a
// refusal check and a probe of the same mode build the same object.
//
// The modes are the probe's own names: default (every property nil), zeros, ones, objones (the struct properties filled
// with ones), zero:<p> and one:<p> (that property zero or one, the others the other value), nil:<p> (that property nil,
// the others one), and path:<s>.<f> (the struct s filled with ones except its field f, which is zero). zero: and one:
// leave the other properties set, so a refusal can be the other properties' and not the named one's; nil: and path: are
// the modes that separate the two.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const void *queueKey = &queueKey;

// What one completion received.
@interface MatterAnswer : NSObject
@property (nonatomic) int calls;
@property (nonatomic) BOOL onQueue;
@property (nonatomic) BOOL dataWasNil;
@property (nonatomic, strong) NSError *error;
@end
@implementation MatterAnswer
@end

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
            [params setValue:nil forKey:name];
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
            // An object property this mode does not fill is set to nil, not left as the initialiser made it: -init stores a
            // child struct, and a member the mode names nil is then not nil.
            if ([attribute hasPrefix:@"T@\""]) {
                [params setValue:nil forKey:name];
            }
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

// The params object of one mode, built as the probe measured it: the default initialiser for "default", and the fills
// named above for the rest.
static id paramsForMode(Class paramsClass, NSString *mode)
{
    id params = [[paramsClass alloc] init];
    // Every object property starts nil, whatever the initialiser stored (-init makes the child structs): the default mode is
    // every property nil, as the probe's header says, and the other modes fill from there.
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(paramsClass, &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = @(property_getName(props[i]));
        if (!isTransportProperty(name) && [@(property_getAttributes(props[i])) hasPrefix:@"T@\""]) {
            [params setValue:nil forKey:name];
        }
    }
    free(props);
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
    return params;
}

// One call of `selector` on `target`: params first when the selector takes more than the completion (nil when the caller
// passes none), nil for the arguments between, and the completion last, built for the arity the SDK declares for it. The
// block is built for that arity, because a block called with fewer arguments than it takes reads whatever was in the
// register. Returns nil when the selector takes more arguments than this passes.
static MatterAnswer *invokeAnswer(id target, SEL selector, id params, NSUInteger arguments, int arity,
                                  dispatch_queue_t queue, BOOL *timedOut)
{
    MatterAnswer *answer = [[MatterAnswer alloc] init];
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
        case 2: ((void (*)(id, SEL, id, id))objc_msgSend)(target, selector, params, completion); break;
        case 3: ((void (*)(id, SEL, id, id, id))objc_msgSend)(target, selector, params, nil, completion); break;
        case 4: ((void (*)(id, SEL, id, id, id, id))objc_msgSend)(target, selector, params, nil, nil, completion); break;
        case 5: ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(target, selector, params, nil, nil, nil, completion);
            break;
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

