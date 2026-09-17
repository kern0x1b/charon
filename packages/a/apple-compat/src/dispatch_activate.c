#include <dispatch/dispatch.h>
#include <objc/runtime.h>
#include "system_function.h"

/* The Objective-C runtime is not part of libSystem; the image that pulls this shim in links it. */
__asm__(".linker_option \"-lobjc\"");

static _Atomic(uintptr_t) charon_system_activate;

__attribute__((constructor))
static void charon_resolve_activate(void)
{
    charon_system_function(&charon_system_activate, CHARON_LIBDISPATCH, "dispatch_activate");
}

static char charon_activated;

/* Inactive objects arrived in iOS 10. Before, of what dispatch_activate is called on only a source starts inactive: created
   suspended, it waits for the one resume activation gives it. Queues start active, and activating an active object does nothing.
   The source remembers its activation on itself (dispatch objects are Objective-C objects from iOS 6 on), so a second call
   does not resume it twice. */
__attribute__((visibility("hidden")))
void charon_dispatch_activate(void *object) __asm("_dispatch_activate");

void charon_dispatch_activate(void *object)
{
    void (*system)(void *) = charon_system_function(&charon_system_activate, CHARON_LIBDISPATCH, "dispatch_activate");
    if (system) {
        system(object);
        return;
    }
    Class source = objc_getClass("OS_dispatch_source");
    Class kind = object_getClass((id)object);
    while (kind && kind != source)
        kind = class_getSuperclass(kind);
    if (!kind || !source)
        return;
    static dispatch_once_t once;
    static dispatch_semaphore_t guard;
    dispatch_once(&once, ^{
        guard = dispatch_semaphore_create(1);
    });
    dispatch_semaphore_wait(guard, DISPATCH_TIME_FOREVER);
    int first = objc_getAssociatedObject((id)object, &charon_activated) == nil;
    if (first)
        objc_setAssociatedObject((id)object, &charon_activated, (id)object_getClass((id)object), OBJC_ASSOCIATION_ASSIGN);
    dispatch_semaphore_signal(guard);
    if (first)
        dispatch_resume((dispatch_source_t)object);
}
