#import "JSInternal.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>

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

- (void)dealloc
{
    JSValueUnprotect(_context.JSGlobalContextRef, _value);
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

- (id)toObject
{
    return charon_js_unbox(_context.JSGlobalContextRef, _value, NULL);
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
    return JSValueToNumber(_context.JSGlobalContextRef, _value, NULL);
}

- (int32_t)toInt32
{
    double value = self.toDouble;
    if (!(value == value) || isinf(value))
        return 0;
    return (int32_t)(uint32_t)(int64_t)fmod(trunc(value), 4294967296.0);
}

- (uint32_t)toUInt32
{
    return (uint32_t)self.toInt32;
}

- (NSNumber *)toNumber
{
    return self.isBoolean ? @(self.toBool) : @(self.toDouble);
}

- (NSString *)toString
{
    JSStringRef string = JSValueToStringCopy(_context.JSGlobalContextRef, _value, NULL);
    NSString *result = charon_ns_string(string);
    if (string)
        JSStringRelease(string);
    return result;
}

- (NSDate *)toDate
{
    return [NSDate dateWithTimeIntervalSince1970:self.toDouble / 1000.0];
}

- (NSArray *)toArray
{
    id object = self.toObject;
    return [object isKindOfClass:[NSArray class]] ? object : nil;
}

- (NSDictionary *)toDictionary
{
    id object = self.toObject;
    if ([object isKindOfClass:[NSDictionary class]])
        return object;
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        [(NSArray *)object enumerateObjectsUsingBlock:^(id item, NSUInteger index, BOOL *stop) { (void)stop; dictionary[@(index).stringValue] = item; }];
        return dictionary;
    }
    return nil;
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

/* JSValueIsArray only arrived in iOS 9; asking the object itself its own kind through
 * Array.isArray keeps the same answer without it. */
- (BOOL)isArray
{
    if (!self.isObject)
        return NO;
    JSValue *global = self.context.globalObject;
    JSValue *arrayCtor = [global valueForProperty:@"Array"];
    JSValue *isArray = [arrayCtor valueForProperty:@"isArray"];
    return [[isArray callWithArguments:@[self]] toBool];
}

- (BOOL)isDate
{
    return [self isInstanceOf:[self.context.globalObject valueForProperty:@"Date"]];
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
    if (asConstructor)
        result = JSObjectCallAsConstructor(ctx, function, count, values, &exception);
    else
        result = JSObjectCallAsFunction(ctx, function, thisObject, count, values, &exception);
    free(values);
    if (exception) {
        [_context charon_noteException:exception];
        return [JSValue valueWithUndefinedInContext:_context];
    }
    return [JSValue charon_valueWithJSValueRef:result ?: JSValueMakeUndefined(ctx) context:_context];
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

+ (JSValue *)valueWithPoint:(CGPoint)point inContext:(JSContext *)context
{
    JSValue *value = [self valueWithNewObjectInContext:context];
    [value setValue:@(point.x) forProperty:@"x"];
    [value setValue:@(point.y) forProperty:@"y"];
    return value;
}

+ (JSValue *)valueWithRange:(NSRange)range inContext:(JSContext *)context
{
    JSValue *value = [self valueWithNewObjectInContext:context];
    [value setValue:@(range.location) forProperty:@"location"];
    [value setValue:@(range.length) forProperty:@"length"];
    return value;
}

+ (JSValue *)valueWithRect:(CGRect)rect inContext:(JSContext *)context
{
    JSValue *value = [self valueWithNewObjectInContext:context];
    [value setValue:@(rect.origin.x) forProperty:@"x"];
    [value setValue:@(rect.origin.y) forProperty:@"y"];
    [value setValue:@(rect.size.width) forProperty:@"width"];
    [value setValue:@(rect.size.height) forProperty:@"height"];
    return value;
}

+ (JSValue *)valueWithSize:(CGSize)size inContext:(JSContext *)context
{
    JSValue *value = [self valueWithNewObjectInContext:context];
    [value setValue:@(size.width) forProperty:@"width"];
    [value setValue:@(size.height) forProperty:@"height"];
    return value;
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
 * Promises and symbols are iOS 13 - past the band this port is scoped to (JSContext itself is
 * iOS 7). The header declares them unconditionally, so they are implemented rather than left to
 * raise "unrecognized selector" the first time a caller's own iOS-13-or-later code path runs on
 * this release: a promise executor never runs and its promise stays pending forever, a symbol
 * comes back as -isSymbol NO because nothing here is one, and neither crashes the caller.
 */
+ (JSValue *)valueWithNewPromiseInContext:(JSContext *)context fromExecutor:(void (^)(JSValue *resolve, JSValue *reject))callback
{
    (void)callback;
    return [self valueWithNewObjectInContext:context];
}

+ (JSValue *)valueWithNewPromiseResolvedWithResult:(id)result inContext:(JSContext *)context
{
    (void)result;
    return [self valueWithNewObjectInContext:context];
}

+ (JSValue *)valueWithNewPromiseRejectedWithReason:(id)reason inContext:(JSContext *)context
{
    (void)reason;
    return [self valueWithNewObjectInContext:context];
}

+ (JSValue *)valueWithNewSymbolFromDescription:(NSString *)description inContext:(JSContext *)context
{
    return [self valueWithObject:[@"Symbol(" stringByAppendingFormat:@"%@)", description ?: @""] inContext:context];
}

- (BOOL)isSymbol
{
    return NO;
}

@end
