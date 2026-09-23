#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Ranks 16/17 of coordination/corpus/crash-demand-top.tsv, LOAD-FAIL, class_confirmed against
// both telegram and session's own trees. Two-step check first: apple.objc.inventory() against
// the armv7 shared cache of 6.1.3 confirms AVCapturePhotoOutput/AVCapturePhotoSettings/
// AVCaptureResolvedPhotoSettings do not exist under any name on this release - a genuine gap -
// while AVCaptureStillImageOutput, the class the header itself documents the new API as sitting
// above, is real, exported, and already a working AVCaptureOutput subclass on this release; grep
// of this tree's own .m files found no orphaned implementation already carrying a demanded
// selector. Ladder-walked with tools' own cache-by-cache inventory (not read from the SDK
// header's availability attribute, which names when Apple published the symbol, not when it
// first exports): all three classes first export at 10.0.1, not the header's bare "10.0".
//
// What Telegram's own delegate implementation resolved this design: the corpus's defcache for
// telegram defines *both*
// -captureOutput:didFinishProcessingPhoto:error: (the AVCapturePhoto-based, iOS 11+ callback) and
// -captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:
// (the original, iOS 10-era CMSampleBufferRef-based callback, deprecated in 13.0 but never
// removed) - the second is the one iOS 10 itself used before AVCapturePhoto existed, needs no
// AVCapturePhoto object (out of scope: not itself demanded, and would need image processing this
// release does not do for us), and is a real fallback path Telegram already ships for pre-11
// devices. This port targets exactly that path.
//
// AVCaptureOutput is not meant to be subclassed by a client and driven through
// -[AVCaptureSession addOutput:]'s private machinery directly - the safe, working pattern
// already established in this tree for absent AVCaptureOutput-family surface
// (AVCaptureDataOutputSynchronizer.m observes *existing* real outputs rather than injecting a
// fake one into the session graph) does not apply here, since this class must itself be
// addable to a session. So AVCapturePhotoOutput here is a facade: a real AVCaptureOutput
// subclass instance that is never actually handed to the session's own internal graph. Instead,
// -[AVCaptureSession addOutput:]/-canAddOutput:/-removeOutput:/-outputs are swizzled to detect an
// AVCapturePhotoOutput facade and substitute a real, internally-held AVCaptureStillImageOutput in
// its place - the genuine graph node is always the real class already on this release; the facade
// only ever forwards to it and is never touched by AVCaptureSession's private setup.

static AVCaptureDevice *CharonDeviceForConnection(AVCaptureConnection *connection)
{
    AVCaptureInputPort *port = connection.inputPorts.firstObject;
    AVCaptureInput *input = port.input;
    return [input isKindOfClass:[AVCaptureDeviceInput class]] ? ((AVCaptureDeviceInput *)input).device : nil;
}

@interface AVCaptureResolvedPhotoSettings ()
@property (nonatomic, readwrite) int64_t uniqueID;
@end

@implementation AVCaptureResolvedPhotoSettings
@synthesize uniqueID = _uniqueID;
@end

@implementation AVCapturePhotoSettings
{
    int64_t _charonUniqueID;
}

@synthesize format = _format;
@synthesize flashMode = _flashMode;
@synthesize autoStillImageStabilizationEnabled = _autoStillImageStabilizationEnabled;
@synthesize previewPhotoFormat = _previewPhotoFormat;

+ (int64_t)charon_nextUniqueID
{
    static int64_t counter;
    @synchronized ([AVCapturePhotoSettings class]) {
        return ++counter;
    }
}

- (instancetype)initCharonWithFormat:(NSDictionary<NSString *, id> *)format
{
    if ((self = [super init])) {
        _format = [format copy];
        _charonUniqueID = [AVCapturePhotoSettings charon_nextUniqueID];
        _flashMode = AVCaptureFlashModeOff;
    }
    return self;
}

+ (instancetype)photoSettings
{
    return [[self alloc] initCharonWithFormat:nil];
}

+ (instancetype)photoSettingsWithFormat:(NSDictionary<NSString *, id> *)format
{
    return [[self alloc] initCharonWithFormat:format];
}

- (int64_t)uniqueID
{
    return _charonUniqueID;
}

@end

@interface AVCapturePhotoOutput ()
@property (nonatomic, strong) AVCaptureStillImageOutput *charonStillImageOutput;
@end

@implementation AVCapturePhotoOutput
{
    BOOL _charonHighResolutionCaptureEnabled;
}

@synthesize charonStillImageOutput = _charonStillImageOutput;

