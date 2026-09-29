/* The 18 string constants of the 14.0 counter family, compared BYTE FOR BYTE against Apple's own.
 *
 * APPLE'S COPY IS READ BY dlsym, NOT BY NAMING IT. If the case declared the eighteen externs and read
 * them, the link would bind each name to whichever definition won - the port's or Apple's - and a port
 * that defined all eighteen wrongly would be compared with itself and pass. So the case opens Apple's
 * Metal BY PATH, dlsyms each name THERE, and reads the bytes of what it finds; the port's value is read
 * from the port's own definition. Two independent answers, compared.
 *
 * THREE ANSWERS ARE TOLD APART, because two of them look alike in a boolean:
 *   - a name that is NOT THERE: dlsym returns NULL, and a PLANTED name proves the lookup can say so;
 *   - a name that IS there and holds NULL;
 *   - a name that is there and holds a string, whose LENGTH and BYTES are compared. Comparing
 *     pointer identity, or the text without the length, would pass a string that is a prefix of
 *     Apple's - which is exactly how "PostTessellationCycle" nearly passed for
 *     "PostTessellationVertexCycles" in an earlier revision of this file.
 *
 * NO DEVICE IS CREATED. These are strings; a device is not involved and MTLCreateSystemDefaultDevice()
 * hangs on a machine with no GPU.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <dlfcn.h>
#import <string.h>

/* THE PORT'S OWN DEFINITIONS, read under the name the harness GIVES THEM.

   The port exports these eighteen under Apple's own names, because iOS 6 carries no constant of any
   of them and a caller writes MTLCommonCounterTimestamp. On this host Apple's Metal declares the
   same names, so the harness compiles the port with -D<name>=charonHost_<name> and this case reads
   the port's copy under that name while dlsym reads Apple's. Without the rename the linker would
   bind the extern here to Apple's definition and the case would be comparing Apple's constant with
   itself - which is how a port could define all eighteen wrongly and pass. */
extern MTLCommonCounter const charonHost_MTLCommonCounterClipperInvocations;
extern MTLCommonCounter const charonHost_MTLCommonCounterClipperPrimitivesOut;
extern MTLCommonCounter const charonHost_MTLCommonCounterComputeKernelInvocations;
extern MTLCommonCounter const charonHost_MTLCommonCounterFragmentCycles;
extern MTLCommonCounter const charonHost_MTLCommonCounterFragmentInvocations;
extern MTLCommonCounter const charonHost_MTLCommonCounterFragmentsPassed;
extern MTLCommonCounter const charonHost_MTLCommonCounterPostTessellationVertexCycles;
extern MTLCommonCounter const charonHost_MTLCommonCounterPostTessellationVertexInvocations;
extern MTLCommonCounter const charonHost_MTLCommonCounterRenderTargetWriteCycles;
extern MTLCommonCounterSet const charonHost_MTLCommonCounterSetStageUtilization;
extern MTLCommonCounterSet const charonHost_MTLCommonCounterSetStatistic;
extern MTLCommonCounterSet const charonHost_MTLCommonCounterSetTimestamp;
extern MTLCommonCounter const charonHost_MTLCommonCounterTessellationCycles;
extern MTLCommonCounter const charonHost_MTLCommonCounterTessellationInputPatches;
extern MTLCommonCounter const charonHost_MTLCommonCounterTimestamp;
extern MTLCommonCounter const charonHost_MTLCommonCounterTotalCycles;
extern MTLCommonCounter const charonHost_MTLCommonCounterVertexCycles;
extern MTLCommonCounter const charonHost_MTLCommonCounterVertexInvocations;
static int failures;
static int checks;

static void check(BOOL ok, NSString *what)
{
    checks++;
    if (ok) { printf("  ok   %s\n", [what UTF8String]); }
    else { printf("  FAIL %s\n", [what UTF8String]); failures++; }
}

/* $1 the symbol name, $2 the port's value. Reads APPLE'S by that name, from Apple's own Metal. */
static void same_bytes(void *apple_metal, const char *name, NSString *port)
{
    void *sym = dlsym(apple_metal, name);
    if (sym == NULL) {
        check(NO, ([NSString stringWithFormat:@"%s: the symbol is not in Apple's Metal at all", name]));
        return;
    }
    NSString * const apple = *(NSString * const *)sym;
    if (apple == NULL) {
        check(NO, ([NSString stringWithFormat:@"%s: Apple's symbol is there and holds NULL, which is "
                                          @"not the same as being absent", name]));
        return;
    }
    if (port == nil) {
        check(NO, ([NSString stringWithFormat:@"%s: the port holds NULL where Apple's holds \"%s\"",
                                          name, [apple UTF8String]]));
        return;
    }
    const char *a = [apple UTF8String];
    const char *p = [port UTF8String];
    size_t alen = (a && p) ? strlen(a) : 0, plen = (a && p) ? strlen(p) : 0;
    BOOL same = (a != NULL && p != NULL && alen == plen && memcmp(a, p, alen) == 0);
    check(same, ([NSString stringWithFormat:@"%s: \"%s\" (%zu bytes) is byte for byte Apple's own "
                                            @"\"%s\" (%zu bytes)", name,
                                             p ? p : "", plen, a ? a : "", alen]));
}

