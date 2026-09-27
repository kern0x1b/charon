/*
 * The QUIC calls of iOS 16: how large a datagram frame may be, whether a stream is a datagram, and
 * how much of such a frame is left to send on a connection.
 *
 * The port has no QUIC transport (facts/Network/NWQUIC.md), so these answer from the options and
 * the metadata a program configured: a datagram frame size of 0 and a stream that is not a datagram
 * until a program says otherwise, and a usable size that is what the program set.
 */

#import "CharonNW.h"
#import "CharonNWSupport.h"

void nw_quic_set_max_datagram_frame_size(nw_protocol_options_t options, uint16_t max_datagram_frame_size)
{
    charon_nw_set_integer((__bridge CFMutableDictionaryRef)((CharonNWProtocolOptions *)options)->_values, "max_datagram_frame_size", max_datagram_frame_size);
}

uint16_t nw_quic_get_max_datagram_frame_size(nw_protocol_options_t options)
{
    return (uint16_t)charon_nw_integer((__bridge CFDictionaryRef)((CharonNWProtocolOptions *)options)->_values, "max_datagram_frame_size", 0);
}

void nw_quic_set_stream_is_datagram(nw_protocol_options_t options, bool is_datagram)
{
    charon_nw_set_flag((__bridge CFMutableDictionaryRef)((CharonNWProtocolOptions *)options)->_values, "stream_is_datagram", is_datagram);
}

bool nw_quic_get_stream_is_datagram(nw_protocol_options_t options)
{
    return charon_nw_flag((__bridge CFDictionaryRef)((CharonNWProtocolOptions *)options)->_values, "stream_is_datagram", false);
}

uint16_t nw_quic_get_stream_usable_datagram_frame_size(nw_protocol_metadata_t metadata)
{
    CharonNWProtocolMetadata *value = (CharonNWProtocolMetadata *)metadata;
    if (![value isKindOfClass:[CharonNWProtocolMetadata class]] ||
        ![value->_definition->_family isEqualToString:@"nw_quic"])
        return 0;
    return (uint16_t)charon_nw_integer((__bridge CFDictionaryRef)value->_values, "usable_datagram_frame_size", 0);
}
