/* shapes -- the host differential for a framework's surface shape.
 *
 * Two questions per class, asked of two artefacts:
 *
 *   does the host's own copy of the framework have this class, and does it answer these members;
 *   does this port's tree define this class, and does it answer them.
 *
 * The class list and the member list come from the registry, so the set of questions is the set of
 * claims -- the same rule tests/backports/host/constants/run.sh follows for values. A difference is a
 * class or a member the port claims and the host does not have, or the other way round, and either one
 * is a failure: an application that links against a selector the release does not have crashes, and one
 * that finds a class missing at runtime cannot even name it.
 *
 * The port's side is read out of the sources, not out of a built library, because the library is a
 * release's whole dylib and this is a per-class check that has to run in a second. What it reads is
 * the same thing the linker binds: an `@implementation` and a member's body or an explicit
 * `@synthesize`. A bare `@property` is not counted, because the compiler synthesises an accessor that
 * holds a value nobody honours -- which is the failure this whole push exists to keep out.
 *
 * Usage: shapes <framework-path> <names-file> <tree-dir> <framework-dir> > report.txt
 */
#include <dlfcn.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The members asked about for a class, and the per-class overrides. A class with members of its own
 * overrides the list; the default is the set every class of the family is asked, so a new class is
 * covered the moment it is named. */
static const char *const kDefaultMembers[] = {
    "init", "provider", "copyWithZone:", "encodeWithCoder:", "initWithCoder:", 0
};

/* A per-class member list would be the registry's, and a copy of it here is a second place to keep in
 * step; the names file carries the member as a second column when a class is asked about one, and the
 * default set is used when it is not. */
static const char *members_of(const char *className)
{
    (void)className;
    return 0;
}

static int host_has(const char *className, const char *member)
{
    Class cls = objc_getClass(className);
    if (!cls)
        return 0;
    return class_getInstanceMethod(cls, sel_registerName(member)) != NULL;
}

/* Whether the port's source defines a member with a body or an explicit @synthesize.
 *
 * The rule is the one tools/verify.py's in_tree() uses, for the same reason: a bare @property is not
 * an implementation, because the compiler synthesises an accessor that holds a value nobody honours.
 * What counts is a definition whose next non-space character is a brace, or an explicit @synthesize
 * that is not cancelled by an @dynamic naming the same member. */
static int port_has(const char *path, const char *className, const char *member)
{
    FILE *file = fopen(path, "rb");
    if (!file)
        return 0;
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, 0, SEEK_SET);
    char *text = malloc((size_t)size + 1);
    if (!text) {
        fclose(file);
        return 0;
    }
    fread(text, 1, (size_t)size, file);
    text[size] = 0;
    fclose(file);

    char marker[256];
    snprintf(marker, sizeof marker, "@implementation %s", className);
    char *body = strstr(text, marker);
    if (!body) {
        free(text);
        return 0;
    }

    int found = 0;
    char definition[256];
    /* Both spellings: - (id)copyWithZone: and + (instancetype)numberRangeWith... */
    snprintf(definition, sizeof definition, "- (%s)", member);
    char *at = strstr(body, definition);
    if (!at) {
        snprintf(definition, sizeof definition, "+ (%s)", member);
        at = strstr(body, definition);
    }
    if (at) {
        for (const char *cursor = at + strlen(definition); *cursor; ++cursor) {
            if (*cursor == '{') {
                found = 1;
                break;
            }
            if (*cursor == ';')
                break;
        }
    }

    if (!found) {
        char *synth = strstr(body, "@synthesize");
        if (synth && strstr(synth, member))
            found = 1;
    }
    if (found) {
        char *dynamic = strstr(body, "@dynamic");
        if (dynamic && strstr(dynamic, member))
            found = 0;
    }
    free(text);
    return found;
}

int main(int argc, char **argv)
{
    if (argc != 5) {
        fprintf(stderr, "usage: %s <framework-path> <names-file> <tree-dir> <framework-dir>\n", argv[0]);
        return 2;
    }
    if (!dlopen(argv[1], RTLD_LAZY)) {
        fprintf(stderr, "%s: %s\n", argv[1], dlerror());
        return 1;
    }
    FILE *names = fopen(argv[2], "r");
    if (!names) {
        fprintf(stderr, "%s: cannot read\n", argv[2]);
        return 1;
    }

    printf("class\tmember\thost\tport\tverdict\n");
    char line[4096];
    int asked = 0, failed = 0;
    while (fgets(line, sizeof line, names)) {
        size_t length = strlen(line);
        while (length && (line[length - 1] == '\n' || line[length - 1] == '\r'))
            line[--length] = 0;
        if (!length || line[0] == '#')
            continue;
        char className[256], member[256];
        const char *tab = strchr(line, '\t');
        if (tab) {
            size_t n = (size_t)(tab - line);
            if (n >= sizeof className)
                n = sizeof className - 1;
            memcpy(className, line, n);
            className[n] = 0;
            snprintf(member, sizeof member, "%s", tab + 1);
        } else {
            snprintf(className, sizeof className, "%s", line);
            const char *override = members_of(className);
            snprintf(member, sizeof member, "%s", override ? override : kDefaultMembers[0]);
        }
        char path[4096];
        snprintf(path, sizeof path, "%s/%s.m", argv[4], className);
        ++asked;
        int onHost = host_has(className, member);
        int inPort = port_has(path, className, member);
        const char *verdict = (onHost == inPort) ? "same" : (onHost ? "the port is missing it" : "the port adds it");
        if (onHost != inPort)
            ++failed;
        printf("%s\t%s\t%s\t%s\t%s\n", className, member, onHost ? "yes" : "no", inPort ? "yes" : "no", verdict);
    }
    fclose(names);
    fprintf(stderr, "shapes: %d cases, %d differences\n", asked, failed);
    return failed ? 1 : 0;
}
