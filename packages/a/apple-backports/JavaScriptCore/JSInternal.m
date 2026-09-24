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
 * A block's Objective-C type encoding, read as the documented clang Block ABI lays it out
 * (clang's docs/Block-ABI-Apple.rst): a block literal is {isa, flags, reserved, invoke,
 * descriptor}; the descriptor is {reserved, size}, then {copy, dispose} when
 * BLOCK_HAS_COPY_DISPOSE (1 << 25) is set, then the encoding when BLOCK_HAS_SIGNATURE (1 << 30)
 * is. The compiler that built the block writes it there, not the runtime, so the release's
 * libsystem_blocks has no say in it. This is the pointer _Block_signature (an SPI of
 * Block_private.h) answers - measured equal on the host for a global, a capturing and a
 * primitive-typed block - read without the SPI. A block with no signature (built by a compiler
 * older than blocks' extended encodings) answers NULL.
 */
struct CharonBlockDescriptor { unsigned long reserved; unsigned long size; void *rest[]; };
struct CharonBlockLayout { void *isa; int flags; int reserved; void *invoke; struct CharonBlockDescriptor *descriptor; };
enum { CharonBlockHasCopyDispose = 1 << 25, CharonBlockHasSignature = 1 << 30 };

static const char *BlockSignature(id block)
{
    struct CharonBlockLayout *layout = (__bridge void *)block;
    if (!(layout->flags & CharonBlockHasSignature))
        return NULL;
    void **field = layout->descriptor->rest;
    if (layout->flags & CharonBlockHasCopyDispose)
        field += 2;
    return *(const char **)field;
}

typedef enum { CharonTypeVoid, CharonTypeJSValue, CharonTypeId, CharonTypeClass, CharonTypeScalar, CharonTypeUnsupported } CharonTypeKind;
typedef struct { CharonTypeKind kind; __unsafe_unretained Class objcClass; } CharonType;

/* The end of the one type at `cursor`, qualifiers, nesting and trailing offset included. */
static const char *SkipType(const char *cursor)
{
    while (*cursor && strchr("rnNoORVA", *cursor))
        cursor++;
    char open = *cursor, close = open == '{' ? '}' : open == '(' ? ')' : open == '[' ? ']' : 0;
    if (close) {
        int depth = 0;
        do {
            if (*cursor == open)
                depth++;
            else if (*cursor == close)
                depth--;
            cursor++;
        } while (*cursor && depth);
    } else if (open == '^') {
        cursor = SkipType(cursor + 1);
    } else if (open == '@') {
        cursor++;
        if (*cursor == '"') {
            const char *end = strchr(cursor + 1, '"');
            cursor = end ? end + 1 : cursor + strlen(cursor);
        } else if (*cursor == '?') {
            cursor++;
            if (*cursor == '<') {
                const char *end = cursor;
                for (int depth = 0; *end; end++)
                    if (*end == '<')
                        depth++;
                    else if (*end == '>' && !--depth)
                        break;
                cursor = *end ? end + 1 : end;
            }
        }
    } else if (*cursor) {
        cursor++;
    }
    while (*cursor >= '0' && *cursor <= '9')
        cursor++;
    return cursor;
}

/*
 * One type of a block's extended encoding (`@"NSString"` names the class), classified as the
 * release's own JSContext treats it (measured against the host's, tests/backports/host/jscontext):
 * JSValue, id, any other class - `@"Class<Protocol>"` counts as the class, a bare `@"<Protocol>"`
 * as id; a C number, BOOL, CGPoint, CGSize, CGRect or NSRange is a scalar; anything else - a
 * block, Class, SEL, a pointer, another struct, a class the runtime does not know - is unsupported, and the release does not make such a block a
 * function at all (`typeof` answers "object").
 */
static CharonType ClassifyType(const char *cursor)
{
    while (*cursor && strchr("rnNoORVA", *cursor))
        cursor++;
    CharonType type = {CharonTypeUnsupported, Nil};
    switch (*cursor) {
    case 'v':
        type.kind = CharonTypeVoid;
        break;
    case '@': {
        if (cursor[1] != '"') {
            type.kind = cursor[1] == '?' ? CharonTypeUnsupported : CharonTypeId;
            break;
        }
        const char *name = cursor + 2;
        size_t length = strcspn(name, "\"<");
        if (!length) {
            type.kind = CharonTypeId;
            break;
        }
        type.objcClass = NSClassFromString([[NSString alloc] initWithBytes:name length:length encoding:NSUTF8StringEncoding]);
        if (type.objcClass)
            type.kind = type.objcClass == [JSValue class] ? CharonTypeJSValue : CharonTypeClass;
        break;
    }
    case 'c': case 'i': case 's': case 'l': case 'q': case 'C': case 'I': case 'S': case 'L': case 'Q':
    case 'f': case 'd': case 'B':
        type.kind = CharonTypeScalar;
        break;
    case '{':
        /* the four structs JSValue converts; any other struct makes no function (measured) */
        for (const char *name = "CGPoint\0CGSize\0CGRect\0_NSRange\0"; *name; name += strlen(name) + 1)
            if (!strncmp(cursor + 1, name, strlen(name)) && cursor[1 + strlen(name)] == '=')
                type.kind = CharonTypeScalar;
        break;
    }
    return type;
}

/* What a block can be to JavaScript, from its encoding: a function whose every argument and
 * return is carried, a function the release could call but this bridge refuses (a scalar - see
 * BlockCallAsFunction), or no function at all. */
typedef enum { CharonBlockNotFunction, CharonBlockRefused, CharonBlockCallable } CharonBlockShape;
enum { CharonBlockMaxArguments = 6 };

static CharonBlockShape BlockShape(id block, CharonType *arguments, NSUInteger *outCount, BOOL *outReturnsVoid)
{
    const char *cursor = BlockSignature(block);
    if (!cursor)
        return CharonBlockNotFunction;
    while (*cursor && strchr("rnNoORVA", *cursor))
        cursor++;
    CharonBlockShape shape = CharonBlockCallable;
    BOOL returnsVoid = *cursor == 'v';
    if (ClassifyType(cursor).kind == CharonTypeScalar)
        shape = CharonBlockRefused;
    else if (!returnsVoid && *cursor != '@') /* any object, a block included, is returned boxed */
        return CharonBlockNotFunction;
    cursor = SkipType(cursor);
    if (cursor[0] != '@' || cursor[1] != '?') /* argument 0 is the block itself */
        return CharonBlockNotFunction;
    cursor = SkipType(cursor);
    NSUInteger count = 0;
    while (*cursor) {
        CharonType type = ClassifyType(cursor);
        if (type.kind == CharonTypeUnsupported || type.kind == CharonTypeVoid)
            return CharonBlockNotFunction;
        if (type.kind == CharonTypeScalar || count == CharonBlockMaxArguments)
            shape = CharonBlockRefused;
        else
            arguments[count] = type;
        count++;
        cursor = SkipType(cursor);
    }
    *outCount = count;
    *outReturnsVoid = returnsVoid;
    return shape;
}

/* One JavaScript argument as its declared class wants it, per the release: JSValue takes the
 * value itself, id takes -toObject, a class goes through charon_js_to_class. */
static id ObjectArgument(JSContextRef ctx, JSContext *context, CharonType type, JSValueRef value, JSValueRef *exception)
{
    switch (type.kind) {
    case CharonTypeJSValue:
        return [JSValue charon_valueWithJSValueRef:value context:context];
    case CharonTypeClass:
        return charon_js_to_class(ctx, value, type.objcClass, exception);
    default:
        return charon_js_unbox(ctx, value);
    }
}

id charon_js_argument(JSContextRef context, const char *type, JSValueRef value, JSValueRef *exception)
{
    JSContext *wrapper = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(context) create:YES];
    return ObjectArgument(context, wrapper, ClassifyType(type), value, exception);
}

