#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>

/* Does the host's own Foundation already have each of these rows?
 *
 * A host differential can only prove the port's own code for an API the host does NOT answer: when
 * the host answers it too, its implementation is the one that runs (measured, with a moved-key
 * mutant, in the report of the NSMutableURLRequest slice), and every assertion becomes a statement
 * about Apple. This probe is the instrument for that question, and it asks the runtime rather than
 * the headers: a selector the class implements, a class or protocol the runtime knows, a constant the
 * image exports.
 *
 * Three controls, one per shape, so a run that examined nothing cannot pass:
 *   -[NSURLSessionTask cancel]                      a selector the host has        -> HAS
 *   -[NSURLSessionTask charonProbeNoSuchSelector]   a planted selector             -> LACKS
 *   NSAttributedString                              a class the host has          -> HAS
 *   NSCharonProbeNoSuchClass                        a planted class                -> LACKS
 */

static int has_instance_method(Class cls, SEL selector)
{
    return cls && class_getInstanceMethod(cls, selector) != NULL;
}

static int has_class_method(Class cls, SEL selector)
{
    return cls && class_getClassMethod(cls, selector) != NULL;
}

static const char *answer(const char *api, const char *kind)
{
    if (strcmp(kind, "class") == 0)
        return NSClassFromString([NSString stringWithUTF8String:api]) ? "HAS" : "LACKS";
    if (strcmp(kind, "protocol") == 0)
        return NSProtocolFromString([NSString stringWithUTF8String:api]) ? "HAS" : "LACKS";
    if (strcmp(kind, "function") == 0 || strcmp(kind, "symbol") == 0 || strcmp(kind, "constant") == 0) {
        char symbol[512];
        snprintf(symbol, sizeof symbol, "_%s", api);
        void *images[] = {
            dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", RTLD_LAZY),
            dlopen("/usr/lib/system/libsystem_trace.dylib", RTLD_LAZY),
            dlopen("/usr/lib/system/libsystem_pthread.dylib", RTLD_LAZY),
            RTLD_DEFAULT,
        };
        for (unsigned i = 0; i < sizeof images / sizeof *images; i++)
            if (images[i] && dlsym(images[i], symbol)) return "HAS";
        return "LACKS";
    }
    if (strcmp(kind, "method") == 0) {
        if (api[0] != '-' && api[0] != '+') return "MALFORMED";
        const char *open = strchr(api, '[');
        const char *close = strchr(api, ']');
        if (!open || !close || close < open) return "MALFORMED";
        char owner[256] = {0}, selector[512] = {0};
        size_t owner_length = (size_t)(strchr(open + 1, ' ') - (open + 1));
        if (owner_length == 0 || owner_length >= sizeof owner) return "MALFORMED";
        memcpy(owner, open + 1, owner_length);
        /* the selector is what follows the space, not the whole bracket: -[NSObject description]
           is the class NSObject and the selector description. */
        const char *selector_start = strchr(open + 1, ' ') + 1;
        if (selector_start <= open + 1 || selector_start > close) return "MALFORMED";
        size_t selector_length = (size_t)(close - selector_start);
        if (selector_length >= sizeof selector) return "MALFORMED";
        memcpy(selector, selector_start, selector_length);
        Class cls = NSClassFromString([NSString stringWithUTF8String:owner]);
        if (!cls) return "LACKS";
        SEL wanted = NSSelectorFromString([NSString stringWithUTF8String:selector]);
        return (api[0] == '+' ? has_class_method(cls, wanted) : has_instance_method(cls, wanted)) ? "HAS" : "LACKS";
    }
    if (strcmp(kind, "property") == 0) {
        const char *dot = strchr(api, '.');
        if (!dot) return "MALFORMED";
        char owner[256] = {0}, member[256] = {0};
        size_t owner_length = (size_t)(dot - api);
        if (owner_length == 0 || owner_length >= sizeof owner) return "MALFORMED";
        memcpy(owner, api, owner_length);
        snprintf(member, sizeof member, "%s", dot + 1);
        Class cls = NSClassFromString([NSString stringWithUTF8String:owner]);
        if (!cls) return "LACKS";
        SEL wanted = NSSelectorFromString([NSString stringWithUTF8String:member]);
        if (has_instance_method(cls, wanted)) return "HAS";
        char setter[300];
        snprintf(setter, sizeof setter, "set%c%s:", (char)toupper((unsigned char)member[0]), member + 1);
        return has_instance_method(cls, NSSelectorFromString([NSString stringWithUTF8String:setter])) ? "HAS" : "LACKS";
    }
    return "MALFORMED";
}

