#import <UIKit/UIKit.h>

#import "CharonDragDrop.h"
#import "CharonDragSession.h"
#import "UIDropCoordinators.h"

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// The table view's half of a drag and drop, in its own object from the collection view's: an object
// carries the API of one release, and the two views reach different things.
