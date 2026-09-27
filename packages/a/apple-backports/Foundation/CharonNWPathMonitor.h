/*
 * The path monitor of the Foundation library, declared for the files that reach into it.
 *
 * The monitor itself is in NWPathMonitor.m with the calls that arrived in iOS 12; a call of a later
 * release is in a file of its own - modules/apple/backports.lua splits an object that exports the
 * symbols of two introductions - and needs the monitor's own state to answer, which is what this
 * header is for. The interface is declared here, the implementation is there.
 */

#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <SystemConfiguration/SystemConfiguration.h>

@interface CharonNWPath : NSObject <OS_nw_path>
@end

@interface CharonNWPathMonitor : NSObject <OS_nw_path_monitor> {
@public
    nw_interface_type_t _required;
    NSMutableArray *_prohibitedTypes;
    dispatch_queue_t _queue;
    nw_path_monitor_update_handler_t _update;
    nw_path_monitor_cancel_handler_t _cancel;
    SCNetworkReachabilityRef _reachability;
    CharonNWPath *_last;
    BOOL _started, _cancelled;
    int _generation;
}
@end
