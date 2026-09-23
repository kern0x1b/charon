#import <AVFoundation/AVFoundation.h>

#define CHARON_DUAL_CAMERA_TYPE @"AVCaptureDeviceTypeBuiltInDualCamera"

NSArray *charon_capture_devices(NSArray *deviceTypes, NSString *mediaType, AVCaptureDevicePosition position);

// Posted, with the session as its object, after a capture session gains an input or an output, starts
// running or commits a configuration, and after a preview layer is given the session.
#define CHARON_CAPTURE_SESSION_CHANGED @"CharonCaptureSessionChanged"

@interface AVCaptureDevice (CharonCaptureSessions)
// The sessions an input of this device was added to, held weakly.
- (NSArray<AVCaptureSession *> *)charon_captureSessions;
@end

@interface AVCaptureSession (CharonCaptureSessions)
// The preview layers given this session, held weakly.
- (NSArray<AVCaptureVideoPreviewLayer *> *)charon_previewLayers;
@end
