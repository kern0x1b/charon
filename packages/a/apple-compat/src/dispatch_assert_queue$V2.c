#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include "system_function.h"

static _Atomic(uintptr_t) charon_system_assert_queue;

__attribute__((constructor))
static void charon_resolve_assert_queue(void)
{
    charon_system_function(&charon_system_assert_queue, CHARON_LIBDISPATCH, "dispatch_assert_queue$V2");
}

static void charon_unmarked(void *unused)
{
    (void)unused;
}

static int charon_global(dispatch_queue_t queue)
{
    static const long priorities[] = {DISPATCH_QUEUE_PRIORITY_HIGH, DISPATCH_QUEUE_PRIORITY_DEFAULT, DISPATCH_QUEUE_PRIORITY_LOW,
                                      DISPATCH_QUEUE_PRIORITY_BACKGROUND};
    for (unsigned index = 0; index < sizeof priorities / sizeof priorities[0]; index++) {
        if (queue == dispatch_get_global_queue(priorities[index], 0) || queue == dispatch_get_global_queue(priorities[index], 0x2))
            return 1;
    }
    return 0;
}

/* The block runs on the queue when the queue is where it runs or a queue it runs on targets it, which dispatch_get_specific
   answers by walking the target chain (iOS 5). The queue is marked under a key only it uses, its address with the low bit set,
   which no object's address is. Global queues take no specifics, so for them only the queue running the block itself counts,
   not a queue that targets them. The main thread holds the main queue, in a block or not, as libdispatch binds it there. */
__attribute__((visibility("hidden")))
void charon_dispatch_assert_queue(dispatch_queue_t queue) __asm("_dispatch_assert_queue$V2");

void charon_dispatch_assert_queue(dispatch_queue_t queue)
{
    void (*system)(dispatch_queue_t) = charon_system_function(&charon_system_assert_queue, CHARON_LIBDISPATCH, "dispatch_assert_queue$V2");
    if (system) {
        system(queue);
        return;
    }
    if (queue == dispatch_get_main_queue()) {
        if (pthread_main_np())
            return;
    } else if (charon_global(queue)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (dispatch_get_current_queue() == queue)
            return;
#pragma clang diagnostic pop
    } else {
        void *key = (void *)((uintptr_t)queue | 1);
        if (dispatch_queue_get_specific(queue, key) != key)
            dispatch_queue_set_specific(queue, key, key, charon_unmarked);
        if (dispatch_get_specific(key) == key)
            return;
    }
    fprintf(stderr, "BUG IN CLIENT OF LIBDISPATCH: Block was expected to execute on queue [%s]\n",
            dispatch_queue_get_label(queue));
    abort();
}
