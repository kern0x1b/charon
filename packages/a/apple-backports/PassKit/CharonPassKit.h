// The shared piece of the PassKit objects: what a device with no wallet hardware says when one of
// these members is reached for, and the reason, in one place so the eleven objects of the releases
// below do not each carry a second copy of the same sentence.
#import <PassKit/PassKit.h>

// PKPassKitErrorDomain is LINKED, never defined: -PKPassKitErrorDomain is first exported at 6.0
// (measured through the gate's own first_releases over the armv7 cache of 6.1.3), so the release
// owns the string and this package names it. The code is the header's own PKUnsupportedVersionError
// (2), the nearest the enumeration comes to "this device cannot do that".
extern NSError *CharonPassKitNoHardwareError(void);

