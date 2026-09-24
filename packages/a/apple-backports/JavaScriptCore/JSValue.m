#import "JSInternal.h"
#import <CoreGraphics/CoreGraphics.h>

@interface JSValue ()
{
    JSValueRef _value;
    JSContext *_context;
}
@end

@implementation JSValue

+ (instancetype)charon_valueWithJSValueRef:(JSValueRef)value context:(JSContext *)context
{
    JSValue *result = [self alloc];
    result->_value = value;
    result->_context = context;
    JSValueProtect(context.JSGlobalContextRef, value);
    return result;
}

+ (JSValue *)valueWithJSValueRef:(JSValueRef)value inContext:(JSContext *)context
{
    return [self charon_valueWithJSValueRef:value context:context];
}

/* No -dealloc here calls the C API (JSInternal.m, charon_js_defer): the value is unprotected once
 * the queue runs, and the work keeps the context, with its JSGlobalContextRef, until then. */
- (void)dealloc
{
    JSContext *context = _context;
    JSValueRef value = _value;
    charon_js_defer(^{
        JSValueUnprotect(context.JSGlobalContextRef, value);
    });
}

- (JSValueRef)JSValueRef
{
    return _value;
}

- (JSContext *)context
{
    return _context;
}

+ (JSValue *)valueWithObject:(id)value inContext:(JSContext *)context
{
    if ([value isKindOfClass:[JSValue class]])
        return value;
    return [self charon_valueWithJSValueRef:charon_js_box(context.JSGlobalContextRef, value) context:context];
}

+ (JSValue *)valueWithBool:(BOOL)value inContext:(JSContext *)context
{
    return [self charon_valueWithJSValueRef:JSValueMakeBoolean(context.JSGlobalContextRef, value) context:context];
}

+ (JSValue *)valueWithDouble:(double)value inContext:(JSContext *)context
{
    return [self charon_valueWithJSValueRef:JSValueMakeNumber(context.JSGlobalContextRef, value) context:context];
}

+ (JSValue *)valueWithInt32:(int32_t)value inContext:(JSContext *)context
{
    return [self valueWithDouble:value inContext:context];
}

+ (JSValue *)valueWithUInt32:(uint32_t)value inContext:(JSContext *)context
{
    return [self valueWithDouble:value inContext:context];
}

+ (JSValue *)valueWithNewObjectInContext:(JSContext *)context
{
    return [self charon_valueWithJSValueRef:JSObjectMake(context.JSGlobalContextRef, NULL, NULL) context:context];
}

+ (JSValue *)valueWithNewArrayInContext:(JSContext *)context
{
    return [self charon_valueWithJSValueRef:JSObjectMakeArray(context.JSGlobalContextRef, 0, NULL, NULL) context:context];
}

+ (JSValue *)valueWithNewRegularExpressionFromPattern:(NSString *)pattern flags:(NSString *)flags inContext:(JSContext *)context
{
    JSStringRef patternString = charon_js_string(pattern);
    JSStringRef flagsString = charon_js_string(flags);
    JSValueRef arguments[2] = {JSValueMakeString(context.JSGlobalContextRef, patternString), JSValueMakeString(context.JSGlobalContextRef, flagsString)};
    JSValueRef exception = NULL;
    JSObjectRef result = JSObjectMakeRegExp(context.JSGlobalContextRef, 2, arguments, &exception);
    JSStringRelease(patternString);
    JSStringRelease(flagsString);
    if (exception)
        [context charon_noteException:exception];
    return [self charon_valueWithJSValueRef:result context:context];
}

+ (JSValue *)valueWithNewErrorFromMessage:(NSString *)message inContext:(JSContext *)context
{
    JSStringRef text = charon_js_string(message);
    JSValueRef argument = JSValueMakeString(context.JSGlobalContextRef, text);
    JSStringRelease(text);
    JSObjectRef result = JSObjectMakeError(context.JSGlobalContextRef, 1, &argument, NULL);
    return [self charon_valueWithJSValueRef:result context:context];
}

+ (JSValue *)valueWithNullInContext:(JSContext *)context
{
    return [self charon_valueWithJSValueRef:JSValueMakeNull(context.JSGlobalContextRef) context:context];
}

+ (JSValue *)valueWithUndefinedInContext:(JSContext *)context
{
    return [self charon_valueWithJSValueRef:JSValueMakeUndefined(context.JSGlobalContextRef) context:context];
}

/* A conversion that runs script (a valueOf or toString) and throws reports the exception to the
 * context's handler and answers NaN, 0 or nil, as the release's JSValue does. */
static id Reported(JSContext *context, id result, JSValueRef exception)
{
    if (exception)
        [context charon_noteException:exception];
    return result;
}

- (id)toObject
{
    return charon_js_unbox(_context.JSGlobalContextRef, _value);
}

- (id)toObjectOfClass:(Class)expectedClass
{
    id object = self.toObject;
    return [object isKindOfClass:expectedClass] ? object : nil;
}

- (BOOL)toBool
{
    return JSValueToBoolean(_context.JSGlobalContextRef, _value);
}