const char *charon_js_skip_type(const char *type)
{
    return SkipType(type);
}

/*
 * A block is exported as a JS function through one shared JSClassRef, whose private data on
 * each JSObjectRef is the retained block. Its arguments are converted by the class its own
 * encoding declares. A block taking or returning a C number or struct, or taking more than six
 * arguments, is a function the release would call; this bridge calls blocks through their invoke
 * pointer with object-sized arguments only, so it throws a TypeError in JavaScript instead of
 * reading a value off the wrong-sized slot.
 */
static JSValueRef BlockCallAsFunction(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception)
{
    id block = (__bridge id)JSObjectGetPrivate(function);
    JSContext *context = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(ctx) create:YES];
    CharonType types[CharonBlockMaxArguments];
    NSUInteger wanted = 0;
    BOOL returnsVoid = NO;
    if (BlockShape(block, types, &wanted, &returnsVoid) != CharonBlockCallable) {
        if (exception)
            *exception = charon_js_type_error(ctx, @"this block's argument or return type is not supported");
        return JSValueMakeUndefined(ctx);
    }
    id args[CharonBlockMaxArguments + 1] = {block};
    for (NSUInteger index = 0; index < wanted; index++) {
        JSValueRef failure = NULL;
        args[index + 1] = ObjectArgument(ctx, context, types[index], index < argumentCount ? arguments[index] : JSValueMakeUndefined(ctx), &failure);
        if (failure) {
            if (exception)
                *exception = failure;
            return JSValueMakeUndefined(ctx);
        }
    }
    NSMutableArray<JSValue *> *callArguments = [NSMutableArray arrayWithCapacity:argumentCount];
    for (size_t index = 0; index < argumentCount; index++)
        [callArguments addObject:[JSValue charon_valueWithJSValueRef:arguments[index] context:context]];
    JSValue *thisValue = [JSValue charon_valueWithJSValueRef:thisObject context:context];
    charon_js_push_callback(context, thisValue, [JSValue charon_valueWithJSValueRef:function context:context], callArguments);
    id result = nil;
    /* The callable function pointer is the `invoke` field, not the block's own address, which is a
     * struct pointer whose first bytes are `isa`, not code. ARC also will not let an Objective-C
     * pointer be called as a raw C function pointer directly; bridging through void first strips
     * that tracking, which is safe here since `block` is kept alive by `args[0]` throughout. */
    void *blockPointer = (__bridge void *)block;
    void *invoke = ((struct CharonBlockLayout *)blockPointer)->invoke;
    void *rawArgs[7] = {blockPointer, (__bridge void *)args[1], (__bridge void *)args[2], (__bridge void *)args[3], (__bridge void *)args[4], (__bridge void *)args[5], (__bridge void *)args[6]};
    /* A block returning void leaves whatever r0 last held; reading that as an id would retain and
     * box a garbage pointer, so it is called through a void-returning type and answers undefined,
     * as the release's own JSContext does for such a block. */
    if (returnsVoid) {
        switch (wanted) {
        case 0: ((void (*)(void *))invoke)(rawArgs[0]); break;
        case 1: ((void (*)(void *, void *))invoke)(rawArgs[0], rawArgs[1]); break;
        case 2: ((void (*)(void *, void *, void *))invoke)(rawArgs[0], rawArgs[1], rawArgs[2]); break;
        case 3: ((void (*)(void *, void *, void *, void *))invoke)(rawArgs[0], rawArgs[1], rawArgs[2], rawArgs[3]); break;
        case 4: ((void (*)(void *, void *, void *, void *, void *))invoke)(rawArgs[0], rawArgs[1], rawArgs[2], rawArgs[3], rawArgs[4]); break;
        case 5: ((void (*)(void *, void *, void *, void *, void *, void *))invoke)(rawArgs[0], rawArgs[1], rawArgs[2], rawArgs[3], rawArgs[4], rawArgs[5]); break;
        case 6: ((void (*)(void *, void *, void *, void *, void *, void *, void *))invoke)(rawArgs[0], rawArgs[1], rawArgs[2], rawArgs[3], rawArgs[4], rawArgs[5], rawArgs[6]); break;
        }
        JSValue *thrown = charon_js_pop_callback();
        if (thrown && exception)
            *exception = thrown.JSValueRef;
        return JSValueMakeUndefined(ctx);
    }
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
    JSValue *thrown = charon_js_pop_callback();
    if (thrown) {
        if (exception)
            *exception = thrown.JSValueRef;
        return JSValueMakeUndefined(ctx);
    }
    return charon_js_box(ctx, result);
}

