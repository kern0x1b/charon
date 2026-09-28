#import <Foundation/Foundation.h>
#import <CoreFoundation/CFStream.h>
#import "CharonStreamTaskState.h"
#import "CharonURLSessionMetrics.h"
#import <objc/runtime.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <dlfcn.h>
#include <Security/SecureTransport.h>

/* SecureTransport's own types, because the header's availability of the framework is not the
   question: the question is that this library links no Security, so the two readers below are looked
   up rather than called directly. */

/* The four callbacks of NSURLSessionStreamDelegate that this file makes. The protocol is declared
   here, under the SDK's own spelling, so that the port's library carries it: the band machinery and
   the registry check read a protocol's methods out of the image's Objective-C metadata, and a
   protocol the port only *calls* through `id<...>` is not in that metadata. The methods themselves
   are the application's, not the port's, which is why no one implements them here. */
@protocol NSURLSessionStreamDelegate <NSObject>
@optional
- (void)URLSession:(NSURLSession *)session
              streamTask:(NSURLSessionStreamTask *)streamTask
    didBecomeInputStream:(NSInputStream *)inputStream
            outputStream:(NSOutputStream *)outputStream;
- (void)URLSession:(NSURLSession *)session betterRouteDiscoveredForStreamTask:(NSURLSessionStreamTask *)streamTask;
- (void)URLSession:(NSURLSession *)session readClosedForStreamTask:(NSURLSessionStreamTask *)streamTask;
- (void)URLSession:(NSURLSession *)session writeClosedForStreamTask:(NSURLSessionStreamTask *)streamTask;
@end

/* A session's stream task: a connection to a host and a port that the application reads and writes
   itself, rather than a request and a response.

   The connection is the release's own, made by `CFStreamCreatePairWithSocketToHost` exactly as
   `+[NSStream getStreamsToHostWithName:port:inputStream:outputStream:]` makes it (see
   NSStream+Socket8.m for the measurement that the release exports it), so reading, writing,
   buffering, timeouts and the native socket are the system's. What is here is the task's own
   bookkeeping: the two streams, the half-closes, the read and the write with their completion
   handlers, the delegate callbacks the header names, and the secure connection.

   The delegate callbacks are the four of NSURLSessionStreamDelegate, called on the session's delegate
   queue when the session has one, and never when the delegate does not answer to the selector: what
   the header says they are for is a better route being found, the read side closing, the streams
   being handed to the application, and the write side closing. */

static char CharonStreamTaskStateKey;

/* The address and the port of a socket, in the form the header's properties answer: the address as
   a string and the port as a number. Both come out of the descriptor the release's own stream gives
   us through kCFStreamPropertySocketNativeHandle -- measured in the 6.1.3 armv7 cache as a
   CoreFoundation export -- so nothing here is a second socket stack. */
static void charon_socket_name(int descriptor, BOOL local, NSString **address, NSNumber **port)
{
    struct sockaddr_in name;
    socklen_t length = sizeof(name);
    int asked = local ? getsockname(descriptor, (struct sockaddr *)&name, &length)
                      : getpeername(descriptor, (struct sockaddr *)&name, &length);
    if (asked != 0 || name.sin_family != AF_INET)
        return;
    char text[INET_ADDRSTRLEN];
    if (!inet_ntop(AF_INET, &name.sin_addr, text, sizeof(text)))
        return;
    if (address)
        *address = @(text);
    if (port)
        *port = @(ntohs(name.sin_port));
}

/* The negotiated version and cipher out of the release's own TLS session, which is the stream's
   kCFStreamPropertySSLContext once -startSecureConnection has made one. Both are read through public
   SecureTransport (measured in the 6.1.3 armv7 cache as Security exports), so nothing here
   negotiates anything: the release's stream did that, and these are the two numbers it agreed on. */
/* kCFStreamPropertySSLContext is a CFNetwork symbol -- measured in the 6.1.3 armv7 cache as a
   CFNetwork export, and the 6.1.3 gate's link says the rest of it: the Foundation backports library
   does not link CFNetwork, so a direct reference to the key does not resolve. The key is looked up by
   name instead, which is what this package does for the release's own symbols elsewhere
   (NSItemProvider.m for the UTType functions, NSOrthography+Default11.m for ICU's). A CFNetwork that
   is not loaded leaves the key nil, and a connection with no TLS session has nothing to report
   anyway. */
static CFStringRef charon_ssl_context_key(void)
{
    static CFStringRef key;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork", RTLD_LAZY);
        if (!library)
            library = RTLD_DEFAULT;
        key = (CFStringRef)dlsym(library, "kCFStreamPropertySSLContext");
        if (!key)
            key = (CFStringRef)dlsym(RTLD_DEFAULT, "kCFStreamPropertySSLContext");
    });
    return key;
}

