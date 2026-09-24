#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

@protocol PointExport <JSExport>
@property (nonatomic) double x;
@property (nonatomic) double y;
- (double)distanceTo:(id)other;
JSExportAs(addTo,
- (double)addTo:(double)a and:(double)b
);
@end

@interface PointObject : NSObject <PointExport>
@property (nonatomic) double x;
@property (nonatomic) double y;
@end

@implementation PointObject
- (double)distanceTo:(id)other
{
    double ox = [other[@"x"] doubleValue];
    double oy = [other[@"y"] doubleValue];
    double dx = self.x - ox, dy = self.y - oy;
    return sqrt(dx * dx + dy * dy);
}
- (double)addTo:(double)a and:(double)b
{
    return a + b;
}
@end

static int failures;

static void check(BOOL condition, NSString *name)
{
    if (condition) {
        printf("ok %s\n", name.UTF8String);
    } else {
        failures++;
        printf("FAIL %s\n", name.UTF8String);
    }
}

/*
 * The collector scans the stack conservatively, so a value is made in a frame of its own and the
 * stack it used is overwritten before collecting. JSSynchronousGarbageCollectForDebugging is the
 * host engine's own exported collect-now entry point; JSGarbageCollect only schedules one.
 */
extern void JSSynchronousGarbageCollectForDebugging(JSContextRef context);

__attribute__((noinline)) static JSManagedValue *ManagedFromScript(JSContext *context, NSString *script)
{
    @autoreleasepool {
        return [JSManagedValue managedValueWithValue:[context evaluateScript:script]];
    }
}

__attribute__((noinline)) static void Collect(JSContext *context)
{
    volatile char stack[16384];
    for (size_t index = 0; index < sizeof(stack); index++)
        stack[index] = 0;
    JSSynchronousGarbageCollectForDebugging(context.JSGlobalContextRef);
}


/* An Objective-C object that owns a managed value, the pattern JSManagedValue.h documents. */
@interface ManagedOwner : NSObject
@property (strong) JSManagedValue *managed;
@end

@implementation ManagedOwner
@end

/*
 * The owner and everything else made here live in this frame only, so that nothing of theirs is
 * left on the stack the collector scans. `global` names a global the owner's wrapper is stored on
 * (reachable from JavaScript), or nil for an owner JavaScript does not reach.
 */
__attribute__((noinline)) static ManagedOwner *OwnerWithManaged(JSContext *context, NSString *global, NSString *script)
{
    @autoreleasepool {
        ManagedOwner *owner = [ManagedOwner new];
        if (global)
            context[global] = owner;
        owner.managed = ManagedFromScript(context, script);
        [context.virtualMachine addManagedReference:owner.managed withOwner:owner];
        return owner;
    }
}

/* The documented leak case: the managed value is a closure that references its owner's wrapper. */
__attribute__((noinline)) static void OwnerOfClosure(JSContext *context, NSString *global, __weak ManagedOwner **weakOwner, __weak JSManagedValue **weakManaged)
{
    @autoreleasepool {
        ManagedOwner *owner = [ManagedOwner new];
        context[@"closureOwner"] = owner;
        JSValue *closure = [context evaluateScript:@"(function (owner) { return function () { return owner; }; })(closureOwner)"];
        owner.managed = [JSManagedValue managedValueWithValue:closure andOwner:owner];
        context[@"closureOwner"] = nil;
        if (global)
            context[global] = owner;
        *weakOwner = owner;
        *weakManaged = owner.managed;
    }
}

__attribute__((noinline)) static void Forget(JSContext *context, NSString *global)
{
    @autoreleasepool {
        context[global] = nil;
    }
}

/*
 * What a managed value reads back: its object's `n`, or -1 once it reads nil. The JSValue a read
 * makes is autoreleased and holds its object strongly, so it is read in a pool of its own.
 */
__attribute__((noinline)) static int ManagedN(JSManagedValue *managed)
{
    @autoreleasepool {
        JSValue *value = managed.value;
        return value ? [value[@"n"] toInt32] : -1;
    }
}

/* Whether a managed closure still answers its owner when called. */
__attribute__((noinline)) static BOOL ClosureAnswersOwner(JSManagedValue *managed, id owner)
{
    @autoreleasepool {
        JSValue *value = managed.value;
        return value && owner && [value callWithArguments:@[]].toObject == owner;
    }
}

