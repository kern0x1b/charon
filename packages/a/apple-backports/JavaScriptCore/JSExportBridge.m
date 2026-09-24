#import "JSInternal.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

/*
 * JSExport turns a protocol's required properties and instance methods into a JavaScript
 * wrapper's own properties and functions. One JSClassRef, shared by every JSExport-conforming
 * object regardless of its own Objective-C class, does the dispatch: its getProperty callback
 * looks the requested name up in a per-class table (built once, from protocol_copyPropertyList
 * and protocol_copyMethodDescriptionList over every JSExport-incorporating protocol the class or
 * its superclasses conform to) and either reads a property through the real accessor or hands
 * back a bound function that calls the real method - both through the object's own
 * -methodSignatureForSelector:, not a re-derivation of the protocol's encoding, so the argument
 * and return types marshaled are the ones the class actually implements.
 *
 * Supported argument and return types: id and Objective-C instance pointers, BOOL, the C integer
 * types up to 64 bits, float and double, and the four structs JSValue itself converts - CGPoint,
 * CGRect, CGSize, NSRange. A method outside that set is still exported - calling it from
 * JavaScript throws rather than reading an argument off the wrong-sized slot.
 */

typedef struct {
    SEL selector;
    BOOL isMethod;
} CharonExportEntry;

@interface CharonExportBinding : NSObject
@property (nonatomic, strong) id target;
@property (nonatomic, assign) SEL selector;
@end

@implementation CharonExportBinding
@synthesize target = _target;
@synthesize selector = _selector;
@end

static NSMapTable<Class, NSDictionary *> *ExportTables(void)
{
    static NSMapTable<Class, NSDictionary *> *tables;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tables = [NSMapTable strongToStrongObjectsMapTable];
    });
    return tables;
}

static NSString *PropertyNameForSetter(NSString *selectorName)
{
    /* setFoo: -> foo */
    if (![selectorName hasPrefix:@"set"] || selectorName.length < 4)
        return nil;
    NSString *rest = [selectorName substringWithRange:NSMakeRange(3, selectorName.length - 4)];
    if (rest.length == 0)
        return nil;
    return [[[rest substringToIndex:1] lowercaseString] stringByAppendingString:[rest substringFromIndex:1]];
}

static NSString *JavaScriptNameForSelector(NSString *selectorName)
{
    /* doFoo:withBar: -> doFooWithBar, per JSExport.h's default conversion */
    NSArray<NSString *> *pieces = [selectorName componentsSeparatedByString:@":"];
    if (pieces.count <= 1)
        return selectorName;
    NSMutableString *name = [pieces[0] mutableCopy];
    for (NSUInteger index = 1; index < pieces.count; index++) {
        NSString *piece = pieces[index];
        if (piece.length == 0)
            continue;
        [name appendString:[[piece substringToIndex:1] uppercaseString]];
        [name appendString:[piece substringFromIndex:1]];
    }
    return name;
}

/*
 * JSExportAs(name, selector) expands to an @optional method that is the @required one with one
 * more keyword appended, "__JS_EXPORT_AS__<name>:(id)argument" - so
 * JSExportAs(doFoo, - (void)doFoo:(id)foo withBar:(id)bar) declares the @optional selector
 * doFoo:withBar:__JS_EXPORT_AS__doFoo: alongside the @required doFoo:withBar:. Recovering the
 * rename means finding that trailing keyword and dropping it to name the @required selector it
 * decorates.
 */
static void CollectRenames(Protocol *protocol, NSMutableDictionary<NSString *, NSString *> *renames)
{
    unsigned optionalCount = 0;
    struct objc_method_description *optional = protocol_copyMethodDescriptionList(protocol, NO, YES, &optionalCount);
    for (unsigned index = 0; index < optionalCount; index++) {
        NSArray<NSString *> *keywords = [NSStringFromSelector(optional[index].name) componentsSeparatedByString:@":"];
        if (keywords.count < 2)
            continue;
        NSString *marker = keywords[keywords.count - 2];
        if (![marker hasPrefix:@"__JS_EXPORT_AS__"])
            continue;
        NSString *jsName = [marker substringFromIndex:@"__JS_EXPORT_AS__".length];
        NSArray<NSString *> *requiredKeywords = [keywords subarrayWithRange:NSMakeRange(0, keywords.count - 2)];
        renames[[[requiredKeywords componentsJoinedByString:@":"] stringByAppendingString:@":"]] = jsName;
    }
    free(optional);
}

