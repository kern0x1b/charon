#import <JavaScriptCore/JavaScriptCore.h>

/*
 * Shared between the four classes: the C API is the only thing iOS 6 actually carries
 * (JSContextRef, JSValueRef, JSObjectRef, JSStringRef and their functions - measured against
 * coordination/corpus/caches/6.0.tsv, not read off a running process's memory), and every
 * Objective-C class here is a wrapper over it. See facts/JavaScriptCore/JSContext.md.
 */

NS_ASSUME_NONNULL_BEGIN

/*
 * Two private parts of the release's C API, declared with WebKit's own signatures
 * (JSWeakObjectMapRefPrivate.h, JSObjectRefPrivate.h; neither header is in the SDK). Both are
 * exported by the JavaScriptCore of iOS 6.0 and of every later release in the ladder
 * (coordination/corpus/caches/<release>.tsv) and by the host's. They are the only way the iOS 6 C API has
 * to hold a JavaScript object without keeping it alive (JSValueProtect is strong and nothing public
 * observes a collection), and to give one JavaScript object a reference to another that script
 * cannot see or change (an ordinary property is visible to Object.getOwnPropertyNames). A weak
 * object map belongs to a global object, which calls `destructor` when it is destroyed; private
 * properties exist only on objects made with a JSClassRef.
 */
typedef struct OpaqueJSWeakObjectMap *JSWeakObjectMapRef;
typedef void (*JSWeakMapDestroyedCallback)(JSWeakObjectMapRef map, void *_Nullable data);
extern JSWeakObjectMapRef JSWeakObjectMapCreate(JSContextRef ctx, void *_Nullable data, JSWeakMapDestroyedCallback destructor);
extern void JSWeakObjectMapSet(JSContextRef ctx, JSWeakObjectMapRef map, void *key, JSObjectRef object);
extern JSObjectRef _Nullable JSWeakObjectMapGet(JSContextRef ctx, JSWeakObjectMapRef map, void *key);
extern void JSWeakObjectMapRemove(JSContextRef ctx, JSWeakObjectMapRef map, void *key);
extern bool JSObjectSetPrivateProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName, JSValueRef _Nullable value);
extern bool JSObjectDeletePrivateProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName);
extern JSValueRef _Nullable JSObjectGetPrivateProperty(JSContextRef ctx, JSObjectRef object, JSStringRef propertyName);

@interface JSVirtualMachine (CharonInternal)
- (JSContextGroupRef)charon_group;
- (instancetype)initWithCharonGroup:(JSContextGroupRef)group retained:(BOOL)retained;
/* The live virtual machine of a context group, or nil: there is one per group. */
+ (nullable JSVirtualMachine *)charon_machineForGroup:(JSContextGroupRef)group;
/* The weak object map every weak reference of this virtual machine is kept in, and its context. */
- (JSGlobalContextRef)charon_weakContext:(JSWeakObjectMapRef _Nonnull *_Nonnull)outWeak;
/* The one wrapper of `object` in `context`'s global object, made with `jsClass` if there is none. */
- (JSObjectRef)charon_wrapperOf:(id)object class:(JSClassRef)jsClass context:(JSContextRef)context;
@end

@interface JSManagedValue (CharonInternal)
/* The object this holds, or NULL for a primitive, a string, or once it has been collected. */
- (nullable JSObjectRef)charon_object;
@end

@interface JSContext (CharonInternal)
+ (nullable JSContext *)charon_wrapperForGlobalContext:(JSGlobalContextRef)context create:(BOOL)create;
- (void)charon_noteException:(JSValueRef)exception;
@end

@interface JSValue (CharonInternal)
+ (instancetype)charon_valueWithJSValueRef:(JSValueRef)value context:(JSContext *)context;
/* Give a context -init made its global Promise (JSValue.m, where promises are built). */
+ (void)charon_installPromiseInContext:(JSContext *)context;
@end

/* Box a native Objective-C object as a JSValueRef in `context`. Never NULL. */
JSValueRef charon_js_box(JSContextRef context, id _Nullable object);

/* Unbox a JSValueRef back to a native Objective-C object, per JSValue.toObject's own rules. */
id _Nullable charon_js_unbox(JSContextRef context, JSValueRef value);

