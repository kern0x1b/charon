/*
 * The listener calls that arrived after iOS 12 and before nothing else, and which the 16.0 cache is
 * the first to export, so an object of their own: the rest of the listener is iOS 12, and
 * tools/release-split.lua is what says so. The SDK's header gives them iOS 13 and iOS 15.
 */

#import "CharonNW.h"

void nw_listener_set_new_connection_group_handler(nw_listener_t listener, nw_listener_new_connection_group_handler_t handler)
{
    CharonNWListenerSetNewConnectionGroup(listener, handler);
}

void nw_listener_set_new_connection_limit(nw_listener_t listener, uint32_t new_connection_limit)
{
    CharonNWListenerSetNewConnectionLimit(listener, new_connection_limit);
}

uint32_t nw_listener_get_new_connection_limit(nw_listener_t listener)
{
    return CharonNWListenerGetNewConnectionLimit(listener);
}
