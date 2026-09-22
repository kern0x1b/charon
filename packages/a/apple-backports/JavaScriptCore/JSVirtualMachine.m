#import "JSInternal.h"

/*
 * A JSVirtualMachine is a JSContextGroupRef and, per the header, a graph of managed references:
 * -addManagedReference:withOwner: exists so an external Objective-C object graph keeps a JSValue
 * alive for as long as the graph itself is reachable. The real engine folds that into its
 * garbage collector; this backport has no such collector to fold into; it keeps the same
 * contract (a reference lasts until removed, or until the owner is deallocated) with a plain
 * retaining map instead, which is the same lifetime for the one thing the reference exists to
 * protect - a JSManagedValue's underlying JSValue.
 */

@interface JSVirtualMachine ()
{
    JSContextGroupRef _group;
    NSMapTable<id, NSMutableSet *> *_managedByOwner;
    NSLock *_lock;
}
@end

@implementation JSVirtualMachine

- (instancetype)init
{
    return [self initWithCharonGroup:JSContextGroupCreate() retained:NO];
}

/*
 * `retained` is NO when the group is a fresh one just created for us (this owns the sole
 * reference), YES when adopting the group of a JSGlobalContextRef handed in through
 * +[JSContext contextWithJSGlobalContextRef:] (some other owner already holds a reference, so
 * this must take its own with JSContextGroupRetain rather than borrow theirs).
 */
- (instancetype)initWithCharonGroup:(JSContextGroupRef)group retained:(BOOL)retained
{
    if ((self = [super init])) {
        _group = group;
        if (retained)
            JSContextGroupRetain(_group);
        _managedByOwner = [NSMapTable weakToStrongObjectsMapTable];
        _lock = [NSLock new];
    }
    return self;
}

- (void)dealloc
{
    JSContextGroupRelease(_group);
}

- (JSContextGroupRef)charon_group
{
    return _group;
}

- (void)addManagedReference:(id)object withOwner:(id)owner
{
    if (!object || !owner)
        return;
    [_lock lock];
    NSMutableSet *kept = [_managedByOwner objectForKey:owner];
    if (!kept) {
        kept = [NSMutableSet set];
        [_managedByOwner setObject:kept forKey:owner];
    }
    [kept addObject:object];
    [_lock unlock];
}

- (void)removeManagedReference:(id)object withOwner:(id)owner
{
    if (!object || !owner)
        return;
    [_lock lock];
    [[_managedByOwner objectForKey:owner] removeObject:object];
    [_lock unlock];
}

@end
