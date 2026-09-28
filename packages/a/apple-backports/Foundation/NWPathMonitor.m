#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#include <sys/ioctl.h>
#import "CharonNWPathMonitor.h"
#import <dlfcn.h>
#import <netinet/in.h>
#import <resolv.h>
#import <sys/socket.h>

@interface CharonNWInterface : CHARON_NW_OBJECT(OS_nw_interface)
@end


@implementation CharonNWInterface {
@public
    NSString *_name;
    uint32_t _index;
    nw_interface_type_t _type;
}
@end

@implementation CharonNWPath {
@public
    nw_path_status_t _status;
    BOOL _expensive, _ipv4, _ipv6, _dns;
    NSArray<CharonNWInterface *> *_interfaces;
}
@end

@implementation CharonNWPathMonitor
@end

/* What an interface *is*, from the number the kernel classifies it with.
 *
 * `getifaddrs` gives every interface a second entry whose address family is `AF_LINK`, and the
 * `struct if_data` behind that address carries `ifi_type`: the IANA ifType number the interface was
 * created with (the public registry, ianaiftype-mib). That is the classification the release itself
 * reads, and this port reads the same number rather than a name. Measured on the host with
 * `getifaddrs` beside `ifconfig -v`, and the table is in facts/Network/NWPath.md:
 *
 *   lo0       24  softwareLoopback   the loopback
 *   en0       6  ethernetCsmacd     the Wi-Fi radio, on a release with no wired Ethernet
 *   utun0     1  other              a tunnel - the kernel does *not* call it IANA `tunnel` (131)
 *   bridge100 209 bridge             a bridge, and a Personal Hotspot hands one out over it
 *
 * The cellular radio is the one number the registry does not carry: it is Apple's own
 * `IFT_CELLULAR`, 0xff, in XNU's `net/if_types.h` (open source, APSL, the same header this port
 * reads the SDK's own `net/if_types.h` for - and that file in the SDK has none of the constants in
 * it, which is why this one is spelled out here and cited rather than taken).
 */
#define CHARON_IFI_TYPE_OTHER       1     /* IANA other, and what a utun carries */
#define CHARON_IFI_TYPE_ETHERNET    6     /* IANA ethernetCsmacd */
#define CHARON_IFI_TYPE_SOFT_LOOPBACK 24  /* IANA softwareLoopback */
#define CHARON_IFI_TYPE_CELLULAR    0xff  /* XNU's IFT_CELLULAR, which IANA does not carry */

/* Whether an interface of this type is on the path a monitor is building.
 *
 * `other` - a tunnel, a bridge - is not, and that is the release's own answer rather than a rule the
 * port invented: on the machine the port is measured against, `ifconfig -l` lists utun0, utun1, utun2,
 * bridge0, awdl0 and llw0, and `nw_path_enumerate_interfaces` on that same machine's own path lists
 * **en0 and nothing else** (measured; the run is in the facts). So the interfaces the kernel names as
 * `other` are exactly the ones a path is not over, and the classifier that tells a tunnel from a
 * bridge is what lets the monitor say so deliberately - and lets a program that asked for a type be
 * told the truth when it is not there.
 */
static BOOL charon_path_wants(nw_interface_type_t required, nw_interface_type_t type, BOOL reachable, BOOL cellular)
{
    if (required == nw_interface_type_other) {
        if (type == nw_interface_type_loopback || type == nw_interface_type_other)
            return NO;
        if (!reachable)
            return NO;
        return (type == nw_interface_type_cellular) == cellular;
    }
    return type == required;
}

