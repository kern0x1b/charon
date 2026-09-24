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
 * stack it used is overwritten before collecting. On the host, JSSynchronousGarbageCollectForDebugging
 * is the engine's own exported collect-now entry point and JSGarbageCollect only schedules one. The
 * release's engine (2012) exports no such entry point; there JSGarbageCollect is the collect-now
 * call, which the device run of these checks measures: every check after a Collect needs it.
 */
#if TARGET_OS_IPHONE
#define CollectNow JSGarbageCollect
#else
extern void JSSynchronousGarbageCollectForDebugging(JSContextRef context);
#define CollectNow JSSynchronousGarbageCollectForDebugging
#endif

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
    CollectNow(context.JSGlobalContextRef);
    /* the backport releases what finalized wrappers held after the collection, on this turn at the
     * latest (CheckReleaseAfterCollection); the release has by the time the collection returns */
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
}


/* An Objective-C object that owns a managed value, the pattern JSManagedValue.h documents. */
/* A JSExport method's and property setter's arguments arrive by their declared class, too. */
@protocol TypedExport <JSExport>
@property (nonatomic, strong) NSURL *link;
- (void)takeValue:(JSValue *)value;
- (void)takeURL:(NSURL *)url;
- (void)takeString:(NSString *)string;
@end

@interface TypedObject : NSObject <TypedExport>
@property (nonatomic, strong) id got;
@property (nonatomic) BOOL called;
@end

@implementation TypedObject
@synthesize link = _link;
- (void)takeValue:(JSValue *)value { self.called = YES; self.got = value; }
- (void)takeURL:(NSURL *)url { self.called = YES; self.got = url; }
- (void)takeString:(NSString *)string { self.called = YES; self.got = string; }
@end

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

    /* Script run through the C API directly, and a block such script calls: a named divergence.
     * The release with promises runs the jobs as the outermost C API call returns; the release's
     * 2012 engine lets nothing outside it see that return, so the backport runs them on the
     * thread's next run loop turn. Each side is held to its own answer. */
    __weak JSContext *weakContext = context;
    context[@"queueFromBlock"] = ^{
        [weakContext evaluateScript:@"Promise.resolve('ran').then(function (v) { fromBlock = v; })"];
    };
    context[@"queueFromCall"] = ^{
        [[weakContext evaluateScript:@"(function () { Promise.resolve('ran').then(function (v) { fromCall = v; }); })"] callWithArguments:@[]];
    };
    struct { const char *script, *name, *what; } directCases[] = {
        {"var direct = 'unset'; Promise.resolve('ran').then(function (v) { direct = v; })", "direct", "script run through the C API directly"},
        {"var fromBlock = 'unset'; queueFromBlock()", "fromBlock", "a block's -evaluateScript: under script run through the C API"},
        {"var fromCall = 'unset'; queueFromCall()", "fromCall", "a block's -callWithArguments: under script run through the C API"},
    };
    for (size_t index = 0; index < sizeof(directCases) / sizeof(directCases[0]); index++) {
        JSStringRef direct = JSStringCreateWithUTF8CString(directCases[index].script);
        JSEvaluateScript(context.JSGlobalContextRef, direct, NULL, NULL, 1, NULL);
        JSStringRelease(direct);
        NSString *onReturn = [context[@(directCases[index].name)] toString];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
        NSString *afterTurn = [context[@(directCases[index].name)] toString];
#ifdef CHARON_PORT
        check([onReturn isEqualToString:@"unset"] && [afterTurn isEqualToString:@"ran"],
              [NSString stringWithFormat:@"jobs queued by %s run on the next run loop turn, not as the C API call returns", directCases[index].what]);
#else
        check([onReturn isEqualToString:@"ran"] && [afterTurn isEqualToString:@"ran"],
              [NSString stringWithFormat:@"jobs queued by %s have run when the C API call returns", directCases[index].what]);
#endif
    }

    /* The release puts the result or reason into an array literal: nil raises. */
    for (int rejected = 0; rejected < 2; rejected++) {
        NSString *raised = nil;
        @try {
            if (rejected)
                [JSValue valueWithNewPromiseRejectedWithReason:nil inContext:context];
            else
                [JSValue valueWithNewPromiseResolvedWithResult:nil inContext:context];
        } @catch (NSException *exception) {
            raised = exception.name;
        }
        check([raised isEqualToString:NSInvalidArgumentException] && !context.exception,
              rejected ? @"valueWithNewPromiseRejectedWithReason:nil raises NSInvalidArgumentException" : @"valueWithNewPromiseResolvedWithResult:nil raises NSInvalidArgumentException");
    }
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

