/*
 * The browser object of Network, and the calls the 12.0 cache already carries.
 *
 * What a browser is here: a Bonjour browse, over the release's own DNS-SD client. A browse is a PTR
 * query for the type in the domain - which is what a browse is on the wire - so the port asks it with
 * `DNSServiceQueryRecord` and reads each instance name out of the answer, and takes every answer from
 * a dispatch source over the reference's own descriptor (`DNSServiceRefSockFD` says when a result is
 * waiting, `DNSServiceProcessResult` is the call that takes it). Every callback therefore runs on the
 * queue the program gave the browser, and none of them runs before the browser has been started.
 * `DNSServiceResolve` answers for each instance with the port it publishes and the record it
 * advertises. Nothing here is a second DNS-SD: the release answers the queries and the release decides
 * what is on the link.
 *
 * What a browse result is: one service instance the browse reported, with the endpoint a program
 * connects to (a Bonjour service endpoint carrying the port the service resolved to), the interfaces
 * the browse named the service on - the `interfaceIndex` every answer carries, which is what tells one
 * answer on the Wi-Fi radio from the same answer on a Personal Hotspot's bridge - and the TXT record
 * when the descriptor asked for one.
 *
 * A result is reported once it can be used. The browse says an instance exists, and the port resolves
 * it before the result is handed over, so the endpoint of the result carries the port the service
 * publishes and not zero. That is also what makes the change bits mean what the header says: a service
 * that has not resolved has nothing a program could compare, so it is never the `old_result` of a pair.
 *
 * The interfaces of a result are this library's own interface objects, reached through the path monitor
 * the library already carries (`nw_path_monitor_*`, `nw_path_enumerate_interfaces`,
 * `nw_interface_get_index`). A browse result hands out `nw_interface_t`, and the only objects of that
 * type anywhere on this release are the ones the path monitor makes, so the browser keeps one object
 * per index as the monitor reports it, and an answer naming an index picks its object out of that
 * table. An answer naming an interface the port has no object for - one that went down between the
 * answer and the last path update - contributes no interface, and the count says so.
 *
 * Why the browse is a PTR query and not `DNSServiceBrowse`: the build SDK is iOS 16.4 and its
 * `DNSServiceBrowse` takes an `interfaceIndex` this port's releases do not pass - the parameter was
 * added to the header years after they shipped, so calling the entry point as the header declares it
 * would read a register the release never wrote. `DNSServiceQueryRecord` and `DNSServiceResolve` have
 * carried `interfaceIndex` since the API was introduced and their signatures are the same on every
 * release this port builds, which is what `facts/Network/NWBrowser.md` records.
 *
 * This file holds the two calls the 12.0 cache already exports - `nw_browser_create` and
 * `nw_browser_cancel`, measured in `coordination/corpus/caches/12.0.tsv` - and the object itself. The
 * rest of the surface is in nw16-browser.m, because the ladder has no rung between 12.0 and 16.0 and
 * those calls are first exported by the 16.0 cache; `tools/release-split.lua` is what says so, and the
 * SDK's header gives the whole family iOS 13. The file reaches the object through the C functions at the
 * end of this one, for the reason `nw12-listener.m` gives for the listener's.
 */

#import "CharonNW.h"
#import "CharonNWSupport.h"

#include <arpa/inet.h>
#include <dns_sd.h>
#include <string.h>

/* The DNS-SD entry points are weak imports, and the reason is measured rather than guessed:
   `coordination/corpus/caches/6.0.tsv` lists every one of them exported by iOS 6.0 -
   DNSServiceQueryRecord, DNSServiceResolve, DNSServiceProcessResult and DNSServiceRefSockFD among them,
   all in libSystem.dylib - and the armv7 ladder this package builds ends at 10.3.4, so every band
   from 6.0 up has them. The floor of that ladder is 4.3 and this machine holds no export list for it,
   so rather than assert what could not be measured the port binds them weakly and answers the browser's
   own documented failure where a band turns out to have none: `nw_browser_state_failed` with
   `nw_error_domain_dns`. */
