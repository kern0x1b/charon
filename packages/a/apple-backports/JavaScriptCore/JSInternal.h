#import <JavaScriptCore/JavaScriptCore.h>

/*
 * Shared between the four classes: the C API is the only thing iOS 6 actually carries
 * (JSContextRef, JSValueRef, JSObjectRef, JSStringRef and their functions - measured against
 * coordination/corpus/caches/6.0.tsv, not read off a running process's memory), and every
 * Objective-C class here is a wrapper over it. See facts/JavaScriptCore/JSContext.md.
 */

NS_ASSUME_NONNULL_BEGIN

@interface JSVirtualMachine (CharonInternal)
- (JSContextGroupRef)charon_group;
- (instancetype)initWithCharonGroup:(JSContextGroupRef)group retained:(BOOL)retained;
@end

@interface JSContext (CharonInternal)
+ (nullable JSContext *)charon_wrapperForGlobalContext:(JSGlobalContextRef)context create:(BOOL)create;
- (void)charon_noteException:(JSValueRef)exception;
@end

@interface JSValue (CharonInternal)
+ (instancetype)charon_valueWithJSValueRef:(JSValueRef)value context:(JSContext *)context;
@end

/* Box a native Objective-C object as a JSValueRef in `context`. Never NULL. */
JSValueRef charon_js_box(JSContextRef context, id _Nullable object);

/* Unbox a JSValueRef back to a native Objective-C object, per JSValue.toObject's own rules. */
id _Nullable charon_js_unbox(JSContextRef context, JSValueRef value, JSValueRef _Nullable *exception);

/* The JSStringRef equivalents, released by the caller. */
JSStringRef charon_js_string(NSString *string);
NSString *charon_ns_string(JSStringRef string);

/*
 * The class used for a JSExport-conforming object's JavaScript wrapper, one JSClassRef cached
 * per Objective-C class - see JSExportBridge.m for how its static functions and values are built
 * from the protocol's own method list.
 */
JSClassRef charon_js_export_class(Class objcClass);
BOOL charon_js_class_conforms_to_export(Class objcClass);

/* Thread-local callback state read by +[JSContext currentContext/currentThis/currentCallee/currentArguments]. */
void charon_js_push_callback(JSContext *context, JSValue *_Nullable thisValue, JSValue *_Nullable callee, NSArray<JSValue *> *_Nullable arguments);
void charon_js_pop_callback(void);

typedef struct CharonJSFrame {
    struct CharonJSFrame *up;
    __unsafe_unretained JSContext *context;
    __unsafe_unretained JSValue *thisValue;
    __unsafe_unretained JSValue *callee;
    __unsafe_unretained NSArray<JSValue *> *arguments;
} CharonJSFrame;

CharonJSFrame *_Nullable CharonCurrentFrame(void);

NS_ASSUME_NONNULL_END