/*
 * The private parts of the release's C API the backport is built on (JSInternal.h), asked directly,
 * so that the device run answers for the release's own engine: private properties take on objects
 * made with a JSClassRef only, and keep what they hold alive; the weak object map holds weakly.
 */
typedef struct OpaqueJSWeakObjectMap *JSWeakObjectMapRef;
typedef void (*JSWeakMapDestroyedCallback)(JSWeakObjectMapRef map, void *data);
extern JSWeakObjectMapRef JSWeakObjectMapCreate(JSContextRef ctx, void *data, JSWeakMapDestroyedCallback destructor);
extern void JSWeakObjectMapSet(JSContextRef ctx, JSWeakObjectMapRef map, void *key, JSObjectRef object);
extern JSObjectRef JSWeakObjectMapGet(JSContextRef ctx, JSWeakObjectMapRef map, void *key);
extern bool JSObjectSetPrivateProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef value);
extern bool JSObjectDeletePrivateProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName);
extern JSValueRef JSObjectGetPrivateProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName);

static void CountDestroyed(JSWeakObjectMapRef map, void *data)
{
    (void)map;
    (*(int *)data)++;
}

/* An object only the weak map knows of, made in a frame of its own; set as `holder`'s private property if given. */
__attribute__((noinline)) static void MakeWeaklyHeld(JSGlobalContextRef context, JSWeakObjectMapRef weak, void *key, JSObjectRef holder, JSStringRef name)
{
    JSObjectRef object = JSObjectMake(context, NULL, NULL);
    JSWeakObjectMapSet(context, weak, key, object);
    if (holder)
        JSObjectSetPrivateProperty(context, holder, name, object);
}

__attribute__((noinline)) static void CollectContext(JSGlobalContextRef context)
{
    volatile char stack[16384];
    for (size_t index = 0; index < sizeof(stack); index++)
        stack[index] = 0;
    CollectNow(context);
}

static void CheckReleaseCAPI(void)
{
    JSClassDefinition definition = kJSClassDefinitionEmpty;
    JSClassRef jsClass = JSClassCreate(&definition);
    JSGlobalContextRef context = JSGlobalContextCreate(NULL);
    JSStringRef name = JSStringCreateWithUTF8CString("charon.check");
    JSObjectRef classed = JSObjectMake(context, jsClass, NULL);
    JSObjectRef plain = JSObjectMake(context, NULL, NULL);
    JSValueProtect(context, classed);
    check(JSObjectSetPrivateProperty(context, classed, name, plain) && JSObjectGetPrivateProperty(context, classed, name) == plain,
          @"a private property takes on an object made with a JSClassRef and reads back");
    check(!JSObjectSetPrivateProperty(context, plain, name, classed), @"a private property is refused on an object made with no JSClassRef");
    check(!JSObjectSetPrivateProperty(context, JSObjectMakeFunctionWithCallback(context, NULL, NULL), name, classed), @"a private property is refused on a function made with a callback");
    JSStringRef names = JSStringCreateWithUTF8CString("Object.getOwnPropertyNames(this).length");
    JSValueRef count = JSEvaluateScript(context, names, classed, NULL, 1, NULL);
    JSStringRelease(names);
    check(JSValueToNumber(context, count, NULL) == 0, @"script does not see a private property");

    JSWeakObjectMapRef weak = JSWeakObjectMapCreate(context, NULL, CountDestroyed);
    char keptKey, looseKey;
    MakeWeaklyHeld(context, weak, &keptKey, classed, name);
    MakeWeaklyHeld(context, weak, &looseKey, NULL, NULL);
    CollectContext(context);
    check(JSWeakObjectMapGet(context, weak, &keptKey) != NULL, @"a private property keeps its value through a collection");
    check(JSWeakObjectMapGet(context, weak, &looseKey) == NULL, @"the weak object map does not keep an object alive");
    JSObjectDeletePrivateProperty(context, classed, name);
    CollectContext(context);
    check(JSWeakObjectMapGet(context, weak, &keptKey) == NULL, @"a deleted private property lets its value go");
    JSValueUnprotect(context, classed);

    /* Measured, not held: the backport's destroyed callback does nothing, so no check needs it. */
    int destroyed = 0;
    JSContextGroupRef group = JSContextGroupCreate();
    JSGlobalContextRef doomed = JSGlobalContextCreateInGroup(group, NULL);
    JSGlobalContextRef other = JSGlobalContextCreateInGroup(group, NULL);
    JSWeakObjectMapCreate(doomed, &destroyed, CountDestroyed);
    JSGlobalContextRelease(doomed);
    CollectContext(other);
    printf("measured: the weak object map's destroyed callback ran %d times after its global context was released and its group collected\n", destroyed);
    JSGlobalContextRelease(other);
    JSContextGroupRelease(group);
    printf("measured: and %d times after the group was released\n", destroyed);

    JSStringRelease(name);
    JSGlobalContextRelease(context);
    JSClassRelease(jsClass);
}

