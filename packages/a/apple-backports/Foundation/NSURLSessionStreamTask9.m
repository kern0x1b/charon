#import <Foundation/Foundation.h>
#import <CoreFoundation/CFStream.h>
#import "CharonStreamTaskState.h"
#import <objc/runtime.h>
#include <unistd.h>

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
    state.input = input;
    state.output = output;
    /* The streams are read and written on the run loop of the thread that resumed the task, which is
       where CFStream's own callbacks want to be delivered. */
    [input scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [output scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [input open];
    [output open];
    [self charon_tellDelegate:@selector(URLSession:streamTask:didBecomeInputStream:outputStream:) input:input];
}

- (void)resume
{
    [self charon_open];
    [super resume];
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
    [self charon_tellDelegate:@selector(URLSession:readClosedForStreamTask:) input:nil];
}

- (void)closeWrite
{
    NSURLSessionStreamTaskState *state = objc_getAssociatedObject(self, &CharonStreamTaskStateKey);
    if (!state.writeOpen)
        return;
    state.writeOpen = NO;
    [state.output close];
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
