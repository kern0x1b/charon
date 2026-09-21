#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <netinet/in.h>
#include <string.h>

int charon_network_cellular_override = -1;

static NSString *const CharonExpensiveKey = @"CharonAllowsExpensiveNetworkAccess";
static NSString *const CharonConstrainedKey = @"CharonAllowsConstrainedNetworkAccess";

static BOOL charon_network_cellular(void)
{
    if (charon_network_cellular_override >= 0)
        return charon_network_cellular_override != 0;
    static void *(*create)(void *, const struct sockaddr *);
    static BOOL (*flags)(void *, uint32_t *);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
        if (!handle)
            return;
        create = dlsym(handle, "SCNetworkReachabilityCreateWithAddress");
        flags = dlsym(handle, "SCNetworkReachabilityGetFlags");
    });
    if (!create || !flags)
        return NO;
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    void *reference = create(NULL, (const struct sockaddr *)&address);
    if (!reference)
        return NO;
    uint32_t bits = 0;
    BOOL known = flags(reference, &bits);
    CFRelease(reference);
    return known && (bits & 0x00040000) != 0;
}

static BOOL charon_network_local(NSURL *URL)
{
    NSString *host = URL.host.lowercaseString;
    return [host isEqualToString:@"localhost"] || [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"::1"] || !host;
}

__attribute__((visibility("hidden")))
@interface CharonNetworkGate : NSURLProtocol
@end

@implementation CharonNetworkGate

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    return ![request allowsExpensiveNetworkAccess] && charon_network_cellular() && !charon_network_local(request.URL);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    NSURL *URL = self.request.URL;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = @"The Internet connection appears to be offline.";
    info[NSURLErrorNetworkUnavailableReasonKey] = @(NSURLErrorNetworkUnavailableReasonExpensive);
    if (URL) {
        info[NSURLErrorFailingURLErrorKey] = URL;
        info[NSURLErrorFailingURLStringErrorKey] = URL.absoluteString;
    }
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:info]];
}

- (void)stopLoading
{
}

@end

static void charon_network_install(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSURLProtocol registerClass:[CharonNetworkGate class]];
    });
}

static BOOL charon_network_allows(NSURLRequest *request, NSString *key)
{
    NSNumber *value = [NSURLProtocol propertyForKey:key inRequest:request];
    return value ? value.boolValue : YES;
}

static void charon_network_set(NSMutableURLRequest *request, NSString *key, BOOL allows)
{
    if (allows)
        [NSURLProtocol removePropertyForKey:key inRequest:request];
    else
        [NSURLProtocol setProperty:@NO forKey:key inRequest:request];
}

@implementation NSURLRequest (CharonNetworkAccess)

- (BOOL)allowsExpensiveNetworkAccess
{
    return charon_network_allows(self, CharonExpensiveKey);
}

- (BOOL)allowsConstrainedNetworkAccess
{
    return charon_network_allows(self, CharonConstrainedKey);
}

@end

@implementation NSMutableURLRequest (CharonNetworkAccess)

- (void)setAllowsExpensiveNetworkAccess:(BOOL)allows
{
    if (!allows)
        charon_network_install();
    charon_network_set(self, CharonExpensiveKey, allows);
}

- (void)setAllowsConstrainedNetworkAccess:(BOOL)allows
{
    if (!allows)
        charon_network_install();
    charon_network_set(self, CharonConstrainedKey, allows);
}

@end
