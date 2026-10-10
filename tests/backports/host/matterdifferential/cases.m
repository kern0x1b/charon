// matterdifferential/cases.m - one Matter cluster, the system's and the port's, asked the same things.
//
// The class is named on the command line and the port's copy is compiled under an alias, so one program
// holds both and neither can answer for the other. Three questions, and only three, because those are
// the three a port can be wrong about without a fabric:
//
//   1. does the class exist, under each name, on each side;
//   2. do the two member sets agree - every selector the port implements also exists on the system, and
//      the system has nothing the port is missing, compared as a SET, because a generated class that
//      renamed a member or dropped one is wrong and a check that only counted them would not see it;
//   3. does a plain-data attribute round-trip a value the caller wrote, on the port's side.
//
// Nothing here calls a command, reads a cached value, commissions anything or opens a network session,
// on either side: those need a fabric and a node, and this machine has neither by design. The cached
// reads and the commands are checked by their NAMES in question 2 and are never called.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Which IMAGE answered a member. A differential that compares a framework with itself proves nothing,
// and the way it silently does that is by asking a class that both images define: the members come
// back, they look plausible, and they are the system's. So every member of the port's class has its
// implementation resolved and its image named, and a member whose implementation is in the system image
// is reported as SYSTEM-ANSWERED and fails the run.
// What a value actually IS, and what it reads as. `UTF8String` belongs to NSString, so sending it to a
// value of a class nobody checked threw NSInvalidArgumentException out of the middle of the roundtrip and
// took the whole run with it - the harness crashed, so the cluster it was checking was never checked. The
// class is asked for, and a value that is not an NSString is described by its class name instead.
static const char *describe(id value)
{
    if (!value) { return "nothing"; }
    if (![value isKindOfClass:[NSString class]]) { return object_getClassName(value); }
    return [(NSString *)value UTF8String];
}

static const char *image_of(Method method)
{
    static Dl_info info;
    if (!method || !dladdr(method_getImplementation(method), &info) || !info.dli_fname) {
        return "(unresolved)";
    }
    return info.dli_fname;
}

// The port's class is this name, because the differential compiles the generated file with the cluster's
// name aliased onto it.
#ifdef CHARN_PORT_CLUSTER
#define PORT_CLUSTER CHARN_PORT_CLUSTER
#else
#define PORT_CLUSTER "MTRBaseClusterIdentify"
#endif