- (double)toDouble
{
    JSValueRef exception = NULL;
    double value = JSValueToNumber(_context.JSGlobalContextRef, _value, &exception);
    if (exception) {
        [_context charon_noteException:exception];
        return NAN;
    }
    return value;
}

- (int32_t)toInt32
{
    return (int32_t)charon_js_uint32(self.toDouble);
}

- (uint32_t)toUInt32
{
    return (uint32_t)self.toInt32;
}

- (NSNumber *)toNumber
{
    JSValueRef exception = NULL;
    return Reported(_context, charon_js_to_number(_context.JSGlobalContextRef, _value, &exception), exception);
}

- (NSString *)toString
{
    JSValueRef exception = NULL;
    return Reported(_context, charon_js_to_string(_context.JSGlobalContextRef, _value, &exception), exception);
}

- (NSDate *)toDate
{
    JSValueRef exception = NULL;
    return Reported(_context, charon_js_to_date(_context.JSGlobalContextRef, _value, &exception), exception);
}

- (NSArray *)toArray
{
    JSValueRef exception = NULL;
    return Reported(_context, charon_js_to_array(_context.JSGlobalContextRef, _value, &exception), exception);
}

- (NSDictionary *)toDictionary
{
    JSValueRef exception = NULL;
    return Reported(_context, charon_js_to_dictionary(_context.JSGlobalContextRef, _value, &exception), exception);
}

- (BOOL)isUndefined
{
    return JSValueIsUndefined(_context.JSGlobalContextRef, _value);
}

- (BOOL)isNull
{
    return JSValueIsNull(_context.JSGlobalContextRef, _value);
}

- (BOOL)isBoolean
{
    return JSValueIsBoolean(_context.JSGlobalContextRef, _value);
}

- (BOOL)isNumber
{
    return JSValueIsNumber(_context.JSGlobalContextRef, _value);
}

- (BOOL)isString
{
    return JSValueIsString(_context.JSGlobalContextRef, _value);
}

- (BOOL)isObject
{
    return JSValueIsObject(_context.JSGlobalContextRef, _value);
}

/* JSValueIsArray and JSValueIsDate only arrived in iOS 9; the object's own class answers the
 * same without them (charon_js_is_array, charon_js_is_date). */
- (BOOL)isArray
{
    return charon_js_is_array(_context.JSGlobalContextRef, _value);
}

- (BOOL)isDate
{
    return charon_js_is_date(_context.JSGlobalContextRef, _value);
}

- (BOOL)isEqualToObject:(id)value
{
    JSValue *other = [JSValue valueWithObject:value inContext:_context];
    return JSValueIsStrictEqual(_context.JSGlobalContextRef, _value, other.JSValueRef);
}

- (BOOL)isEqualWithTypeCoercionToObject:(id)value
{
    JSValue *other = [JSValue valueWithObject:value inContext:_context];
    JSValueRef exception = NULL;
    BOOL equal = JSValueIsEqual(_context.JSGlobalContextRef, _value, other.JSValueRef, &exception);
    if (exception)
        [_context charon_noteException:exception];
    return equal;
}

- (BOOL)isInstanceOf:(id)value
{
    JSValue *constructor = [JSValue valueWithObject:value inContext:_context];
    if (!JSValueIsObject(_context.JSGlobalContextRef, constructor.JSValueRef))
        return NO;
    JSValueRef exception = NULL;
    BOOL result = JSValueIsInstanceOfConstructor(_context.JSGlobalContextRef, _value, JSValueToObject(_context.JSGlobalContextRef, constructor.JSValueRef, &exception), &exception);
    if (exception)
        [_context charon_noteException:exception];
    return result;
}

- (JSValue *)callWithArguments:(NSArray *)arguments
{
    return [self charon_callWithArguments:arguments thisValue:NULL asConstructor:NO];
}

- (JSValue *)constructWithArguments:(NSArray *)arguments
{
    return [self charon_callWithArguments:arguments thisValue:NULL asConstructor:YES];
}

- (JSValue *)charon_callWithArguments:(NSArray *)arguments thisValue:(JSObjectRef)thisObject asConstructor:(BOOL)asConstructor
{
    JSContextRef ctx = _context.JSGlobalContextRef;
    JSValueRef exception = NULL;
    JSObjectRef function = JSValueToObject(ctx, _value, &exception);
    if (!function) {
        if (exception)
            [_context charon_noteException:exception];
        return [JSValue valueWithUndefinedInContext:_context];
    }
    NSUInteger count = arguments.count;
    JSValueRef *values = count ? malloc(sizeof(JSValueRef) * count) : NULL;
    for (NSUInteger index = 0; index < count; index++)
        values[index] = charon_js_box(ctx, arguments[index]);
    JSValueRef result;
    charon_js_enter();
    if (asConstructor)
        result = JSObjectCallAsConstructor(ctx, function, count, values, &exception);
    else
        result = JSObjectCallAsFunction(ctx, function, thisObject, count, values, &exception);
    free(values);
    JSValue *value = [JSValue charon_valueWithJSValueRef:(exception || !result) ? JSValueMakeUndefined(ctx) : result context:_context];
    JSValue *thrown = exception ? [JSValue charon_valueWithJSValueRef:exception context:_context] : nil;
    charon_js_leave();
    if (thrown)
        [_context charon_noteException:thrown.JSValueRef];
    return value;
}

