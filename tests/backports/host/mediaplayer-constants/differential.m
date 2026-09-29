// The value of every constant this port carries, measured from the host's own MediaPlayer and compared
// with what the port carries. The port's objects are compiled with each name renamed to charonHost_*, and
// Apple's own MediaPlayer answers for the unrenamed name beside it: the two values are therefore in ONE
// process, one from this port and one from Apple's own framework, and compared.
//
// A constant is READ, never CALLED. Nothing here touches MPMediaLibrary, MPMediaQuery or a library.
//
// The iOS 6.1.3 cache exports NONE of the 31 MediaPlayer constants, read with the tools in
// charon/tools, which is why the port carries every one of them. That is a per-row fact in the registry,
// not an assumption here, and it is what makes this band's values Apple's to carry.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include <stdio.h>
#include <string.h>

@@DECLS@@

static void *g_handle;
static int g_failures;

static void charonCompareString(NSString *name, NSString *port, NSString *const *apple) {
  const char *p = port ? [port UTF8String] : NULL;
  // apple is a dlsym result and can be NULL ITSELF, not only the value it points at: dereferencing a NULL
  // symbol pointer is a segfault, and that is what the first run did.
  const char *a = (apple && *apple) ? [*apple UTF8String] : NULL;
  if (!a) { printf("MISSING\t%s\tApple's own MediaPlayer has no such symbol\n", [name UTF8String]); g_failures++; return; }
  if (!p) { printf("NULL\t%s\tthe port defines it as NULL\n", [name UTF8String]); g_failures++; return; }
  if (strcmp(p, a) != 0) {
    printf("DIFFERS\t%s\tthe port has %s and Apple's has %s\n", [name UTF8String], p, a);
    g_failures++;
    return;
  }
  printf("OK\t%s\t%s\t", [name UTF8String], p);
  for (const unsigned char *b = (const unsigned char *)p; *b; b++) printf("%02x", *b);
  printf("\n");
}

@@CHECKS@@

int main(void) {
  @autoreleasepool {
    g_handle = dlopen("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer", RTLD_LAZY);
    if (!g_handle) { printf("NO-FRAMEWORK\t%s\n", dlerror()); return 2; }
@@CALLS@@
    // the PLANTED control: a name neither side has, which must be REPORTED and must not pass
    charonCompareString(@"MPNoSuchConstantForTheControl", nil,
                         (NSString *const *)dlsym(g_handle, "MPNoSuchConstantForTheControl"));
    printf("failures\t%d\n", g_failures);
  }
  return g_failures ? 1 : 0;
}
