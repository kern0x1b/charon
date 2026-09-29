#import <CoreFoundation/CoreFoundation.h>
#import <CFNetwork/CFNetwork.h>
#import <CFNetwork/CFHTTPMessage.h>
#import <CFNetwork/CFSocketStream.h>

// The names CFNetwork of iOS 13.0 added, with the texts CFNetwork itself gives them
// (facts/CFNetwork/Names.md). Nothing between 12.0 and 16.0 is held on the ladder, so all four are
// measured first appearing in the cache of iOS 16.0, an upper bound for the 13.0 their headers
// annotate; they are carried in one object for that reason, and the release they are carried from is
// 16.0.

const CFStringRef kCFHTTPVersion3_0 = CFSTR("HTTP/3.0");

const CFStringRef kCFStreamPropertyAllowConstrainedNetworkAccess = CFSTR("kCFStreamPropertyAllowConstrainedNetworkAccess");
const CFStringRef kCFStreamPropertyAllowExpensiveNetworkAccess = CFSTR("kCFStreamPropertyAllowExpensiveNetworkAccess");
const CFStringRef kCFStreamPropertyConnectionIsExpensive = CFSTR("kCFStreamPropertyConnectionIsExpensive");