/*
 * Objects whose wrappers the collector finalized, waiting to be released outside the collection.
 * A finalizer must call nothing that may collect or allocate, "all functions that have a
 * JSContextRef parameter" included (JSObjectRef.h, JSObjectFinalizeCallback), and the last
 * release of a wrapped object runs its -dealloc, which may reach the C API (a JSManagedValue, a
 * graph token of JSVirtualMachine). The release's bridge hands such objects to the heap to release
 * after the collection (WebKit's Heap::releaseSoon); the C API has no end-of-collection hook, so
 * this releases them at the next outermost leave of any thread, or on the next turn of the run
 * loop of the thread that finalized them, whichever comes first. A finalizer can run on any thread
 * that uses the context group, so the list is shared and locked; each release happens outside the
 * lock, in a pool of its own, and a -dealloc that collects and finalizes more is taken in turn.
 */
typedef struct CharonReleaseNode {
    struct CharonReleaseNode *next;
    const void *object;
} CharonReleaseNode;

static pthread_mutex_t charon_release_lock = PTHREAD_MUTEX_INITIALIZER;
static CharonReleaseNode *charon_release_list;

void charon_js_release_soon(const void *object)
{
    CharonReleaseNode *node = malloc(sizeof(CharonReleaseNode));
    node->object = object;
    pthread_mutex_lock(&charon_release_lock);
    BOOL wasEmpty = !charon_release_list;
    node->next = charon_release_list;
    charon_release_list = node;
    pthread_mutex_unlock(&charon_release_lock);
    if (wasEmpty) {
        CFRunLoopRef loop = CFRunLoopGetCurrent();
        CFRunLoopPerformBlock(loop, kCFRunLoopCommonModes, ^{
            charon_js_release_pending();
        });
        CFRunLoopWakeUp(loop);
    }
}

