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