static void CollectProtocol(Protocol *protocol, NSMutableDictionary<NSString *, NSValue *> *entries)
{
    if (!protocol_conformsToProtocol(protocol, @protocol(JSExport)))
        return;
    unsigned propertyCount = 0;
    objc_property_t *properties = protocol_copyPropertyList(protocol, &propertyCount);
    for (unsigned index = 0; index < propertyCount; index++) {
        const char *name = property_getName(properties[index]);
        NSString *propertyName = @(name);
        char *getterAttribute = property_copyAttributeValue(properties[index], "G");
        char *setterAttribute = property_copyAttributeValue(properties[index], "S");
        BOOL readonly = property_copyAttributeValue(properties[index], "R") != NULL;
        SEL getter = sel_registerName(getterAttribute ?: name);
        NSString *defaultSetterName = [NSString stringWithFormat:@"set%@%@:", [[propertyName substringToIndex:1] uppercaseString], [propertyName substringFromIndex:1]];
        SEL setter = sel_registerName(setterAttribute ?: defaultSetterName.UTF8String);
        CharonExportEntry getEntry = {getter, NO};
        entries[propertyName] = [NSValue value:&getEntry withObjCType:@encode(CharonExportEntry)];
        if (!readonly) {
            CharonExportEntry setEntry = {setter, NO};
            entries[[propertyName stringByAppendingString:@"$set"]] = [NSValue value:&setEntry withObjCType:@encode(CharonExportEntry)];
        }
        free(getterAttribute);
        free(setterAttribute);
    }
    free(properties);

    NSMutableDictionary<NSString *, NSString *> *renames = [NSMutableDictionary dictionary];
    CollectRenames(protocol, renames);

    unsigned methodCount = 0;
    struct objc_method_description *required = protocol_copyMethodDescriptionList(protocol, YES, YES, &methodCount);
    for (unsigned index = 0; index < methodCount; index++) {
        NSString *selectorName = NSStringFromSelector(required[index].name);
        NSString *jsName = renames[selectorName] ?: JavaScriptNameForSelector(selectorName);
        CharonExportEntry entry = {required[index].name, YES};
        entries[jsName] = [NSValue value:&entry withObjCType:@encode(CharonExportEntry)];
    }
    free(required);

    unsigned adoptedCount = 0;
    Protocol *__unsafe_unretained *adopted = protocol_copyProtocolList(protocol, &adoptedCount);
    for (unsigned index = 0; index < adoptedCount; index++)
        CollectProtocol(adopted[index], entries);
    free(adopted);
}

static NSDictionary<NSString *, NSValue *> *ExportTableForClass(Class objcClass)
{
    NSMapTable *tables = ExportTables();
    @synchronized(tables) {
        NSDictionary *found = [tables objectForKey:objcClass];
        if (found)
            return found;
    }
    NSMutableDictionary<NSString *, NSValue *> *entries = [NSMutableDictionary dictionary];
    for (Class cursor = objcClass; cursor; cursor = class_getSuperclass(cursor)) {
        unsigned count = 0;
        Protocol *__unsafe_unretained *protocols = class_copyProtocolList(cursor, &count);
        for (unsigned index = 0; index < count; index++)
            CollectProtocol(protocols[index], entries);
        free(protocols);
    }
    @synchronized(tables) {
        [tables setObject:entries forKey:objcClass];
    }
    return entries;
}

BOOL charon_js_class_conforms_to_export(Class objcClass)
{
    for (Class cursor = objcClass; cursor; cursor = class_getSuperclass(cursor)) {
        unsigned count = 0;
        Protocol *__unsafe_unretained *protocols = class_copyProtocolList(cursor, &count);
        BOOL found = NO;
        for (unsigned index = 0; index < count && !found; index++) {
            if (protocol_conformsToProtocol(protocols[index], @protocol(JSExport)))
                found = YES;
        }
        free(protocols);
        if (found)
            return YES;
    }
    return NO;
}