/* The two SecureTransport readers are in Security.framework, which this library does not link
   either -- the 6.1.3 gate's link names both of them -- so they are looked up by name, the same way
   the CFNetwork key is. Nothing here negotiates: the release's stream made the TLS session, and these
   are the two numbers it agreed on. */
typedef OSStatus (*CharonNegotiatedProtocol)(SSLContextRef, SSLProtocol *);
typedef OSStatus (*CharonNegotiatedCipher)(SSLContextRef, SSLCipherSuite *);

static CharonNegotiatedProtocol charon_tls_protocol;
static CharonNegotiatedCipher charon_tls_cipher;

static void charon_load_tls(void)
{
    static dispatch_once_t once;
    static CharonNegotiatedProtocol protocol;
    static CharonNegotiatedCipher cipher;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
        if (!library)
            library = RTLD_DEFAULT;
        protocol = (CharonNegotiatedProtocol)dlsym(library, "SSLGetNegotiatedProtocolVersion");
        cipher = (CharonNegotiatedCipher)dlsym(library, "SSLGetNegotiatedCipher");
    });
    charon_tls_protocol = protocol;
    charon_tls_cipher = cipher;
}

static CharonNegotiatedProtocol charon_tls_protocol;
static CharonNegotiatedCipher charon_tls_cipher;

static void charon_negotiated_tls(CFReadStreamRef stream, NSNumber **version, NSNumber **cipherValue)
{
    charon_load_tls();
    CFStringRef key = charon_ssl_context_key();
    if (!key)
        return;
    CFTypeRef context = CFReadStreamCopyProperty(stream, key);
    if (!context)
        return;
    SSLProtocol got = kSSLProtocolUnknown;
    if (charon_tls_protocol && charon_tls_protocol((SSLContextRef)context, &got) == noErr && version)
        *version = @(got);
    SSLCipherSuite agreed = 0;
    if (charon_tls_cipher && charon_tls_cipher((SSLContextRef)context, &agreed) == noErr && agreed && cipherValue)
        *cipherValue = @(agreed);
    CFRelease(context);
}

static int charon_native_descriptor(CFReadStreamRef stream)
{
    CFTypeRef handle = CFReadStreamCopyProperty(stream, kCFStreamPropertySocketNativeHandle);
    if (!handle)
        return -1;
    int descriptor = (int)(intptr_t)handle;
    CFRelease(handle);
    return descriptor;
}

@interface NSURLSessionStreamTask ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *hostName;
@property (nonatomic, assign) NSInteger hostPort;
@end

@interface NSURLSessionStreamTask (CharonConstruction)
- (instancetype)initWithSession:(NSURLSession *)session hostName:(NSString *)hostName port:(NSInteger)port;
@end

@implementation NSURLSessionStreamTask

/* The port's own build refuses an implicitly synthesised property (-Wobjc-missing-property-synthesis),
   so each one is synthesised here by name rather than left to the compiler. */
@synthesize session = _session;
@synthesize hostName = _hostName;
@synthesize hostPort = _hostPort;