- (JSValue *)invokeMethod:(NSString *)method withArguments:(NSArray *)arguments
{
    JSValue *function = [self valueForProperty:method];
    JSContextRef ctx = _context.JSGlobalContextRef;
    JSValueRef exception = NULL;
    JSObjectRef thisObject = JSValueToObject(ctx, _value, &exception);
    if (exception)
        [_context charon_noteException:exception];
    return [function charon_callWithArguments:arguments thisValue:thisObject asConstructor:NO];
}

- (JSValue *)valueForProperty:(NSString *)property
{
    JSContextRef ctx = _context.JSGlobalContextRef;
    JSValueRef exception = NULL;
    JSObjectRef object = JSValueToObject(ctx, _value, &exception);
    if (!object) {
        if (exception)
            [_context charon_noteException:exception];
        return [JSValue valueWithUndefinedInContext:_context];
    }
    JSStringRef name = charon_js_string(property);
    JSValueRef result = JSObjectGetProperty(ctx, object, name, &exception);
    JSStringRelease(name);
    if (exception)
        [_context charon_noteException:exception];
    return [JSValue charon_valueWithJSValueRef:result ?: JSValueMakeUndefined(ctx) context:_context];
}

- (void)setValue:(id)value forProperty:(NSString *)property
{
    JSContextRef ctx = _context.JSGlobalContextRef;
    JSValueRef exception = NULL;
    JSObjectRef object = JSValueToObject(ctx, _value, &exception);
    if (!object)
        return;
    JSStringRef name = charon_js_string(property);
    JSObjectSetProperty(ctx, object, name, charon_js_box(ctx, value), kJSPropertyAttributeNone, &exception);
    JSStringRelease(name);
    if (exception)
        [_context charon_noteException:exception];
}

- (BOOL)deleteProperty:(NSString *)property
{
    JSContextRef ctx = _context.JSGlobalContextRef;
    JSValueRef exception = NULL;
    JSObjectRef object = JSValueToObject(ctx, _value, &exception);
    if (!object)
        return NO;
    JSStringRef name = charon_js_string(property);
    BOOL result = JSObjectDeleteProperty(ctx, object, name, &exception);
    JSStringRelease(name);
    if (exception)
        [_context charon_noteException:exception];
    return result;
}

- (BOOL)hasProperty:(NSString *)property
{
    JSContextRef ctx = _context.JSGlobalContextRef;
    JSValueRef exception = NULL;
    JSObjectRef object = JSValueToObject(ctx, _value, &exception);
    if (!object)
        return NO;
    JSStringRef name = charon_js_string(property);
    BOOL result = JSObjectHasProperty(ctx, object, name);
    JSStringRelease(name);
    return result;
}

- (void)defineProperty:(NSString *)property descriptor:(id)descriptor
{
    JSValue *definePropertyFunction = [[self.context.globalObject valueForProperty:@"Object"] valueForProperty:@"defineProperty"];
    [definePropertyFunction callWithArguments:@[self, property, descriptor]];
}

- (JSValue *)valueAtIndex:(NSUInteger)index
{
    JSContextRef ctx = _context.JSGlobalContextRef;
    JSValueRef exception = NULL;
    JSObjectRef object = JSValueToObject(ctx, _value, &exception);
    if (!object)
        return [JSValue valueWithUndefinedInContext:_context];
    JSValueRef result = JSObjectGetPropertyAtIndex(ctx, object, (unsigned)index, &exception);
    if (exception)
        [_context charon_noteException:exception];
    return [JSValue charon_valueWithJSValueRef:result ?: JSValueMakeUndefined(ctx) context:_context];
}

- (void)setValue:(id)value atIndex:(NSUInteger)index
{
    JSContextRef ctx = _context.JSGlobalContextRef;
    JSValueRef exception = NULL;
    JSObjectRef object = JSValueToObject(ctx, _value, &exception);
    if (!object)
        return;
    JSObjectSetPropertyAtIndex(ctx, object, (unsigned)index, charon_js_box(ctx, value), &exception);
    if (exception)
        [_context charon_noteException:exception];
}

- (JSValue *)objectForKeyedSubscript:(id)key
{
    return [self valueForProperty:[key description]];
}

- (JSValue *)objectAtIndexedSubscript:(NSUInteger)index
{
    return [self valueAtIndex:index];
}

- (void)setObject:(id)object forKeyedSubscript:(id)key
{
    [self setValue:object forProperty:[key description]];
}

- (void)setObject:(id)object atIndexedSubscript:(NSUInteger)index
{
    [self setValue:object atIndex:index];
}

/* The release makes these four from a dictionary literal, so their properties come in that
 * dictionary's order, and so do these. */
+ (JSValue *)valueWithPoint:(CGPoint)point inContext:(JSContext *)context
{
    return [self valueWithObject:@{@"x": @(point.x), @"y": @(point.y)} inContext:context];
}

+ (JSValue *)valueWithRange:(NSRange)range inContext:(JSContext *)context
{
    return [self valueWithObject:@{@"location": @(range.location), @"length": @(range.length)} inContext:context];
}

