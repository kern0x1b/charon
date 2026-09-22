#import "JSInternal.h"
#import <pthread.h>

static NSMapTable<id, JSContext *> *charon_context_registry;
static NSLock *charon_context_registry_lock;

static NSMapTable<id, JSContext *> *ContextRegistry(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        /* keyed by the JSGlobalContextRef itself, an opaque C pointer with no Objective-C object
         * behind it - NSPointerFunctionsOpaqueMemory tells the map table not to send it retain
         * and release, which is what strongToWeakObjectsMapTable's ordinary object keys do and
         * would crash on. The value is a real JSContext, held weakly: the registry answers the
         * same wrapper for as long as one is alive, and stops answering once nothing else is. */
        charon_context_registry = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality
                                                          valueOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPersonality];
        charon_context_registry_lock = [NSLock new];
    });
    return charon_context_registry;
}

/*
 * +currentContext, +currentThis, +currentCallee and +currentArguments only answer from inside a
 * callback JavaScript makes into Objective-C - a block or a JSExport method. A pthread key holds
 * a small stack of frames, one push per nested callback, so a callback that itself calls back
 * into JavaScript which calls back into Objective-C again still answers correctly for its own
 * frame once the inner one pops.
 */
typedef struct CharonJSFrame {
    struct CharonJSFrame *up;
    __unsafe_unretained JSContext *context;
    __unsafe_unretained JSValue *thisValue;
    __unsafe_unretained JSValue *callee;
    __unsafe_unretained NSArray<JSValue *> *arguments;
} CharonJSFrame;

static pthread_key_t charon_frame_key;
static pthread_once_t charon_frame_once = PTHREAD_ONCE_INIT;

static void CharonMakeFrameKey(void)
{
    pthread_key_create(&charon_frame_key, NULL);
}

static CharonJSFrame *CharonCurrentFrame(void)
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

@interface JSContext ()
{
    JSGlobalContextRef _globalContext;
    JSVirtualMachine *_virtualMachine;
    JSValue *_exception;
    NSString *_name;
    BOOL _inspectable;
}
@end

@implementation JSContext

@synthesize exceptionHandler = _exceptionHandler;

- (instancetype)init
{
    return [self initWithVirtualMachine:[[JSVirtualMachine alloc] init]];
}

- (instancetype)initWithVirtualMachine:(JSVirtualMachine *)virtualMachine
{
    if ((self = [super init])) {
        _virtualMachine = virtualMachine;
        _globalContext = JSGlobalContextCreateInGroup([virtualMachine charon_group], NULL);
        [self charon_register];
        __weak JSContext *weakSelf = self;
        _exceptionHandler = [^(JSContext *context, JSValue *exception) {
            (void)context;
            weakSelf.exception = exception;
        } copy];
    }
    return self;
}

- (void)charon_register
{
    [charon_context_registry_lock lock];
    [ContextRegistry() setObject:self forKey:(__bridge id)_globalContext];
    [charon_context_registry_lock unlock];
}

- (void)dealloc
{
    [charon_context_registry_lock lock];
    [ContextRegistry() removeObjectForKey:(__bridge id)_globalContext];
    [charon_context_registry_lock unlock];
    JSGlobalContextRelease(_globalContext);
}

+ (nullable JSContext *)charon_wrapperForGlobalContext:(JSGlobalContextRef)context create:(BOOL)create
{
    if (!context)
        return nil;
    [charon_context_registry_lock lock];
    JSContext *found = [ContextRegistry() objectForKey:(__bridge id)context];
    [charon_context_registry_lock unlock];
    if (found || !create)
        return found;
    JSGlobalContextRetain(context);
    JSVirtualMachine *vm = [[JSVirtualMachine alloc] initWithCharonGroup:JSContextGetGroup(context) retained:YES];
    return [[JSContext alloc] initCharonWrapping:context virtualMachine:vm];
}

- (instancetype)initCharonWrapping:(JSGlobalContextRef)context virtualMachine:(JSVirtualMachine *)virtualMachine
{
    if ((self = [super init])) {
        _virtualMachine = virtualMachine;
        _globalContext = context;
        [self charon_register];
        __weak JSContext *weakSelf = self;
        _exceptionHandler = [^(JSContext *ctx, JSValue *exception) {
            (void)ctx;
            weakSelf.exception = exception;
        } copy];
    }
    return self;
}

- (JSGlobalContextRef)JSGlobalContextRef
{
    return _globalContext;
}

+ (JSContext *)contextWithJSGlobalContextRef:(JSGlobalContextRef)jsGlobalContextRef
{
    return [self charon_wrapperForGlobalContext:jsGlobalContextRef create:YES];
}

- (JSVirtualMachine *)virtualMachine
{
    return _virtualMachine;
}

- (NSString *)name
{
    return _name;
}

- (void)setName:(NSString *)name
{
    _name = [name copy];
}

- (BOOL)isInspectable
{
    return _inspectable;
}

- (void)setInspectable:(BOOL)inspectable
{
    _inspectable = inspectable;
}

- (JSValue *)globalObject
{
    return [JSValue charon_valueWithJSValueRef:JSContextGetGlobalObject(_globalContext) context:self];
}

- (JSValue *)exception
{
    return _exception;
}

- (void)setException:(JSValue *)exception
{
    _exception = exception;
}

- (void)charon_noteException:(JSValueRef)exception
{
    if (!exception)
        return;
    JSValue *value = [JSValue charon_valueWithJSValueRef:exception context:self];
    if (_exceptionHandler)
        _exceptionHandler(self, value);
    else
        _exception = value;
}

- (JSValue *)evaluateScript:(NSString *)script
{
    return [self evaluateScript:script withSourceURL:nil];
}

- (JSValue *)evaluateScript:(NSString *)script withSourceURL:(NSURL *)sourceURL
{
    self.exception = nil;
    JSStringRef body = charon_js_string(script ?: @"");
    JSStringRef url = sourceURL ? charon_js_string(sourceURL.absoluteString) : NULL;
    JSValueRef exception = NULL;
    JSValueRef result = JSEvaluateScript(_globalContext, body, NULL, url, 1, &exception);
    JSStringRelease(body);
    if (url)
        JSStringRelease(url);
    if (exception) {
        [self charon_noteException:exception];
        return [JSValue charon_valueWithJSValueRef:JSValueMakeUndefined(_globalContext) context:self];
    }
    return [JSValue charon_valueWithJSValueRef:result context:self];
}

+ (JSContext *)currentContext
{
    CharonJSFrame *frame = CharonCurrentFrame();
    return frame ? frame->context : nil;
}

+ (JSValue *)currentThis
{
    CharonJSFrame *frame = CharonCurrentFrame();
    return frame ? frame->thisValue : nil;
}

+ (JSValue *)currentCallee
{
    CharonJSFrame *frame = CharonCurrentFrame();
    return frame ? frame->callee : nil;
}

+ (NSArray *)currentArguments
{
    CharonJSFrame *frame = CharonCurrentFrame();
    return frame ? frame->arguments : nil;
}

- (JSValue *)objectForKeyedSubscript:(id)key
{
    return [self.globalObject objectForKeyedSubscript:key];
}

- (void)setObject:(id)object forKeyedSubscript:(NSObject<NSCopying> *)key
{
    [self.globalObject setObject:object forKeyedSubscript:(id)key];
}

@end
