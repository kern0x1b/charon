// ARConfiguration.m - the description of what a session is asked to do, and the questions the
// hardware answers about it.
//
// The base class and the video formats live here because they are questions about the camera: which
// device would be captured from, which formats it really has, and the two recommendations chosen
// from those. ARConfiguration2.m holds the subclasses' own settings, because those are the settings
// each one carries, and each class has exactly one implementation across the two files.
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

#import "CharonARKitPrivate.h"
#import "CharonARKitPrivate.h"
#import "CharonARTracker.h"

// `+supportedVideoFormats`, `+configurableCaptureDeviceForPrimaryCamera` and the two recommendations
// are declared by the 16.0 headers and are implemented here for a runtime that predates them; the
// class itself only exists from 11.3. A caller reaching one of these is by definition on a release
// new enough for the answer, which is the same reasoning every other backport in this package uses.
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

@implementation ARConfiguration

    
    
    
    @dynamic isSupported;
@synthesize worldAlignment = _worldAlignment;
    @synthesize lightEstimationEnabled = _lightEstimationEnabled;
    @synthesize providesAudioData = _providesAudioData;
- (instancetype)initCharonCommon
{
    return [super init];
}

+ (BOOL)supportsFrameSemantics:(ARFrameSemantics)frameSemantics
{
    // Scene semantics are read out of a depth sensor's classification of what the camera sees, and
    // this device has none, so there is no semantics to enable.
    return NO;
}

- (id)copyWithZone:(NSZone *)zone
{
    // A configuration describes what a session is asked to do; copying one and changing the copy
    // must not change the original, so every value the base class stores is carried over.
    ARConfiguration *copy = [[self class] allocWithZone:zone];
    copy.worldAlignment = self.worldAlignment;
    copy.lightEstimationEnabled = self.isLightEstimationEnabled;
    copy.providesAudioData = self.providesAudioData;
    copy.frameSemantics = self.frameSemantics;
    return copy;
}

+ (NSArray<ARVideoFormat *> *)supportedVideoFormats
{
    // The formats the back camera really has, in the order the camera reports them, so that a format
    // offered here is one the session can be configured with.
    NSArray<AVCaptureDeviceFormat *> *formats =
            [CharonARTracker supportedCaptureFormatsForPosition:AVCaptureDevicePositionBack];
    NSMutableArray<ARVideoFormat *> *result = [NSMutableArray arrayWithCapacity:formats.count];
    for (AVCaptureDeviceFormat *format in formats)
        [result addObject:[[ARVideoFormat alloc] initWithCaptureFormat:format]];
    return result;
}

+ (AVCaptureDevice *)configurableCaptureDeviceForPrimaryCamera
{
    return [CharonARTracker captureDeviceForPosition:AVCaptureDevicePositionBack];
}

+ (ARVideoFormat *)recommendedVideoFormatFor4KResolution
{
    return [self videoFormatNearestTo:CGSizeMake(3840, 2160)];
}

+ (ARVideoFormat *)recommendedVideoFormatForHighResolutionFrameCapturing
{
    // The largest frame the primary camera can deliver, and the first one at that size.
    ARVideoFormat *best = nil;
    CGFloat bestArea = 0;
    for (ARVideoFormat *format in self.supportedVideoFormats) {
        CGFloat area = format.imageResolution.width * format.imageResolution.height;
        if (area > bestArea) {
            bestArea = area;
            best = format;
        }
    }
    return best;
}

/// The offered format whose frame is closest to the one asked for, measured on the log of each
/// dimension so that a factor of two in either direction costs the same.
+ (ARVideoFormat *)videoFormatNearestTo:(CGSize)size
{
    ARVideoFormat *best = nil;
    CGFloat bestDistance = INFINITY;
    for (ARVideoFormat *format in self.supportedVideoFormats) {
        CGFloat width = format.imageResolution.width;
        CGFloat height = format.imageResolution.height;
        if (width <= 0 || height <= 0)
            continue;
        CGFloat distance = hypot(log(width / size.width), log(height / size.height));
        if (distance < bestDistance) {
            bestDistance = distance;
            best = format;
        }
    }
    return best;
}

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

