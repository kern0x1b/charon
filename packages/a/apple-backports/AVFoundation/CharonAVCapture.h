#import <AVFoundation/AVFoundation.h>

#define CHARON_DUAL_CAMERA_TYPE @"AVCaptureDeviceTypeBuiltInDualCamera"

NSArray *charon_capture_devices(NSArray *deviceTypes, NSString *mediaType, AVCaptureDevicePosition position);