#define CHARON_NW_DNS_WEAK __attribute__((weak_import))
extern DNSServiceErrorType DNSServiceQueryRecord(DNSServiceRef *, DNSServiceFlags, uint32_t, const char *,
                                                uint16_t, uint16_t, DNSServiceQueryRecordReply, void *) CHARON_NW_DNS_WEAK;
extern DNSServiceErrorType DNSServiceResolve(DNSServiceRef *, DNSServiceFlags, uint32_t, const char *,
                                            const char *, const char *, DNSServiceResolveReply, void *) CHARON_NW_DNS_WEAK;
extern void DNSServiceRefDeallocate(DNSServiceRef) CHARON_NW_DNS_WEAK;
extern int DNSServiceProcessResult(DNSServiceRef) CHARON_NW_DNS_WEAK;
extern int DNSServiceRefSockFD(DNSServiceRef) CHARON_NW_DNS_WEAK;

@class CharonNWBrowser;

/* One service instance the browse reported, and the resolve that turns its name into a port and a
   record. The browser owns every lookup, so the way back to it is weak: a resolve that answers after
   the browser is gone finds nothing and does nothing. */
@interface CharonNWBrowserLookup : NSObject {
@public
    NSString *_key;
    NSString *_name;
    NSString *_type;
    NSString *_domain;
    NSMutableArray *_interfaceIndexes;
    __weak CharonNWBrowser *_browser;
    DNSServiceRef _resolve;
    dispatch_source_t _source;
    NSString *_port;
    CharonNWTxtRecord *_txt;
    BOOL _resolved;
    BOOL _reported;
    BOOL _wantRecord;
}
@end

@implementation CharonNWBrowserLookup

/* The reference owns the descriptor the source watches, so the source goes first and never fires
   against a reference that is gone. Nothing else closes that descriptor: `DNSServiceRefDeallocate` is
   what closes it, and a source that closed it as well would close a descriptor number the process may
   have handed out again in between. */
- (void)close
{
    if (_source) {
        dispatch_source_cancel(_source);
        _source = nil;
    }
    if (_resolve) {
        DNSServiceRefDeallocate(_resolve);
        _resolve = NULL;
    }
}

@end

@interface CharonNWBrowser : NSObject <OS_nw_browser> {
@public
    CharonNWBrowseDescriptor *_descriptor;
    CharonNWParameters *_parameters;
    dispatch_queue_t _queue;
    nw_browser_state_changed_handler_t _state;
    nw_browser_browse_results_changed_handler_t _results;
    nw_browser_state_t _value;
    NSString *_type;
    NSString *_domain;
    DNSServiceRef _browse;
    dispatch_source_t _source;
    NSMutableDictionary *_reported;
    NSMutableDictionary *_lookups;
    NSMutableArray *_batch;
    NSMutableDictionary *_interfaces;
    nw_path_monitor_t _monitor;
    BOOL _started;
    BOOL _cancelled;
}
@end

@implementation CharonNWBrowser
@end

/* The states are the SDK's: never backwards, `waiting` before the browse runs, `ready` once it does,
   `failed` with the error that stopped it and `cancelled` when the program said so. */
static void charon_browser_report(CharonNWBrowser *browser, nw_browser_state_t state, CharonNWError *error)
{
    @synchronized(browser) {
        if (browser->_cancelled && state != nw_browser_state_cancelled)
            return;
        if (browser->_value == state && state != nw_browser_state_failed && state != nw_browser_state_ready)
            return;
        browser->_value = state;
    }
    nw_browser_state_changed_handler_t handler = browser->_state;
    if (handler)
        handler(state, (nw_error_t)error);
}

static CharonNWError *charon_browser_error(nw_error_domain_t domain, int code)
{
    CharonNWError *error = [[CharonNWError alloc] init];
    error->_domain = domain;
    error->_code = code;
    return error;
}

