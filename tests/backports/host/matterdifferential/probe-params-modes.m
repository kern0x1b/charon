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
#import "params-fill.h"

// The answer as commands.m prints it: the count, whether the data was nil, and the error's domain, code and keys.
static NSString *answerLine(MatterAnswer *answer, BOOL timedOut)
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
                id params = paramsForMode(paramsClass, mode);
                BOOL timedOut = NO;
                MatterAnswer *answer = invokeAnswer(cluster, name, params, arguments, completionArity, queue, &timedOut);
                printf("%s\t%s\t%s\t%s\n", selector.UTF8String, mode.UTF8String, NSStringFromClass(paramsClass).UTF8String,
                       answer ? answerLine(answer, timedOut).UTF8String : "not called");
            }
        }
    }
    return 0;
}