+ (JSValue *)valueWithRect:(CGRect)rect inContext:(JSContext *)context
{
    return [self valueWithObject:@{@"x": @(rect.origin.x), @"y": @(rect.origin.y), @"width": @(rect.size.width), @"height": @(rect.size.height)} inContext:context];
}

+ (JSValue *)valueWithSize:(CGSize)size inContext:(JSContext *)context
{
    return [self valueWithObject:@{@"width": @(size.width), @"height": @(size.height)} inContext:context];
}

- (CGPoint)toPoint
{
    return CGPointMake([[self valueForProperty:@"x"] toDouble], [[self valueForProperty:@"y"] toDouble]);
}

- (NSRange)toRange
{
    return NSMakeRange((NSUInteger)[[self valueForProperty:@"location"] toDouble], (NSUInteger)[[self valueForProperty:@"length"] toDouble]);
}

- (CGRect)toRect
{
    return CGRectMake([[self valueForProperty:@"x"] toDouble], [[self valueForProperty:@"y"] toDouble], [[self valueForProperty:@"width"] toDouble], [[self valueForProperty:@"height"] toDouble]);
}

- (CGSize)toSize
{
    return CGSizeMake([[self valueForProperty:@"width"] toDouble], [[self valueForProperty:@"height"] toDouble]);
}

- (NSString *)description
{
    return self.toString;
}

/*
 * Promises. The release's engine (2012) has none, so one is built here, the way the JavaScriptCore
 * that has them builds its own: the algorithms are script (WebKit's PromiseOperations.js and
 * PromiseConstructor.js are too), and the state a promise keeps is a private property of an object
 * made with a JSClassRef whose class name is "Promise", which script cannot see or change and which
 * makes Object.prototype.toString answer "[object Promise]". Reactions run as jobs from the queue in
 * JSInternal.m, when the outermost call into script returns. What the 2012 engine cannot iterate
 * does not exist in it: arrays, strings and arguments objects are all the iterables it has, and
 * Promise.all/race/allSettled take exactly those. The constructor is found again through the
 * virtual machine's weak object map, keyed by the global object, so a context has one for as long
 * as anything can reach it; a context -init makes also gets it as its global Promise, and a context
 * adopted from elsewhere (a web view's page) is left as its owner made it.
 */
