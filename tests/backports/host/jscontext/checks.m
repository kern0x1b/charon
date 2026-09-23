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

static NSString *Run(JSContext *context, NSString *script)
{
    return [[context evaluateScript:script] toString];
}

/* Promises, each expectation as the host's JavaScriptCore answers it. */
static void CheckPromises(JSContext *context)
{
    __block BOOL ran = NO;
    __block NSString *executorThis = nil;
    __block NSUInteger executorArguments = 0;
    __block JSValue *resolve = nil;
    JSValue *promise = [JSValue valueWithNewPromiseInContext:context fromExecutor:^(JSValue *resolveFunction, JSValue *rejectFunction) {
        (void)rejectFunction;
        ran = YES;
        executorThis = [[JSContext currentThis] toString];
        executorArguments = [JSContext currentArguments].count;
        resolve = resolveFunction;
    }];
    check(ran, @"a promise's executor runs before valueWithNewPromiseInContext: returns");
    check([executorThis isEqualToString:@"[object Promise]"] && executorArguments == 2, @"the executor is a callback whose this is the promise and whose arguments are its two resolving functions");
    context[@"p"] = promise;
    context[@"r"] = resolve;
    check([Run(context, @"typeof r") isEqualToString:@"function"], @"the resolving functions are JavaScript functions");
    check([Run(context, @"Object.prototype.toString.call(p)") isEqualToString:@"[object Promise]"], @"a promise's class is Promise");
    check([Run(context, @"(p instanceof Promise) + ',' + (p.constructor === Promise) + ',' + Object.getOwnPropertyNames(p).length") isEqualToString:@"true,true,0"], @"a promise is an instance of the global Promise with no own properties");
    check([Run(context, @"Object.getOwnPropertyNames(Promise.prototype).sort().join(',')") isEqualToString:@"catch,constructor,finally,then"], @"Promise.prototype has then, catch and finally");
    check([Run(context, @"Object.keys(Promise.prototype).length + ',' + Object.keys(this).indexOf('Promise')") isEqualToString:@"0,-1"], @"Promise and its methods are not enumerable");
    check([Run(context, @"var got; p.then(function (v) { got = v; }); r(42); typeof got") isEqualToString:@"undefined"], @"a reaction does not run while the script that queued it is running");
    check([context[@"got"] toInt32] == 42, @"a reaction has run once the script that queued it returns");

    JSValue *later = [JSValue valueWithNewPromiseInContext:context fromExecutor:^(JSValue *resolveFunction, JSValue *rejectFunction) {
        (void)rejectFunction;
        resolve = resolveFunction;
    }];
    context[@"later"] = later;
    [context evaluateScript:@"var laterValue = 'unset'; later.then(function (v) { laterValue = v; })"];
    [resolve callWithArguments:@[@7]];
    check([context[@"laterValue"] toInt32] == 7, @"resolving from Objective-C runs the reaction before callWithArguments: returns");

    context[@"resolved"] = [JSValue valueWithNewPromiseResolvedWithResult:@"x" inContext:context];
    context[@"rejected"] = [JSValue valueWithNewPromiseRejectedWithReason:@"why" inContext:context];
    [context evaluateScript:@"var resolvedValue, rejectedReason; resolved.then(function (v) { resolvedValue = v; }); rejected.catch(function (v) { rejectedReason = v; })"];
    check([[context[@"resolvedValue"] toString] isEqualToString:@"x"] && [[context[@"rejectedReason"] toString] isEqualToString:@"why"], @"valueWithNewPromiseResolvedWithResult: and ...RejectedWithReason: settle as asked");
    JSValue *adopting = [JSValue valueWithNewPromiseResolvedWithResult:promise inContext:context];
    context[@"adopting"] = adopting;
    [context evaluateScript:@"var adopted; adopting.then(function (v) { adopted = v; })"];
    check(![adopting isEqualToObject:promise] && [context[@"adopted"] toInt32] == 42, @"a promise resolved with a promise is a new promise that adopts its value");

    check([Run(context, @"var thenable; new Promise(function (ok) { ok({ then: function (f) { f('thenable'); } }); }).then(function (v) { thenable = v; }); 0") isEqualToString:@"0"] && [[context[@"thenable"] toString] isEqualToString:@"thenable"], @"a thenable is adopted");
    [context evaluateScript:@"var itself; var ownResolve; var own = new Promise(function (ok) { ownResolve = ok; }); ownResolve(own); own.catch(function (e) { itself = (e instanceof TypeError) + ':' + e.message; })"];
    check([[context[@"itself"] toString] isEqualToString:@"true:Cannot resolve a promise with itself"], @"a promise resolved with itself rejects with a TypeError");
    check([Run(context, @"var order = []; var done = Promise.resolve(1); done.then(function () { order.push('a'); }); done.then(function () { order.push('b'); }); order.push('sync'); 0") isEqualToString:@"0"] && [Run(context, @"order.join(',')") isEqualToString:@"sync,a,b"], @"reactions run after the script, in the order they were added");
    [context evaluateScript:@"var chain = []; Promise.reject(new Error('e1')).then(function () { chain.push('skipped'); }).catch(function (e) { chain.push(e.message); return 'next'; }).finally(function () { chain.push('finally'); return 'ignored'; }).then(function (v) { chain.push(v); })"];
    check([Run(context, @"chain.join(',')") isEqualToString:@"e1,finally,next"], @"then, catch and finally chain as specified");
    [context evaluateScript:@"var combined = []; Promise.all([1, Promise.resolve(2), { then: function (f) { f(3); } }]).then(function (v) { combined.push('all:' + v.join('+')); }); Promise.race([new Promise(function () {}), Promise.resolve('first')]).then(function (v) { combined.push('race:' + v); }); Promise.allSettled([Promise.reject('no'), 'yes']).then(function (v) { combined.push('settled:' + v[0].status + '/' + v[0].reason + '/' + v[1].status + '/' + v[1].value); }); Promise.all([]).then(function (v) { combined.push('empty:' + v.length); }); Promise.all([Promise.reject('bad'), 1]).catch(function (e) { combined.push('allrejected:' + e); })"];
    check([Run(context, @"combined.sort().join(',')") isEqualToString:@"all:1+2+3,allrejected:bad,empty:0,race:first,settled:rejected/no/fulfilled/yes"], @"Promise.all, race and allSettled combine as specified");
    [context evaluateScript:@"var notIterable; Promise.all(5).catch(function (e) { notIterable = e instanceof TypeError; })"];
    check([Run(context, @"notIterable") isEqualToString:@"true"], @"Promise.all of a value that is not iterable rejects with a TypeError");
    check([Run(context, @"var errors = []; try { Promise(function () {}); } catch (e) { errors.push(e instanceof TypeError); } try { Promise.prototype.then.call({}); } catch (e) { errors.push(e instanceof TypeError); } try { new Promise(5); } catch (e) { errors.push(e instanceof TypeError); } errors.join(',')") isEqualToString:@"true,true,true"], @"Promise without new, then on a non-promise and a non-function executor throw TypeError");

    context[@"nest"] = ^JSValue *{
        [[JSContext currentContext] evaluateScript:@"Promise.resolve().then(function () { inner = 'ran'; })"];
        return [[JSContext currentContext] evaluateScript:@"typeof inner"];
    };
    check([Run(context, @"var inner; nest()") isEqualToString:@"undefined"] && [[context[@"inner"] toString] isEqualToString:@"ran"], @"jobs queued inside a callback wait for the outermost call to return");

    __block int handled = 0;
    void (^previous)(JSContext *, JSValue *) = context.exceptionHandler;
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        handled++;
        ctx.exception = exception;
    };
    context[@"throwing"] = [JSValue valueWithNewPromiseInContext:context fromExecutor:^(JSValue *resolveFunction, JSValue *rejectFunction) {
        (void)resolveFunction;
        (void)rejectFunction;
        JSContext *current = [JSContext currentContext];
        current.exception = [JSValue valueWithNewErrorFromMessage:@"boom" inContext:current];
    }];
    [context evaluateScript:@"var thrown = 'pending'; throwing.then(function () { thrown = 'resolved'; }, function (e) { thrown = 'rejected:' + e.message; })"];
    check([[context[@"thrown"] toString] isEqualToString:@"rejected:boom"] && !context.exception && handled == 0, @"an exception the executor sets rejects its promise and reaches no handler");
    context[@"setsException"] = ^{
        JSContext *current = [JSContext currentContext];
        current.exception = [JSValue valueWithNewErrorFromMessage:@"from a block" inContext:current];
    };
    check([Run(context, @"var caught; try { setsException(); caught = 'no'; } catch (e) { caught = 'caught ' + e.message; } caught") isEqualToString:@"caught from a block"] && handled == 0 && !context.exception, @"an exception a block sets on its context is thrown into the script that called it");
    context.exceptionHandler = previous;

    /* Script run through the C API directly: the release with promises runs the jobs as that call
     * returns, the backport on the thread's next run loop turn; after one turn both have. */
    JSStringRef direct = JSStringCreateWithUTF8CString("var direct = 'unset'; Promise.resolve('ran').then(function (v) { direct = v; })");
    JSEvaluateScript(context.JSGlobalContextRef, direct, NULL, NULL, 1, NULL);
    JSStringRelease(direct);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
    check([[context[@"direct"] toString] isEqualToString:@"ran"], @"jobs queued by script run through the C API directly have run after one run loop turn");
}

