#import "CharonAVCapture.h"

NSArray *charon_capture_devices(NSArray *deviceTypes, NSString *mediaType, AVCaptureDevicePosition position)
{
    NSMutableArray *found = [NSMutableArray array];
    if ([deviceTypes containsObject:AVCaptureDeviceTypeBuiltInWideAngleCamera] || [deviceTypes containsObject:AVCaptureDeviceTypeBuiltInTelephotoCamera]
        || [deviceTypes containsObject:CHARON_DUAL_CAMERA_TYPE])
        [found addObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]];
    if ([deviceTypes containsObject:AVCaptureDeviceTypeBuiltInMicrophone])
        [found addObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio]];
    NSMutableArray *matching = [NSMutableArray array];
    for (AVCaptureDevice *device in found) {
        if (device.connected && (position == AVCaptureDevicePositionUnspecified || device.position == position)
            && (!mediaType || [device hasMediaType:mediaType]) && [deviceTypes containsObject:[device deviceType]])
            [matching addObject:device];
    }
    return [matching sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(AVCaptureDevice *first, AVCaptureDevice *second) {
        NSUInteger firstType = [deviceTypes indexOfObject:[first deviceType]], secondType = [deviceTypes indexOfObject:[second deviceType]];
        if (firstType != secondType)
            return firstType < secondType ? NSOrderedAscending : NSOrderedDescending;
        if (first.position == second.position)
            return NSOrderedSame;
        return first.position < second.position ? NSOrderedAscending : NSOrderedDescending;
    }];
}
