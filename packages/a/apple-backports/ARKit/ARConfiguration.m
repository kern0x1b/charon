// ARConfiguration.m - the description of what a session is asked to do, and the four configurations
// that carry it.
//
// `+[ARConfiguration isSupported]` and the three subclasses' own are the whole question an
// application asks before it does anything, and here the answer is the hardware's: a configuration
// that needs the camera and the gyroscope is supported on a device that has both, and one that
// needs a LiDAR's depth or a TrueDepth's face is not, which is what Apple answers for a device
// without those sensors.
//
// Source: ARKit of the arm64 shared cache of iOS 12.0, read with the image's symbols -
// `+[ARConfiguration isSupported]` at 0x19d3b54a0 and `+[ARWorldTrackingConfiguration isSupported]`
// at 0x19d3cfaf4, both of which reach `ARDeviceSupported`, a value computed once from the hardware.

#import <ARKit/ARKit.h>
#import <CoreLocation/CoreLocation.h>

#import "CharonARTracker.h"

@implementation ARConfiguration

+ (BOOL)isSupported
{
    // The device, asked the question its own sensors can answer.
    return [CharonARTracker isSupported];
}

- (BOOL)isSupported
{
    return [[self class] isSupported];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p>", NSStringFromClass([self class]), self];
}

@end

@implementation ARWorldTrackingConfiguration

+ (BOOL)isSupported
{
    // A world-tracking session is a camera and a gyroscope, which is what this device has.
    return [CharonARTracker isSupported];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; planeDetection = %lu>",
            NSStringFromClass([self class]), self, (unsigned long)_planeDetection];
}

@end

@implementation AROrientationTrackingConfiguration

+ (BOOL)isSupported
{
    // The gyroscope alone, which is the one sensor this class needs and the one it was named for.
    Class manager = NSClassFromString(@"CMMotionManager");
    return [manager isAvailable];
}

@end

@implementation ARPositionalTrackingConfiguration

+ (BOOL)isSupported
{
    // A tracked image and a place to put it: the camera, and a location service.
    if (![CharonARTracker isSupported])
        return NO;
    return [CLLocationManager class] != nil;
}

@end

@implementation ARFaceTrackingConfiguration

+ (BOOL)isSupported
{
    // A face is measured by a depth sensor across the face, and this device has none: no TrueDepth, and
    // no LiDAR either. Apple answers NO for a device without the sensor, and so does this.
    return NO;
}

@end

@implementation ARBodyTrackingConfiguration

+ (BOOL)isSupported
{
    // A body is a pose estimated from the camera's own frames, which needs no sensor of its own, and
    // the front camera. This device has a front camera, so the answer is what the hardware gives.
    return [CharonARTracker hasFrontCamera];
}

@end

@implementation ARImageTrackingConfiguration

+ (BOOL)isSupported
{
    // A tracked image is found in the camera's frames and needs no depth sensor.
    return [CharonARTracker isSupported];
}

@end

@implementation ARObjectScanningConfiguration

+ (BOOL)isSupported
{
    // Object scanning reads a mesh out of the depth the camera sees; without a depth sensor there is
    // no mesh to read, and the framework is right to say so.
    return NO;
}

@end