/* A source over a descriptor, without the close-on-cancel of `charon_nw_read_source`: a DNS-SD
   reference closes its own descriptor in `DNSServiceRefDeallocate`, and a source that closed it as
   well would close a descriptor number the process may have handed out again in between. */
static dispatch_source_t charon_browser_source(int handle, dispatch_queue_t queue)
{
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)handle, 0, queue);
    if (source)
        dispatch_resume(source);
    return source;
}

/* One interface object of this library, or NULL when the path monitor has not reported that index:
   `nw_interface_get_index` is the port's own way of saying which interface an object is, and the
   monitor is where those objects come from. */
static nw_interface_t charon_browser_interface(CharonNWBrowser *browser, NSNumber *index)
{
    return (nw_interface_t)browser->_interfaces[index];
}

/* The result as the service is known now: a fresh instance every time, because the handler's contract
   is that the new result replaces the old one. */
static CharonNWBrowseResult *charon_browser_result(CharonNWBrowser *browser, CharonNWBrowserLookup *lookup)
{
    CharonNWBrowseResult *result = [[CharonNWBrowseResult alloc] init];
    result->_name = lookup->_name;
    result->_type = lookup->_type;
    result->_domain = lookup->_domain;
    result->_txtRecord = lookup->_txt;
    NSMutableArray *interfaces = [NSMutableArray array];
    for (NSNumber *index in lookup->_interfaceIndexes) {
        nw_interface_t interface = charon_browser_interface(browser, index);
        if (interface)
            [interfaces addObject:(id)interface];
    }
    result->_interfaces = interfaces;
    CharonNWEndpoint *endpoint = [[CharonNWEndpoint alloc] init];
    endpoint->_type = nw_endpoint_type_bonjour_service;
    endpoint->_bonjourName = lookup->_name;
    endpoint->_bonjourType = lookup->_type;
    endpoint->_bonjourDomain = lookup->_domain;
    endpoint->_port = lookup->_port ?: @"0";
    endpoint->_txtRecord = lookup->_txt;
    result->_endpoint = endpoint;
    return result;
}

static void charon_browser_enqueue(CharonNWBrowser *browser, CharonNWBrowseResult *old, CharonNWBrowseResult *fresh)
{
    [browser->_batch addObject:[NSArray arrayWithObjects:(id)(old ?: [NSNull null]),
                                                   (id)(fresh ?: [NSNull null]), nil]];
}

/* One batch of browse answers is one batch of handler calls and the last of them says so, which is
   what `batch_complete` is for: a program that draws a list of services redraws it once. */
static void charon_browser_drain(CharonNWBrowser *browser)
{
    if (!browser->_batch.count)
        return;
    NSArray *batch = [browser->_batch copy];
    [browser->_batch removeAllObjects];
    nw_browser_browse_results_changed_handler_t handler = browser->_results;
    if (!handler)
        return;
    for (NSUInteger index = 0; index < batch.count; index++) {
        id old = [batch[index][0] isKindOfClass:[NSNull class]] ? nil : batch[index][0];
        id fresh = [batch[index][1] isKindOfClass:[NSNull class]] ? nil : batch[index][1];
        handler((nw_browse_result_t)old, (nw_browse_result_t)fresh, index + 1 == batch.count);
    }
}

/* Take what a reference has waiting. The answers delivered here may have started resolves of their
   own; each of those has a reference and a source of its own and is taken the same way. */
static void charon_browser_pump(DNSServiceRef reference, CharonNWBrowser *browser)
{
    if (reference)
        DNSServiceProcessResult(reference);
    charon_browser_drain(browser);
}

/* The service is no longer on any interface: the last result the program was given goes away with it,
   and a service that never resolved was never given one, so it goes quietly. */
static void charon_browser_gone(CharonNWBrowser *browser, CharonNWBrowserLookup *lookup)
{
    CharonNWBrowseResult *reported = browser->_reported[lookup->_key];
    [lookup close];
    [browser->_lookups removeObjectForKey:lookup->_key];
    if (!reported)
        return;
    [browser->_reported removeObjectForKey:lookup->_key];
    charon_browser_enqueue(browser, reported, nil);
}

