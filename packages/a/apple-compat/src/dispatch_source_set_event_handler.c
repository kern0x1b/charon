#include "dispatch_block.h"

/* A source whose event handler is a barrier block runs the handler as a barrier on its target queue from iOS 10
   (libdispatch-703 marks the source DQF_BARRIER_BIT); the release's runs it beside the queue's other blocks. So the release
   is given a handler that holds the source and submits the block as a barrier to the queue the handler runs on, which
   dispatch_get_current_queue answers there (libdispatch-228's _dispatch_source_invoke calls the handler only on the
   source's target queue, and no other call names that queue); the source goes on once the block has run. It delivers
   nothing while it is held, so dispatch_source_get_data in the block answers the event it was called for, and events that
   come meanwhile are merged into the next one, as they are while a handler runs.

   It answers as Darwin does on a concurrent target queue, for a handler set before the source's first resume. It differs
   in three configurations, measured against Darwin's own calls on the host (tests/compat_test.py, DISPATCH_BARRIERS,
   "source differences"), because no public call says whether a queue is serial or a source activated: dispatch/queue.h,
   source.h and object.h of the macOS and the iPhoneOS 16.4 SDKs have setters of a target queue and no getter, and the
   header route (renaming dispatch_queue_create, dispatch_resume and the rest, as dispatch_async is renamed) would record
   only what one program's own code made, and go stale on a later dispatch_set_target_queue:
   - a serial target queue: Darwin runs the handler in its place in the queue (event, then blocks A and B: H A B); the
     barrier means nothing there, and the block submitted to the tail runs after them (A B H);
   - a handler set after the source's first resume: libdispatch-703 sets the barrier only in _dispatch_source_finalize_activation
     (source.c:805-806) and _dispatch_source_set_handler never sets it again, so Darwin runs such a handler beside the
     queue's blocks; here it is a barrier as well (the stronger guarantee);
   - the source's other handlers: libdispatch-703's barrier belongs to the source, so its cancellation and registration
     handlers run alone too; here only the event handler is covered.
   coordination/crutches.md, "apple-compat: a barrier source handler below iOS 10 differs from Darwin's in three configurations". */
__attribute__((visibility("hidden")))
void charon_dispatch_source_set_event_handler(dispatch_source_t source, dispatch_block_t handler)
{
    if (!handler || !charon_block_unseen_barrier(handler)) {
        dispatch_source_set_event_handler(source, handler);
        return;
    }
    dispatch_source_set_event_handler(source, ^{
        /* dispatch_get_current_queue is deprecated since iOS 6 in the SDK and exported by every libdispatch of the
           releases these shims run on (libdispatch-228 has it); it is the documented call that names the queue a block runs on. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        dispatch_queue_t target = dispatch_get_current_queue();
#pragma clang diagnostic pop
        dispatch_suspend(source);
        dispatch_retain(source);
        dispatch_barrier_async(target, ^{
            handler();
            dispatch_resume(source);
            dispatch_release(source);
        });
    });
}