void charon_js_release_pending(void)
{
    for (;;) {
        pthread_mutex_lock(&charon_release_lock);
        CharonReleaseNode *list = charon_release_list;
        charon_release_list = NULL;
        pthread_mutex_unlock(&charon_release_lock);
        if (!list)
            return;
        @autoreleasepool {
            for (CharonReleaseNode *node = list, *next; node; node = next) {
                next = node->next;
                CFRelease(node->object);
                free(node);
            }
        }
    }
}

static void BlockFinalize(JSObjectRef object)
{
    charon_js_release_soon(JSObjectGetPrivate(object));
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
    charon_js_release_soon(JSObjectGetPrivate(object));
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

id charon_js_wrapped_object(JSContextRef context, JSValueRef value)
{
    if (!JSValueIsObjectOfClass(context, value, BlockClass()) && !JSValueIsObjectOfClass(context, value, OpaqueClass()) &&
        !JSValueIsObjectOfClass(context, value, charon_js_export_class()))
        return nil;
    return (__bridge id)JSObjectGetPrivate((JSObjectRef)value);
}

static JSObjectRef Wrapper(JSContextRef context, id object, JSClassRef jsClass)
{
    JSContext *wrapper = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(context) create:YES];
    return [wrapper.virtualMachine charon_wrapperOf:object class:jsClass context:context];
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
        CharonType arguments[CharonBlockMaxArguments];
        NSUInteger count = 0;
        BOOL returnsVoid = NO;
        return Wrapper(context, object, BlockShape(object, arguments, &count, &returnsVoid) == CharonBlockNotFunction ? OpaqueClass() : BlockClass());
    }
    if (charon_js_class_conforms_to_export(object_getClass(object)))
        return Wrapper(context, object, charon_js_export_class());
    return Wrapper(context, object, OpaqueClass());
}

