// probe.m - PKPaymentToken and PKPayment, the port's against the host's PassKit, in one process.
//
// run.sh builds the port's PKPayment8.m with its two classes renamed (charonHost_PKPayment and
// charonHost_PKPaymentToken), so the system's PassKit keeps the real names. Each case is asked of both sides
// the same way, through the runtime: the host's header does not declare every selector the 8.0 surface has, and
// a message the header does not declare cannot be compiled, so every message here is sent by name. A case prints
// SAME when the two answers are equal, and FAIL when they are not; the process exits 1 on any FAIL.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <stdio.h>

static int failures = 0;

// Answers of a getter, sent by name: the object, or nil when the selector is not there.
static id get(id target, NSString *name)
{
    SEL selector = NSSelectorFromString(name);
    if (![target respondsToSelector:selector])
        return @"(no selector)";
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static BOOL set(id target, NSString *name, id value)
{
    SEL selector = NSSelectorFromString(name);
    if (![target respondsToSelector:selector])
        return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(target, selector, value);
    return YES;
}

static id make(NSString *className, NSString *initializer, id argument)
{
    Class cls = NSClassFromString(className);
    if (!cls)
        return nil;
    id allocated = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(alloc));
    if (!argument)
        return ((id (*)(id, SEL))objc_msgSend)(allocated, NSSelectorFromString(initializer));
    return ((id (*)(id, SEL, id))objc_msgSend)(allocated, NSSelectorFromString(initializer), argument);
}

static void report(NSString *name, NSString *host, NSString *port)
{
    BOOL same = [host isEqualToString:port];
    if (!same)
        failures++;
    printf("%s %s host=%s port=%s\n", same ? "SAME" : "FAIL", name.UTF8String, host.UTF8String, port.UTF8String);
}

// An answer as a string a person can compare: the description of an object, "nil", or the "no selector" marker.
static NSString *show(id value)
{
    if (!value)
        return @"nil";
    if ([value isKindOfClass:[NSString class]])
        return value;
    if ([value isKindOfClass:[NSData class]])
        return [NSString stringWithFormat:@"data(%lu)", (unsigned long)[value length]];
    return [NSString stringWithFormat:@"%@", NSStringFromClass([value class])];
}

