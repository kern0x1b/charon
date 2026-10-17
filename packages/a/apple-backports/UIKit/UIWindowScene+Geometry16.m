#import <UIKit/UIKit.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// -[UIWindowScene requestGeometryUpdateWithPreferences:errorHandler:], iOS 16. The port's scene is one fixed window: its windowing mode does not
// allow a programmatic change to the interface orientation, so the request is refused, as the host's own scene refuses it under Mac Catalyst
// (UISceneErrorDomain code 101, measured by tests/backports/host/window-scene-geometry). The refusal is delivered to the handler before the
// request returns, on the calling thread, and a nil handler is allowed and gets nothing.
@implementation UIWindowScene (CharonGeometry16)

- (void)requestGeometryUpdateWithPreferences:(UIWindowSceneGeometryPreferences *)geometryPreferences errorHandler:(void (^)(NSError *error))errorHandler
{
    if (!errorHandler)
        return;
    errorHandler([NSError errorWithDomain:UISceneErrorDomain code:101 userInfo:@{NSLocalizedDescriptionKey: @"The current windowing mode does not allow for programmatic changes to interface orientation."}]);
}

@end
