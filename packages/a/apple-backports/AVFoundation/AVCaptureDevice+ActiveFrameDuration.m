#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static const char CharonActiveMinFrameDurationKey;
static const char CharonActiveMaxFrameDurationKey;

@interface AVCaptureDevice (CharonActiveFrameDurationSessions)
- (NSHashTable<AVCaptureSession *> *)charon_activeFrameDurationSessions;
@end

static CMTime charon_default_min_frame_duration(AVCaptureDevice *device)
{
    CMTime shortest = kCMTimeInvalid;
    for (AVFrameRateRange *range in device.activeFormat.videoSupportedFrameRateRanges) {
        if (CMTIME_IS_INVALID(shortest) || CMTimeCompare(range.minFrameDuration, shortest) < 0)
            shortest = range.minFrameDuration;
    }
    return shortest;
}

static CMTime charon_default_max_frame_duration(AVCaptureDevice *device)
{
    CMTime longest = kCMTimeInvalid;
    for (AVFrameRateRange *range in device.activeFormat.videoSupportedFrameRateRanges) {
        if (CMTIME_IS_INVALID(longest) || CMTimeCompare(range.maxFrameDuration, longest) > 0)
            longest = range.maxFrameDuration;
    }
    return longest;
}

static void charon_apply_frame_durations(AVCaptureSession *session)
{
    for (AVCaptureOutput *output in session.outputs) {
        for (AVCaptureConnection *connection in output.connections) {
            AVCaptureInputPort *port = connection.inputPorts.firstObject;
            if (![port.mediaType isEqualToString:AVMediaTypeVideo] || ![port.input isKindOfClass:[AVCaptureDeviceInput class]])
                continue;
            AVCaptureDevice *device = ((AVCaptureDeviceInput *)port.input).device;
            NSValue *min = objc_getAssociatedObject(device, &CharonActiveMinFrameDurationKey);
            NSValue *max = objc_getAssociatedObject(device, &CharonActiveMaxFrameDurationKey);
            if (min && connection.isVideoMinFrameDurationSupported)
                connection.videoMinFrameDuration = min.CMTimeValue;
            if (max && connection.isVideoMaxFrameDurationSupported)
                connection.videoMaxFrameDuration = max.CMTimeValue;
        }
    }
}

static void charon_swap_session(SEL selector)
{
    Method method = class_getInstanceMethod([AVCaptureSession class], selector);
    if (!method)
        return;
    IMP original = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^(AVCaptureSession *self) {
        ((void (*)(AVCaptureSession *, SEL))original)(self, selector);
        charon_apply_frame_durations(self);
    }));
}

@interface CharonActiveFrameDurationInstaller : NSObject
@end

@implementation CharonActiveFrameDurationInstaller

+ (void)load
{
    charon_swap_session(@selector(startRunning));
    charon_swap_session(@selector(commitConfiguration));

    SEL addOutput = @selector(addOutput:);
    Method outputMethod = class_getInstanceMethod([AVCaptureSession class], addOutput);
    IMP originalAddOutput = method_getImplementation(outputMethod);
    method_setImplementation(outputMethod, imp_implementationWithBlock(^(AVCaptureSession *self, AVCaptureOutput *output) {
        ((void (*)(AVCaptureSession *, SEL, AVCaptureOutput *))originalAddOutput)(self, addOutput, output);
        charon_apply_frame_durations(self);
    }));

    SEL addInput = @selector(addInput:);
    Method inputMethod = class_getInstanceMethod([AVCaptureSession class], addInput);
    IMP originalAddInput = method_getImplementation(inputMethod);
    method_setImplementation(inputMethod, imp_implementationWithBlock(^(AVCaptureSession *self, AVCaptureInput *input) {
        ((void (*)(AVCaptureSession *, SEL, AVCaptureInput *))originalAddInput)(self, addInput, input);
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDevice *device = ((AVCaptureDeviceInput *)input).device;
            [[device charon_activeFrameDurationSessions] addObject:self];
            charon_apply_frame_durations(self);
        }
    }));
}

@end

@implementation AVCaptureDevice (CharonActiveFrameDuration)

- (CMTime)activeVideoMinFrameDuration
{
    NSValue *stored = objc_getAssociatedObject(self, &CharonActiveMinFrameDurationKey);
    return stored ? stored.CMTimeValue : charon_default_min_frame_duration(self);
}

- (void)setActiveVideoMinFrameDuration:(CMTime)activeVideoMinFrameDuration
{
    objc_setAssociatedObject(self, &CharonActiveMinFrameDurationKey, CMTIME_IS_VALID(activeVideoMinFrameDuration) ? [NSValue valueWithCMTime:activeVideoMinFrameDuration] : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (AVCaptureSession *session in [self charon_activeFrameDurationSessions])
        charon_apply_frame_durations(session);
}

- (CMTime)activeVideoMaxFrameDuration
{
    NSValue *stored = objc_getAssociatedObject(self, &CharonActiveMaxFrameDurationKey);
    return stored ? stored.CMTimeValue : charon_default_max_frame_duration(self);
}

- (void)setActiveVideoMaxFrameDuration:(CMTime)activeVideoMaxFrameDuration
{
    objc_setAssociatedObject(self, &CharonActiveMaxFrameDurationKey, CMTIME_IS_VALID(activeVideoMaxFrameDuration) ? [NSValue valueWithCMTime:activeVideoMaxFrameDuration] : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (AVCaptureSession *session in [self charon_activeFrameDurationSessions])
        charon_apply_frame_durations(session);
}

@end

@implementation AVCaptureDevice (CharonActiveFrameDurationSessions)

- (NSHashTable<AVCaptureSession *> *)charon_activeFrameDurationSessions
{
    static const char key;
    NSHashTable *sessions = objc_getAssociatedObject(self, &key);
    if (!sessions) {
        sessions = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(self, &key, sessions, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return sessions;
}

@end
