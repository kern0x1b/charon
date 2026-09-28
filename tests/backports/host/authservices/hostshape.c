/* hostshape -- what the HOST's own copy of a framework answers for a class's members.
 *
 * The host side of the AuthenticationServices shape check, and nothing else: the port's side is read
 * out of the built library by portshape.py, because the port's own objects are armv7 and this host is
 * arm64 -- a library built for another architecture cannot be dlopen'd here, so its method list is read
 * out of the file rather than asked of a runtime that could not load it.
 *
 * Both sides are answered the same way in principle: from the runtime's own view of the class. Here
 * that is class_getInstanceMethod and class_getClassMethod on the class the framework was opened from,
 * so an inherited method counts as present -- which is the control the coordinator asked for: +new comes
 * from NSObject and is visible here, so a port that also inherits +new agrees rather than being reported
 * as missing one.
 *
 * Usage: hostshape <cases-file>
 * cases: <class> TAB <selector> TAB instance|class TAB available|must-be-unavailable
 */
#include <dlfcn.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *open_framework(const char *name)
{
    char path[4096];
    const char *roots[] = {
        "/System/Library/Frameworks/%s.framework/%s",
        "/System/Library/PrivateFrameworks/%s.framework/Versions/A/%s",
        NULL
    };
    for (int index = 0; roots[index]; ++index) {
        snprintf(path, sizeof path, roots[index], name, name);
        void *handle = dlopen(path, RTLD_LAZY);
        if (handle)
            return handle;
    }
    return NULL;
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: %s <framework-name> <cases-file>\n", argv[0]);
        return 2;
    }
    void *handle = open_framework(argv[1]);
    if (!handle) {
        fprintf(stderr, "%s.framework did not open: %s\n", argv[1], dlerror());
        return 1;
    }
    FILE *cases = fopen(argv[2], "r");
    if (!cases) {
        fprintf(stderr, "%s: cannot read\n", argv[2]);
        return 1;
    }

    printf("class\tselector\tkind\tstate\thost\n");
    char line[4096];
    int asked = 0, missing = 0;
    while (fgets(line, sizeof line, cases)) {
        size_t length = strlen(line);
        while (length && (line[length - 1] == '\n' || line[length - 1] == '\r'))
            line[--length] = 0;
        if (!length || line[0] == '#')
            continue;
        char className[256], selector[512], kind[32], state[64];
        if (sscanf(line, "%255[^\t]\t%511[^\t]\t%31[^\t]\t%63s", className, selector, kind, state) != 4) {
            fprintf(stderr, "a case is not four tab-separated fields: %s\n", line);
            fclose(cases);
            return 2;
        }
        ++asked;
        Class cls = objc_getClass(className);
        int present = 0;
        if (cls) {
            SEL sel = sel_registerName(selector);
            present = (strcmp(kind, "class") == 0) ? (class_getClassMethod(cls, sel) != NULL)
                                                  : (class_getInstanceMethod(cls, sel) != NULL);
        }
        if (!present)
            ++missing;
        printf("%s\t%s\t%s\t%s\t%s\n", className, selector, kind, state, present ? "yes" : "no");
    }
    fclose(cases);
    fprintf(stderr, "hostshape: %d cases, %d the host does not answer\n", asked, missing);
    return 0;
}