/*
 * Where a wrapper's Objective-C object is released: never inside the collection that finalized the
 * wrapper (JSObjectRef.h forbids the C API a -dealloc may call in a finalizer). A named divergence
 * in when: the release hands it to the heap to release as the collection ends, still inside the
 * call that collected; the backport, which has no end-of-collection hook, on the thread's next run
 * loop turn or its next outermost call into script. Each side is held to its own answer.
 */
static int releasedOwners, releasedWhileCollecting;
static BOOL collecting;

@interface ReleaseProbe : NSObject
@property (strong) JSManagedValue *managed;
@end

@implementation ReleaseProbe
- (void)dealloc
{
    releasedOwners++;
    if (collecting)
        releasedWhileCollecting++;
}
@end

__attribute__((noinline)) static void ExportReleaseProbe(JSContext *context)
{
    @autoreleasepool {
        ReleaseProbe *owner = [ReleaseProbe new];
        context[@"releaseProbe"] = owner;
        owner.managed = [JSManagedValue managedValueWithValue:[context evaluateScript:@"({n: 1})"]];
        [context.virtualMachine addManagedReference:owner.managed withOwner:owner];
        context[@"releaseProbe"] = nil;
    }
}

__attribute__((noinline)) static void CollectOnly(JSContext *context)
{
    volatile char stack[16384];
    for (size_t index = 0; index < sizeof(stack); index++)
        stack[index] = 0;
    collecting = YES;
    CollectNow(context.JSGlobalContextRef);
    collecting = NO;
}

static void CheckReleaseAfterCollection(JSContext *context)
{
    for (int index = 0; index < 4; index++)
        ExportReleaseProbe(context);
    CollectOnly(context);
    int onReturn = releasedOwners;
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
#ifdef CHARON_PORT
    check(onReturn == 0 && releasedWhileCollecting == 0 && releasedOwners == 4,
          @"an exported owner whose wrapper was collected is released on the next run loop turn, outside the collection");
#else
    check(onReturn == 4 && releasedOwners == 4, @"an exported owner whose wrapper was collected is released by the time the collection returns");
#endif
    for (int index = 0; index < 4; index++)
        ExportReleaseProbe(context);
    CollectOnly(context);
    [context evaluateScript:@"0"];
    check(releasedOwners == 8, @"and released by the next call into script at the latest");
}

/* Arrays and Dates are told by the object's own class, as the release asks it. */
static void CheckOwnClass(void)
{
    JSVirtualMachine *machine = [JSVirtualMachine new];
    JSContext *a = [[JSContext alloc] initWithVirtualMachine:machine];
    JSContext *b = [[JSContext alloc] initWithVirtualMachine:machine];
    a[@"arrayOfB"] = [b evaluateScript:@"[1, 2]"];
    a[@"dateOfB"] = [b evaluateScript:@"new Date(5000)"];
    JSValue *arrayOfB = a[@"arrayOfB"], *dateOfB = a[@"dateOfB"];
    check([[arrayOfB toObject] isKindOfClass:[NSArray class]] && arrayOfB.isArray, @"an array of another context of the same virtual machine is an array");
    check([[dateOfB toObject] isEqual:[NSDate dateWithTimeIntervalSince1970:5]] && dateOfB.isDate, @"a Date of another context of the same virtual machine is a Date");
    NSArray *wrapped = [[a evaluateScript:@"[arrayOfB]"] toObject];
    check([wrapped[0] isKindOfClass:[NSArray class]], @"and so is one met inside a container");
    JSValue *dateLike = [a evaluateScript:@"Object.create(Date.prototype)"];
    check([[dateLike toObject] isKindOfClass:[NSDictionary class]] && !dateLike.isDate, @"an object that only inherits Date.prototype is not a Date");
    JSValue *arrayLike = [a evaluateScript:@"Object.create(Array.prototype)"];
    check([[arrayLike toObject] isKindOfClass:[NSDictionary class]] && !arrayLike.isArray, @"an object that only inherits Array.prototype is not an array");
    JSValue *rebased = [a evaluateScript:@"var d = new Date(1000); d.__proto__ = Object.prototype; d"];
    check([[rebased toObject] isKindOfClass:[NSDate class]] && rebased.isDate, @"a Date whose prototype was replaced is still a Date");
    [a evaluateScript:@"var RealDate = Date; Array.isArray = function () { return false; }; Object.prototype.toString = function () { return '[object Object]'; }; Date = function () {};"];
    JSValue *array = [a evaluateScript:@"[3]"], *date = [a evaluateScript:@"new RealDate(2000)"];
    check([[array toObject] isKindOfClass:[NSArray class]] && array.isArray && [[date toObject] isKindOfClass:[NSDate class]] && date.isDate,
          @"script that replaces Array.isArray, Object.prototype.toString and Date does not change the answer");
}