JSValueRef charon_js_type_error(JSContextRef context, NSString *message)
{
    JSContext *wrapper = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(context) create:YES];
    return [wrapper[@"TypeError"] constructWithArguments:@[message]].JSValueRef;
}

/* Object.prototype.toString of the object `value` (classOf) or Array.isArray(value), both the
 * virtual machine's own. Neither can throw for an object (ES5 15.2.4.2, 15.4.3.2). */
static JSValueRef AskOwnContext(JSContextRef context, JSValueRef value, BOOL classOf)
{
    JSVirtualMachine *machine = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(context) create:YES].virtualMachine;
    JSObjectRef isArray, toString;
    JSGlobalContextRef own = [machine charon_ownContextIsArray:&isArray classOf:&toString];
    return classOf ? JSObjectCallAsFunction(own, toString, (JSObjectRef)value, 0, NULL, NULL)
                   : JSObjectCallAsFunction(own, isArray, NULL, 1, &value, NULL);
}

BOOL charon_js_is_array(JSContextRef context, JSValueRef value)
{
    return JSValueIsObject(context, value) && JSValueToBoolean(context, AskOwnContext(context, value, NO));
}

BOOL charon_js_is_date(JSContextRef context, JSValueRef value)
{
    if (!JSValueIsObject(context, value))
        return NO;
    JSStringRef tag = JSValueToStringCopy(context, AskOwnContext(context, value, YES), NULL);
    BOOL date = JSStringIsEqualToUTF8CString(tag, "[object Date]");
    JSStringRelease(tag);
    return date;
}

uint32_t charon_js_uint32(double value)
{
    if (!(value == value) || isinf(value))
        return 0;
    return (uint32_t)(int64_t)fmod(trunc(value), 4294967296.0);
}

/*
 * JSValue's container conversion, walked as the release's JSContainerConvertor walks it: every
 * object met is recorded once against the Objective-C object made for it, so a cycle or a shared
 * reference answers that same object (`d[@"self"] == d`), and containers are filled from a
 * worklist rather than by recursion, so depth costs no stack. null is NSNull wherever it stands;
 * undefined is nil at the top, NSNull in an array, and left out of a dictionary. An array is read
 * by its length, anything else by its enumerable property names, inherited ones included. A
 * getter that throws is passed over and the exception reported nowhere, as the release does
 * (measured: its handler is not called). Each recorded value is protected until the walk ends,
 * since the map and worklist live on the heap where the collector does not look.
 */
typedef struct {
    JSContextRef context;
    NSMapTable *seen;              /* JSValueRef -> the Objective-C object made for it */
    NSPointerArray *pendingValues; /* worklist: the containers still to fill ... */
    NSMutableArray *pendingObjects; /* ... and their JavaScript objects, by index */
} CharonConvertor;

static void ConvertorRecord(CharonConvertor *convertor, JSValueRef value, id object, BOOL fill)
{
    JSValueProtect(convertor->context, value);
    [convertor->seen setObject:object forKey:(__bridge id)(void *)value];
    if (fill) {
        [convertor->pendingValues addPointer:(void *)value];
        [convertor->pendingObjects addObject:object];
    }
}

static id ConvertorConvert(CharonConvertor *convertor, JSValueRef value)
{
    JSContextRef context = convertor->context;
    switch (JSValueGetType(context, value)) {
    case kJSTypeUndefined:
        return nil;
    case kJSTypeNull:
        return [NSNull null];
    case kJSTypeBoolean:
        return @(JSValueToBoolean(context, value));
    case kJSTypeNumber:
        return @(JSValueToNumber(context, value, NULL));
    case kJSTypeString: {
        JSStringRef string = JSValueToStringCopy(context, value, NULL);
        NSString *result = charon_ns_string(string);
        JSStringRelease(string);
        return result;
    }
    default:
        break;
    }
    id known = [convertor->seen objectForKey:(__bridge id)(void *)value];
    if (known)
        return known;
    id object = charon_js_wrapped_object(context, value);
    BOOL fill = NO;
    if (object) {
    } else if (charon_js_is_date(context, value)) {
        object = [NSDate dateWithTimeIntervalSince1970:JSValueToNumber(context, value, NULL) / 1000.0];
    } else if (charon_js_is_array(context, value)) {
        object = [NSMutableArray array];
        fill = YES;
    } else {
        object = [NSMutableDictionary dictionary];
        fill = YES;
    }
    ConvertorRecord(convertor, value, object, fill);
    return object;
}

