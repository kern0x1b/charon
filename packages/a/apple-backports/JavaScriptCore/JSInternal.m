#import "JSInternal.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <pthread.h>

/*
 * Every symbol this file defines is Charon's own (the charon_/Charon prefix modules/apple/
 * backports.lua's internal_symbol() keys on), never a real SDK name, and that is deliberate: it
 * is the one place in this package that must be kept whole on every band regardless of whether
 * JSValue, JSContext or any other class here gets reexported from the release instead of carried.
 * A helper functions like these two ever needed unconditionally - charon_js_box/unbox, the string
 * bridge, the block- and opaque-object JSClassRefs, the callback frame stack - used to live inside
 * JSValue.m and JSContext.m, the same object files as the JSValue/JSContext classes themselves.
 * Once a band's release genuinely carries JavaScriptCore (iOS 7.0 and later), those two classes
 * are reexported from the system instead of kept, and band() in backports.lua drops their whole
 * object file - taking these helpers down with it, even though JSExportBridge.m (whose own class,
 * CharonExportBinding, is never a real SDK name and so is always kept) calls them unconditionally
 * on every band. That produced "Undefined symbols: _charon_js_box" etc. at write_deb's
 * multi-band link step only - never at a single-release build(), which never reexports anything -
 * confirmed by instrumenting link() directly: kept every JavaScriptCore object on the 6.1.3 band,
 * kept only JSExportBridge.o on the 7.0 band. Moving them here, where nothing but Charon's own
 * names is defined, means band() always keeps this object regardless of what else in the library
 * gets reexported.
 */

extern const char *_Block_signature(void *block);

JSStringRef charon_js_string(NSString *string)
{
    return JSStringCreateWithCFString((__bridge CFStringRef)(string ?: @""));
}

NSString *charon_ns_string(JSStringRef string)
{
    return string ? CFBridgingRelease(JSStringCopyCFString(kCFAllocatorDefault, string)) : @"";
}

static BOOL IsCFBoolean(id value)
{
    return value && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

/*
 * A block is exported as a JS function through one shared JSClassRef, whose private data on
 * each JSObjectRef is the retained block. Supported blocks: every argument and the return value
 * is object-pointer-shaped (id, an NSObject subclass, or another block) - checked once, against
 * the block's own Objective-C type encoding from _Block_signature, not assumed. A block with a
 * primitive argument or return type is still wrapped, but calling it throws in JavaScript rather
 * than reading a garbage value off the wrong-sized argument slot.
 */
static BOOL BlockSignatureIsAllObjects(const char *encoding, NSUInteger *outArgumentCount)
{
    if (!encoding)
        return NO;
    NSMethodSignature *signature = nil;
    @try {
        signature = [NSMethodSignature signatureWithObjCTypes:encoding];
    } @catch (__unused NSException *exception) {
        return NO;
    }
    if (!signature)
        return NO;
    const char *returnType = signature.methodReturnType;
    if (!(returnType[0] == '@' || returnType[0] == 'v'))
        return NO;
    NSUInteger arguments = signature.numberOfArguments; /* argument 0 is the block itself */
    if (arguments < 1 || arguments > 7)
        return NO;
    for (NSUInteger index = 1; index < arguments; index++) {
        const char *type = [signature getArgumentTypeAtIndex:index];
        if (type[0] != '@')
            return NO;
    }
    if (outArgumentCount)
        *outArgumentCount = arguments - 1;
    return YES;
}

static JSValueRef BlockCallAsFunction(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception)
{
    id block = (__bridge id)JSObjectGetPrivate(function);
    const char *encoding = _Block_signature((__bridge void *)block);
    NSUInteger wanted = 0;
    if (!BlockSignatureIsAllObjects(encoding, &wanted)) {
        JSContext *context = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(ctx) create:YES];
        JSValue *error = [JSValue valueWithNewErrorFromMessage:@"this block's argument or return type is not supported" inContext:context];
        if (exception)
            *exception = error.JSValueRef;
        return JSValueMakeUndefined(ctx);
    }
    JSContext *context = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(ctx) create:YES];
    id args[7] = {block, nil, nil, nil, nil, nil, nil};
    for (NSUInteger index = 0; index < wanted && index < argumentCount; index++)
        args[index + 1] = charon_js_unbox(ctx, arguments[index], exception);
    NSMutableArray<JSValue *> *boxedArguments = [NSMutableArray array];
    for (NSUInteger index = 0; index < wanted; index++)
        [boxedArguments addObject:[JSValue charon_valueWithJSValueRef:charon_js_box(ctx, args[index + 1]) context:context]];
    JSValue *thisValue = [JSValue charon_valueWithJSValueRef:thisObject context:context];
    charon_js_push_callback(context, thisValue, [JSValue charon_valueWithJSValueRef:function context:context], boxedArguments);
    id result = nil;
    /* A block literal is {isa, flags, reserved, invoke, descriptor, ...captures} - the callable
     * function pointer is the `invoke` field, not the block's own address, which is a struct
     * pointer whose first bytes are `isa`, not code. ARC also will not let an Objective-C
     * pointer be called as a raw C function pointer directly; bridging through void first strips
     * that tracking, which is safe here since `block` is kept alive by `args[0]` throughout. */
    struct CharonBlockLayout { void *isa; int flags; int reserved; void *invoke; };
    void *blockPointer = (__bridge void *)block;
    void *invoke = ((struct CharonBlockLayout *)blockPointer)->invoke;
    void *rawArgs[7] = {blockPointer, (__bridge void *)args[1], (__bridge void *)args[2], (__bridge void *)args[3], (__bridge void *)args[4], (__bridge void *)args[5], (__bridge void *)args[6]};
    id unretainedResult = nil;
    switch (wanted) {
    case 0: unretainedResult = ((id (*)(void *))invoke)(rawArgs[0]); break;
    case 1: unretainedResult = ((id (*)(void *, void *))invoke)(rawArgs[0], rawArgs[1]); break;
    case 2: unretainedResult = ((id (*)(void *, void *, void *))invoke)(rawArgs[0], rawArgs[1], rawArgs[2]); break;
    case 3: unretainedResult = ((id (*)(void *, void *, void *, void *))invoke)(rawArgs[0], rawArgs[1], rawArgs[2], rawArgs[3]); break;
    case 4: unretainedResult = ((id (*)(void *, void *, void *, void *, void *))invoke)(rawArgs[0], rawArgs[1], rawArgs[2], rawArgs[3], rawArgs[4]); break;
    case 5: unretainedResult = ((id (*)(void *, void *, void *, void *, void *, void *))invoke)(rawArgs[0], rawArgs[1], rawArgs[2], rawArgs[3], rawArgs[4], rawArgs[5]); break;
    case 6: unretainedResult = ((id (*)(void *, void *, void *, void *, void *, void *, void *))invoke)(rawArgs[0], rawArgs[1], rawArgs[2], rawArgs[3], rawArgs[4], rawArgs[5], rawArgs[6]); break;
    }
    result = unretainedResult;
    charon_js_pop_callback();
    return charon_js_box(ctx, result);
}