// AVCaptureOutput marks -init AV_INIT_UNAVAILABLE (a client is meant to instantiate only a
// concrete Apple subclass) - real for the abstract base, not for a subclass overriding -init
// itself, so this reaches over it with objc_msgSendSuper the same way this tree's other
// not-meant-to-be-instantiated classes already do (see MPRemoteCommandCenter71.m). Nothing this
// facade does depends on AVCaptureOutput's own (private, nil-after-alloc) internal state - see
// this file's header comment on why the facade is never handed to AVCaptureSession's real graph.
- (instancetype)init
{
    struct objc_super target = {self, [AVCaptureOutput class]};
    self = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&target, sel_registerName("init"));
    if (self)
        _charonStillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    return self;
}

- (NSArray<AVCaptureConnection *> *)connections
{
    return self.charonStillImageOutput.connections;
}

- (NSArray<NSNumber *> *)availablePhotoPixelFormatTypes
{
    return self.charonStillImageOutput.availableImageDataCVPixelFormatTypes ?: @[];
}

// iOS 6's AVCaptureStillImageOutput has no Bayer/Apple ProRAW capture path at all - real
// hardware and software support for RAW capture arrived with iOS 10's own AVCapturePhotoOutput,
// so an honestly empty array is correct here, not a stub standing in for one this port cannot
// build: nothing on this release could ever populate it.
- (NSArray<NSNumber *> *)availableRawPhotoPixelFormatTypes
{
    return @[];
}

// No preview-photo pipeline exists on this release's still image path (unlike the RAW/processed
// buffer, generating a distinct smaller preview buffer was never part of AVCaptureStillImageOutput).
// An empty array here is the same honest "not available" this port already gives
// -availableRawPhotoPixelFormatTypes; -capturePhotoWithSettings:delegate: below refuses a caller
// who sets -previewPhotoFormat rather than silently ignoring it.
- (NSArray<NSNumber *> *)availablePreviewPhotoPixelFormatTypes
{
    return @[];
}

- (NSArray<NSNumber *> *)supportedFlashModes
{
    AVCaptureDevice *device = CharonDeviceForConnection(self.charonStillImageOutput.connections.firstObject);
    if (!device)
        return @[@(AVCaptureFlashModeOff)];
    NSMutableArray<NSNumber *> *modes = [NSMutableArray arrayWithObject:@(AVCaptureFlashModeOff)];
    if ([device isFlashModeSupported:AVCaptureFlashModeOn])
        [modes addObject:@(AVCaptureFlashModeOn)];
    if ([device isFlashModeSupported:AVCaptureFlashModeAuto])
        [modes addObject:@(AVCaptureFlashModeAuto)];
    return modes;
}

// The real property "always returns NO unless you set photoSettingsForSceneMonitoring to a
// non-nil value" (Apple's own header). This port carries no scene-monitoring pipeline, so
// photoSettingsForSceneMonitoring is never non-nil, and NO is the release's own documented
// default answer for that state - not a fabricated default standing in for real monitoring.
- (BOOL)isFlashScene
{
    return NO;
}

// AVCaptureStillImageOutput already captures at the device's full active-format resolution by
// default (it has no separate preview-resolution/high-resolution distinction the way a video data
// output does), so there is no lower-resolution capture path this property would need to opt out
// of; it is real, settable storage rather than a fabricated always-on default, and observing it
// costs this port nothing to honor since the release's own still image path already behaves as if
// it were always enabled.
- (BOOL)isHighResolutionCaptureEnabled
{
    return _charonHighResolutionCaptureEnabled;
}

- (void)setHighResolutionCaptureEnabled:(BOOL)highResolutionCaptureEnabled
{
    _charonHighResolutionCaptureEnabled = highResolutionCaptureEnabled;
}

// Live Photo capture needs a motion/video pipeline paired to the still capture that this
// release's AVCaptureStillImageOutput has no counterpart for. Real AVCapturePhotoOutput throws
// NSInvalidArgumentException when livePhotoCaptureEnabled is set YES without
// livePhotoCaptureSupported also being YES; livePhotoCaptureSupported is unconditionally NO here,
// so this port reproduces that same real exception rather than silently accepting a YES it could
// never honor.
- (BOOL)isLivePhotoCaptureSupported
{
    return NO;
}

- (BOOL)isLivePhotoCaptureEnabled
{
    return NO;
}

