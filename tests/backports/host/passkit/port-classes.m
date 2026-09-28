// The classes the port's categories hang on, under the names the probe build gives them.
//
// The run compiles the port with -DPKPassLibrary=charonHost_PKPassLibrary and the rest, so the port's
// categories attach to THESE classes and never to the host framework's own -- a category on the
// host's class would be a second implementation of a class the host already has, and the runner
// would be measuring Apple rather than the port.
//
// Three of the four are the release's own classes (PKPass, PKPassLibrary, PKAddPassesViewController
// are in 6.1.3, measured), so here they are the host's, subclassed, which is what lets a category add
// to them without re-implementing what the host has. PKPaymentAuthorizationController and
// PKPaymentAuthorizationViewController are absent from 6.1.3 entirely, so they are the port's own and
// get their own classes here; the probe's cases are about the fifteen members the port adds, and
// none of the runner's cases sends a message to a host method of either class.
#import <Foundation/Foundation.h>
#import <PassKit/PassKit.h>

@interface charonHost_PKPassLibrary : PKPassLibrary
@end
@implementation charonHost_PKPassLibrary
@end

@interface charonHost_PKAddPassesViewController : PKAddPassesViewController
@end
@implementation charonHost_PKAddPassesViewController
@end

@interface charonHost_PKPaymentAuthorizationController : NSObject
@end
@implementation charonHost_PKPaymentAuthorizationController
@end

@interface charonHost_PKPaymentAuthorizationViewController : UIViewController
@end
@implementation charonHost_PKPaymentAuthorizationViewController
@end
