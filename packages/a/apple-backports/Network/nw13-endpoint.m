/*
 * The URL endpoint of iOS 13, and the one call of iOS 12 that answers for it.
 *
 * A URL endpoint keeps the URL as it was given, and answers its host and its port from it: the host
 * is what the URL names without its port, and the port is the URL's own when it has one. A URL the
 * port cannot make an endpoint of is refused, as a host that is not a host is.
 */

#import "CharonNW.h"
#import "CharonNWSupport.h"

#include <string.h>

nw_endpoint_t nw_endpoint_create_url(const char *url)
{
    if (!url || !*url)
        return NULL;
    CFStringRef host = charon_nw_url_host(url);
    if (!host)
        return NULL;
    CharonNWEndpoint *endpoint = [[CharonNWEndpoint alloc] init];
    endpoint->_type = nw_endpoint_type_url;
    endpoint->_url = @(url);
    endpoint->_hostname = (__bridge_transfer NSString *)host;
    uint16_t port = charon_nw_url_port(url);
    if (port)
        endpoint->_port = [NSString stringWithFormat:@"%u", port];
    return endpoint;
}

const char *nw_endpoint_get_url(nw_endpoint_t endpoint)
{
    CharonNWEndpoint *value = (CharonNWEndpoint *)endpoint;
    if (!value || value->_type != nw_endpoint_type_url)
        return NULL;
    return value->_url.UTF8String;
}