/* The Objective-C object a managed wrapper reads back, or nil. */
__attribute__((noinline)) static id WrappedObject(JSManagedValue *managed)
{
    @autoreleasepool {
        return managed.value.toObject;
    }
}

__attribute__((noinline)) static void CheckManagedReferences(JSContext *context)
{
    JSVirtualMachine *vm = context.virtualMachine;

    JSManagedValue *reachable = ManagedFromScript(context, @"globalThis.keptByScript = {n: 1}; keptByScript");
    JSManagedValue *unowned = ManagedFromScript(context, @"({n: 3})");
    ManagedOwner *reachableOwner = OwnerWithManaged(context, @"reachableOwner", @"({n: 2})");
    ManagedOwner *hiddenOwner = OwnerWithManaged(context, nil, @"({n: 4})");
    Collect(context);
    check(ManagedN(reachable) == 1, @"JSManagedValue keeps an object JavaScript still reaches");
    check(ManagedN(unowned) == -1, @"JSManagedValue reads back nil once the collector has taken its object");
    check(ManagedN(reachableOwner.managed) == 2, @"JSManagedValue keeps an object whose owner JavaScript reaches");
    check(ManagedN(hiddenOwner.managed) == -1, @"JSManagedValue does not keep an object whose owner is alive but out of JavaScript's reach");
    Forget(context, @"reachableOwner");
    Collect(context);
    check(ManagedN(reachableOwner.managed) == -1, @"JSManagedValue lets its object go once JavaScript no longer reaches the owner");

    __weak ManagedOwner *weakOwner = nil;
    __weak JSManagedValue *weakManaged = nil;
    OwnerOfClosure(context, nil, &weakOwner, &weakManaged);
    Collect(context);
    check(weakOwner == nil && weakManaged == nil, @"a managed closure over its owner's wrapper does not keep the owner alive");
    OwnerOfClosure(context, @"closureOwnerKept", &weakOwner, &weakManaged);
    Collect(context);
    check(ClosureAnswersOwner(weakManaged, weakOwner), @"a managed closure over its owner's wrapper is kept while JavaScript reaches the owner");
    Forget(context, @"closureOwnerKept");
    Collect(context);
    check(weakOwner == nil && weakManaged == nil, @"the closure and its owner both go once JavaScript lets go of the owner");

    ManagedOwner *twice = OwnerWithManaged(context, @"twiceOwner", @"({n: 5})");
    [vm addManagedReference:twice.managed withOwner:twice];
    [vm removeManagedReference:twice.managed withOwner:twice];
    Collect(context);
    check(ManagedN(twice.managed) == 5, @"a managed reference added twice stays after one removal");
    [vm removeManagedReference:twice.managed withOwner:twice];
    Collect(context);
    check(ManagedN(twice.managed) == -1, @"removeManagedReference: lets the object go");
    Forget(context, @"twiceOwner");

    ManagedOwner *root = OwnerWithManaged(context, @"rootOwner", @"({n: 6})");
    ManagedOwner *middle = OwnerWithManaged(context, nil, @"({n: 7})");
    [vm addManagedReference:middle withOwner:root];
    Collect(context);
    check(ManagedN(middle.managed) == 7, @"an owned Objective-C object passes its owner's reachability on to what it owns");
    [vm removeManagedReference:middle withOwner:root];
    Collect(context);
    check(ManagedN(middle.managed) == -1, @"and stops passing it on once the reference is removed");

    JSManagedValue *other = nil;
    @autoreleasepool {
        root.managed = ManagedFromScript(context, @"globalThis.shared = {n: 8}; shared");
        [vm addManagedReference:root.managed withOwner:root];
        other = [JSManagedValue managedValueWithValue:root.managed.value];
        Forget(context, @"shared");
    }
    Collect(context);
    check(ManagedN(other) == 8, @"a second managed value of an owned object reads it back");
    /* the release's -[JSManagedValue dealloc] reads its own value, autoreleased: release it in a pool */
    @autoreleasepool {
        root.managed = nil;
    }
    Collect(context);
    check(ManagedN(other) == -1, @"a JSManagedValue that is gone no longer keeps its object through its owner");

    NSObject *wrapped = [NSObject new];
    @autoreleasepool {
        context[@"wrappedObject"] = wrapped;
        root.managed = [JSManagedValue managedValueWithValue:context[@"wrappedObject"]];
        [vm addManagedReference:root.managed withOwner:root];
        Forget(context, @"wrappedObject");
    }
    Collect(context);
    check(WrappedObject(root.managed) == wrapped, @"a managed wrapper of an Objective-C object is kept through its owner");
    Forget(context, @"rootOwner");
}