static void BlockFinalize(JSObjectRef object)
{
    CFBridgingRelease(JSObjectGetPrivate(object));
}

static JSClassRef BlockClass(void)
{
    static JSClassRef blockClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        JSClassDefinition definition = kJSClassDefinitionEmpty;
        definition.className = "CharonBlockFunction";
        definition.callAsFunction = BlockCallAsFunction;
        definition.finalize = BlockFinalize;
        blockClass = JSClassCreate(&definition);
    });
    return blockClass;
}

/* An opaque wrapper for a plain Objective-C object that JSExport does not describe: it round
 * trips through -toObject, but exposes no properties or methods to JavaScript. */
static void OpaqueFinalize(JSObjectRef object)
{
    CFBridgingRelease(JSObjectGetPrivate(object));
}

static JSClassRef OpaqueClass(void)
{
    static JSClassRef opaqueClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        JSClassDefinition definition = kJSClassDefinitionEmpty;
        definition.className = "CharonOpaqueObject";
        definition.finalize = OpaqueFinalize;
        opaqueClass = JSClassCreate(&definition);
    });
    return opaqueClass;
}

JSValueRef charon_js_box(JSContextRef context, id object)
{
    if (!object)
        return JSValueMakeUndefined(context);
    /* a JSValue passed back in as a plain `id` is already a JavaScript value - unwrap it rather
     * than wrapping the wrapper as a fresh opaque object */
    if ([object isKindOfClass:[JSValue class]])
        return ((JSValue *)object).JSValueRef;
    if (object == (id)kCFNull || [object isKindOfClass:[NSNull class]])
        return JSValueMakeNull(context);
    if (IsCFBoolean(object))
        return JSValueMakeBoolean(context, [object boolValue]);
    if ([object isKindOfClass:[NSNumber class]])
        return JSValueMakeNumber(context, [object doubleValue]);
    if ([object isKindOfClass:[NSString class]]) {
        JSStringRef string = charon_js_string(object);
        JSValueRef value = JSValueMakeString(context, string);
        JSStringRelease(string);
        return value;
    }
    if ([object isKindOfClass:[NSDate class]])
        return JSObjectMakeDate(context, 1, (const JSValueRef[]){JSValueMakeNumber(context, [(NSDate *)object timeIntervalSince1970] * 1000.0)}, NULL);
    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *array = object;
        NSUInteger count = array.count;
        JSValueRef *values = count ? malloc(sizeof(JSValueRef) * count) : NULL;
        for (NSUInteger index = 0; index < count; index++)
            values[index] = charon_js_box(context, array[index]);
        JSValueRef result = JSObjectMakeArray(context, count, values, NULL);
        free(values);
        return result;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        JSObjectRef result = JSObjectMake(context, NULL, NULL);
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            (void)stop;
            JSStringRef name = charon_js_string([key description]);
            JSObjectSetProperty(context, result, name, charon_js_box(context, value), kJSPropertyAttributeNone, NULL);
            JSStringRelease(name);
        }];
        return result;
    }
    if ([object isKindOfClass:NSClassFromString(@"NSBlock")]) {
        JSObjectRef function = JSObjectMake(context, BlockClass(), (void *)CFBridgingRetain(object));
        return function;
    }
    if (charon_js_class_conforms_to_export(object_getClass(object)))
        return JSObjectMake(context, charon_js_export_class(object_getClass(object)), (void *)CFBridgingRetain(object));
    return JSObjectMake(context, OpaqueClass(), (void *)CFBridgingRetain(object));
}

