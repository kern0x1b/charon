/*
 * What a browser looks for: the calls of browse_descriptor.h that arrived in iOS 13.
 *
 * A descriptor is the service type and domain a browser is asked to browse, and whether the records
 * of what it finds carry their TXT record with them. Nothing here reaches the network: a browser
 * takes the descriptor and starts looking, which is nw13-browser.m's business.
 */

#import "CharonNW.h"

nw_browse_descriptor_t nw_browse_descriptor_create_bonjour_service(const char *type, const char *domain)
{
    /* A type and a domain are what a browse is: without either there is nothing to look for and
       nowhere to look, and the host's own Network refuses it (tests/backports/host/network-objects). */
    if (!type || !*type || !domain || !*domain)
        return NULL;
    CharonNWBrowseDescriptor *descriptor = [[CharonNWBrowseDescriptor alloc] init];
    descriptor->_bonjourType = @(type);
    descriptor->_bonjourDomain = @(domain);
    return descriptor;
}

const char *nw_browse_descriptor_get_bonjour_service_type(nw_browse_descriptor_t descriptor)
{
    CharonNWBrowseDescriptor *value = (CharonNWBrowseDescriptor *)descriptor;
    return value ? value->_bonjourType.UTF8String : NULL;
}

const char *nw_browse_descriptor_get_bonjour_service_domain(nw_browse_descriptor_t descriptor)
{
    CharonNWBrowseDescriptor *value = (CharonNWBrowseDescriptor *)descriptor;
    return value ? value->_bonjourDomain.UTF8String : NULL;
}

bool nw_browse_descriptor_get_include_txt_record(nw_browse_descriptor_t descriptor)
{
    CharonNWBrowseDescriptor *value = (CharonNWBrowseDescriptor *)descriptor;
    return value ? value->_includeTxtRecord : false;
}

void nw_browse_descriptor_set_include_txt_record(nw_browse_descriptor_t descriptor, bool include_txt_record)
{
    CharonNWBrowseDescriptor *value = (CharonNWBrowseDescriptor *)descriptor;
    if (value)
        value->_includeTxtRecord = include_txt_record;
}
