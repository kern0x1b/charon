// The one constant iOS 8.2 added, with the value HealthKit gave it.
//
// Every value below was read out of the armv7 shared cache of iOS 9.0, the first release that exports it, not assumed: the image was extracted with
// modules/apple/dyld.lua's extract() and each constant followed through its entry in the image's own
// symbol table to the __cfstring it points at, so what is written here is the string that release
// held. The reader is .agent-work/runs/api-kits/cfconst32.py and its output hk9.0.constvalues.
//
// The declaration of each is the SDK's own.

#import <HealthKit/HealthKit.h>


NSString *const HKUserPreferencesDidChangeNotification = @"HKUserPreferencesDidChangeNotification";