/*
 * JSValue's other conversions, as the release makes them both for its -toString... methods and for
 * a block argument of that declared class. A failure is left in *exception (which must start
 * NULL) for the caller to report - to the context's handler from a JSValue method, thrown into
 * the calling script from a block. charon_js_to_class dispatches NSString, NSNumber, NSDate,
 * NSArray and NSDictionary to these, and takes any other class only as the bridge's own wrapper of
 * an instance of it, or nil for undefined and null.
 */
NSString *_Nullable charon_js_to_string(JSContextRef context, JSValueRef value, JSValueRef _Nullable *_Nonnull exception);
NSNumber *charon_js_to_number(JSContextRef context, JSValueRef value, JSValueRef _Nullable *_Nonnull exception);
NSDate *_Nullable charon_js_to_date(JSContextRef context, JSValueRef value, JSValueRef _Nullable *_Nonnull exception);
NSArray *_Nullable charon_js_to_array(JSContextRef context, JSValueRef value, JSValueRef _Nullable *_Nonnull exception);
NSDictionary *_Nullable charon_js_to_dictionary(JSContextRef context, JSValueRef value, JSValueRef _Nullable *_Nonnull exception);
id _Nullable charon_js_to_class(JSContextRef context, JSValueRef value, Class objcClass, JSValueRef _Nullable *_Nonnull exception);

/*
 * An object-typed argument of a block or a JSExport method, converted by the class its extended
 * type encoding `type` (`@"NSString"`, `@"JSValue"`, `@`) declares, as the release converts it; a
 * refusal is left in *exception. charon_js_skip_type steps past one type of such an encoding.
 */
id _Nullable charon_js_argument(JSContextRef context, const char *type, JSValueRef value, JSValueRef _Nullable *_Nonnull exception);
const char *charon_js_skip_type(const char *type);

/* ECMAScript ToUint32: NaN and the infinities are 0, anything else is taken modulo 2^32. */
uint32_t charon_js_uint32(double value);

/* A new TypeError of `message` in `context`, as script's own `new TypeError(message)` makes it. */
JSValueRef charon_js_type_error(JSContextRef context, NSString *message);

/* The Objective-C object `value` is the bridge's wrapper of, or nil for any other value. */
id _Nullable charon_js_wrapped_object(JSContextRef context, JSValueRef value);

/* The JSStringRef equivalents, released by the caller. */
JSStringRef charon_js_string(NSString *string);
NSString *charon_ns_string(JSStringRef string);

/*
 * The class used for every JSExport-conforming object's JavaScript wrapper: one JSClassRef, whose
 * callbacks look each name up in a per-Objective-C-class table built from the protocol's own method
 * list (JSExportBridge.m).
 */
JSClassRef charon_js_export_class(void);
BOOL charon_js_class_conforms_to_export(Class objcClass);

/*
 * Thread-local callback state read by +[JSContext currentContext/currentThis/currentCallee/currentArguments].
 * A push keeps the context's exception aside and clears it, as the release's own JSContext does
 * around a callback; the pop puts it back and answers the exception the callback set, if any,
 * which the caller throws into the script that made the call.
 */
void charon_js_push_callback(JSContext *context, JSValue *_Nullable thisValue, JSValue *_Nullable callee, NSArray<JSValue *> *_Nullable arguments);
JSValue *_Nullable charon_js_pop_callback(void);

/*
 * The job queue promise reactions run from. The JavaScriptCore that has promises runs its queued
 * jobs when the outermost API call on a thread returns, never while script is on the stack.
 * charon_js_enter and charon_js_leave bracket every call this port makes into script, a callback
 * counts as a level too, and the leave that ends the outermost level runs `drain` for every
 * context charon_js_note_jobs named, in the order they were named, until none is left. Jobs
 * queued by script this port did not enter (a direct C API call, a web view's page) run on the
 * thread's next run loop turn instead; the property accessors of JSValue are not a level, so a
 * job a getter or setter queues waits for the next leave.
 */
void charon_js_enter(void);
void charon_js_leave(void);
void charon_js_note_jobs(JSContextRef context, JSObjectRef drain);

typedef struct CharonJSFrame {
    struct CharonJSFrame *up;
    __unsafe_unretained JSContext *context;
    __unsafe_unretained JSValue *thisValue;
    __unsafe_unretained JSValue *callee;
    __unsafe_unretained NSArray<JSValue *> *arguments;
    void *_Nullable preservedException; /* a retained JSValue, or NULL */
} CharonJSFrame;

CharonJSFrame *_Nullable CharonCurrentFrame(void);

NS_ASSUME_NONNULL_END