/* JSValue's conversions, each expectation measured on the host's own JavaScriptCore. */
static void CheckConversions(void)
{
    JSContext *context = [JSContext new];
    __block NSString *handled = nil;
    context.exceptionHandler = ^(JSContext *c, JSValue *exception) { handled = [exception toString]; };
    NSDictionary *cyclic = [[context evaluateScript:@"var a = {n: 1}; a.self = a; a"] toObject];
    check(cyclic[@"self"] == cyclic, @"toObject gives a cyclic object back as the same dictionary");
    NSArray *cyclicArray = [[context evaluateScript:@"var b = []; b.push(b); b"] toObject];
    check(cyclicArray.count == 1 && cyclicArray[0] == cyclicArray, @"toObject gives a cyclic array back as the same array");
    NSDictionary *shared = [[context evaluateScript:@"var s = {k: 1}; ({x: s, y: s})"] toObject];
    check(shared[@"x"] == shared[@"y"], @"toObject converts an object reached twice once");
    NSDictionary *dates = [[context evaluateScript:@"({d: new Date(1000), a: [new Date(2000)]})"] toObject];
    check([dates[@"d"] isEqual:[NSDate dateWithTimeIntervalSince1970:1]] && [dates[@"a"][0] isEqual:[NSDate dateWithTimeIntervalSince1970:2]],
          @"toObject turns a Date, nested too, into an NSDate");
    NSDate *invalid = [[context evaluateScript:@"new Date(NaN)"] toObject];
    check([invalid isKindOfClass:[NSDate class]] && isnan(invalid.timeIntervalSince1970), @"an invalid Date is an NSDate of NaN");
    NSDictionary *nulls = [[context evaluateScript:@"({a: null, b: undefined, c: 1})"] toObject];
    check(nulls[@"a"] == [NSNull null] && !nulls[@"b"] && nulls.count == 2, @"null is NSNull in a dictionary and undefined is left out");
    NSArray *holes = [[context evaluateScript:@"[1, , undefined, null]"] toObject];
    check(holes.count == 4 && holes[1] == [NSNull null] && holes[2] == [NSNull null] && holes[3] == [NSNull null], @"a hole, undefined and null are NSNull in an array");
    check([[context evaluateScript:@"null"] toObject] == [NSNull null] && ![[context evaluateScript:@"undefined"] toObject], @"top-level null is NSNull and undefined nil");
    id function = [[context evaluateScript:@"(function f() {})"] toObject];
    check([function isKindOfClass:[NSDictionary class]] && [function count] == 0, @"a function converts to an empty dictionary");
    NSDictionary *inherited = [[context evaluateScript:@"var P = function () { this.own = 1; }; P.prototype.inh = 2; new P()"] toObject];
    check([inherited[@"own"] isEqual:@1] && [inherited[@"inh"] isEqual:@2], @"enumerable inherited properties are converted");
    handled = nil;
    NSDictionary *getter = [[context evaluateScript:@"({get x() { throw new Error('g'); }, y: 1})"] toObject];
    check(getter.count == 1 && [getter[@"y"] isEqual:@1] && !handled, @"a throwing getter is left out and reported nowhere");
    NSArray *asArray = [[context evaluateScript:@"({a: 1})"] toArray];
    check([asArray isKindOfClass:[NSArray class]] && asArray.count == 0, @"toArray reads any object as an array");
    NSDictionary *asDictionary = [[context evaluateScript:@"[5, 6]"] toDictionary];
    check([asDictionary[@"0"] isEqual:@5] && [asDictionary[@"1"] isEqual:@6], @"toDictionary reads an array by its indexes");
    handled = nil;
    check(![[context evaluateScript:@"'ab'"] toArray] && [handled isEqualToString:@"TypeError: Cannot convert primitive to NSArray"], @"toArray of a primitive is nil and a TypeError to the handler");
    handled = nil;
    check(![[context evaluateScript:@"5"] toDictionary] && [handled isEqualToString:@"TypeError: Cannot convert primitive to NSDictionary"], @"toDictionary of a primitive is nil and a TypeError to the handler");
    handled = nil;
    check(![[context evaluateScript:@"null"] toArray] && !handled, @"toArray of null is nil with no exception");
    JSValue *badString = [context evaluateScript:@"({toString: function () { throw new Error('ts'); }})"];
    JSValue *badNumber = [context evaluateScript:@"({valueOf: function () { throw new Error('vo'); }})"];
    handled = nil;
    check(![badString toString] && [handled isEqualToString:@"Error: ts"], @"toString that throws is nil and reaches the handler");
    handled = nil;
    check(isnan([badNumber toDouble]) && [handled isEqualToString:@"Error: vo"], @"toDouble that throws is NaN and reaches the handler");
    handled = nil;
    check([badNumber toInt32] == 0 && [handled isEqualToString:@"Error: vo"], @"toInt32 that throws is 0 and reaches the handler");
    handled = nil;
    check(isnan([[badNumber toNumber] doubleValue]) && [handled isEqualToString:@"Error: vo"], @"toNumber that throws is NaN and reaches the handler");
    check([[[context evaluateScript:@"'x'"] toDate] isKindOfClass:[NSDate class]] && isnan([[[context evaluateScript:@"'x'"] toDate] timeIntervalSince1970]), @"toDate of a non-number is an NSDate of NaN");
}

