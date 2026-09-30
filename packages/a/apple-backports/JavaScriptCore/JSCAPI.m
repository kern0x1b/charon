#import "JSInternal.h"
#import "../CharonSayOnce.h"

/*
 * The C API of a JavaScriptCore the release does not export, answered by asking the release's own
 * engine. Every function here is a question the 2012 engine can be asked and the SDK dates after
 * iOS 6; what each one is, and the primitive of the release's own export table that answers it, is
 * in facts/JavaScriptCore/CAPI.md, and tests/backports/host/jscontext/checks.m holds each one to the
 * host's own JavaScriptCore.
 *
 * The release's C API is what this answers over, and nothing called here is absent from it. Directly:
 * JSValueToStringCopy, JSStringRelease and the four property functions. Through the two helpers of
 * JSInternal.m: JSValueIsObject, JSValueToBoolean, JSStringIsEqualToUTF8CString, JSObjectCallAsFunction
 * and the rest of what charon_js_is_array and charon_js_is_date ask. All exported since 3.0
 * (first-rung.py over the 50 held rungs, the oldest held rung carrying each), each present in the 6.1.3
 * armv7 cache and in the 4.3 one this package also builds.
 */

/*
 * ToPropertyKey, as JSObjectRef.cpp's four ForKey functions do it: a string key is the name
 * itself, and anything else is ToString, which for a number is the same string the engine's own
 * property lookup would have formed and for an object runs its toString/valueOf and can throw. The
 * release's JSValueToStringCopy is ES ToString, so it is both cases, and a key of the symbol type -
 * the one kind ToPropertyKey answers that ToString does not - cannot arise: no value of the 2012
 * engine is a symbol (JSC::Symbol is 0 among the 300 JSC:: symbols the 6.1.3 cache carries).
 * *exception must start NULL; the name is returned for the caller to release, and NULL only when
 * the key itself threw, with the exception left where the caller reads it.
 */
static JSStringRef PropertyName(JSContextRef context, JSValueRef key, JSValueRef *exception)
{
    return JSValueToStringCopy(context, key, exception);
}

/*
 * JSValueIsArray and JSValueIsDate ask whether a value inherits from the engine's Array and Date,
 * which is what the release's own `inherits<JSArray>()` and `inherits<DateInstance>()` ask
 * (JSValueRef.cpp:205 and :217). The engine answers that for itself, in script, as Array.isArray
 * and as Object.prototype.toString's [[Class]] - ES5 15.4.3.2 and 15.2.4.2, the same two tests -
 * and charon_js_is_array and charon_js_is_date already ask them of the virtual machine's own
 * context, where no script but this port's runs, so script that replaces either changes nothing and
 * an object that only inherits Array.prototype is neither. -isArray and -isDate answer through these
 * two; there is one answer and one place it is computed.
 */
bool JSValueIsArray(JSContextRef context, JSValueRef value)
{
    return charon_js_is_array(context, value);
}

bool JSValueIsDate(JSContextRef context, JSValueRef value)
{
    return charon_js_is_date(context, value);
}

/*
 * The release's engine has no symbol type: JSC::Symbol is 0 among the JSC:: symbols its own cache
 * carries, and nothing of this port makes one - +[JSValue valueWithNewSymbolFromDescription:]
 * refuses at the seam with a TypeError, for the same reason. So no value this engine can hold is a
 * symbol and the answer for every one of them is false, which is also the answer the release with
 * symbols gives for every value that is not a symbol. This row is carried so a client can find that
 * out before it calls JSValueMakeSymbol(), which this port does not carry: a weak reference to that
 * one is NULL.
 */
bool JSValueIsSymbol(JSContextRef context, JSValueRef value)
{
    (void)context;
    (void)value;
    return false;
}

/*
 * The four property functions of a value key, which is the string-keyed property API of the release
 * reached through ToPropertyKey. The release's own JSObjectGetProperty, JSObjectSetProperty,
 * JSObjectHasProperty and JSObjectDeleteProperty do the work; the key is the only thing added, and
 * the same way JSC's get, put, hasProperty and deleteProperty take an Identifier.
 *
 * The exception out-parameter the SDK's signature of the three of them carries is passed straight
 * through, so a getter or a setter that throws leaves it where the caller reads it. Every other
 * call of these four in this package already passes the SDK's arity with NULL there - JSValue.m's
 * NamedProperty and every property read of JSExportBridge.m - and answers correctly on a 6.1.3
 * device (facts/JavaScriptCore/JSContext.md, 151 of 151 on an iPad 2), so a release whose own
 * function takes no such argument is reading none of it.
 */