static nw_interface_type_t charon_type_of(const struct ifaddrs *item)
{
    for (const struct ifaddrs *link = item; link; link = link->ifa_next) {
        if (!link->ifa_addr || link->ifa_addr->sa_family != AF_LINK || !link->ifa_data)
            continue;
        const struct if_data *data = (const struct if_data *)link->ifa_data;
        switch (data->ifi_type) {
        case CHARON_IFI_TYPE_SOFT_LOOPBACK:
            return nw_interface_type_loopback;
        case CHARON_IFI_TYPE_CELLULAR:
            return nw_interface_type_cellular;
        case CHARON_IFI_TYPE_ETHERNET:
            return nw_interface_type_wifi;
        default:
            /* Everything else keeps its own kind and is `other` to a program: a tunnel and a bridge are
               the interfaces a VPN and a Personal Hotspot put a path on, and a path that dropped them
               would be a path that could not describe itself. */
            return nw_interface_type_other;
        }
    }
    /* No AF_LINK entry, so the kernel classified nothing: where `ifi_type` cannot decide, this asks
     * whether the interface is a point-to-point link with a gateway, which is the cellular radio on
     * this release. A tunnel is point-to-point too and has no gateway, so it answers `other` - the
     * same answer its `ifi_type` gives, from the other end. */
    if (item->ifa_flags & IFF_POINTOPOINT) {
        int probe = socket(AF_INET, SOCK_DGRAM, 0);
        BOOL gateway = NO;
        if (probe >= 0) {
            struct ifreq request;
            memset(&request, 0, sizeof request);
            strncpy(request.ifr_name, item->ifa_name, IFNAMSIZ - 1);
            gateway = ioctl(probe, SIOCGIFDSTADDR, &request) == 0;
            close(probe);
        }
        return gateway ? nw_interface_type_cellular : nw_interface_type_other;
    }
    /* IFF_LOOPBACK stays as the cross-check it always was: the flag and the number agree, and where
       they do not, the flag is what the release's own path has always used. */
    if (item->ifa_flags & IFF_LOOPBACK)
        return nw_interface_type_loopback;
    return nw_interface_type_wifi;
}

/* The classifier, named for the objects differential: it is the only place the port decides what kind
   of interface something is, and the differential asks it with the numbers measured on the host
   (CHARON_TRACE_PATH aside) so that each branch of it is a check that can fail. */
nw_interface_type_t charon_path_interface_type(const struct ifaddrs *item);

static BOOL charon_usable_v4(const struct sockaddr *address)
{
    const struct sockaddr_in *v4 = (const struct sockaddr_in *)address;
    uint32_t host = ntohl(v4->sin_addr.s_addr);
    return (host >> 16) != 0xA9FE && host != 0;
}

static BOOL charon_usable_v6(const struct sockaddr *address)
{
    const struct sockaddr_in6 *v6 = (const struct sockaddr_in6 *)address;
    return !IN6_IS_ADDR_LINKLOCAL(&v6->sin6_addr) && !IN6_IS_ADDR_UNSPECIFIED(&v6->sin6_addr) && !IN6_IS_ADDR_LOOPBACK(&v6->sin6_addr);
}

static BOOL charon_has_nameserver(void)
{
    static int (*initialise)(struct __res_state *);
    static void (*destroy)(struct __res_state *);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *image = dlopen("/usr/lib/libresolv.dylib", RTLD_NOW);
        initialise = image ? dlsym(image, "res_9_ninit") : NULL;
        destroy = image ? dlsym(image, "res_9_ndestroy") : NULL;
    });
    if (!initialise || !destroy)
        return NO;
    struct __res_state state;
    memset(&state, 0, sizeof state);
    if (initialise(&state) != 0)
        return NO;
    BOOL has = state.nscount > 0;
    destroy(&state);
    return has;
}

static CharonNWInterface *charon_interface(const char *name, nw_interface_type_t type)
{
    CharonNWInterface *interface = [[CharonNWInterface alloc] init];
    interface->_name = @(name);
    interface->_index = if_nametoindex(name);
    interface->_type = type;
    return interface;
}

