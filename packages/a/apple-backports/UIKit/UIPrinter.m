#import <UIKit/UIKit.h>
#import <errno.h>
#import <fcntl.h>
#import <netdb.h>
#import <poll.h>
#import <sys/socket.h>
#import <unistd.h>

// A printer is the URL it is reached at. The release has no printer object: the print system that knows the printers
// is not reached from here, so the descriptive properties are the host's answers for a printer it cannot describe
// (facts/UIKit/UIPrinter.md). contactPrinter: opens a TCP connection to the URL's host and port, as the newer system
// does before it talks IPP, and answers YES only if the connection is made.

static const NSTimeInterval kCharonContactTimeout = 30;

// Blocking, so it runs on a background queue. Only ipp, ipps, http and https name a host the port can reach; every
// other URL, and one with no host, is not reachable.
static BOOL charon_printerReachable(NSURL *url)
{
    NSString *scheme = [[url scheme] lowercaseString];
    NSString *host = [url host];
    if (![host length])
        return NO;

    NSString *port;
    if ([url port])
        port = [[url port] stringValue];
    else if ([scheme isEqualToString:@"ipp"] || [scheme isEqualToString:@"ipps"])
        port = @"631";
    else if ([scheme isEqualToString:@"http"])
        port = @"80";
    else if ([scheme isEqualToString:@"https"])
        port = @"443";
    else
        return NO;

    struct addrinfo hints = { 0 }, *addresses = NULL;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo([host UTF8String], [port UTF8String], &hints, &addresses) != 0)
        return NO;

    BOOL reached = NO;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:kCharonContactTimeout];
    for (struct addrinfo *address = addresses; address && !reached; address = address->ai_next) {
        int fd = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
        if (fd < 0)
            continue;
        if (fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK) < 0) {
            close(fd);
            continue;
        }
        if (connect(fd, address->ai_addr, address->ai_addrlen) == 0) {
            reached = YES;
        } else if (errno == EINPROGRESS) {
            NSTimeInterval left = [deadline timeIntervalSinceNow];
            struct pollfd wait = { fd, POLLOUT, 0 };
            if (left > 0 && poll(&wait, 1, (int)(left * 1000)) == 1) {
                int error = -1;
                socklen_t length = sizeof error;
                if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0)
                    reached = (error == 0);
            }
        }
        close(fd);
    }
    freeaddrinfo(addresses);
    return reached;
}

@implementation UIPrinter {
    NSURL *_URL;
}

+ (UIPrinter *)printerWithURL:(NSURL *)url
{
    UIPrinter *printer = [[UIPrinter alloc] init];
    printer->_URL = [url copy];
    return printer;
}

- (NSURL *)URL
{
    return _URL;
}

- (NSString *)displayName
{
    return @"";
}

- (NSString *)displayLocation
{
    return nil;
}

- (NSString *)makeAndModel
{
    return nil;
}

- (UIPrinterJobTypes)supportedJobTypes
{
    return UIPrinterJobTypeUnknown;
}

- (BOOL)supportsColor
{
    return NO;
}

- (BOOL)supportsDuplex
{
    return NO;
}

// The handler runs once. A printer with no URL answers at once, before this method returns, as the host does; any
// other printer answers later, on the main queue.
- (void)contactPrinter:(void (^)(BOOL available))completionHandler
{
    if (!completionHandler)
        return;
    NSURL *url = _URL;
    void (^handler)(BOOL) = [completionHandler copy];
    if (!url) {
        handler(NO);
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL available = charon_printerReachable(url);
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(available);
        });
    });
}

@end