static void ConvertorFill(CharonConvertor *convertor, JSObjectRef object, id container)
{
    JSContextRef context = convertor->context;
    if ([container isKindOfClass:[NSMutableArray class]]) {
        JSStringRef lengthName = charon_js_string(@"length");
        uint32_t length = charon_js_uint32(JSValueToNumber(context, JSObjectGetProperty(context, object, lengthName, NULL), NULL));
        JSStringRelease(lengthName);
        for (uint32_t index = 0; index < length; index++) {
            JSValueRef thrown = NULL;
            JSValueRef value = JSObjectGetPropertyAtIndex(context, object, index, &thrown);
            [container addObject:(thrown ? nil : ConvertorConvert(convertor, value)) ?: [NSNull null]];
        }
        return;
    }
    JSPropertyNameArrayRef names = JSObjectCopyPropertyNames(context, object);
    size_t count = JSPropertyNameArrayGetCount(names);
    for (size_t index = 0; index < count; index++) {
        JSStringRef name = JSPropertyNameArrayGetNameAtIndex(names, index);
        JSValueRef thrown = NULL;
        JSValueRef property = JSObjectGetProperty(context, object, name, &thrown);
        id value = thrown ? nil : ConvertorConvert(convertor, property);
        if (value)
            container[charon_ns_string(name)] = value;
    }
    JSPropertyNameArrayRelease(names);
}

/* Convert `value`; a non-nil `container` is the top's container, filled as `value` read that way. */
static id Convert(JSContextRef context, JSValueRef value, id container)
{
    CharonConvertor convertor = {
        context,
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality valueOptions:NSPointerFunctionsStrongMemory],
        [NSPointerArray pointerArrayWithOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality],
        [NSMutableArray array],
    };
    id result = container;
    if (container)
        ConvertorRecord(&convertor, value, container, YES);
    else
        result = ConvertorConvert(&convertor, value);
    for (NSUInteger next = 0; next < convertor.pendingObjects.count; next++)
        ConvertorFill(&convertor, (JSObjectRef)[convertor.pendingValues pointerAtIndex:next], convertor.pendingObjects[next]);
    for (id key in convertor.seen)
        JSValueUnprotect(context, (__bridge void *)key);
    return result;
}

id charon_js_unbox(JSContextRef context, JSValueRef value)
{
    return value ? Convert(context, value, nil) : nil;
}

/* -toArray and -toDictionary: any object is read as the container asked for, undefined and null
 * are nil, and any other primitive is a TypeError, as the release words it. */
static id ToContainer(JSContextRef context, JSValueRef value, Class containerClass, JSValueRef *exception)
{
    id wrapped = charon_js_wrapped_object(context, value);
    if ([wrapped isKindOfClass:containerClass])
        return wrapped;
    BOOL array = containerClass == [NSArray class];
    if (JSValueIsObject(context, value))
        return Convert(context, value, array ? [NSMutableArray array] : [NSMutableDictionary dictionary]);
    if (!JSValueIsNull(context, value) && !JSValueIsUndefined(context, value))
        *exception = charon_js_type_error(context, array ? @"Cannot convert primitive to NSArray" : @"Cannot convert primitive to NSDictionary");
    return nil;
}

NSArray *charon_js_to_array(JSContextRef context, JSValueRef value, JSValueRef *exception)
{
    return ToContainer(context, value, [NSArray class], exception);
}

NSDictionary *charon_js_to_dictionary(JSContextRef context, JSValueRef value, JSValueRef *exception)
{
    return ToContainer(context, value, [NSDictionary class], exception);
}