/* The resolve answered: the port the service publishes, and the record it advertises when the
   descriptor asked for one. */
static void charon_browser_resolved(DNSServiceRef sdRef, DNSServiceFlags flags, uint32_t interfaceIndex,
                                    DNSServiceErrorType errorCode, const char *fullname, const char *hosttarget,
                                    uint16_t port, uint16_t txtLen, const unsigned char *txtRecord, void *context)
{
    CharonNWBrowserLookup *lookup = (__bridge CharonNWBrowserLookup *)context;
    CharonNWBrowser *browser = lookup->_browser;
    (void)sdRef;
    (void)flags;
    (void)interfaceIndex;
    (void)fullname;
    (void)hosttarget;
    [lookup close];
    if (!browser || browser->_cancelled)
        return;
    /* A resolve that failed is a service the port cannot connect to. Nothing is reported for it, and a
       service already reported keeps the result it had: a browse keeps going when one service on the
       link goes away mid-resolve, and no browse error is raised for that. */
    if (errorCode != kDNSServiceErr_NoError)
        return;
    lookup->_port = [NSString stringWithFormat:@"%u", ntohs(port)];
    if (lookup->_wantRecord && txtLen)
        lookup->_txt = (CharonNWTxtRecord *)nw_txt_record_create_with_bytes(txtRecord, txtLen);
    lookup->_resolved = YES;
    CharonNWBrowseResult *old = browser->_reported[lookup->_key];
    CharonNWBrowseResult *fresh = charon_browser_result(browser, lookup);
    lookup->_reported = YES;
    browser->_reported[lookup->_key] = fresh;
    if (old && nw_txt_record_is_equal((nw_txt_record_t)old->_txtRecord, (nw_txt_record_t)fresh->_txtRecord))
        return;
    charon_browser_enqueue(browser, old, fresh);
}

static CharonNWBrowserLookup *charon_browser_lookup(CharonNWBrowser *browser, NSString *name, NSString *type,
                                                    NSString *domain)
{
    CharonNWBrowserLookup *lookup = [[CharonNWBrowserLookup alloc] init];
    lookup->_key = name;
    lookup->_name = name;
    lookup->_type = type;
    lookup->_domain = domain;
    lookup->_interfaceIndexes = [NSMutableArray array];
    lookup->_wantRecord = browser->_descriptor->_includeTxtRecord;
    lookup->_browser = browser;
    browser->_lookups[name] = lookup;
    return lookup;
}

/* Resolve the service once: its port, and its record when the descriptor asked for one. A resolve that
   cannot be started leaves the service unreported - there is no port to connect to - and the next
   browse answer for it tries again. */
static void charon_browser_resolve(CharonNWBrowser *browser, CharonNWBrowserLookup *lookup)
{
    DNSServiceRef resolve = NULL;
    if (!DNSServiceResolve || DNSServiceResolve(&resolve, 0, kDNSServiceInterfaceIndexAny,
                                                lookup->_name.UTF8String, lookup->_type.UTF8String,
                                                lookup->_domain.UTF8String, charon_browser_resolved,
                                                (__bridge void *)lookup) != kDNSServiceErr_NoError || !resolve)
        return;
    lookup->_resolve = resolve;
    lookup->_source = charon_browser_source(DNSServiceRefSockFD(resolve), browser->_queue);
    if (!lookup->_source) {
        [lookup close];
        return;
    }
    __weak CharonNWBrowser *weak = browser;
    dispatch_source_set_event_handler(lookup->_source, ^{
        CharonNWBrowser *strong = weak;
        if (strong && !strong->_cancelled)
            charon_browser_pump(lookup->_resolve, strong);
    });
}

/* The name a PTR answer carries: the instance name in wire form, which is a sequence of length-prefixed
   labels. A label whose top two bits are set is a compression pointer, and the name before it is
   complete - a compressed suffix is the domain the query was for, which the port already holds. */