- (void)setLivePhotoCaptureEnabled:(BOOL)livePhotoCaptureEnabled
{
    if (livePhotoCaptureEnabled)
        [NSException raise:NSInvalidArgumentException format:@"livePhotoCaptureEnabled may only be set to YES if livePhotoCaptureSupported is YES"];
}

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate
{
    if (settings.previewPhotoFormat) {
        [NSException raise:NSInvalidArgumentException format:@"previewPhotoFormat's pixel format type must be present in availablePreviewPhotoPixelFormatTypes"];
        return;
    }
    AVCaptureConnection *connection = self.charonStillImageOutput.connections.firstObject;
    if (!connection) {
        [NSException raise:NSInvalidArgumentException format:@"AVCapturePhotoOutput has no connection to capture from - add it to a running AVCaptureSession first"];
        return;
    }

    self.charonStillImageOutput.automaticallyEnablesStillImageStabilizationWhenAvailable = settings.autoStillImageStabilizationEnabled;
    if (settings.format)
        self.charonStillImageOutput.outputSettings = settings.format;

    AVCaptureDevice *device = CharonDeviceForConnection(connection);
    AVCaptureFlashMode flashMode = settings.flashMode;
    if (device.hasFlash && [device isFlashModeSupported:flashMode] && [device lockForConfiguration:NULL]) {
        device.flashMode = flashMode;
        [device unlockForConfiguration];
    }

    AVCaptureResolvedPhotoSettings *resolved = ((id (*)(id, SEL))objc_msgSend)([AVCaptureResolvedPhotoSettings alloc], sel_registerName("init"));
    resolved.uniqueID = settings.uniqueID;

    if ([delegate respondsToSelector:@selector(captureOutput:willBeginCaptureForResolvedSettings:)])
        [delegate captureOutput:self willBeginCaptureForResolvedSettings:resolved];

    [self.charonStillImageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        if ([delegate respondsToSelector:@selector(captureOutput:didCapturePhotoForResolvedSettings:)])
            [delegate captureOutput:self didCapturePhotoForResolvedSettings:resolved];
        if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:)]) {
            ((void (*)(id, SEL, id, CMSampleBufferRef, CMSampleBufferRef, id, id, id))objc_msgSend)(delegate, sel_registerName("captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:"),
                self, imageDataSampleBuffer, NULL, resolved, nil, error);
        }
        if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)])
            [delegate captureOutput:self didFinishCaptureForResolvedSettings:resolved error:error];
    }];
}

@end

// Session integration: never let the facade itself reach AVCaptureSession's private graph setup.
// -addOutput:/-canAddOutput:/-removeOutput:/-outputs are swizzled to substitute the facade's real
// AVCaptureStillImageOutput on the way in, and to substitute the facade back on the way out, so
// -[session.outputs containsObject:photoOutput] still answers correctly for a caller holding the
// facade it originally passed to -addOutput:.
static NSMapTable<AVCaptureOutput *, AVCapturePhotoOutput *> *CharonPhotoFacadesByReal(void)
{
    static NSMapTable<AVCaptureOutput *, AVCapturePhotoOutput *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSMapTable weakToWeakObjectsMapTable];
    });
    return table;
}

@implementation AVCaptureSession (CharonPhotoOutputBridge)

+ (void)load
{
    SEL pairs[][2] = {
        {@selector(addOutput:), @selector(charon_addOutput:)},
        {@selector(canAddOutput:), @selector(charon_canAddOutput:)},
        {@selector(removeOutput:), @selector(charon_removeOutput:)},
        {@selector(outputs), @selector(charon_outputs)},
    };
    for (size_t index = 0; index < sizeof(pairs) / sizeof(pairs[0]); index++) {
        Method original = class_getInstanceMethod(self, pairs[index][0]);
        Method replacement = class_getInstanceMethod(self, pairs[index][1]);
        method_exchangeImplementations(original, replacement);
    }
}

- (AVCaptureStillImageOutput *)charon_realOutput:(AVCaptureOutput *)output
{
    if (![output isKindOfClass:[AVCapturePhotoOutput class]])
        return nil;
    return ((AVCapturePhotoOutput *)output).charonStillImageOutput;
}

- (void)charon_addOutput:(AVCaptureOutput *)output
{
    AVCaptureStillImageOutput *real = [self charon_realOutput:output];
    if (real) {
        [self charon_addOutput:real];
        [CharonPhotoFacadesByReal() setObject:(AVCapturePhotoOutput *)output forKey:real];
        return;
    }
    [self charon_addOutput:output];
}

- (BOOL)charon_canAddOutput:(AVCaptureOutput *)output
{
    AVCaptureStillImageOutput *real = [self charon_realOutput:output];
    return [self charon_canAddOutput:real ?: output];
}

- (void)charon_removeOutput:(AVCaptureOutput *)output
{
    AVCaptureStillImageOutput *real = [self charon_realOutput:output];
    if (real) {
        [self charon_removeOutput:real];
        [CharonPhotoFacadesByReal() removeObjectForKey:real];
        return;
    }
    [self charon_removeOutput:output];
}

- (NSArray<AVCaptureOutput *> *)charon_outputs
{
    NSArray<AVCaptureOutput *> *real = [self charon_outputs];
    NSMutableArray<AVCaptureOutput *> *mapped = [NSMutableArray arrayWithCapacity:real.count];
    for (AVCaptureOutput *output in real) {
        AVCapturePhotoOutput *facade = [CharonPhotoFacadesByReal() objectForKey:output];
        [mapped addObject:facade ?: output];
    }
    return mapped;
}

@end