int main(void)
{
    @autoreleasepool {
        void *apple_metal = dlopen("/System/Library/Frameworks/Metal.framework/Metal",
                                   RTLD_LAZY | RTLD_NOLOAD);
        if (apple_metal == NULL) {
            apple_metal = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_LAZY);
        }
        if (apple_metal == NULL) {
            check(NO, @"Apple's Metal could not be opened, so no constant can be compared");
            printf("%d failure(s)\n", failures);
            return 1;
        }

        /* THE PLANTED MISSING-NAME CONTROL, first: a name that does not exist must read NULL, and
         * that has to be shown BEFORE the eighteen comparisons, or "NULL" below proves nothing. */
        check(dlsym(apple_metal, "MTLCommonCounterNoSuchNamePlantedForTheControl") == NULL,
              @"the planted control: a name Apple's Metal does not have reads NULL, so a NULL below "
              @"means a missing VALUE and not a missing NAME");
        check(dlsym(apple_metal, "MTLCommonCounterTimestamp") != NULL,
              @"and a name it does have does not read NULL, so the two are told apart");
        same_bytes(apple_metal, "MTLCommonCounterClipperInvocations", charonHost_MTLCommonCounterClipperInvocations);
        same_bytes(apple_metal, "MTLCommonCounterClipperPrimitivesOut", charonHost_MTLCommonCounterClipperPrimitivesOut);
        same_bytes(apple_metal, "MTLCommonCounterComputeKernelInvocations", charonHost_MTLCommonCounterComputeKernelInvocations);
        same_bytes(apple_metal, "MTLCommonCounterFragmentCycles", charonHost_MTLCommonCounterFragmentCycles);
        same_bytes(apple_metal, "MTLCommonCounterFragmentInvocations", charonHost_MTLCommonCounterFragmentInvocations);
        same_bytes(apple_metal, "MTLCommonCounterFragmentsPassed", charonHost_MTLCommonCounterFragmentsPassed);
        same_bytes(apple_metal, "MTLCommonCounterPostTessellationVertexCycles", charonHost_MTLCommonCounterPostTessellationVertexCycles);
        same_bytes(apple_metal, "MTLCommonCounterPostTessellationVertexInvocations", charonHost_MTLCommonCounterPostTessellationVertexInvocations);
        same_bytes(apple_metal, "MTLCommonCounterRenderTargetWriteCycles", charonHost_MTLCommonCounterRenderTargetWriteCycles);
        same_bytes(apple_metal, "MTLCommonCounterSetStageUtilization", charonHost_MTLCommonCounterSetStageUtilization);
        same_bytes(apple_metal, "MTLCommonCounterSetStatistic", charonHost_MTLCommonCounterSetStatistic);
        same_bytes(apple_metal, "MTLCommonCounterSetTimestamp", charonHost_MTLCommonCounterSetTimestamp);
        same_bytes(apple_metal, "MTLCommonCounterTessellationCycles", charonHost_MTLCommonCounterTessellationCycles);
        same_bytes(apple_metal, "MTLCommonCounterTessellationInputPatches", charonHost_MTLCommonCounterTessellationInputPatches);
        same_bytes(apple_metal, "MTLCommonCounterTimestamp", charonHost_MTLCommonCounterTimestamp);
        same_bytes(apple_metal, "MTLCommonCounterTotalCycles", charonHost_MTLCommonCounterTotalCycles);
        same_bytes(apple_metal, "MTLCommonCounterVertexCycles", charonHost_MTLCommonCounterVertexCycles);
        same_bytes(apple_metal, "MTLCommonCounterVertexInvocations", charonHost_MTLCommonCounterVertexInvocations);

        printf("no device was created: %d checks, every constant read from Apple's own Metal by name\n",
               checks);
    }
    if (failures) { printf("%d failure(s)\n", failures); return 1; }
    printf("all checks passed\n");
    return 0;
}
