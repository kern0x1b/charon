#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/* The per-task delegate of iOS 15.0.

   NSURLSessionTask's -delegate is the one delegate a caller sets on a task rather than on a session, and
   a task that has one is sent the task-scoped messages instead of the session's. The class already
   declares the property (@dynamic delegate, in NSURLSession.m) and nothing implemented it, so a task
   answered the accessor with doesNotRecognizeSelector:.

   The accessors are the value in an associated object, the way NSURLSessionTask+Priority.m keeps that
   property's: a category cannot add an ivar, and the SDK's own declaration of the property is
   (nullable, retain), so the association retains. The messages are the other half and are not the
   accessors' business, so they are read through charon_task_delegate() in NSURLSession.m, which every
   task-scoped send there asks before the session's own delegate.

   Measured against the system's own Foundation by tests/backports/host/attributed15/run.sh, where the
   port's accessors and the system's answer beside each other: a fresh task has no delegate of its own
   although its session has one, a delegate set on the task reads back, and it is held for as long as
   the caller holds it and not longer. */

static char CharonTaskDelegateKey;

@implementation NSURLSessionTask (CharonTaskDelegate15)

- (id<NSURLSessionTaskDelegate>)delegate
{
    return objc_getAssociatedObject(self, &CharonTaskDelegateKey);
}

- (void)setDelegate:(id<NSURLSessionTaskDelegate>)delegate
{
    objc_setAssociatedObject(self, &CharonTaskDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