static BOOL SetInvocationArgument(NSInvocation *invocation, NSUInteger index, const char *type, JSContextRef ctx, JSValueRef jsValue, JSValueRef *exception)
{
    switch (type[0]) {
    case '@':
    case '#': {
        id object = charon_js_unbox(ctx, jsValue, exception);
        [invocation setArgument:&object atIndex:index];
        return YES;
    }
    case 'c':
    case 'B': {
        BOOL value = JSValueToBoolean(ctx, jsValue);
        [invocation setArgument:&value atIndex:index];
        return YES;
    }
    case 'i': case 's': case 'l': case 'q': case 'I': case 'S': case 'L': case 'Q': {
        long long value = (long long)JSValueToNumber(ctx, jsValue, exception);
        [invocation setArgument:&value atIndex:index];
        return YES;
    }
    case 'f': {
        float value = (float)JSValueToNumber(ctx, jsValue, exception);
        [invocation setArgument:&value atIndex:index];
        return YES;
    }
    case 'd': {
        double value = JSValueToNumber(ctx, jsValue, exception);
        [invocation setArgument:&value atIndex:index];
        return YES;
    }
    case '{': {
        JSContext *context = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(ctx) create:YES];
        JSValue *value = [JSValue charon_valueWithJSValueRef:jsValue context:context];
        if (strstr(type, "CGPoint")) {
            CGPoint point = value.toPoint;
            [invocation setArgument:&point atIndex:index];
        } else if (strstr(type, "CGRect")) {
            CGRect rect = value.toRect;
            [invocation setArgument:&rect atIndex:index];
        } else if (strstr(type, "CGSize")) {
            CGSize size = value.toSize;
            [invocation setArgument:&size atIndex:index];
        } else if (strstr(type, "_NSRange") || strstr(type, "NSRange")) {
            NSRange range = value.toRange;
            [invocation setArgument:&range atIndex:index];
        } else {
            return NO;
        }
        return YES;
    }
    default:
        return NO;
    }
}

static JSValueRef BoxInvocationReturn(NSInvocation *invocation, const char *returnType, JSContextRef ctx)
{
    switch (returnType[0]) {
    case 'v':
        return JSValueMakeUndefined(ctx);
    case '@':
    case '#': {
        __unsafe_unretained id object = nil;
        [invocation getReturnValue:&object];
        return charon_js_box(ctx, object);
    }
    case 'c':
    case 'B': {
        BOOL value = NO;
        [invocation getReturnValue:&value];
        return JSValueMakeBoolean(ctx, value);
    }
    case 'i': case 's': case 'l': case 'I': case 'S': case 'L': {
        int value = 0;
        [invocation getReturnValue:&value];
        return JSValueMakeNumber(ctx, value);
    }
    case 'q': case 'Q': {
        long long value = 0;
        [invocation getReturnValue:&value];
        return JSValueMakeNumber(ctx, (double)value);
    }
    case 'f': {
        float value = 0;
        [invocation getReturnValue:&value];
        return JSValueMakeNumber(ctx, value);
    }
    case 'd': {
        double value = 0;
        [invocation getReturnValue:&value];
        return JSValueMakeNumber(ctx, value);
    }
    case '{': {
        JSContext *context = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(ctx) create:YES];
        if (strstr(returnType, "CGPoint")) {
            CGPoint point; [invocation getReturnValue:&point];
            return [JSValue valueWithPoint:point inContext:context].JSValueRef;
        }
        if (strstr(returnType, "CGRect")) {
            CGRect rect; [invocation getReturnValue:&rect];
            return [JSValue valueWithRect:rect inContext:context].JSValueRef;
        }
        if (strstr(returnType, "CGSize")) {
            CGSize size; [invocation getReturnValue:&size];
            return [JSValue valueWithSize:size inContext:context].JSValueRef;
        }
        if (strstr(returnType, "NSRange")) {
            NSRange range; [invocation getReturnValue:&range];
            return [JSValue valueWithRange:range inContext:context].JSValueRef;
        }
        return JSValueMakeUndefined(ctx);
    }
    default:
        return JSValueMakeUndefined(ctx);
    }
}

static JSValueRef InvokeSelector(JSContextRef ctx, id target, SEL selector, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception)
{
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature) {
        JSContext *context = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(ctx) create:YES];
        if (exception)
            *exception = [JSValue valueWithNewErrorFromMessage:[NSString stringWithFormat:@"%@ does not respond to %@", target, NSStringFromSelector(selector)] inContext:context].JSValueRef;
        return JSValueMakeUndefined(ctx);
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    invocation.target = target;
    /* -setArgument:atIndex: only copies bytes; without this, an object argument set from a local
     * that goes out of scope once SetInvocationArgument returns dangles by the time -invoke
     * actually runs. */
    [invocation retainArguments];
    NSUInteger expected = signature.numberOfArguments - 2;
    for (NSUInteger index = 0; index < expected; index++) {
        const char *type = [signature getArgumentTypeAtIndex:index + 2];
        JSValueRef value = index < argumentCount ? arguments[index] : JSValueMakeUndefined(ctx);
        if (!SetInvocationArgument(invocation, index + 2, type, ctx, value, exception)) {
            JSContext *context = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(ctx) create:YES];
            if (exception)
                *exception = [JSValue valueWithNewErrorFromMessage:[NSString stringWithFormat:@"argument %lu of %@ has an unsupported type for JSExport", (unsigned long)index, NSStringFromSelector(selector)] inContext:context].JSValueRef;
            return JSValueMakeUndefined(ctx);
        }
    }
    [invocation invoke];
    return BoxInvocationReturn(invocation, signature.methodReturnType, ctx);
}

