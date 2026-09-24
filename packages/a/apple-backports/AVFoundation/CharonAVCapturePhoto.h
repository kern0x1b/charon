#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

// How AVCapturePhotoOutput.m makes the resolved settings of a request (AVCaptureResolvedPhotoSettings.m).
@interface AVCaptureResolvedPhotoSettings ()
- (instancetype)initCharonWithUniqueID:(int64_t)uniqueID photoDimensions:(CMVideoDimensions)photoDimensions
                     previewDimensions:(CMVideoDimensions)previewDimensions flashEnabled:(BOOL)flashEnabled
        stillImageStabilizationEnabled:(BOOL)stillImageStabilizationEnabled;
@end