/* A block's arguments arrive as the class its own signature declares (measured on the host). */
static void CheckBlockArguments(void)
{
    JSContext *context = [JSContext new];
    __block NSString *handled = nil;
    context.exceptionHandler = ^(JSContext *c, JSValue *exception) { handled = [exception toString]; };
    __block id got = nil;
    __block BOOL called = NO;
    context[@"takeValue"] = ^(JSValue *value) { called = YES; got = value; };
    context[@"takeString"] = ^(NSString *value) { called = YES; got = value; };
    context[@"takeNumber"] = ^(NSNumber *value) { called = YES; got = value; };
    context[@"takeDate"] = ^(NSDate *value) { called = YES; got = value; };
    context[@"takeArray"] = ^(NSArray *value) { called = YES; got = value; };
    context[@"takeURL"] = ^(NSURL *value) { called = YES; got = value; };
    context[@"takeAny"] = ^(id value) { called = YES; got = value; };
    context[@"takeBlock"] = ^(void (^value)(void)) { called = YES; };
    context[@"url"] = [NSURL URLWithString:@"http://example.com/"];
    [context evaluateScript:@"takeValue(5)"];
    check([got isKindOfClass:[JSValue class]] && [got toInt32] == 5, @"a JSValue argument receives the JavaScript value itself");
    [context evaluateScript:@"takeValue({a: 1})"];
    check([got isKindOfClass:[JSValue class]] && [got[@"a"] toInt32] == 1, @"a JSValue argument receives an object as a JSValue");
    [context evaluateScript:@"takeValue()"];
    check([got isKindOfClass:[JSValue class]] && [got isUndefined], @"a missing JSValue argument is undefined");
    [context evaluateScript:@"takeString(5)"];
    check([got isEqual:@"5"], @"an NSString argument receives the value's string");
    [context evaluateScript:@"takeString(null)"];
    check([got isEqual:@"null"], @"an NSString argument receives null as \"null\"");
    [context evaluateScript:@"takeNumber('12')"];
    check([got isEqual:@12], @"an NSNumber argument receives the value's number");
    [context evaluateScript:@"takeDate(new Date(3000))"];
    check([got isEqual:[NSDate dateWithTimeIntervalSince1970:3]], @"an NSDate argument receives a Date as an NSDate");
    [context evaluateScript:@"takeArray([1, 2])"];
    check([got isEqual:(@[@1, @2])], @"an NSArray argument receives an array");
    called = NO;
    handled = nil;
    [context evaluateScript:@"takeArray(5)"];
    check(!called && [handled isEqualToString:@"TypeError: Cannot convert primitive to NSArray"], @"an NSArray argument refuses a primitive with a TypeError before the block runs");
    [context evaluateScript:@"takeURL(url)"];
    check([got isEqual:[NSURL URLWithString:@"http://example.com/"]], @"a class-typed argument receives the wrapped object of that class");
    got = @"";
    [context evaluateScript:@"takeURL(null)"];
    check(!got, @"a class-typed argument receives nil for null");
    called = NO;
    handled = nil;
    [context evaluateScript:@"takeURL('http://example.com/')"];
    check(!called && [handled isEqualToString:@"TypeError: Argument does not match Objective-C Class"], @"a class-typed argument refuses another value with a TypeError");
    [context evaluateScript:@"takeAny(null)"];
    check(got == [NSNull null], @"an id argument receives null as NSNull, as toObject does");
    [context evaluateScript:@"takeAny(function () {})"];
    check([got isKindOfClass:[NSDictionary class]], @"an id argument receives a function as toObject converts it");
    check([[[context evaluateScript:@"typeof takeBlock"] toString] isEqualToString:@"object"], @"a block taking a block is no function, as the release has it");
    typedef struct { int field; } CharonCheckStruct;
    context[@"takeStruct"] = ^(CharonCheckStruct value) { (void)value; };
    context[@"takeRange"] = ^(NSRange value) { (void)value; };
    check([[[context evaluateScript:@"typeof takeStruct"] toString] isEqualToString:@"object"], @"a block taking a struct JSValue does not convert is no function");
    check([[[context evaluateScript:@"typeof takeRange"] toString] isEqualToString:@"function"], @"a block taking an NSRange is a function");
    context[@"two"] = ^(NSString *first, JSValue *second) { got = @[first, [second toString]]; };
    [context evaluateScript:@"two(1, 2, 3)"];
    check([got isEqual:(@[@"1", @"2"])], @"extra JavaScript arguments are dropped");
    context[@"count"] = ^(id first) { got = @([JSContext currentArguments].count); };
    [context evaluateScript:@"count(1, 2, 3)"];
    check([got isEqual:@3], @"currentArguments holds every JavaScript argument, not only the declared ones");
}