static const char CharonPromiseSource[] =
    "(function (makePromise, promiseState, callFunction, noteJobs, reportError) {\n"
    "'use strict';\n"
    "var TypeErrorConstructor = TypeError, isArray = Array.isArray, toTag = Object.prototype.toString;\n"
    "var define = Object.defineProperty, PENDING = 0, FULFILLED = 1, REJECTED = 2;\n"
    "var jobs = [], head = 0;\n"
    "function drain() {\n"
    "    while (head < jobs.length) {\n"
    "        var job = jobs[head];\n"
    "        jobs[head++] = undefined;\n"
    "        try { job(); } catch (error) { reportError(error); }\n"
    "    }\n"
    "    jobs.length = 0;\n"
    "    head = 0;\n"
    "}\n"
    "function enqueue(job) {\n"
    "    jobs[jobs.length] = job;\n"
    "    if (jobs.length - head === 1)\n"
    "        noteJobs(drain);\n"
    "}\n"
    "function isObject(value) {\n"
    "    return value !== null && (typeof value === 'object' || typeof value === 'function');\n"
    "}\n"
    "function settle(state, outcome, value) {\n"
    "    var reactions = state.reactions;\n"
    "    state.outcome = outcome;\n"
    "    state.value = value;\n"
    "    state.reactions = undefined;\n"
    "    for (var index = 0; index < reactions.length; index++)\n"
    "        react(reactions[index], outcome, value);\n"
    "}\n"
    "function react(reaction, outcome, value) {\n"
    "    enqueue(function () {\n"
    "        var handler = outcome === FULFILLED ? reaction.onFulfilled : reaction.onRejected, result;\n"
    "        if (handler === undefined) {\n"
    "            if (outcome === FULFILLED)\n"
    "                reaction.resolve(value);\n"
    "            else\n"
    "                reaction.reject(value);\n"
    "            return;\n"
    "        }\n"
    "        try {\n"
    "            result = handler(value);\n"
    "        } catch (error) {\n"
    "            reaction.reject(error);\n"
    "            return;\n"
    "        }\n"
    "        reaction.resolve(result);\n"
    "    });\n"
    "}\n"
    "function resolvingFunctions(promise, state) {\n"
    "    var alreadyResolved = false;\n"
    "    function resolve(resolution) {\n"
    "        if (alreadyResolved)\n"
    "            return;\n"
    "        alreadyResolved = true;\n"
    "        if (resolution === promise)\n"
    "            return settle(state, REJECTED, new TypeErrorConstructor('Cannot resolve a promise with itself'));\n"
    "        if (!isObject(resolution))\n"
    "            return settle(state, FULFILLED, resolution);\n"
    "        var then;\n"
    "        try {\n"
    "            then = resolution.then;\n"
    "        } catch (error) {\n"
    "            return settle(state, REJECTED, error);\n"
    "        }\n"
    "        if (typeof then !== 'function')\n"
    "            return settle(state, FULFILLED, resolution);\n"
    "        enqueue(function () {\n"
    "            var functions = resolvingFunctions(promise, state);\n"
    "            try {\n"
    "                callFunction(then, resolution, functions.resolve, functions.reject);\n"
    "            } catch (error) {\n"
    "                functions.reject(error);\n"
    "            }\n"
    "        });\n"
    "    }\n"
    "    function reject(reason) {\n"
    "        if (alreadyResolved)\n"
    "            return;\n"
    "        alreadyResolved = true;\n"
    "        settle(state, REJECTED, reason);\n"
    "    }\n"
    "    return { resolve: resolve, reject: reject };\n"
    "}\n"
    "function newState() {\n"
    "    return { outcome: PENDING, value: undefined, reactions: [] };\n"
    "}\n"
    "function Promise(executor) {\n"
    "    if (!(this instanceof Promise) || promiseState(this) !== undefined)\n"
    "        throw new TypeErrorConstructor('Promise constructor cannot be called without new');\n"
    "    if (typeof executor !== 'function')\n"
    "        throw new TypeErrorConstructor('Promise constructor takes a function argument');\n"
    "    var state = newState(), promise = makePromise(prototype, state), functions = resolvingFunctions(promise, state);\n"
    "    try {\n"
    "        executor(functions.resolve, functions.reject);\n"
    "    } catch (error) {\n"
    "        functions.reject(error);\n"
    "    }\n"
    "    return promise;\n"
    "}\n"
    "var prototype = Promise.prototype;\n"
    "function capability(C) {\n"
    "    if (C === Promise) {\n"
    "        var state = newState(), promise = makePromise(prototype, state), functions = resolvingFunctions(promise, state);\n"
    "        return { promise: promise, resolve: functions.resolve, reject: functions.reject };\n"
    "    }\n"
    "    if (typeof C !== 'function')\n"
    "        throw new TypeErrorConstructor('A promise capability needs a constructor');\n"
    "    var resolve, reject;\n"
    "    var made = new C(function (resolveFunction, rejectFunction) {\n"
    "        if (resolve !== undefined || reject !== undefined)\n"
    "            throw new TypeErrorConstructor('A promise executor was called twice');\n"
    "        resolve = resolveFunction;\n"
    "        reject = rejectFunction;\n"
    "    });\n"
    "    if (typeof resolve !== 'function' || typeof reject !== 'function')\n"
    "        throw new TypeErrorConstructor('A promise constructor did not supply its resolving functions');\n"
    "    return { promise: made, resolve: resolve, reject: reject };\n"
    "}\n"
    /* The engine has no @@species; the one thing it stands for that an ES5 script can build is a
     * constructor whose prototype inherits Promise.prototype, and that is what is kept. */
    "function speciesConstructor(promise) {\n"
    "    var C = promise.constructor;\n"
    "    if (C === undefined)\n"
    "        return Promise;\n"
    "    if (!isObject(C))\n"
    "        throw new TypeErrorConstructor('A promise\\'s constructor property is not an object');\n"
    "    if (C !== Promise && typeof C === 'function' && isObject(C.prototype) && C.prototype instanceof Promise)\n"
    "        return C;\n"
    "    return Promise;\n"
    "}\n"
    "function promiseResolve(C, value) {\n"
    "    if (promiseState(value) !== undefined && value.constructor === C)\n"
    "        return value;\n"
    "    var made = capability(C);\n"
    "    made.resolve(value);\n"
    "    return made.promise;\n"
    "}\n"
    "function then(onFulfilled, onRejected) {\n"
    "    var state = promiseState(this);\n"
    "    if (state === undefined)\n"
    "        throw new TypeErrorConstructor('Promise.prototype.then called on an object that is not a promise');\n"
    "    var made = capability(speciesConstructor(this));\n"
    "    var reaction = { resolve: made.resolve, reject: made.reject,\n"
    "        onFulfilled: typeof onFulfilled === 'function' ? onFulfilled : undefined,\n"
    "        onRejected: typeof onRejected === 'function' ? onRejected : undefined };\n"
    "    if (state.outcome === PENDING)\n"
    "        state.reactions[state.reactions.length] = reaction;\n"
    "    else\n"
    "        react(reaction, state.outcome, state.value);\n"
    "    return made.promise;\n"
    "}\n"
    "function catchRejection(onRejected) {\n"
    "    return this.then(undefined, onRejected);\n"
    "}\n"
    "function runFinally(onFinally) {\n"
    "    var promise = this;\n"
    "    if (!isObject(promise))\n"
    "        throw new TypeErrorConstructor('Promise.prototype.finally called on a value that is not an object');\n"
    "    var C = speciesConstructor(promise);\n"
    "    if (typeof onFinally !== 'function')\n"
    "        return promise.then(onFinally, onFinally);\n"
    "    return promise.then(function (value) {\n"
    "        return promiseResolve(C, onFinally()).then(function () { return value; });\n"
    "    }, function (reason) {\n"
    "        return promiseResolve(C, onFinally()).then(function () { throw reason; });\n"
    "    });\n"
    "}\n"
    "function resolveStatic(value) {\n"
    "    if (!isObject(this))\n"
    "        throw new TypeErrorConstructor('Promise.resolve called on a value that is not an object');\n"
    "    return promiseResolve(this, value);\n"
    "}\n"
    "function rejectStatic(reason) {\n"
    "    var made = capability(this);\n"
    "    made.reject(reason);\n"
    "    return made.promise;\n"
    "}\n"
    /* Each iterable this engine has, walked the way its iterator would: an array or arguments object
     * by index up to a length read before each step, a string by code point. */
    "function forEachOf(iterable, visit) {\n"
    "    var index;\n"
    "    if (typeof iterable === 'string') {\n"
    "        for (index = 0; index < iterable.length; index++) {\n"
    "            var unit = iterable.charCodeAt(index), next = iterable.charCodeAt(index + 1);\n"
    "            if (unit >= 0xD800 && unit <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {\n"
    "                visit(iterable.charAt(index) + iterable.charAt(index + 1));\n"
    "                index++;\n"
    "            } else {\n"
    "                visit(iterable.charAt(index));\n"
    "            }\n"
    "        }\n"
    "        return;\n"
    "    }\n"
    "    if (!isArray(iterable) && callFunction(toTag, Object(iterable)) !== '[object Arguments]')\n"
    "        throw new TypeErrorConstructor('The value is not iterable');\n"
    "    for (index = 0; index < iterable.length; index++)\n"
    "        visit(iterable[index]);\n"
    "}\n"
    "function combine(C, iterable, onEach, onEnd) {\n"
    "    var made = capability(C);\n"
    "    try {\n"
    "        var resolveFunction = C.resolve;\n"
    "        if (typeof resolveFunction !== 'function')\n"
    "            throw new TypeErrorConstructor('Promise resolve is not a function');\n"
    "        var values = [], remaining = 1, index = 0;\n"
    "        forEachOf(iterable, function (item) {\n"
    "            var position = index++;\n"
    "            values[position] = undefined;\n"
    "            remaining++;\n"
    "            var called = false;\n"
    "            onEach(callFunction(resolveFunction, C, item), made, function (value) {\n"
    "                if (called)\n"
    "                    return;\n"
    "                called = true;\n"
    "                values[position] = value;\n"
    "                if (--remaining === 0)\n"
    "                    made.resolve(values);\n"
    "            });\n"
    "        });\n"
    "        if (onEnd && --remaining === 0)\n"
    "            made.resolve(values);\n"
    "    } catch (error) {\n"
    "        made.reject(error);\n"
    "    }\n"
    "    return made.promise;\n"
    "}\n"
    "function all(iterable) {\n"
    "    return combine(this, iterable, function (next, made, store) {\n"
    "        next.then(store, made.reject);\n"
    "    }, true);\n"
    "}\n"
    "function allSettled(iterable) {\n"
    "    return combine(this, iterable, function (next, made, store) {\n"
    "        next.then(function (value) {\n"
    "            store({ status: 'fulfilled', value: value });\n"
    "        }, function (reason) {\n"
    "            store({ status: 'rejected', reason: reason });\n"
    "        });\n"
    "    }, true);\n"
    "}\n"
    "function race(iterable) {\n"
    "    return combine(this, iterable, function (next, made) {\n"
    "        next.then(made.resolve, made.reject);\n"
    "    }, false);\n"
    "}\n"
    "function method(target, name, value) {\n"
    "    define(target, name, { value: value, writable: true, enumerable: false, configurable: true });\n"
    "}\n"
    "method(prototype, 'then', then);\n"
    "method(prototype, 'catch', catchRejection);\n"
    "method(prototype, 'finally', runFinally);\n"
    "method(Promise, 'resolve', resolveStatic);\n"
    "method(Promise, 'reject', rejectStatic);\n"
    "method(Promise, 'all', all);\n"
    "method(Promise, 'allSettled', allSettled);\n"
    "method(Promise, 'race', race);\n"
    "define(Promise, 'prototype', { writable: false });\n"
    "return Promise;\n"
    "})";

