#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

// AVFoundation's 10.0 surface, the five rows DEMAND-AVFoundation-10.tsv measured CRASH-ON-USE
// against 6.1.3. ONE OBJECT for 10.0 only.

#pragma mark - AVPlayer.automaticallyWaitsToMinimizeStalling

// 6.1.3's -[AVPlayer setRate:] already plays immediately at the given rate - there is no
// stall-avoidance wait to turn on or off, so the flag has one real consumer in this port:
// -playImmediatelyAtRate: below, which the header says must not be called while this is YES.

static const char charon_waitsToMinimizeStallingKey;

@implementation AVPlayer (CharonAutomaticWaiting10)

- (BOOL)automaticallyWaitsToMinimizeStalling
{
    NSNumber *stored = objc_getAssociatedObject(self, &charon_waitsToMinimizeStallingKey);
    return stored ? stored.boolValue : YES;
}

- (void)setAutomaticallyWaitsToMinimizeStalling:(BOOL)automaticallyWaitsToMinimizeStalling
{
    objc_setAssociatedObject(self, &charon_waitsToMinimizeStallingKey, @(automaticallyWaitsToMinimizeStalling), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

#pragma mark - AVPlayer.playImmediatelyAtRate:

@implementation AVPlayer (CharonPlayImmediately10)

- (void)playImmediatelyAtRate:(float)rate
{
    if (self.automaticallyWaitsToMinimizeStalling)
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"playImmediatelyAtRate: should not be used when automaticallyWaitsToMinimizeStalling is YES"
                                     userInfo:nil];
    // 6.1.3 has no stall-avoidance wait of its own, so setting the rate already is "immediately".
    self.rate = rate;
}

@end

#pragma mark - AVPlayerItemVideoOutput.initWithOutputSettings:

// 6.1.3's AVPlayerItemVideoOutput already has -initWithPixelBufferAttributes:
// (objc.inventory over ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7); outputSettings is the later
// name for the same pixel-buffer-attributes dictionary, so this forwards to it unchanged.

@implementation AVPlayerItemVideoOutput (CharonOutputSettings10)

- (instancetype)initWithOutputSettings:(NSDictionary<NSString *, id> *)outputSettings
{
    return [self initWithPixelBufferAttributes:outputSettings];
}

@end

#pragma mark - AVCaptureDeviceFormat.supportedColorSpaces

// 6.1.3's capture stack has no color space selection of any kind - every format it reports captures
// in sRGB, which is what the release's own AVCaptureColorSpace enumeration calls
// AVCaptureColorSpaceSRGB (0). There being exactly one, and no way for a format to answer otherwise,
// is the real state of 6.1.3's camera stack, not a placeholder.

@implementation AVCaptureDeviceFormat (CharonSupportedColorSpaces10)

- (NSArray<NSNumber *> *)supportedColorSpaces
{
    return @[@(AVCaptureColorSpaceSRGB)];
}

@end

#pragma mark - AVCaptureSession.automaticallyConfiguresCaptureDeviceForWideColor

// Stored and real as a flag; it has nothing to act on. Wide color capture needs a format whose
// supportedColorSpaces carries more than sRGB, which -[AVCaptureDeviceFormat supportedColorSpaces]
// above never answers on this hardware (no iPad 2 or iPhone 4S camera ever reports a wide-color
// format), so there is never a format for this flag to switch the session to.

static const char charon_wideColorKey;

@implementation AVCaptureSession (CharonWideColor10)

- (BOOL)automaticallyConfiguresCaptureDeviceForWideColor
{
    NSNumber *stored = objc_getAssociatedObject(self, &charon_wideColorKey);
    return stored ? stored.boolValue : YES;
}

- (void)setAutomaticallyConfiguresCaptureDeviceForWideColor:(BOOL)automaticallyConfiguresCaptureDeviceForWideColor
{
    objc_setAssociatedObject(self, &charon_wideColorKey, @(automaticallyConfiguresCaptureDeviceForWideColor), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