static NSString *charon_browser_instance(const void *rdata, uint16_t rdlen)
{
    const uint8_t *bytes = (const uint8_t *)rdata;
    const uint8_t *end = bytes + rdlen;
    NSMutableString *name = [NSMutableString string];
    while (bytes < end) {
        uint8_t length = *bytes++;
        if (length == 0)
            break;
        if (length & 0xC0)
            break;
        if (bytes + length > end)
            break;
        if (name.length)
            [name appendString:@"."];
        [name appendString:[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding]];
        bytes += length;
    }
    return name.length ? name : nil;
}

/* The name a PTR query is for: `<type>.<domain>` in wire form, with the trailing dot the descriptor's
   domain ends in made the label's own terminator. */
static NSString *charon_browser_query(NSString *type, NSString *domain)
{
    NSString *name = domain;
    while ([name hasSuffix:@"."])
        name = [name substringToIndex:name.length - 1];
    return [NSString stringWithFormat:@"%@.%@.", type, name];
}

/* One browse answer: the instance is on an interface, or it is not any more. */
static void charon_browser_answer(DNSServiceRef sdRef, DNSServiceFlags flags, uint32_t interfaceIndex,
                                  DNSServiceErrorType errorCode, const char *fullname, uint16_t rrtype,
                                  uint16_t rrclass, uint16_t rdlen, const void *rdata, uint32_t ttl,
                                  void *context)
{
    CharonNWBrowser *browser = (__bridge CharonNWBrowser *)context;
    (void)sdRef;
    (void)fullname;
    (void)rrtype;
    (void)rrclass;
    (void)ttl;
    if (!browser || browser->_cancelled || errorCode != kDNSServiceErr_NoError)
        return;
    /* The query is for PTR records, so anything else is not an answer about a service. */
    if (rrtype != kDNSServiceType_PTR)
        return;
    NSString *name = charon_browser_instance(rdata, rdlen);
    if (!name)
        return;
    /* `Add` is what a PTR answer carries when the instance is there; the same answer without it is the
       instance going away, which is what the flag's own documentation says of an enumeration. */
    BOOL added = (flags & kDNSServiceFlagsAdd) != 0;
    CharonNWBrowserLookup *lookup = browser->_lookups[name];
    if (!lookup) {
        if (!added)
            return;
        lookup = charon_browser_lookup(browser, name, browser->_type, browser->_domain);
    }
    NSNumber *index = @(interfaceIndex);
    if (added == (BOOL)[lookup->_interfaceIndexes containsObject:index])
        return;
    if (added)
        [lookup->_interfaceIndexes addObject:index];
    else
        [lookup->_interfaceIndexes removeObject:index];
    if (!lookup->_interfaceIndexes.count) {
        charon_browser_gone(browser, lookup);
        charon_browser_drain(browser);
        return;
    }
    if (!lookup->_resolve && !lookup->_resolved) {
        /* Nothing has been reported for this service yet; the first result is the resolve's, and it
           carries the interfaces as they stand when the resolve answers. */
        charon_browser_resolve(browser, lookup);
        return;
    }
    CharonNWBrowseResult *old = browser->_reported[lookup->_key];
    if (!old)
        return;
    CharonNWBrowseResult *fresh = charon_browser_result(browser, lookup);
    browser->_reported[lookup->_key] = fresh;
    charon_browser_enqueue(browser, old, fresh);
}

static void charon_browser_interfaces(CharonNWBrowser *browser, nw_path_t path)
{
    NSMutableDictionary *interfaces = [NSMutableDictionary dictionary];
    /* The typedef, not a spelled-out `bool`: dns_sd.h above pulled in stdbool.h, where `bool` is a
       macro, and the block's own return type is C99 bool. */
    nw_path_enumerate_interfaces_block_t each = ^(nw_interface_t interface) {
        interfaces[@(nw_interface_get_index(interface))] = (id)interface;
        return (bool)true;
    };
    nw_path_enumerate_interfaces(path, each);
    browser->_interfaces = interfaces;
}