id charon_js_unbox(JSContextRef context, JSValueRef value, JSValueRef *exception)
{
    if (!value)
        return nil;
    switch (JSValueGetType(context, value)) {
    case kJSTypeUndefined:
    case kJSTypeNull:
        return nil;
    case kJSTypeBoolean:
        return @(JSValueToBoolean(context, value));
    case kJSTypeNumber:
        return @(JSValueToNumber(context, value, exception));
    case kJSTypeString: {
        JSStringRef string = JSValueToStringCopy(context, value, exception);
        NSString *result = charon_ns_string(string);
        if (string)
            JSStringRelease(string);
        return result;
    }
    default:
        break;
    }
    if (!JSValueIsObject(context, value))
        return nil;
    JSObjectRef object = JSValueToObject(context, value, exception);
    if (!object)
        return nil;
    void *private = JSObjectGetPrivate(object);
    if (private)
        return (__bridge id)private;
    if (JSObjectIsFunction(context, object) || JSObjectIsConstructor(context, object))
        return [JSValue charon_valueWithJSValueRef:value context:[JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(context) create:YES]];
    /* a plain JavaScript object or array with no private data: copy its own properties */
    JSObjectRef globalObject = JSContextGetGlobalObject(context);
    JSStringRef arrayName = charon_js_string(@"Array");
    JSValueRef arrayConstructor = JSObjectGetProperty(context, globalObject, arrayName, NULL);
    JSStringRelease(arrayName);
    BOOL isArray = arrayConstructor && JSValueIsObject(context, arrayConstructor) &&
                   JSValueIsInstanceOfConstructor(context, value, JSValueToObject(context, arrayConstructor, NULL), NULL);
    if (isArray) {
        JSStringRef lengthName = charon_js_string(@"length");
        double length = JSValueToNumber(context, JSObjectGetProperty(context, object, lengthName, exception), exception);
        JSStringRelease(lengthName);
        if (length == length && length >= 0 && length < 1e9) {
            NSMutableArray *array = [NSMutableArray array];
            for (NSUInteger index = 0; index < (NSUInteger)length; index++)
                [array addObject:charon_js_unbox(context, JSObjectGetPropertyAtIndex(context, object, (unsigned)index, exception), exception) ?: [NSNull null]];
            return array;
        }
    }
    JSPropertyNameArrayRef names = JSObjectCopyPropertyNames(context, object);
    size_t count = JSPropertyNameArrayGetCount(names);
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:count];
    for (size_t index = 0; index < count; index++) {
        JSStringRef name = JSPropertyNameArrayGetNameAtIndex(names, index);
        id unboxed = charon_js_unbox(context, JSObjectGetProperty(context, object, name, exception), exception);
        if (unboxed)
            dictionary[charon_ns_string(name)] = unboxed;
    }
    JSPropertyNameArrayRelease(names);
    return dictionary;
}

/*
 * +currentContext, +currentThis, +currentCallee and +currentArguments only answer from inside a
 * callback JavaScript makes into Objective-C - a block or a JSExport method. A pthread key holds
 * a small stack of frames, one push per nested callback, so a callback that itself calls back
 * into JavaScript which calls back into Objective-C again still answers correctly for its own
 * frame once the inner one pops.
 */
static pthread_key_t charon_frame_key;
static pthread_once_t charon_frame_once = PTHREAD_ONCE_INIT;

static void CharonMakeFrameKey(void)
{
    pthread_key_create(&charon_frame_key, NULL);
}

CharonJSFrame *CharonCurrentFrame(void)
{
    pthread_once(&charon_frame_once, CharonMakeFrameKey);
    return pthread_getspecific(charon_frame_key);
}

void charon_js_push_callback(JSContext *context, JSValue *thisValue, JSValue *callee, NSArray<JSValue *> *arguments)
{
    pthread_once(&charon_frame_once, CharonMakeFrameKey);
    CharonJSFrame *frame = calloc(1, sizeof(CharonJSFrame));
    frame->up = CharonCurrentFrame();
    frame->context = context;
    frame->thisValue = thisValue;
    frame->callee = callee;
    frame->arguments = arguments;
    pthread_setspecific(charon_frame_key, frame);
}

void charon_js_pop_callback(void)
{
    CharonJSFrame *frame = CharonCurrentFrame();
    if (!frame)
        return;
    pthread_setspecific(charon_frame_key, frame->up);
    free(frame);
}