/*
 * Symbols: a named divergence. The host's engine has symbols; the release's (2012) has none, and
 * the backport refuses at the seam. Each side is held to its own answer, so the check fails if the
 * backport ever stops refusing or the oracle ever stops making one.
 */
static void CheckSymbols(JSContext *context)
{
    context.exception = nil;
    JSValue *symbol = [JSValue valueWithNewSymbolFromDescription:@"d" inContext:context];
#ifdef CHARON_PORT
    check(!symbol.isSymbol && symbol.isUndefined && [[context.exception[@"name"] toString] isEqualToString:@"TypeError"], @"a symbol is refused with a TypeError on the context (the release's engine has no symbols)");
#else
    check(symbol.isSymbol && [[[context evaluateScript:@"(function (x) { return typeof x; })"] callWithArguments:@[symbol]].toString isEqualToString:@"symbol"], @"the host's engine makes a symbol (the divergence the backport names)");
#endif
    context.exception = nil;
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
        CheckPromises(context);
        CheckSymbols(context);

        JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
        JSContext *second = [[JSContext alloc] initWithVirtualMachine:vm];
        check(second.virtualMachine == vm, @"a context created with an explicit JSVirtualMachine reports it back");

        printf(failures == 0 ? "checks=all passed\n" : "checks=%d failed\n", failures);
    }
    return failures;
}
