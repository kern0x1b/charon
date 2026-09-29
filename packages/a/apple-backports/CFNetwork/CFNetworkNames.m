#import <CoreFoundation/CoreFoundation.h>
#import <CFNetwork/CFNetwork.h>
#import <CFNetwork/CFHTTPMessage.h>
#import <CFNetwork/CFSocketStream.h>

// The names CFNetwork of iOS 13 and 10 added, carried with the text CFNetwork itself gives them,
// read from the arm64e shared cache of iOS 18.0 (facts/CFNetwork/Names.md). iOS 6.1.3 exports
// kCFHTTPVersion1_1 and none of these, so an application that names one of them loads where it
// would otherwise die in dyld. The release's own streams know none of the five keys, which is what
// the properties say of a system with no low data mode and no per-app traffic limit to read.

const CFStringRef kCFHTTPVersion2_0 = CFSTR("HTTP/2.0");
const CFStringRef kCFHTTPVersion3_0 = CFSTR("HTTP/3.0");

const CFStringRef kCFStreamNetworkServiceTypeCallSignaling = CFSTR("kCFStreamNetworkServiceTypeCallSignaling");

const CFStringRef kCFStreamPropertyAllowConstrainedNetworkAccess = CFSTR("kCFStreamPropertyAllowConstrainedNetworkAccess");
const CFStringRef kCFStreamPropertyAllowExpensiveNetworkAccess = CFSTR("kCFStreamPropertyAllowExpensiveNetworkAccess");
const CFStringRef kCFStreamPropertyConnectionIsExpensive = CFSTR("kCFStreamPropertyConnectionIsExpensive");
const CFStringRef kCFStreamPropertySocketExtendedBackgroundIdleMode = CFSTR("kCFStreamPropertySocketExtendedBackgroundIdleMode");