NSString *charon_js_to_string(JSContextRef context, JSValueRef value, JSValueRef *exception)
{
    id wrapped = charon_js_wrapped_object(context, value);
    if ([wrapped isKindOfClass:[NSString class]])
        return wrapped;
    JSStringRef string = JSValueToStringCopy(context, value, exception);
    if (!string)
        return nil;
    NSString *result = charon_ns_string(string);
    JSStringRelease(string);
    return result;
}

NSNumber *charon_js_to_number(JSContextRef context, JSValueRef value, JSValueRef *exception)
{
    id wrapped = charon_js_wrapped_object(context, value);
    if ([wrapped isKindOfClass:[NSNumber class]])
        return wrapped;
    if (JSValueIsBoolean(context, value))
        return @(JSValueToBoolean(context, value));
    double number = JSValueToNumber(context, value, exception);
    return @(*exception ? NAN : number);
}

NSDate *charon_js_to_date(JSContextRef context, JSValueRef value, JSValueRef *exception)
{
    id wrapped = charon_js_wrapped_object(context, value);
    if ([wrapped isKindOfClass:[NSDate class]])
        return wrapped;
    double milliseconds = JSValueToNumber(context, value, exception);
    return *exception ? nil : [NSDate dateWithTimeIntervalSince1970:milliseconds / 1000.0];
}

