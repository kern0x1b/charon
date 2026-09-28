/* host-probe -- the measurement a backported constant's value is checked with.
 *
 * A constant's value is a fact about the release that declares it, and the only way to be sure of one
 * is to ask that release. This asks the host: it opens a framework with dlopen, looks each name up with
 * dlsym, and -- because the symbol is a `NSString *const` whose own bytes are a pointer to the
 * constant string -- walks that object with CFStringGetCString and prints what the release holds.
 *
 * The walk is the part worth being careful about. Reading the pointer with a fixed slide is how a wrong
 * address reads as another string; CFStringGetCString goes through the string's own layout and its own
 * length, and the length it reports is what the value printed is sized to, so a wrong address shows up as
 * a failed conversion rather than as a plausible wrong answer. There is deliberately no CFGetTypeID test
 * first: the isa pointer inside a constant string in a dyld shared cache is stored with the cache's own
 * fixups, so that test answers "not a CFString" for every one of them while the conversion reads the
 * same object correctly.
 *
 * The release half of a constant's provenance is a different measurement and a different tool: this one
 * does not say which iOS release first exported a name, and tools/release-split.lua is what does.
 *
 * Usage:
 *   host-probe <framework-path> <names-file> > constant-values.tsv
 *
 * <names-file> holds one symbol name per line. The TSV it prints carries the columns the ledger's
 * constant-values tables use, so a table this produces and one another band produced are the same
 * shape and diff as one. Names the framework does not export are reported as such and do not stop the
 * run: a name a framework never had is a fact about the framework, and a table with a hole in it says
 * more than a run that stopped at the hole.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The framework the port's own HomeKit and AuthenticationServices come from, when it has no path of
 * its own on disk. The port's HomeKit is a private framework on this machine and lives in the dyld
 * shared cache, which dlopen reaches by its install path. */
static const char *const kDefaultFrameworks[] = {
    "/System/Library/PrivateFrameworks/HomeKit.framework/Versions/A/HomeKit",
    "/System/Library/Frameworks/HomeKit.framework/HomeKit",
    "/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices",
    NULL
};

/* The value of a `NSString *const`: the symbol's own bytes are a pointer to the constant string. The
 * cast goes through void * because a data symbol's type is not the type the declaration says it is at
 * the byte level, and the length is read from the object rather than assumed. */
static const char *value_of(void *symbol, size_t *outLength)
{
    void *const *slot = (void *const *)symbol;
    CFStringRef string = (CFStringRef)*slot;
    if (!string)
        return NULL;
    /* The size comes from the string's own length, and the conversion is one call. CFStringGetCString
     * is not a two-call form: asked with a null buffer it fails, which is how this tool first reported
     * all 255 values as "not a CFString" while the same walk in Objective-C read every one of them. */
    CFIndex length = CFStringGetLength(string);
    char *buffer = malloc((size_t)length + 1);
    if (!buffer)
        return NULL;
    if (!CFStringGetCString(string, buffer, (CFIndex)length + 1, kCFStringEncodingUTF8)) {
        free(buffer);
        return NULL;
    }
    if (outLength)
        *outLength = (size_t)length;
    return buffer;
}

int main(int argc, char **argv)
{
    const char *framework = NULL;
    const char *names = NULL;
    if (argc == 3) {
        framework = argv[1];
        names = argv[2];
    } else if (argc == 2) {
        names = argv[1];
    } else {
        fprintf(stderr, "usage: %s [framework-path] <names-file>\n", argv[0]);
        return 2;
    }

    void *handle = NULL;
    if (framework) {
        handle = dlopen(framework, RTLD_LAZY);
        if (!handle) {
            fprintf(stderr, "%s: %s\n", framework, dlerror());
            return 1;
        }
    } else {
        for (int index = 0; kDefaultFrameworks[index] && !handle; ++index) {
            handle = dlopen(kDefaultFrameworks[index], RTLD_LAZY);
            if (handle)
                framework = kDefaultFrameworks[index];
        }
        if (!handle) {
            fprintf(stderr, "none of the default frameworks opened: %s\n", dlerror());
            return 1;
        }
    }

    FILE *in = strcmp(names, "-") == 0 ? stdin : fopen(names, "r");
    if (!in) {
        fprintf(stderr, "%s: %s\n", names, strerror(errno));
        return 1;
    }

    printf("api\tintroduced\tc-type\tvalue\thow-measured\tsource-binary\tos-build\n");
    char line[4096];
    int asked = 0, missing = 0, notAString = 0;
    while (fgets(line, sizeof line, in)) {
        size_t length = strlen(line);
        while (length && (line[length - 1] == '\n' || line[length - 1] == '\r'))
            line[--length] = 0;
        if (!length || line[0] == '#')
            continue;
        ++asked;
        dlerror();
        void *symbol = dlsym(handle, line);
        if (!symbol) {
            ++missing;
            printf("%s\t-\t-\t-\t%s does not export it\t%s\thost\n", line, framework, framework);
            continue;
        }
        size_t valueLength = 0;
        const char *value = value_of(symbol, &valueLength);
        if (!value) {
            ++notAString;
            printf("%s\t-\t-\t-\texported, and the value is not a CFString\t%s\thost\n", line, framework);
            continue;
        }
        printf("%s\t-\tNSString *const\t%s\t"
               "dlopen + dlsym on the host, decoded through CFStringGetCString as UTF-8\t%s\thost\n",
               line, value, framework);
        free((void *)value);
    }
    if (in != stdin)
        fclose(in);
    fprintf(stderr, "asked %d, %d not exported, %d not a CFString\n", asked, missing, notAString);
    return missing || notAString ? 1 : 0;
}