static CharonNWPath *charon_path(SCNetworkReachabilityRef reachability, CharonNWPathMonitor *monitor)
{
    CharonNWPath *path = [[CharonNWPath alloc] init];
    SCNetworkReachabilityFlags flags = 0;
    SCNetworkReachabilityGetFlags(reachability, &flags);
    BOOL reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    BOOL required = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
    BOOL cellular = NO;
#if TARGET_OS_IPHONE
    cellular = (flags & kSCNetworkReachabilityFlagsIsWWAN) != 0;
#endif
    NSMutableArray *interfaces = [NSMutableArray array];
    BOOL v4 = NO, v6 = NO;
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) == 0) {
        NSMutableSet *seen = [NSMutableSet set];
        for (struct ifaddrs *item = list; item; item = item->ifa_next) {
            if (!item->ifa_addr || !(item->ifa_flags & IFF_UP) || !(item->ifa_flags & IFF_RUNNING))
                continue;
            nw_interface_type_t type = charon_type_of(item);
            for (NSNumber *prohibited in monitor->_prohibitedTypes) {
                if ((nw_interface_type_t)prohibited.unsignedIntegerValue == type)
                    goto next;
            }
            /* An `other` monitor is the default one and it takes every usable interface that is not
               the loopback - including the ones the kernel names as `other` (a tunnel, a bridge), which
               is how the release enumerates them: they are the interfaces a path is over, not noise to
               be dropped. A monitor that asked for a type takes only that type. */
            if (!charon_path_wants(monitor->_required, type, reachable, cellular))
                continue;
            BOOL address4 = item->ifa_addr->sa_family == AF_INET && charon_usable_v4(item->ifa_addr);
            BOOL address6 = item->ifa_addr->sa_family == AF_INET6 && charon_usable_v6(item->ifa_addr);
            if (!address4 && !address6)
                continue;
            if (type != nw_interface_type_loopback) {
                v4 = v4 || address4;
                v6 = v6 || address6;
            }
            if (![seen containsObject:@(item->ifa_name)]) {
                [seen addObject:@(item->ifa_name)];
                [interfaces addObject:charon_interface(item->ifa_name, type)];
            }
        next:;
        }
        freeifaddrs(list);
    }
    path->_interfaces = interfaces;
    path->_ipv4 = v4;
    path->_ipv6 = v6;
    path->_dns = interfaces.count && monitor->_required != nw_interface_type_loopback && charon_has_nameserver();
    path->_expensive = interfaces.count && cellular;
    if (!interfaces.count)
        path->_status = reachable && required ? nw_path_status_satisfiable : nw_path_status_unsatisfied;
    else
        path->_status = required ? nw_path_status_satisfiable : nw_path_status_satisfied;
    return path;
}

nw_path_monitor_t nw_path_monitor_create(void)
{
    CharonNWPathMonitor *monitor = [[CharonNWPathMonitor alloc] init];
    monitor->_required = nw_interface_type_other;
    monitor->_prohibitedTypes = [NSMutableArray array];
    return monitor;
}

nw_path_monitor_t nw_path_monitor_create_with_type(nw_interface_type_t required_interface_type)
{
    CharonNWPathMonitor *monitor = (CharonNWPathMonitor *)nw_path_monitor_create();
    monitor->_required = required_interface_type;
    return monitor;
}

void nw_path_monitor_set_cancel_handler(nw_path_monitor_t monitor, nw_path_monitor_cancel_handler_t cancel_handler)
{
    ((CharonNWPathMonitor *)monitor)->_cancel = [cancel_handler copy];
}

void nw_path_monitor_set_update_handler(nw_path_monitor_t monitor, nw_path_monitor_update_handler_t update_handler)
{
    ((CharonNWPathMonitor *)monitor)->_update = [update_handler copy];
}

void nw_path_monitor_set_queue(nw_path_monitor_t monitor, dispatch_queue_t queue)
{
    ((CharonNWPathMonitor *)monitor)->_queue = queue;
}

static void charon_deliver(CharonNWPathMonitor *monitor, int generation, BOOL always)
{
    if (monitor->_cancelled || generation != monitor->_generation || !monitor->_reachability)
        return;
    CharonNWPath *path = charon_path(monitor->_reachability, monitor);
    if (!always && monitor->_last && nw_path_is_equal(monitor->_last, path))
        return;
    monitor->_last = path;
    if (monitor->_update)
        monitor->_update(path);
}

static void charon_reachability_callback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info)
{
    CharonNWPathMonitor *monitor = (__bridge CharonNWPathMonitor *)info;
    charon_deliver(monitor, monitor->_generation, NO);
}

void nw_path_monitor_start(nw_path_monitor_t handle)
{
    CharonNWPathMonitor *monitor = (CharonNWPathMonitor *)handle;
    @synchronized (monitor) {
        if (monitor->_cancelled || !monitor->_queue)
            return;
        int generation = ++monitor->_generation;
        if (!monitor->_reachability) {
            struct sockaddr_in zero;
            memset(&zero, 0, sizeof zero);
            zero.sin_len = sizeof zero;
            zero.sin_family = AF_INET;
            monitor->_reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zero);
            SCNetworkReachabilityContext context = {0, (__bridge void *)monitor, CFRetain, CFRelease, NULL};
            SCNetworkReachabilitySetCallback(monitor->_reachability, charon_reachability_callback, &context);
            SCNetworkReachabilitySetDispatchQueue(monitor->_reachability, monitor->_queue);
        }
        monitor->_started = YES;
        CharonNWPath *initial = charon_path(monitor->_reachability, monitor);
        dispatch_async(monitor->_queue, ^{
            if (generation != monitor->_generation)
                return;
            monitor->_last = initial;
            if (monitor->_update)
                monitor->_update(initial);
        });
    }
}