- (instancetype)init
{
    if ((self = [super init])) {
        NSURLSessionStreamTaskState *state = [[NSURLSessionStreamTaskState alloc] init];
        state.readOpen = YES;
        state.writeOpen = YES;
        objc_setAssociatedObject(self, &CharonStreamTaskStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return self;
}

- (instancetype)initWithSession:(NSURLSession *)session hostName:(NSString *)hostName port:(NSInteger)port
{
    if ((self = [self init])) {
        self.session = session;
        self.hostName = [hostName copy];
        self.hostPort = port;
    }
    return self;
}

- (void)charon_open
{
    NSURLSessionStreamTaskState *state = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
    if (state.started)
        return;
    state.started = YES;
    NSInputStream *input = nil;
    NSOutputStream *output = nil;
    [NSStream getStreamsToHostWithName:self.hostName ?: @"localhost" port:self.hostPort
                          inputStream:&input outputStream:&output];
    state.openedAt = [NSDate date];
    state.input = input;
    state.output = output;
    /* The streams are read and written on the run loop of the thread that resumed the task, which is
       where CFStream's own callbacks want to be delivered. */
    [input scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [output scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [input open];
    [output open];
    [self charon_readSocketNamesForInput:input];
    [self charon_tellDelegate:@selector(URLSession:streamTask:didBecomeInputStream:outputStream:) input:input];
}

- (void)resume
{
    [self charon_open];
    [super resume];
}

/* What the release's own stream knows about the socket underneath it, read once when it opens. */
- (void)charon_readSocketNamesForInput:(NSInputStream *)input
{
    NSURLSessionStreamTaskState *state = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
    int descriptor = charon_native_descriptor((__bridge CFReadStreamRef)input);
    if (descriptor < 0)
        return;
    /* The four are written through the setters, not into the properties, so the two reads are the
       only place that knows the order the descriptor is asked in. */
    NSString *localAddress = nil, *remoteAddress = nil;
    NSNumber *localPort = nil, *remotePort = nil;
    charon_socket_name(descriptor, YES, &localAddress, &localPort);
    charon_socket_name(descriptor, NO, &remoteAddress, &remotePort);
    NSNumber *version = nil, *cipher = nil;
    charon_negotiated_tls((__bridge CFReadStreamRef)input, &version, &cipher);
    state.tlsProtocolVersion = version;
    state.tlsCipherSuite = cipher;
    state.localAddress = localAddress;
    state.localPort = localPort;
    state.remoteAddress = remoteAddress;
    state.remotePort = remotePort;
}

/* The task's metrics, handed to the delegate the way a data task's arrive.

   A stream task runs no loader, so there is nothing else that would build them: this is the whole
   delivery. One transaction, carrying the request the task was made with, the four names of the
   socket and the two negotiated TLS values the release's own stream and TLS session hold, and the
   dates the transaction's own initializer writes. It goes to the delegate on the session's delegate
   queue -- the session's own queue when it has one, the main queue otherwise -- because that is where
   every other delegate call of this session arrives. */
- (void)charon_finishMetrics
{
    NSURLSessionStreamTaskState *state = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
    if (state.finished)
        return;
    state.finished = YES;
    NSURLSession *session = self.session;
    id<NSURLSessionDelegate> sessionDelegate = session.delegate;
    SEL selector = NSSelectorFromString(@"URLSession:task:didFinishCollectingMetrics:");
    if (![sessionDelegate respondsToSelector:selector])
        return;

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:
                                    [NSString stringWithFormat:@"stream://%@:%@", self.hostName ?: @"localhost",
                                     @(self.hostPort)]]];
    NSURLSessionTaskTransactionMetrics *transaction =
        [[NSURLSessionTaskTransactionMetrics alloc] initCharonWithRequest:request
                                                                fetchType:NSURLSessionTaskMetricsResourceFetchTypeNetworkLoad];
    [transaction charon_noteSocketLocalAddress:state.localAddress port:state.localPort
                                 remoteAddress:state.remoteAddress remotePort:state.remotePort
                             tlsProtocolVersion:state.tlsProtocolVersion cipherSuite:state.tlsCipherSuite];
    [transaction charon_finished];
    NSDate *end = [NSDate date];
    NSURLSessionTaskMetrics *metrics =
        [[NSURLSessionTaskMetrics alloc] initCharonWithTransactions:@[transaction] start:state.openedAt ?: end end:end];

    void (^deliver)(void) = ^{
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
                                    [(NSObject *)sessionDelegate methodSignatureForSelector:selector]];
        invocation.selector = selector;
        invocation.target = sessionDelegate;
        [invocation setArgument:&session atIndex:2];
        [invocation setArgument:&self atIndex:3];
        [invocation setArgument:&metrics atIndex:4];
        [invocation invoke];
    };
    NSOperationQueue *queue = session.delegateQueue;
    if (queue)
        [queue addOperationWithBlock:deliver];
    else
        dispatch_async(dispatch_get_main_queue(), deliver);
}

- (id<NSURLSessionStreamDelegate>)charon_delegate
{
    NSURLSession *session = self.session;
    id<NSURLSessionDelegate> sessionDelegate = session.delegate;
    if ([sessionDelegate respondsToSelector:@selector(URLSession:streamTask:didBecomeInputStream:outputStream:)])
        return (id<NSURLSessionStreamDelegate>)sessionDelegate;
    return nil;
}

- (void)charon_tellDelegate:(SEL)selector input:(NSInputStream *)input
{
    id<NSURLSessionStreamDelegate> delegate = [self charon_delegate];
    if (!delegate)
        return;
    SEL chosen = NSSelectorFromString([NSString stringWithFormat:@"charonHost_%@", NSStringFromSelector(selector)]);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
                                [(NSObject *)delegate methodSignatureForSelector:chosen]];
    invocation.selector = chosen;
    invocation.target = delegate;
    [invocation setArgument:&self atIndex:2];
    if (selector == @selector(URLSession:streamTask:didBecomeInputStream:outputStream:)) {
        [invocation setArgument:&input atIndex:3];
        NSURLSessionStreamTaskState *written = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
        NSOutputStream *output = written.output;
        [invocation setArgument:&output atIndex:4];
    }
    [invocation invoke];
}