JSValueRef JSObjectGetPropertyForKey(JSContextRef context, JSObjectRef object, JSValueRef propertyKey, JSValueRef *exception)
{
    JSStringRef name = PropertyName(context, propertyKey, exception);
    if (!name)
        return NULL;
    JSValueRef value = JSObjectGetProperty(context, object, name, exception);
    JSStringRelease(name);
    return value;
}

bool JSObjectHasPropertyForKey(JSContextRef context, JSObjectRef object, JSValueRef propertyKey, JSValueRef *exception)
{
    JSStringRef name = PropertyName(context, propertyKey, exception);
    if (!name)
        return false;
    bool has = JSObjectHasProperty(context, object, name);
    JSStringRelease(name);
    return has;
}

void JSObjectSetPropertyForKey(JSContextRef context, JSObjectRef object, JSValueRef propertyKey, JSValueRef value,
                               JSPropertyAttributes attributes, JSValueRef *exception)
{
    JSStringRef name = PropertyName(context, propertyKey, exception);
    if (!name)
        return;
    JSObjectSetProperty(context, object, name, value, attributes, exception);
    JSStringRelease(name);
}

bool JSObjectDeletePropertyForKey(JSContextRef context, JSObjectRef object, JSValueRef propertyKey, JSValueRef *exception)
{
    JSStringRef name = PropertyName(context, propertyKey, exception);
    if (!name)
        return false;
    bool deleted = JSObjectDeleteProperty(context, object, name, exception);
    JSStringRelease(name);
    return deleted;
}

/*
 * A context's name and its inspectable flag are the Web Inspector's two fields for a context:
 * what the inspector lists a context under, and whether it may attach to it at all. This port
 * carries no Web Inspector - there is no protocol here that could be refused or attached - so
 * nothing on it reads either. They are carried, they answer what this port can answer - nothing, and a
 * NULL or a NO - and the three that are reached to set or to report something say so in the log the
 * first time an application calls them, which is what a row marked inert is for: SetName, CopyName and
 * SetInspectable. IsInspectable is the fourth and the only one that says nothing, because a question
 * that reads a flag nothing on this port sets is not a thing to report. None of the four is bridged to
 * -[JSContext name] and -[JSContext setInspectable:], which keep
 * their own value in the wrapper: that registry holds wrappers weakly, by design, so a store a C
 * client could reach would have to outlive the wrapper and die with the context, and the only such
 * store the release has - a JSWeakObjectMap - holds JavaScript values rather than a name. Stated
 * here rather than left to be found by a client that mixes the two.
 */
void JSGlobalContextSetName(JSGlobalContextRef context, JSStringRef name)
{
    (void)context;
    (void)name;
    charon_say_once_for(@"JavaScriptCore.JSGlobalContextSetName",
                       @"JavaScriptCore: JSGlobalContextSetName does nothing here: a context's name is shown by a "
                       @"Web Inspector, and this port carries none. -[JSContext setName:] keeps a name in its own "
                       @"wrapper, which the two do not share.");
}

JSStringRef JSGlobalContextCopyName(JSGlobalContextRef context)
{
    (void)context;
    charon_say_once_for(@"JavaScriptCore.JSGlobalContextCopyName",
                       @"JavaScriptCore: JSGlobalContextCopyName answers NULL here: a context's name is shown by a "
                       @"Web Inspector, and this port carries none.");
    return NULL;
}

void JSGlobalContextSetInspectable(JSGlobalContextRef context, bool inspectable)
{
    (void)context;
    (void)inspectable;
    charon_say_once_for(@"JavaScriptCore.JSGlobalContextSetInspectable",
                       @"JavaScriptCore: JSGlobalContextSetInspectable does nothing here: the flag is read by a Web "
                       @"Inspector deciding whether it may attach, and this port carries none.");
}

bool JSGlobalContextIsInspectable(JSGlobalContextRef context)
{
    (void)context;
    return false;
}