static JSValueRef BoundFunctionCallAsFunction(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argumentCount, const JSValueRef arguments[], JSValueRef *exception)
{
    (void)thisObject;
    CharonExportBinding *binding = (__bridge CharonExportBinding *)JSObjectGetPrivate(function);
    JSContext *context = [JSContext charon_wrapperForGlobalContext:JSContextGetGlobalContext(ctx) create:YES];
    NSMutableArray<JSValue *> *boxedArguments = [NSMutableArray array];
    for (size_t index = 0; index < argumentCount; index++)
        [boxedArguments addObject:[JSValue charon_valueWithJSValueRef:arguments[index] context:context]];
    charon_js_push_callback(context, [JSValue charon_valueWithJSValueRef:thisObject context:context], [JSValue charon_valueWithJSValueRef:function context:context], boxedArguments);
    JSValueRef result = InvokeSelector(ctx, binding.target, binding.selector, argumentCount, arguments, exception);
    charon_js_pop_callback();
    return result;
}

static void BoundFunctionFinalize(JSObjectRef object)
{
    CFRelease(JSObjectGetPrivate(object));
}

static JSClassRef BoundFunctionClass(void)
{
    static JSClassRef boundClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        JSClassDefinition definition = kJSClassDefinitionEmpty;
        definition.className = "CharonExportMethod";
        definition.callAsFunction = BoundFunctionCallAsFunction;
        definition.finalize = BoundFunctionFinalize;
        boundClass = JSClassCreate(&definition);
    });
    return boundClass;
}

static BOOL LookupEntry(NSDictionary<NSString *, NSValue *> *table, NSString *name, CharonExportEntry *outEntry)
{
    NSValue *boxed = table[name];
    if (!boxed)
        return NO;
    [boxed getValue:outEntry];
    return YES;
}

static JSValueRef ExportGetProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef *exception)
{
    id target = (__bridge id)JSObjectGetPrivate(object);
    if (!target)
        return NULL;
    NSDictionary *table = ExportTableForClass(object_getClass(target));
    NSString *name = charon_ns_string(propertyName);
    CharonExportEntry entry;
    if (!LookupEntry(table, name, &entry))
        return NULL;
    if (!entry.isMethod)
        return InvokeSelector(ctx, target, entry.selector, 0, NULL, exception);
    CharonExportBinding *binding = [CharonExportBinding new];
    binding.target = target;
    binding.selector = entry.selector;
    return JSObjectMake(ctx, BoundFunctionClass(), (void *)CFBridgingRetain(binding));
}

static bool ExportSetProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef value, JSValueRef *exception)
{
    id target = (__bridge id)JSObjectGetPrivate(object);
    if (!target)
        return false;
    NSDictionary *table = ExportTableForClass(object_getClass(target));
    NSString *name = [charon_ns_string(propertyName) stringByAppendingString:@"$set"];
    CharonExportEntry entry;
    if (!LookupEntry(table, name, &entry))
        return false;
    InvokeSelector(ctx, target, entry.selector, 1, &value, exception);
    return true;
}

static bool ExportHasProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName)
{
    (void)ctx;
    id target = (__bridge id)JSObjectGetPrivate(object);
    if (!target)
        return false;
    NSDictionary *table = ExportTableForClass(object_getClass(target));
    CharonExportEntry entry;
    return LookupEntry(table, charon_ns_string(propertyName), &entry);
}

static void ExportFinalize(JSObjectRef object)
{
    CFRelease(JSObjectGetPrivate(object));
}

JSClassRef charon_js_export_class(Class objcClass)
{
    (void)objcClass;
    static JSClassRef exportClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        JSClassDefinition definition = kJSClassDefinitionEmpty;
        definition.className = "CharonExportObject";
        definition.getProperty = ExportGetProperty;
        definition.setProperty = ExportSetProperty;
        definition.hasProperty = ExportHasProperty;
        definition.finalize = ExportFinalize;
        exportClass = JSClassCreate(&definition);
    });
    return exportClass;
}
