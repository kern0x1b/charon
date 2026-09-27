#import "CharonURLSessionMetrics.h"
#include <SystemConfiguration/SystemConfiguration.h>
#import <objc/runtime.h>

/* The transaction metrics' own numbers, on top of the dates and the request the object already keeps.

   The shape is swift-corelibs-foundation's `URLSessionTaskTransactionMetrics` (Apache-2.0), which is
   a plain data holder and says so: every count is an Int64 that starts at zero, every flag is a Bool
   that starts false, `resourceFetchType` and `domainResolutionProtocol` start at their own "unknown",
   and the addresses and the negotiated TLS values start at nil. What fills them is the load, and the
   two fields that are easy to confuse are two fields: `countOfRequestBodyBytesBeforeEncoding` is what
   the caller handed over, `countOfRequestBodyBytesSent` is what went on the wire.

   The port's loader knows part of that and the rest it cannot reach, and the split is in the facts
   file. What it knows: the bytes of a body it sent and the bytes of a body it received, whether the
   host it is talking to already had a connection open (the session's own per-host table), whether the
   interface it is on is cellular and whether the link is expensive or constrained (SystemConfiguration,
   which the session already asks), and that nothing here is a proxy connection when the release's own
   connection was used. What it cannot reach is the socket itself, and with it the two addresses, the
   two ports, the negotiated TLS values and the two header byte counts: the release's NSURLConnection
   hands a port a request and a response and nothing in between. Those are `absent`, and the reason
   names the wall rather than answering nil. */

static char CharonTransactionCountsKey;
static char CharonTransactionFlagsKey;

@implementation NSURLSessionTaskTransactionMetrics (CharonCounts)

/* The session's own per-host table, which is where "was there already a connection" is answered. */
- (void)charon_noteConnectionReused:(BOOL)reused bytesSent:(int64_t)sent beforeEncoding:(int64_t)before received:(int64_t)received
{
    NSMutableDictionary *counts = objc_getAssociatedObject(self, &CharonTransactionCountsKey);
    if (!counts) {
        counts = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &CharonTransactionCountsKey, counts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    counts[@"sent"] = @(sent);
    counts[@"before"] = @(before);
    counts[@"received"] = @(received);
    counts[@"decoded"] = @(received);
    NSMutableDictionary *flags = objc_getAssociatedObject(self, &CharonTransactionFlagsKey);
    if (!flags) {
        flags = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &CharonTransactionFlagsKey, flags, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    flags[@"reused"] = @(reused);
}

- (void)charon_noteInterfaceFlags:(BOOL)cellular expensive:(BOOL)expensive constrained:(BOOL)constrained proxy:(BOOL)proxy
{
    NSMutableDictionary *flags = objc_getAssociatedObject(self, &CharonTransactionFlagsKey);
    if (!flags) {
        flags = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &CharonTransactionFlagsKey, flags, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    flags[@"cellular"] = @(cellular);
    flags[@"expensive"] = @(expensive);
    flags[@"constrained"] = @(constrained);
    flags[@"proxy"] = @(proxy);
}

static int64_t charon_count(NSDictionary *counts, NSString *key)
{
    return [counts[key] longLongValue];
}

- (int64_t)countOfRequestBodyBytesSent { return charon_count(objc_getAssociatedObject(self, &CharonTransactionCountsKey), @"sent"); }
- (int64_t)countOfRequestBodyBytesBeforeEncoding { return charon_count(objc_getAssociatedObject(self, &CharonTransactionCountsKey), @"before"); }
- (int64_t)countOfResponseBodyBytesReceived { return charon_count(objc_getAssociatedObject(self, &CharonTransactionCountsKey), @"received"); }
- (int64_t)countOfResponseBodyBytesAfterDecoding { return charon_count(objc_getAssociatedObject(self, &CharonTransactionCountsKey), @"decoded"); }

- (BOOL)isCellular { return [objc_getAssociatedObject(self, &CharonTransactionFlagsKey)[@"cellular"] boolValue]; }
- (BOOL)isExpensive { return [objc_getAssociatedObject(self, &CharonTransactionFlagsKey)[@"expensive"] boolValue]; }
- (BOOL)isConstrained { return [objc_getAssociatedObject(self, &CharonTransactionFlagsKey)[@"constrained"] boolValue]; }
- (BOOL)isProxyConnection { return [objc_getAssociatedObject(self, &CharonTransactionFlagsKey)[@"proxy"] boolValue]; }
- (BOOL)isReusedConnection { return [objc_getAssociatedObject(self, &CharonTransactionFlagsKey)[@"reused"] boolValue]; }

/* 6.1.3 has no multipath, so nothing here is one; the header's answer on a system without the
   feature is the default, and that is what a Bool of false is. */
- (BOOL)isMultipath { return NO; }

/* The release's own connection resolves and connects with whatever it uses, and hands a port
   nothing that says which, so the answer is the enumeration's own "unknown" rather than a guess. */
- (NSURLSessionTaskMetricsDomainResolutionProtocol)domainResolutionProtocol
{
    return NSURLSessionTaskMetricsDomainResolutionProtocolUnknown;
}

@end
