#import <Foundation/Foundation.h>

/* The state of one stream task: the two streams, which halves are open, whether the connection has
   started, whether it is secured, and whether the application has taken the streams over.

   It is declared here and defined in CharonStreamTaskState.m because of what
   `tools/release-split.lua` measures: NSURLSessionStreamTask9.m holds the task's own class, which a
   release exports from 9.0, and this one, which no release exports at all -- one object with two
   release groups in it. One object per group is what the tool asks for. */
@interface NSURLSessionStreamTaskState : NSObject
@property NSInputStream *input;
@property NSOutputStream *output;
@property BOOL readOpen;
@property BOOL writeOpen;
@property BOOL secure;
@property BOOL captured;
@property BOOL finished;
/* Whether the read-side close has been reported, so the peer's end is announced once. */
@property BOOL readClosedReported;
@property NSDate *openedAt;
@property BOOL started;
/* What the release's own stream knows about the socket underneath it, read once when it opens:
   kCFStreamPropertySocketNativeHandle for the descriptor, then getsockname and getpeername. */
@property NSString *localAddress;
@property NSNumber *localPort;
@property NSString *remoteAddress;
@property NSNumber *remotePort;
@property NSNumber *tlsProtocolVersion;
@property NSNumber *tlsCipherSuite;
@end