static NSString *const CharonPromiseStateName = @"charon.promise.state";

static JSClassRef PromiseClass(void)
{
    static JSClassRef promiseClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        JSClassDefinition definition = kJSClassDefinitionEmpty;
        definition.className = "Promise";
        definition.attributes = kJSClassAttributeNoAutomaticPrototype;
        promiseClass = JSClassCreate(&definition);
    });
    return promiseClass;
}


/* makePromise(prototype, state): a promise object holding `state` where script cannot reach it. */
static JSValueRef MakePromise(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception)
{
    (void)function;
    (void)thisObject;
    JSObjectRef promise = JSObjectMake(ctx, PromiseClass(), NULL);
    JSObjectSetPrototype(ctx, promise, arguments[0]);
    JSStringRef name = charon_js_string(CharonPromiseStateName);
    bool kept = argumentCount == 2 && JSObjectSetPrivateProperty(ctx, promise, name, arguments[1]);
    JSStringRelease(name);
    if (!kept) {
        *exception = charon_js_type_error(ctx, @"this release's JavaScriptCore keeps no private property on a promise object");
        return JSValueMakeUndefined(ctx);
    }
    return promise;
}

/* promiseState(value): the state makePromise gave `value`, or undefined for anything else. */
static JSValueRef PromiseState(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception)
{
    (void)function;
    (void)thisObject;
    (void)exception;
    if (argumentCount < 1 || !JSValueIsObjectOfClass(ctx, arguments[0], PromiseClass()))
        return JSValueMakeUndefined(ctx);
    JSStringRef name = charon_js_string(CharonPromiseStateName);
    JSValueRef state = JSObjectGetPrivateProperty(ctx, (JSObjectRef)arguments[0], name);
    JSStringRelease(name);
    return state ?: JSValueMakeUndefined(ctx);
}