/* What the browser browses for. A Bonjour descriptor names the type and the domain itself; an
   application service is one name that stands for both, and an application service's name on the link
   is `_<name>._tcp` in the local domain - the spelling facts/Network/NWBrowser.md carries. */
static BOOL charon_browser_target(CharonNWBrowser *browser, NSString **out_type, NSString **out_domain)
{
    NSString *application = browser->_descriptor->_applicationService;
    if (application.length) {
        *out_type = [NSString stringWithFormat:@"_%@._tcp", application];
        *out_domain = @"local.";
        return YES;
    }
    if (!browser->_descriptor->_bonjourType.length || !browser->_descriptor->_bonjourDomain.length)
        return NO;
    *out_type = browser->_descriptor->_bonjourType;
    *out_domain = browser->_descriptor->_bonjourDomain;
    return YES;
}

static void charon_browser_begin(nw_browser_t browser)
{
    CharonNWBrowser *self = (CharonNWBrowser *)browser;
    dispatch_async(self->_queue, ^{
        if (self->_cancelled)
            return;
        charon_browser_report(self, nw_browser_state_waiting, nil);
        NSString *type = nil, *domain = nil;
        if (!charon_browser_target(self, &type, &domain)) {
            charon_browser_report(self, nw_browser_state_failed,
                                  charon_browser_error(nw_error_domain_dns, kDNSServiceErr_BadParam));
            return;
        }
        self->_type = type;
        self->_domain = domain;
        if (!DNSServiceQueryRecord || !DNSServiceResolve || !DNSServiceProcessResult || !DNSServiceRefSockFD ||
            !DNSServiceRefDeallocate) {
            charon_browser_report(self, nw_browser_state_failed,
                                  charon_browser_error(nw_error_domain_dns, kDNSServiceErr_Unknown));
            return;
        }
        DNSServiceRef browse = NULL;
        DNSServiceErrorType failure = DNSServiceQueryRecord(&browse, 0, kDNSServiceInterfaceIndexAny,
                                                           charon_browser_query(type, domain).UTF8String,
                                                           kDNSServiceClass_IN, kDNSServiceType_PTR,
                                                           charon_browser_answer, (__bridge void *)self);
        int descriptor = browse ? DNSServiceRefSockFD(browse) : -1;
        if (failure != kDNSServiceErr_NoError || !browse || descriptor < 0) {
            if (browse)
                DNSServiceRefDeallocate(browse);
            charon_browser_report(self, nw_browser_state_failed,
                                  charon_browser_error(nw_error_domain_dns,
                                                       (int)(failure != kDNSServiceErr_NoError ? failure
                                                                                          : kDNSServiceErr_Unknown)));
            return;
        }
        self->_browse = browse;
        self->_source = charon_browser_source(descriptor, self->_queue);
        if (!self->_source) {
            charon_browser_report(self, nw_browser_state_failed,
                                  charon_browser_error(nw_error_domain_dns, kDNSServiceErr_Unknown));
            return;
        }
        __weak CharonNWBrowser *weak = self;
        dispatch_source_set_event_handler(self->_source, ^{
            CharonNWBrowser *strong = weak;
            if (strong && !strong->_cancelled)
                charon_browser_pump(strong->_browse, strong);
        });
        /* The interfaces a browse answer names are handed out as objects of the library's own path
           monitor, which is where `nw_interface_t` comes from on a release with no Network.framework. */
        self->_monitor = nw_path_monitor_create();
        nw_path_monitor_set_queue(self->_monitor, self->_queue);
        nw_path_monitor_set_update_handler(self->_monitor, ^(nw_path_t path) {
            CharonNWBrowser *strong = weak;
            if (strong && !strong->_cancelled)
                charon_browser_interfaces(strong, path);
        });
        nw_path_monitor_start(self->_monitor);
        charon_browser_report(self, nw_browser_state_ready, nil);
    });
}