id charon_js_to_class(JSContextRef context, JSValueRef value, Class objcClass, JSValueRef *exception)
{
    if (objcClass == [NSString class])
        return charon_js_to_string(context, value, exception);
    if (objcClass == [NSNumber class])
        return charon_js_to_number(context, value, exception);
    if (objcClass == [NSDate class])
        return charon_js_to_date(context, value, exception);
    if (objcClass == [NSArray class])
        return charon_js_to_array(context, value, exception);
    if (objcClass == [NSDictionary class])
        return charon_js_to_dictionary(context, value, exception);
    id wrapped = charon_js_wrapped_object(context, value);
    if ([wrapped isKindOfClass:objcClass])
        return wrapped;
    if (!JSValueIsNull(context, value) && !JSValueIsUndefined(context, value))
        *exception = charon_js_type_error(context, @"Argument does not match Objective-C Class");
    return nil;
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

/*
 * One queue of contexts with jobs per thread, and the level of calls into script the thread is
 * at. A context and its drain function are kept (JSGlobalContextRetain, JSValueProtect) from the
 * moment its first job is queued until its drain has run.
 */
typedef struct CharonPendingJobs {
    struct CharonPendingJobs *next;
    JSGlobalContextRef context;
    JSObjectRef drain;
} CharonPendingJobs;

typedef struct CharonJobState {
    unsigned depth;   /* every level of script on this thread's stack: ours and a callback's */
    unsigned entered; /* the levels this port entered itself (charon_js_enter), which a leave ends */
    BOOL scheduled;   /* a run loop turn of this thread is to drain the queue */
    CharonPendingJobs *first;
    CharonPendingJobs *last;
} CharonJobState;

static pthread_key_t charon_jobs_key;
static pthread_once_t charon_jobs_once = PTHREAD_ONCE_INIT;

static void CharonFreeJobs(void *value)
{
    CharonJobState *state = value;
    for (CharonPendingJobs *pending = state->first, *next; pending; pending = next) {
        next = pending->next;
        JSValueUnprotect(pending->context, pending->drain);
        JSGlobalContextRelease(pending->context);
        free(pending);
    }
    free(state);
}

static void CharonMakeJobsKey(void)
{
    pthread_key_create(&charon_jobs_key, CharonFreeJobs);
}

static CharonJobState *CharonJobs(void)
{
    pthread_once(&charon_jobs_once, CharonMakeJobsKey);
    CharonJobState *state = pthread_getspecific(charon_jobs_key);
    if (!state) {
        state = calloc(1, sizeof(CharonJobState));
        pthread_setspecific(charon_jobs_key, state);
    }
    return state;
}

void charon_js_push_callback(JSContext *context, JSValue *thisValue, JSValue *callee, NSArray<JSValue *> *arguments)
{
    pthread_once(&charon_frame_once, CharonMakeFrameKey);
    CharonJSFrame *frame = calloc(1, sizeof(CharonJSFrame));
    frame->up = CharonCurrentFrame();
    frame->context = CFBridgingRetain(context);
    frame->thisValue = thisValue ? CFBridgingRetain(thisValue) : NULL;
    frame->callee = callee ? CFBridgingRetain(callee) : NULL;
    frame->arguments = arguments ? CFBridgingRetain(arguments) : NULL;
    JSValue *preserved = context.exception;
    frame->preservedException = preserved ? (void *)CFBridgingRetain(preserved) : NULL;
    context.exception = nil;
    pthread_setspecific(charon_frame_key, frame);
    CharonJobs()->depth++;
}

JSValue *charon_js_pop_callback(void)
{
    CharonJSFrame *frame = CharonCurrentFrame();
    if (!frame)
        return nil;
    CharonJobs()->depth--;
    pthread_setspecific(charon_frame_key, frame->up);
    JSContext *context = CFBridgingRelease(frame->context);
    JSValue *thrown = context.exception;
    context.exception = frame->preservedException ? CFBridgingRelease(frame->preservedException) : nil;
    for (const void *held[] = {frame->thisValue, frame->callee, frame->arguments}, **each = held; each < held + 3; each++)
        if (*each)
            CFRelease(*each);
    free(frame);
    return thrown;
}

void charon_js_enter(void)
{
    CharonJobState *state = CharonJobs();
    state->depth++;
    state->entered++;
}

/*
 * Script this port did not enter - a direct C API call, a web view's own page - has no leave of
 * ours to run its jobs at, and neither has a callback such script makes: the callback's own calls
 * into script are levels of ours, but the last of them ends with the caller's script still on the
 * stack, where no job may run. The thread's run loop runs them on its next turn instead. The
 * release runs them as the outermost C API call returns, which nothing outside the engine sees.
 */
static void ScheduleDrain(CharonJobState *state)
{
    if (state->scheduled)
        return;
    state->scheduled = YES;
    CFRunLoopRef loop = CFRunLoopGetCurrent();
    CFRunLoopPerformBlock(loop, kCFRunLoopCommonModes, ^{
        CharonJobs()->scheduled = NO;
        charon_js_enter();
        charon_js_leave();
    });
    CFRunLoopWakeUp(loop);
}

void charon_js_note_jobs(JSContextRef context, JSObjectRef drain)
{
    CharonJobState *state = CharonJobs();
    CharonPendingJobs *pending = calloc(1, sizeof(CharonPendingJobs));
    pending->context = JSGlobalContextRetain(JSContextGetGlobalContext(context));
    pending->drain = drain;
    JSValueProtect(pending->context, drain);
    if (state->last)
        state->last->next = pending;
    else
        state->first = pending;
    state->last = pending;
    if (!state->entered)
        ScheduleDrain(state);
}

void charon_js_leave(void)
{
    CharonJobState *state = CharonJobs();
    state->entered--;
    if (--state->depth) {
        if (!state->entered && state->first)
            ScheduleDrain(state);
        return;
    }
    /* The drains run a level deep, so a call they make into script and back leaves them alone. */
    state->depth++;
    state->entered++;
    while (state->first) {
        CharonPendingJobs *pending = state->first;
        state->first = pending->next;
        if (!state->first)
            state->last = NULL;
        JSValueRef exception = NULL;
        JSObjectCallAsFunction(pending->context, pending->drain, NULL, 0, NULL, &exception);
        if (exception)
            [[JSContext charon_wrapperForGlobalContext:pending->context create:YES] charon_noteException:exception];
        JSValueUnprotect(pending->context, pending->drain);
        JSGlobalContextRelease(pending->context);
        free(pending);
    }
    state->depth--;
    state->entered--;
    charon_js_release_pending();
}