/* --by-owner groups the LACKS rows by the class or protocol they belong to, which is the shape the
   facts file's table is written from: a table of groups that nobody printed is a table that drifts. */
static int print_by_owner(const char *path)
{
    FILE *input = fopen(path, "r");
    if (!input) { printf("FAIL cannot read %s\n", path); return 2; }
    char line[1024];
    unsigned rows = 0, unparsed = 0;
    while (fgets(line, sizeof line, input)) {
        char api[512], kind[64], introduced[32];
        if (sscanf(line, "%511[^\t]\t%63[^\t]\t%31s", api, kind, introduced) != 3) { unparsed++; continue; }
        if (strcmp(answer(api, kind), "LACKS") != 0) continue;
        char owner[256] = {0};
        const char *open = strchr(api, '[');
        const char *dot = strchr(api, '.');
        if (open) {
            const char *space = strchr(open + 1, ' ');
            size_t length = (size_t)(space - (open + 1));
            if (length && length < sizeof owner) { memcpy(owner, open + 1, length); }
        } else if (dot && (size_t)(dot - api) < sizeof owner) {
            size_t length = (size_t)(dot - api);
            memcpy(owner, api, length);
        } else {
            snprintf(owner, sizeof owner, "%s", api);
        }
        printf("%s\n", owner);
        rows++;
    }
    fclose(input);
    printf("# %u rows the host lacks, over this tree\n", rows);
    return unparsed ? 1 : 0;
}

int main(int argc, char **argv)
{
    if (argc > 2 && strcmp(argv[1], "--by-owner") == 0)
        return print_by_owner(argv[2]);
    const char *path = argc > 1 ? argv[1] : NULL;
    if (!path) { printf("usage: host-has-row <tsv of api/kind/introduced>\n"); return 2; }
    printf("CONTROL -[NSURLSessionTask cancel]                       %s\n",
           answer("-[NSURLSessionTask cancel]", "method"));
    printf("CONTROL -[NSURLSessionTask charonProbeNoSuchSelector]    %s\n",
           answer("-[NSURLSessionTask charonProbeNoSuchSelector]", "method"));
    printf("CONTROL NSAttributedString                               %s\n", answer("NSAttributedString", "class"));
    printf("CONTROL NSCharonProbeNoSuchClass                         %s\n", answer("NSCharonProbeNoSuchClass", "class"));
    FILE *input = fopen(path, "r");
    if (!input) { printf("FAIL cannot read %s\n", path); return 2; }
    char line[1024];
    unsigned rows = 0, has = 0, lacks = 0, malformed = 0, input_lines = 0, unparsed = 0;
    /* One loop over every line, the first included: reading the first line outside the loop is how
       a row goes missing from the totals while the summary still says the totals cover the file. */
    while (fgets(line, sizeof line, input)) {
        input_lines++;
        char api[512], kind[64], introduced[32];
        /* A line that does not parse is counted, not skipped: a row this probe never read cannot be
           in its totals, and a summary that says "0 malformed" over 114 of 115 rows has measured
           nothing about the one it dropped. */
        if (sscanf(line, "%511[^\t]\t%63[^\t]\t%31s", api, kind, introduced) != 3) {
            unparsed++;
            printf("UNPARSED\t-\t-\t%s", line);
            continue;
        }
        const char *verdict = answer(api, kind);
        rows++;
        if (strcmp(verdict, "HAS") == 0) has++;
        else if (strcmp(verdict, "LACKS") == 0) lacks++;
        else malformed++;
        printf("%s\t%s\t%s\t%s\n", verdict, kind, introduced, api);
    }
    fclose(input);
    if (input_lines == 0) { printf("FAIL %s is empty: nothing was examined\n", path); return 1; }
    printf("#SUMMARY input_lines=%u parsed=%u has=%u lacks=%u malformed=%u unparsed=%u\n",
           input_lines, rows, has, lacks, malformed, unparsed);
    if (unparsed) {
        printf("FAIL %u line(s) did not parse: the totals above do not cover them\n", unparsed);
        return 1;
    }
    return 0;
}