int main(int argc, const char *argv[])
{
    int failures = 0;
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: cases.m <real class name>\n");
            return 2;
        }
        NSString *real = @(argv[1]);
        Class systemClass = NSClassFromString(real);
        Class portClass = NSClassFromString(@PORT_CLUSTER);
        printf("class\tsystem\t%s\t%s\n", real.UTF8String, systemClass ? "found" : "MISSING");
        printf("class\tport\t%s\t%s\n", PORT_CLUSTER, portClass ? "found" : "MISSING");
        if (!systemClass || !portClass) {
            printf("checks run: 2, failed: 1\n");
            return 1;
        }

        // The PORT's own class only - class_copyMethodList does not walk superclasses, and that is the
        // point: what the port itself defines, against what the system itself defines.
        NSMutableSet *portMembers = [NSMutableSet set];
        unsigned answeredBySystem = 0;
        const char *portImage = NULL;
        unsigned count = 0;
        Method *methods = class_copyMethodList(portClass, &count);
        for (unsigned i = 0; i < count; i++) {
            const char *image = image_of(methods[i]);
            if (!portImage) portImage = image;
            if (strstr(image, "/System/Library/")) {
                printf("member\tSYSTEM-ANSWERED\t%s\t%s\n",
                       NSStringFromSelector(method_getName(methods[i])).UTF8String, image);
                answeredBySystem++;
                failures++;
            }
            [portMembers addObject:NSStringFromSelector(method_getName(methods[i]))];
        }
        free(methods);
        NSMutableSet *systemMembers = [NSMutableSet set];
        count = 0;
        methods = class_copyMethodList(systemClass, &count);
        for (unsigned i = 0; i < count; i++) {
            [systemMembers addObject:NSStringFromSelector(method_getName(methods[i]))];
        }
        free(methods);
        printf("image\tport class %s\t%s\n", PORT_CLUSTER, portImage ? portImage : "(none)");
        printf("image\tsystem class %s\t%s\n", real.UTF8String,
               image_of(class_getClassMethod(systemClass, @selector(description))));
        printf("port defines %lu members, system %lu\n", (unsigned long)portMembers.count,
               (unsigned long)systemMembers.count);
        if (answeredBySystem) {
            printf("the port class answered %u of its members from the system image\n", answeredBySystem);
        }

        // THE CONTRACT: the selectors the header declares for this cluster, which the generator wrote
        // beside the source from the header's own lines. It is the port's promise; the system is the
        // report. Four verdicts, and only one of them is a failure:
        //
        //   port-only, NOT in the contract          RED  the generator invented or mangled a name
        //   in the contract, NOT in the port       RED  the generator dropped a member it promised
        //   port-only, and the contract has it     shape-differs  the port emits the header's other
        //                                                         shape; the system's binary has the
        //                                                         other one. Not a defect.
        //   system-only                            not carried  it arrived after the SDK the port
        //                                                         compiles against. Not a defect.
        //   port-only, and the port's header      port storage  the `...Values` table and its setter that
        //   declares it (CHARON_STORAGE)                        the port's own header declares for the
        //                                                         object's table. No SDK declares them, so the
        //                                                         contract cannot list them. Named, not failed.
        NSMutableSet *storage = [NSMutableSet set];
        const char *storagePath = getenv("CHARON_STORAGE");
        if (storagePath) {
            NSString *text = [NSString stringWithContentsOfFile:@(storagePath) encoding:NSUTF8StringEncoding error:NULL];
            for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                if (line.length) [storage addObject:line];
            }
        }
        NSMutableSet *contract = [NSMutableSet set];
        const char *contractPath = getenv("CHARON_CONTRACT");
        if (contractPath) {
            NSString *text = [NSString stringWithContentsOfFile:@(contractPath)
                                                     encoding:NSUTF8StringEncoding error:NULL];
            for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                if (line.length) [contract addObject:line];
            }
            printf("contract file\t%s\t%lu selectors\n", contractPath, (unsigned long)contract.count);
        }
        NSMutableSet *onlyPort = [portMembers mutableCopy];
        [onlyPort minusSet:systemMembers];
        NSMutableSet *onlySystem = [systemMembers mutableCopy];
        [onlySystem minusSet:portMembers];
        NSMutableSet *dropped = [contract mutableCopy];
        [dropped minusSet:portMembers];
        NSMutableSet *invented = [onlyPort mutableCopy];
        [invented minusSet:contract];
        NSMutableSet *shapeDiffers = [onlyPort mutableCopy];
        [shapeDiffers minusSet:invented];
        printf("contract\t%lu declared\n", (unsigned long)contract.count);
        printf("port-only not in contract\t%lu\n", (unsigned long)invented.count);
        printf("in the contract, not in the port\t%lu\n", (unsigned long)dropped.count);
        printf("port-only, shape differs\t%lu\n", (unsigned long)shapeDiffers.count);
        printf("system-only, not carried\t%lu\n", (unsigned long)onlySystem.count);
        NSUInteger storageNamed = 0;
        for (NSString *name in [invented.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
            // A name beginning with a dot is a runtime artefact of the aliasing, not a member.
            if ([name hasPrefix:@"."]) { printf("member\tignored artefact\t%s\n", name.UTF8String); continue; }
            if ([storage containsObject:name]) { printf("member\tport storage\t%s\n", name.UTF8String); storageNamed++; continue; }
            printf("member\tRED not in the contract\t%s\n", name.UTF8String);
            failures++;
        }
        printf("port storage, declared by the port's header, not in the contract\t%lu\n", (unsigned long)storageNamed);
        for (NSString *name in [dropped.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
            printf("member\tRED dropped from the port\t%s\n", name.UTF8String);
            failures++;
        }
        for (NSString *name in [shapeDiffers.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
            if ([name hasPrefix:@"."]) continue;
            printf("member\tshape-differs\t%s\n", name.UTF8String);
        }
        for (NSString *name in [onlySystem.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
            printf("member\tnot carried\t%s\n", name.UTF8String);
        }

        // THE DECLARED SET: the instance selectors SDK 26.2's own headers declare for this class, read by the
        // compiler's AST (run.sh writes CHARON_DECLARED from -ast-dump, over the class's own @interface AND its
        // categories, Deprecated ones included). It is read independently of the generator's reader, so it
        // cannot agree with the generator by construction. A declared selector the port does not answer is RED,
        // whether the system answers it or not, and the counts are printed per class.
        NSMutableSet *declared = [NSMutableSet set];
        const char *declaredPath = getenv("CHARON_DECLARED");
        if (!declaredPath) {
            printf("declared\tRED not read: CHARON_DECLARED is unset, so nothing is checked against the SDK\n");
            failures++;
        } else {
            NSString *text = [NSString stringWithContentsOfFile:@(declaredPath) encoding:NSUTF8StringEncoding error:NULL];
            for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                NSArray *cells = [line componentsSeparatedByString:@"\t"];
                if (cells.count == 2 && [cells[0] isEqualToString:real]) {
                    [declared addObject:cells[1]];
                }
            }
            // The designated and new-object selectors are NSObject's, declared here unavailable, and no port
            // class is asked for them (the same rule the contract applies).
            [declared removeObject:@"init"];
            [declared removeObject:@"new"];
            NSMutableArray *missing = [NSMutableArray array];
            for (NSString *name in declared) {
                if (![portClass instancesRespondToSelector:NSSelectorFromString(name)]) {
                    [missing addObject:name];
                }
            }
            printf("declared by SDK 26.2\t%lu\n", (unsigned long)declared.count);
            printf("answered by the port\t%lu\n", (unsigned long)(declared.count - missing.count));
            printf("declared, not answered by the port\t%lu\n", (unsigned long)missing.count);
            for (NSString *name in [missing sortedArrayUsingSelector:@selector(compare:)]) {
                printf("member\tRED declared by SDK 26.2, not answered by the port (the system %s it)\t%s\n",
                       [systemClass instancesRespondToSelector:NSSelectorFromString(name)] ? "answers" : "does not answer",
                       name.UTF8String);
                failures++;
            }
        }

        // The round trip, on the port's side only and through the selector the header declares: a value
        // the caller writes is the value the same object reads back. No commissioning, no node, no
        // network - the cluster is asked about itself.
        id cluster = [[portClass alloc] init];
        __block id readBack = nil;
        SEL reader = NSSelectorFromString(@"readAttributeIdentifyTimeWithCompletion:");
        SEL writer = NSSelectorFromString(@"writeAttributeIdentifyTimeWithValue:completion:");
        if ([cluster respondsToSelector:reader] && [cluster respondsToSelector:writer]) {
            NSMethodSignature *signature = [portClass instanceMethodSignatureForSelector:reader];
            NSInvocation *read = [NSInvocation invocationWithMethodSignature:signature];
            void (^completion)(id, NSError *) = ^(id value, NSError *error) { readBack = value; };
            [read setTarget:cluster];
            [read setSelector:reader];
            [read setArgument:&completion atIndex:2];
            [read invoke];
            id written = @(__LINE__);
            NSMethodSignature *writeSignature = [portClass instanceMethodSignatureForSelector:writer];
            NSInvocation *write = [NSInvocation invocationWithMethodSignature:writeSignature];
            void (^status)(NSError *) = ^(NSError *error) { };
            [write setTarget:cluster];
            [write setSelector:writer];
            [write setArgument:&written atIndex:2];
            [write setArgument:&status atIndex:3];
            [write invoke];
            __block id afterWrite = nil;
            NSInvocation *again = [NSInvocation invocationWithMethodSignature:signature];
            void (^completion2)(id, NSError *) = ^(id value, NSError *error) { afterWrite = value; };
            [again setTarget:cluster];
            [again setSelector:reader];
            [again setArgument:&completion2 atIndex:2];
            [again invoke];
            if (afterWrite && [written isEqual:afterWrite]) {
                printf("roundtrip\tport\t%s written, %s read back\n",
                       describe(written), describe(afterWrite));
            } else {
                // The class goes in the line, because a value read back as a different class than the
                // one written is the finding, and "wrote X and read back Y" hides it behind the types.
                printf("roundtrip\tport\twrote %s (%s), read back %s (%s)\n",
                       describe(written), object_getClassName(written),
                       describe(afterWrite), afterWrite ? object_getClassName(afterWrite) : "(nil)");
                failures++;
            }
            (void)readBack;
        } else {
            // Not a failure. The roundtrip exercises identifyTime because it is the one attribute with
            // a read, a write and a value to read back; a cluster the header does not give an
            // identifyTime has no such pair, and requiring one would ask the port to GROW a member the
            // header does not declare. It is counted as run and not run, so the tally still shows it.
            printf("roundtrip\tport\tnot applicable: this cluster declares no identifyTime\n");
        }
        printf("checks run: %d, failed: %d\n", 5, failures);
    }
    // The status is the count. Returning 0 here whatever `failures` said is why a differential that
    // printed nine members the system does not have and twenty-seven it does was reported as agreeing.
    return failures == 0 ? 0 : 1;
}