/* callFunction(function, thisObject, ...arguments): a call no script can intercept by replacing
 * Function.prototype.call. `thisObject` is always an object here. */
static JSValueRef CallFunction(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception)
{
    (void)function;
    (void)thisObject;
    JSObjectRef callee = argumentCount > 0 ? JSValueToObject(ctx, arguments[0], exception) : NULL;
    if (!callee || !JSObjectIsFunction(ctx, callee)) {
        if (!*exception)
            *exception = charon_js_type_error(ctx, @"the value is not a function");
        return JSValueMakeUndefined(ctx);
    }
    JSObjectRef receiver = argumentCount > 1 ? JSValueToObject(ctx, arguments[1], exception) : NULL;
    if (*exception)
        return JSValueMakeUndefined(ctx);
    size_t count = argumentCount > 2 ? argumentCount - 2 : 0;
    return JSObjectCallAsFunction(ctx, callee, receiver, count, count ? arguments + 2 : NULL, exception);
}

/* noteJobs(drain): this context has jobs queued; see charon_js_note_jobs. */
static JSValueRef NoteJobs(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception)
{
    (void)function;
    (void)thisObject;
    JSObjectRef drain = argumentCount > 0 ? JSValueToObject(ctx, arguments[0], exception) : NULL;
    if (drain)
        charon_js_note_jobs(ctx, drain);
    return JSValueMakeUndefined(ctx);
}

/* reportError(error): a job threw past its own promise, which is the context's uncaught exception. */
static JSValueRef ReportError(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception)
{
    (void)function;
    (void)thisObject;
    (void)exception;
    if (argumentCount > 0)
        [[JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(ctx) create:YES] charon_noteException:arguments[0]];
    return JSValueMakeUndefined(ctx);
}

static JSObjectRef PromiseHelper(JSContextRef ctx, const char *name, JSObjectCallAsFunctionCallback callback)
{
    JSStringRef string = JSStringCreateWithUTF8CString(name);
    JSObjectRef helper = JSObjectMakeFunctionWithCallback(ctx, string, callback);
    JSStringRelease(string);
    return helper;
}

/* The executor's resolving functions, caught by the executor function the constructor calls. */
typedef struct CharonPromiseCapture {
    JSValueRef resolve;
    JSValueRef reject;
} CharonPromiseCapture;

static JSValueRef CaptureExecutor(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception)
{
    (void)thisObject;
    (void)exception;
    CharonPromiseCapture *capture = JSObjectGetPrivate(function);
    if (capture && argumentCount >= 2) {
        capture->resolve = arguments[0];
        capture->reject = arguments[1];
    }
    return JSValueMakeUndefined(ctx);
}

static JSClassRef CaptureClass(void)
{
    static JSClassRef captureClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        JSClassDefinition definition = kJSClassDefinitionEmpty;
        definition.className = "CharonPromiseExecutor";
        definition.callAsFunction = CaptureExecutor;
        captureClass = JSClassCreate(&definition);
    });
    return captureClass;
}

/* The context's Promise constructor, made the first time it is asked for; NULL only if making it
 * failed, which the context's exception handler has then been told. */
static JSObjectRef PromiseConstructor(JSContext *context)
{
    JSGlobalContextRef ctx = context.JSGlobalContextRef;
    JSWeakObjectMapRef weak;
    JSGlobalContextRef weakContext = [context.virtualMachine charon_weakContext:&weak];
    void *key = JSContextGetGlobalObject(ctx);
    JSObjectRef constructor = JSWeakObjectMapGet(weakContext, weak, key);
    if (constructor)
        return constructor;
    JSStringRef source = JSStringCreateWithUTF8CString(CharonPromiseSource);
    JSValueRef exception = NULL;
    JSValueRef factory = JSEvaluateScript(ctx, source, NULL, NULL, 1, &exception);
    JSStringRelease(source);
    JSValueRef made = NULL;
    if (!exception) {
        JSValueRef helpers[] = {
            PromiseHelper(ctx, "makePromise", MakePromise),
            PromiseHelper(ctx, "promiseState", PromiseState),
            PromiseHelper(ctx, "callFunction", CallFunction),
            PromiseHelper(ctx, "noteJobs", NoteJobs),
            PromiseHelper(ctx, "reportError", ReportError),
        };
        made = JSObjectCallAsFunction(ctx, (JSObjectRef)factory, NULL, sizeof helpers / sizeof helpers[0], helpers, &exception);
    }
    if (exception || !made || !JSValueIsObject(ctx, made)) {
        NSLog(@"JSValue: this context's Promise constructor could not be made");
        [context charon_noteException:exception];
        return NULL;
    }
    constructor = (JSObjectRef)made;
    JSWeakObjectMapSet(weakContext, weak, key, constructor);
    return constructor;
}