static void CheckExportArguments(void)
{
    JSContext *context = [JSContext new];
    __block NSString *handled = nil;
    context.exceptionHandler = ^(JSContext *c, JSValue *exception) { handled = [exception toString]; };
    TypedObject *object = [TypedObject new];
    context[@"typed"] = object;
    context[@"url"] = [NSURL URLWithString:@"http://example.com/"];
    [context evaluateScript:@"typed.takeValue(function () { return 7; })"];
    check([object.got isKindOfClass:[JSValue class]] && [[object.got callWithArguments:@[]] toInt32] == 7, @"a JSExport method's JSValue argument receives a function it can call");
    [context evaluateScript:@"typed.takeString(5)"];
    check([object.got isEqual:@"5"], @"a JSExport method's NSString argument receives the value's string");
    [context evaluateScript:@"typed.takeURL(url)"];
    check([object.got isEqual:[NSURL URLWithString:@"http://example.com/"]], @"a JSExport method's class-typed argument receives the wrapped object");
    object.called = NO;
    handled = nil;
    [context evaluateScript:@"typed.takeURL('x')"];
    check(!object.called && [handled isEqualToString:@"TypeError: Argument does not match Objective-C Class"], @"a JSExport method refuses a value of another class before it runs");
    handled = nil;
    [context evaluateScript:@"typed.link = 'x'"];
    check(!object.link && [handled isEqualToString:@"TypeError: Argument does not match Objective-C Class"], @"a JSExport property setter refuses a value of another class");
    [context evaluateScript:@"typed.link = url"];
    check([object.link isEqual:[NSURL URLWithString:@"http://example.com/"]], @"a JSExport property setter takes a value of its class");
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
        CheckConversions();
        CheckBlockArguments();
        CheckExportArguments();
        CheckReleaseCAPI();
        CheckReleaseAfterCollection(context);
        CheckOwnClass();

        JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
        JSContext *second = [[JSContext alloc] initWithVirtualMachine:vm];
        check(second.virtualMachine == vm, @"a context created with an explicit JSVirtualMachine reports it back");

        printf(failures == 0 ? "checks=all passed\n" : "checks=%d failed\n", failures);
    }
    return failures;
}