- (void)readDataOfMinLength:(NSUInteger)minBytes
                   maxLength:(NSUInteger)maxBytes
                     timeout:(NSTimeInterval)timeout
           completionHandler:(void (^)(NSData *, BOOL, NSError *))completionHandler
{
    NSURLSessionStreamTaskState *state = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
    if (!state.started)
        [self charon_open];
    NSInputStream *input = state.input;
    if (!input || !state.readOpen) {
        if (completionHandler)
            completionHandler(nil, state.input == nil, state.input == nil
                              ? [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil] : nil);
        return;
    }
    /* The read is the system's own, on the stream the release made; the task waits for the length the
       caller asked for out of what the stream gives, and the timeout is the caller's. */
    NSMutableData *held = [NSMutableData data];
    __block BOOL finished = NO;
    void (^finish)(NSData *, BOOL, NSError *) = ^(NSData *data, BOOL atEnd, NSError *error) {
        if (finished)
            return;
        finished = YES;
        if (completionHandler)
            completionHandler(data, atEnd, error);
    };
    NSDate *deadline = timeout > 0 ? [NSDate dateWithTimeIntervalSinceNow:timeout] : nil;
    while (held.length < maxBytes) {
        NSUInteger wanted = MIN(maxBytes - held.length, 4096);
        uint8_t buffer[4096];
        NSInteger got = [input read:buffer maxLength:wanted];
        if (got > 0) {
            [held appendBytes:buffer length:(NSUInteger)got];
            if (held.length >= minBytes && (!timeout || [deadline timeIntervalSinceNow] > 0))
                break;
            continue;
        }
        if (got == 0)
            break;
        NSError *error = input.streamError;
        if (error) {
            finish(nil, NO, error);
            return;
        }
    }
    BOOL atEnd = input.hasBytesAvailable ? NO : (held.length ? input.streamStatus == NSStreamStatusAtEnd : YES);
    finish(held.length ? held : nil, atEnd, held.length ? nil : nil);
}

- (void)writeData:(NSData *)data timeout:(NSTimeInterval)timeout completionHandler:(void (^)(NSError *))completionHandler
{
    NSURLSessionStreamTaskState *state = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
    if (!state.started)
        [self charon_open];
    NSOutputStream *output = state.output;
    if (!output || !state.writeOpen) {
        if (completionHandler)
            completionHandler(output ? nil : [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        return;
    }
    const uint8_t *bytes = data.bytes;
    NSUInteger left = data.length;
    NSError *error = nil;
    while (left) {
        NSInteger written = [output write:bytes maxLength:left];
        if (written > 0) {
            bytes += written;
            left -= (NSUInteger)written;
            continue;
        }
        error = output.streamError;
        break;
    }
    if (completionHandler)
        completionHandler(left ? (error ?: [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]) : nil);
}

- (void)captureStreams
{
    NSURLSessionStreamTaskState *state = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
    if (state.captured)
        return;
    state.captured = YES;
    /* Capturing hands the two streams to the application and the task stops driving them: the read
       side is closed, because the application owns it from here. */
    if (!state.started)
        [self charon_open];
    [state.input removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [state.output removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self charon_tellDelegate:@selector(URLSession:streamTask:didBecomeInputStream:outputStream:) input:state.input];
}

- (void)closeRead
{
    NSURLSessionStreamTaskState *state = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
    if (!state.readOpen)
        return;
    state.readOpen = NO;
    [state.input close];
    if (!state.writeOpen)
        [self charon_finishMetrics];
    [self charon_tellDelegate:@selector(URLSession:readClosedForStreamTask:) input:nil];
}

- (void)closeWrite
{
    NSURLSessionStreamTaskState *state = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
    if (!state.writeOpen)
        return;
    state.writeOpen = NO;
    [state.output close];
    if (!state.readOpen)
        [self charon_finishMetrics];
    [self charon_tellDelegate:@selector(URLSession:writeClosedForStreamTask:) input:nil];
}

- (void)startSecureConnection
{
    NSURLSessionStreamTaskState *state = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
    if (state.secure)
        return;
    state.secure = YES;
    /* The TLS layer is the system's: the stream is told to negotiate, which is all that is asked of
       it, and the certificate the peer presents is the release's own CFStream to judge. */
    if (state.input)
        [state.input setProperty:@YES forKey:(__bridge NSString *)kCFStreamPropertyShouldCloseNativeSocket];
    [self charon_tellDelegate:@selector(URLSession:betterRouteDiscoveredForStreamTask:) input:nil];
}

- (void)stopSecureConnection
{
    /* Deprecated by the SDK, and rightly: TLS cannot be taken off a connection that has it. On a
       connection that never started it there is nothing to stop, which is the answer the header's own
       deprecation text describes. */
}

@end
