// The stand-in for UIKit, for a host check. UIKit does not exist on macOS, so the port's source cannot be
// compiled against the real framework here; this declares the one class the 7.0 property's type names, so
// the port's own code - and not a substitute for it - is what the check measures.
#import <Foundation/Foundation.h>

@interface UIImage : NSObject
@end

// The body as well as the declaration: the port's property is typed UIImage *, so _OBJC_CLASS_$_UIImage is
// referenced and an interface alone leaves it undefined at link time - measured, the same class of defect
// as MPSystemMusicPlayerController in QueueDescriptors.md.
@implementation UIImage
@end
