#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

// How AVCapturePhotoOutput.m makes the resolved settings of a request (AVCaptureResolvedPhotoSettings.m).
@interface AVCaptureResolvedPhotoSettings ()
- (instancetype)initCharonWithUniqueID:(int64_t)uniqueID photoDimensions:(CMVideoDimensions)photoDimensions
                     previewDimensions:(CMVideoDimensions)previewDimensions
           embeddedThumbnailDimensions:(CMVideoDimensions)embeddedThumbnailDimensions flashEnabled:(BOOL)flashEnabled
        stillImageStabilizationEnabled:(BOOL)stillImageStabilizationEnabled;
@end

// The RAW pixel formats, Bayer and Apple ProRAW (AVCapturePhotoSettings.m), for the settings and the output alike.
BOOL CharonIsBayerRAWPixelFormat(OSType format);
BOOL CharonIsAppleProRAWPixelFormat(OSType format);

// The wait of a capture for the camera's flash (AVCapturePhotoOutput.m): `then` runs once, at the first change of the
// camera's flashActive or after `bound` seconds. Hidden, for the host test of the photo output.
__attribute__((visibility("hidden"))) void CharonAfterFlashActiveChanges(id camera, NSTimeInterval bound, void (^then)(void));