/* A context -init made carries the constructor as its global Promise, as one with promises does.
 * The release's engine makes a fresh global object with no Promise of its own, so nothing is
 * replaced there; on an engine that has one, this constructor replaces it, which is how the host
 * test holds this implementation, not the host's, to the host's answers. */
+ (void)charon_installPromiseInContext:(JSContext *)context
{
    JSObjectRef constructor = PromiseConstructor(context);
    if (!constructor)
        return;
    JSGlobalContextRef ctx = context.JSGlobalContextRef;
    JSStringRef name = JSStringCreateWithUTF8CString("Promise");
    JSObjectSetProperty(ctx, JSContextGetGlobalObject(ctx), name, constructor, kJSPropertyAttributeDontEnum, NULL);
    JSStringRelease(name);
}

/*
 * As the release with promises does it: the promise exists before the executor runs, the executor
 * is called as a callback whose this is the promise and whose arguments are its resolving
 * functions, and an exception it sets on the context rejects the promise instead of reaching the
 * exception handler.
 */
+ (JSValue *)valueWithNewPromiseInContext:(JSContext *)context fromExecutor:(void (^)(JSValue *resolve, JSValue *reject))callback
{
    JSGlobalContextRef ctx = context.JSGlobalContextRef;
    charon_js_enter();
    JSObjectRef constructor = PromiseConstructor(context);
    if (!constructor) {
        charon_js_leave();
        return [JSValue valueWithUndefinedInContext:context];
    }
    CharonPromiseCapture capture = {NULL, NULL};
    JSObjectRef executor = JSObjectMake(ctx, CaptureClass(), &capture);
    JSValueRef argument = executor;
    JSValueRef exception = NULL;
    JSObjectRef promise = JSObjectCallAsConstructor(ctx, constructor, 1, &argument, &exception);
    JSObjectSetPrivate(executor, NULL);
    if (exception || !promise || !capture.resolve || !capture.reject) {
        JSValue *thrown = exception ? [JSValue charon_valueWithJSValueRef:exception context:context] : nil;
        charon_js_leave();
        [context charon_noteException:thrown.JSValueRef];
        return [JSValue valueWithUndefinedInContext:context];
    }
    JSValue *result = [JSValue charon_valueWithJSValueRef:promise context:context];
    JSValue *resolve = [JSValue charon_valueWithJSValueRef:capture.resolve context:context];
    JSValue *reject = [JSValue charon_valueWithJSValueRef:capture.reject context:context];
    if (callback) {
        /* The frame holds its arguments unretained; this local keeps them for the call. */
        NSArray<JSValue *> *arguments = @[resolve, reject];
        charon_js_push_callback(context, result, nil, arguments);
        callback(resolve, reject);
        JSValue *thrown = charon_js_pop_callback();
        if (thrown)
            [reject callWithArguments:@[thrown]];
    }
    charon_js_leave();
    return result;
}

/* The release builds these two on the executor form above and so does this. It puts the result
 * or reason into an array literal, so a nil one raises NSInvalidArgumentException out of it
 * (measured on the host: "attempt to insert nil object from objects[0]"); this makes the same
 * literal before any script runs, so the exception reaches the caller without unwinding through
 * the engine's frames. */
+ (JSValue *)valueWithNewPromiseResolvedWithResult:(id)result inContext:(JSContext *)context
{
    NSArray *arguments = @[result];
    return [self valueWithNewPromiseInContext:context fromExecutor:^(JSValue *resolve, JSValue *reject) {
        (void)reject;
        [resolve callWithArguments:arguments];
    }];
}

+ (JSValue *)valueWithNewPromiseRejectedWithReason:(id)reason inContext:(JSContext *)context
{
    NSArray *arguments = @[reason];
    return [self valueWithNewPromiseInContext:context fromExecutor:^(JSValue *resolve, JSValue *reject) {
        (void)resolve;
        [reject callWithArguments:arguments];
    }];
}

/*
 * Symbols. The release's engine has no symbol type: there is no value a symbol could be, and a
 * string or object standing in for one would be a different value that says it is the same. So
 * this refuses at the seam: the context is told a TypeError, as the release with symbols tells it
 * when a symbol is used where it cannot be, and the answer is undefined. -isSymbol is NO because
 * no value of this engine is one.
 */
+ (JSValue *)valueWithNewSymbolFromDescription:(NSString *)description inContext:(JSContext *)context
{
    (void)description;
    JSValue *error = [context[@"TypeError"] constructWithArguments:@[@"this release's JavaScript engine has no symbols"]];
    [context charon_noteException:error.JSValueRef];
    return [JSValue valueWithUndefinedInContext:context];
}

- (BOOL)isSymbol
{
    return NO;
}

@end