/* The bridge keeps one wrapper per Objective-C object, so identity and expandos survive. */
__attribute__((noinline)) static void CheckWrapperIdentity(JSContext *context)
{
    NSObject *object = [NSObject new];
    context[@"first"] = object;
    context[@"second"] = object;
    check([[context evaluateScript:@"first === second"] toBool], @"the same Objective-C object boxes to the same JavaScript object");
    [context evaluateScript:@"first.expando = 9"];
    context[@"third"] = object;
    check([[context evaluateScript:@"third.expando"] toInt32] == 9, @"a property set on an object's wrapper is still there when it is boxed again");
    [context evaluateScript:@"first = second = third = undefined"];
}

int main(void)
{
    @autoreleasepool {
        JSContext *context = [[JSContext alloc] init];
        check([[context evaluateScript:@"1 + 2"] toInt32] == 3, @"evaluateScript arithmetic");

        context[@"greeting"] = @"hello";
        check([[context[@"greeting"] toString] isEqualToString:@"hello"], @"subscript round trip");

        context[@"add"] = ^(NSNumber *a, NSNumber *b) {
            return @(a.doubleValue + b.doubleValue);
        };
        check([[context evaluateScript:@"add(3, 4)"] toInt32] == 7, @"block boxed as a callable JS function");

        __block NSString *logged = nil;
        context[@"log"] = ^(NSString *line) {
            logged = line;
        };
        JSValue *logResult = [context evaluateScript:@"log('from a block returning void')"];
        check([logged isEqualToString:@"from a block returning void"], @"a block returning void is called with its argument");
        check(logResult.isUndefined, @"a block returning void answers undefined to JavaScript");

        PointObject *point = [PointObject new];
        point.x = 3;
        point.y = 4;
        context[@"origin"] = point;
        JSValue *distance = [context evaluateScript:@"origin.distanceTo({x:0,y:0})"];
        check(fabs([distance toDouble] - 5.0) < 0.0001, @"JSExport instance method, called from JavaScript with a plain object literal argument");
        check([[context evaluateScript:@"origin.addTo(2, 5)"] toInt32] == 7, @"JSExportAs renames the exported selector");
        [context evaluateScript:@"origin.x = 10"];
        check(point.x == 10, @"JSExport property setter mutates the native object");

        NSArray *array = @[@1, @2, @3];
        context[@"arr"] = array;
        check([[context evaluateScript:@"arr.length"] toInt32] == 3, @"NSArray boxed as a JS array");
        check([[context[@"arr"] toArray] isEqualToArray:array], @"JS array round trips back to NSArray");
        check([context[@"arr"] isArray], @"isArray agrees with the JS engine's own Array.isArray");

        NSDictionary *dict = @{@"a": @1, @"b": @2};
        context[@"dict"] = dict;
        check([[context evaluateScript:@"dict.a"] toInt32] == 1, @"NSDictionary boxed as a JS object");

        JSValue *undefinedRead = [context evaluateScript:@"thisNameIsNotDefinedAnywhere"];
        check(context.exception != nil, @"an uncaught reference error lands on context.exception");
        check(undefinedRead.isUndefined, @"a failed evaluation still returns a usable JSValue (undefined)");
        context.exception = nil;

        JSValue *product = [[context evaluateScript:@"(function(a,b){ return a*b; })"] callWithArguments:@[@6, @7]];
        check([product toInt32] == 42, @"callWithArguments invokes a JS function value directly");

        JSManagedValue *managed = nil;
        @autoreleasepool {
            JSValue *five = [JSValue valueWithInt32:5 inContext:context];
            managed = [JSManagedValue managedValueWithValue:five];
            check([managed.value toInt32] == 5, @"JSManagedValue reads back its value while something else retains it");
        }
        check([managed.value toInt32] == 5, @"JSManagedValue keeps a primitive after the JSValue it was made from is released");

        CheckManagedReferences(context);
        CheckWrapperIdentity(context);

        JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
        JSContext *second = [[JSContext alloc] initWithVirtualMachine:vm];
        check(second.virtualMachine == vm, @"a context created with an explicit JSVirtualMachine reports it back");

        printf(failures == 0 ? "checks=all passed\n" : "checks=%d failed\n", failures);
    }
    return failures;
}