void nw_path_monitor_cancel(nw_path_monitor_t handle)
{
    CharonNWPathMonitor *monitor = (CharonNWPathMonitor *)handle;
    dispatch_queue_t queue;
    nw_path_monitor_cancel_handler_t cancel;
    @synchronized (monitor) {
        if (monitor->_cancelled)
            return;
        monitor->_cancelled = YES;
        if (monitor->_reachability) {
            SCNetworkReachabilitySetDispatchQueue(monitor->_reachability, NULL);
            SCNetworkReachabilitySetCallback(monitor->_reachability, NULL, NULL);
            CFRelease(monitor->_reachability);
            monitor->_reachability = NULL;
        }
        queue = monitor->_queue;
        cancel = monitor->_cancel;
    }
    if (queue && cancel)
        dispatch_async(queue, cancel);
}

nw_path_status_t nw_path_get_status(nw_path_t path)
{
    return ((CharonNWPath *)path)->_status;
}

void nw_path_enumerate_interfaces(nw_path_t path, nw_path_enumerate_interfaces_block_t enumerate_block)
{
    for (CharonNWInterface *interface in ((CharonNWPath *)path)->_interfaces) {
        if (!enumerate_block(interface))
            break;
    }
}

bool nw_path_is_equal(nw_path_t first, nw_path_t second)
{
    CharonNWPath *a = (CharonNWPath *)first, *b = (CharonNWPath *)second;
    if (a == b)
        return true;
    if (!a || !b || a->_status != b->_status || a->_expensive != b->_expensive || a->_ipv4 != b->_ipv4 || a->_ipv6 != b->_ipv6 || a->_dns != b->_dns || a->_interfaces.count != b->_interfaces.count)
        return false;
    for (NSUInteger index = 0; index < a->_interfaces.count; index++) {
        if (![a->_interfaces[index]->_name isEqualToString:b->_interfaces[index]->_name])
            return false;
    }
    return true;
}

bool nw_path_is_expensive(nw_path_t path)
{
    return ((CharonNWPath *)path)->_expensive;
}

bool nw_path_has_ipv4(nw_path_t path)
{
    return ((CharonNWPath *)path)->_ipv4;
}

bool nw_path_has_ipv6(nw_path_t path)
{
    return ((CharonNWPath *)path)->_ipv6;
}

bool nw_path_has_dns(nw_path_t path)
{
    return ((CharonNWPath *)path)->_dns;
}

bool nw_path_uses_interface_type(nw_path_t path, nw_interface_type_t interface_type)
{
    for (CharonNWInterface *interface in ((CharonNWPath *)path)->_interfaces) {
        if (interface->_type == interface_type)
            return true;
    }
    return false;
}

nw_endpoint_t nw_path_copy_effective_local_endpoint(nw_path_t path)
{
    return nil;
}

nw_endpoint_t nw_path_copy_effective_remote_endpoint(nw_path_t path)
{
    return nil;
}

nw_interface_type_t nw_interface_get_type(nw_interface_t interface)
{
    return ((CharonNWInterface *)interface)->_type;
}

const char *nw_interface_get_name(nw_interface_t interface)
{
    return ((CharonNWInterface *)interface)->_name.UTF8String;
}

uint32_t nw_interface_get_index(nw_interface_t interface)
{
    return ((CharonNWInterface *)interface)->_index;
}

nw_interface_type_t charon_path_interface_type(const struct ifaddrs *item)
{
    return charon_type_of(item);
}

/* The path's own decision, named for the objects differential: it is asked about synthetic interfaces
   there, so that a filter on the path can be a check that can fail rather than a line in a comment. */
BOOL charon_path_wants_interface(nw_interface_type_t required, nw_interface_type_t type, BOOL reachable, BOOL cellular)
{
    return charon_path_wants(required, type, reachable, cellular);
}