static void charon_browser_stop(nw_browser_t browser)
{
    CharonNWBrowser *self = (CharonNWBrowser *)browser;
    dispatch_block_t stop = ^{
        @synchronized(self) {
            if (self->_cancelled)
                return;
            self->_cancelled = YES;
        }
        if (self->_source) {
            dispatch_source_cancel(self->_source);
            self->_source = nil;
        }
        if (self->_browse) {
            DNSServiceRefDeallocate(self->_browse);
            self->_browse = NULL;
        }
        for (CharonNWBrowserLookup *lookup in [self->_lookups allValues]) {
            [lookup close];
        }
        [self->_lookups removeAllObjects];
        [self->_reported removeAllObjects];
        [self->_batch removeAllObjects];
        if (self->_monitor) {
            nw_path_monitor_cancel(self->_monitor);
            self->_monitor = NULL;
        }
        self->_state = nil;
        self->_results = nil;
        charon_browser_report(self, nw_browser_state_cancelled, nil);
    };
    if (self->_queue)
        dispatch_async(self->_queue, stop);
    else
        stop();
}

/* What nw16-browser.m needs from the object, as C functions, for the reason the listener's are: with
   the fragile ABI a class's ivar offsets are emitted by every file that sees its @interface, so the
   class lives in this one file and its neighbour asks for what it needs. */
void CharonNWBrowserSetQueue(nw_browser_t browser, dispatch_queue_t queue)
{
    if (browser)
        ((CharonNWBrowser *)browser)->_queue = queue;
}

void CharonNWBrowserSetStateHandler(nw_browser_t browser, nw_browser_state_changed_handler_t handler)
{
    if (browser)
        ((CharonNWBrowser *)browser)->_state = [handler copy];
}

void CharonNWBrowserSetResultsHandler(nw_browser_t browser, nw_browser_browse_results_changed_handler_t handler)
{
    if (browser)
        ((CharonNWBrowser *)browser)->_results = [handler copy];
}

nw_browse_descriptor_t CharonNWBrowserCopyBrowseDescriptor(nw_browser_t browser)
{
    return browser ? (nw_browse_descriptor_t)((CharonNWBrowser *)browser)->_descriptor : NULL;
}

nw_parameters_t CharonNWBrowserCopyParameters(nw_browser_t browser)
{
    return browser ? (nw_parameters_t)((CharonNWBrowser *)browser)->_parameters : NULL;
}

void CharonNWBrowserStart(nw_browser_t browser)
{
    if (!browser)
        return;
    CharonNWBrowser *self = (CharonNWBrowser *)browser;
    @synchronized(self) {
        /* The header says the queue must be set before the browser is started, and a browser started
           twice is the same browse: the second start says nothing and calls nobody. */
        if (self->_started || self->_cancelled || !self->_queue)
            return;
        self->_started = YES;
    }
    charon_browser_begin(browser);
}

nw_browser_t nw_browser_create(nw_browse_descriptor_t descriptor, nw_parameters_t parameters)
{
    if (!descriptor)
        return NULL;
    CharonNWBrowser *browser = [[CharonNWBrowser alloc] init];
    browser->_descriptor = (CharonNWBrowseDescriptor *)descriptor;
    /* The header says an empty parameters object is created internally when the caller has none, and
       `nw_browser_copy_parameters` hands back what the browse runs with either way. */
    browser->_parameters = parameters ? (CharonNWParameters *)parameters : (CharonNWParameters *)nw_parameters_create();
    browser->_reported = [NSMutableDictionary dictionary];
    browser->_lookups = [NSMutableDictionary dictionary];
    browser->_batch = [NSMutableArray array];
    browser->_interfaces = [NSMutableDictionary dictionary];
    browser->_value = nw_browser_state_invalid;
    return browser;
}

void nw_browser_cancel(nw_browser_t browser)
{
    if (!browser)
        return;
    charon_browser_stop(browser);
}