int main(void)
{
    @autoreleasepool {
        // The class exists on both sides and says it supports secure coding.
        for (NSString *cls in @[@"PKPaymentToken", @"PKPayment"]) {
            NSString *host = NSClassFromString(cls) ? @"yes" : @"no";
            NSString *port = NSClassFromString([@"charonHost_" stringByAppendingString:cls]) ? @"yes" : @"no";
            report([cls stringByAppendingString:@" exists"], host, port);
        }
        for (NSString *cls in @[@"PKPaymentToken", @"PKPayment"]) {
            NSString *host = [NSClassFromString(cls) respondsToSelector:@selector(supportsSecureCoding)]
                ? ([NSClassFromString(cls) supportsSecureCoding] ? @"yes" : @"no") : @"no";
            NSString *port = [NSClassFromString([@"charonHost_" stringByAppendingString:cls])
                respondsToSelector:@selector(supportsSecureCoding)]
                ? ([NSClassFromString([@"charonHost_" stringByAppendingString:cls]) supportsSecureCoding] ? @"yes" : @"no")
                : @"no";
            report([cls stringByAppendingString:@" supportsSecureCoding"], host, port);
        }

        // A fresh token answers nil in every member both sides have.
        NSArray *tokenGetters = @[@"paymentData", @"transactionIdentifier", @"paymentInstrumentName", @"paymentNetwork"];
        for (NSString *getter in tokenGetters) {
            id hostToken = make(@"PKPaymentToken", @"init", nil);
            id portToken = make(@"charonHost_PKPaymentToken", @"init", nil);
            report([@"fresh token " stringByAppendingString:getter], show(get(hostToken, getter)), show(get(portToken, getter)));
        }

        // The two members the host lets a caller set copy what they are given, so the caller's later change
        // does not reach the object.
        NSMutableData *hostData = [NSMutableData dataWithBytes:"abc" length:3];
        NSMutableData *portData = [NSMutableData dataWithBytes:"abc" length:3];
        id hostToken = make(@"PKPaymentToken", @"init", nil);
        id portToken = make(@"charonHost_PKPaymentToken", @"init", nil);
        set(hostToken, @"setPaymentData:", hostData);
        set(portToken, @"setPaymentData:", portData);
        hostData.length = 1;
        portData.length = 1;
        report(@"token paymentData copies what it is given", show(get(hostToken, @"paymentData")),
               show(get(portToken, @"paymentData")));

        NSMutableString *hostID = [NSMutableString stringWithString:@"id-1"];
        NSMutableString *portID = [NSMutableString stringWithString:@"id-1"];
        set(hostToken, @"setTransactionIdentifier:", hostID);
        set(portToken, @"setTransactionIdentifier:", portID);
        [hostID appendString:@"-changed"];
        [portID appendString:@"-changed"];
        report(@"token transactionIdentifier copies what it is given", show(get(hostToken, @"transactionIdentifier")),
               show(get(portToken, @"transactionIdentifier")));

        // A token that has been set round-trips through its own coder, with its two settable fields intact.
        NSData *hostArchive = [NSKeyedArchiver archivedDataWithRootObject:hostToken requiringSecureCoding:YES error:NULL];
        NSError *portArchiveError = nil;
        NSData *portArchive = [NSKeyedArchiver archivedDataWithRootObject:portToken requiringSecureCoding:YES error:&portArchiveError];
        if (!portArchive)
            printf("  port token archive error: %s\n", portArchiveError.description.UTF8String);
        id hostBack = [NSKeyedUnarchiver unarchivedObjectOfClass:NSClassFromString(@"PKPaymentToken") fromData:hostArchive error:NULL];
        NSError *portError = nil;
        id portBack = [NSKeyedUnarchiver unarchivedObjectOfClass:NSClassFromString(@"charonHost_PKPaymentToken") fromData:portArchive error:&portError];
        if (!portBack)
            printf("  port token unarchive error: %s\n", portError.description.UTF8String);
        report(@"token round trip keeps transactionIdentifier", show(get(hostBack, @"transactionIdentifier")),
               show(get(portBack, @"transactionIdentifier")));
        report(@"token round trip keeps paymentData", show(get(hostBack, @"paymentData")), show(get(portBack, @"paymentData")));

        // A payment keeps the token it was built with, and the same object comes back: not a copy.
        id hostPayment = make(@"PKPayment", @"initWithToken:", hostToken);
        id portPayment = make(@"charonHost_PKPayment", @"initWithToken:", portToken);
        report(@"payment token is the same object", [get(hostPayment, @"token") isEqual:hostToken] ? @"same" : @"other",
               [get(portPayment, @"token") isEqual:portToken] ? @"same" : @"other");

        // A payment built with plain -init has no token, and no shipping method.
        id hostEmpty = make(@"PKPayment", @"init", nil);
        id portEmpty = make(@"charonHost_PKPayment", @"init", nil);
        report(@"empty payment token", show(get(hostEmpty, @"token")), show(get(portEmpty, @"token")));
        report(@"empty payment shippingMethod", show(get(hostEmpty, @"shippingMethod")), show(get(portEmpty, @"shippingMethod")));

        // A payment's shipping method, when set, comes back as the object it was given.
        id hostMethod = [NSString stringWithFormat:@"method"];
        id portMethod = [NSString stringWithFormat:@"method"];
        set(hostEmpty, @"setShippingMethod:", hostMethod);
        set(portEmpty, @"setShippingMethod:", portMethod);
        report(@"payment shippingMethod is the object set", show(get(hostEmpty, @"shippingMethod")),
               show(get(portEmpty, @"shippingMethod")));

        // A payment round-trips its token through its own coder.
        NSData *hostPaymentArchive = [NSKeyedArchiver archivedDataWithRootObject:hostPayment requiringSecureCoding:YES error:NULL];
        NSData *portPaymentArchive = [NSKeyedArchiver archivedDataWithRootObject:portPayment requiringSecureCoding:YES error:NULL];
        id hostPaymentBack = [NSKeyedUnarchiver unarchivedObjectOfClass:NSClassFromString(@"PKPayment") fromData:hostPaymentArchive error:NULL];
        id portPaymentBack = [NSKeyedUnarchiver unarchivedObjectOfClass:NSClassFromString(@"charonHost_PKPayment") fromData:portPaymentArchive error:NULL];
        report(@"payment round trip keeps the token's identifier",
               show(get(get(hostPaymentBack, @"token"), @"transactionIdentifier")),
               show(get(get(portPaymentBack, @"token"), @"transactionIdentifier")));
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
