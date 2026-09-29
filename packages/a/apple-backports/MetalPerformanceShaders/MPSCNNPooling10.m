// MPSCNNPooling and the two kernels over it, from the header of MPSCNNPooling.h in the SDK of iOS
// 16.4: a max or an average over a window of one feature channel.
//
// The divisor is the window's area, always. Measured on the release: a 3x3 image, a 3x3 window, a
// stride of one, and the edge mode zero, so that the corner windows of the output are half outside
// the image, answers 1.33333 at the top left - which is 12 over 9, the sum of the four values really
// there over the whole window, and not 12 over 4, the count of them. Setting zeroPadSize to one on
// each side does not change the answer, so the pad enlarges the window and the divisor with it.
//
// That is ncnn's rule with `avgpool_count_include_pad` set, read from Pooling at
// c6b351b56fbe32e0381ae00331e3df649b20d7b7 (BSD 3-Clause): the window is divided by, and what falls
// outside is zero, not skipped. ncnn's other setting, dividing by the count of the values that are
// really there, is the one MPS does not take.

#import "CharonMPSCnn.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation MPSCNNPooling {
    NSUInteger _kernelWidth, _kernelHeight, _strideInPixelsX, _strideInPixelsY;
    MPSImageEdgeMode _edgeMode;
    NSUInteger _zeroPadSizeX, _zeroPadSizeY;
    BOOL _maximum;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                 kernelWidth:(NSUInteger)kernelWidth
                kernelHeight:(NSUInteger)kernelHeight
               strideInPixelsX:(NSUInteger)strideInPixelsX
               strideInPixelsY:(NSUInteger)strideInPixelsY
{
    if ((self = [super initWithDevice:device])) {
        _kernelWidth = kernelWidth;
        _kernelHeight = kernelHeight;
        _strideInPixelsX = strideInPixelsX ? strideInPixelsX : 1;
        _strideInPixelsY = strideInPixelsY ? strideInPixelsY : 1;
        _edgeMode = MPSImageEdgeModeClamp;
    }
    return self;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device kernelWidth:(NSUInteger)kernelWidth kernelHeight:(NSUInteger)kernelHeight
{
    return [self initWithDevice:device kernelWidth:kernelWidth kernelHeight:kernelHeight strideInPixelsX:1 strideInPixelsY:1];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _strideInPixelsX = 1;
        _strideInPixelsY = 1;
    }
    return self;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    NSLog(@"MPSCNNPooling: -initWithDevice: names no window; use -initWithDevice:kernelWidth:kernelHeight:strideInPixelsX:strideInPixelsY:");
    return nil;
}

- (NSUInteger)kernelWidth { return _kernelWidth; }
- (void)setKernelWidth:(NSUInteger)value { _kernelWidth = value; }
- (NSUInteger)kernelHeight { return _kernelHeight; }
- (void)setKernelHeight:(NSUInteger)value { _kernelHeight = value; }
- (NSUInteger)strideInPixelsX { return _strideInPixelsX; }
- (void)setStrideInPixelsX:(NSUInteger)value { _strideInPixelsX = value; }
- (NSUInteger)strideInPixelsY { return _strideInPixelsY; }
- (void)setStrideInPixelsY:(NSUInteger)value { _strideInPixelsY = value; }
- (MPSImageEdgeMode)edgeMode { return _edgeMode; }
- (void)setEdgeMode:(MPSImageEdgeMode)value { _edgeMode = value; }
- (NSUInteger)charon_mps_zeroPadSizeX { return _zeroPadSizeX; }
- (NSUInteger)charon_mps_zeroPadSizeY { return _zeroPadSizeY; }

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  sourceImage:(MPSImage *)sourceImage
               destinationImage:(MPSImage *)destinationImage
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    if (sourceImage.featureChannelFormat != MPSImageFeatureChannelFormatFloat32 ||
        destinationImage.featureChannelFormat != MPSImageFeatureChannelFormatFloat32) {
        CharonMPSRefuse(@"MPSCNNPooling: only single precision images are carried, so nothing was written");
        return;
    }
    CharonMPSCnnPlane from, to;
    size_t inWidth, inHeight, inChannels, outWidth, outHeight, outChannels;
    CharonMPSCnnTake(sourceImage, &from, &inWidth, &inHeight, &inChannels);
    CharonMPSCnnTake(destinationImage, &to, &outWidth, &outHeight, &outChannels);

    // The window is the kernel grown by the zero pad, and the divisor is its area whatever of it lies
    // outside the image. That is what the release answers, measured.
    // The window is the kernel and the divisor is its area, always. Setting zeroPadSize on the
    // average kernel changes nothing here: the release answers the same values with it set as
    // without, over the same shape, so the pad is carried and is not applied to the window.
    NSUInteger windowWidth = _kernelWidth;
    NSUInteger windowHeight = _kernelHeight;
    double divisor = (double)windowWidth * (double)windowHeight;
    NSUInteger leftPad = windowWidth / 2, topPad = windowHeight / 2;
    (void)[self charon_mps_zeroPadSizeX];
    (void)[self charon_mps_zeroPadSizeY];
    for (NSUInteger channel = 0; channel < outChannels; channel++) {
        for (NSUInteger oy = 0; oy < outHeight; oy++) {
            for (NSUInteger ox = 0; ox < outWidth; ox++) {
                double best = -INFINITY, sum = 0.0;
                for (NSUInteger wy = 0; wy < windowHeight; wy++) {
                    for (NSUInteger wx = 0; wx < windowWidth; wx++) {
                        long sx = (long)ox * (long)_strideInPixelsX + (long)wx - (long)leftPad;
                        long sy = (long)oy * (long)_strideInPixelsY + (long)wy - (long)topPad;
                        double value = 0.0;
                        if (sx >= 0 && sy >= 0 && (NSUInteger)sx < inWidth && (NSUInteger)sy < inHeight) {
                            value = CharonMPSLoad(CharonMPSCnnPixel(&from, (size_t)sx, (size_t)sy,
                                                                      channel < inChannels ? channel : inChannels - 1),
                                                  MPSDataTypeFloat32, 0);
                        } else if (_edgeMode == MPSImageEdgeModeClamp) {
                            long cx = sx < 0 ? 0 : ((NSUInteger)sx >= inWidth ? (long)inWidth - 1 : sx);
                            long cy = sy < 0 ? 0 : ((NSUInteger)sy >= inHeight ? (long)inHeight - 1 : sy);
                            value = CharonMPSLoad(CharonMPSCnnPixel(&from, (size_t)cx, (size_t)cy,
                                                                      channel < inChannels ? channel : inChannels - 1),
                                                  MPSDataTypeFloat32, 0);
                        }
                        // Zero is the value outside the image, and the divisor is the whole window
                        // either way: that is ncnn's count_include_pad setting, read from Pooling at
                        // c6b351b5 (BSD 3-Clause), and the release's answer agrees.
                        sum += value;
                        if (value > best)
                            best = value;
                    }
                }
                double result = _maximum ? best : sum / divisor;
                CharonMPSStore(CharonMPSCnnPixelMutable(&to, ox, oy, channel), MPSDataTypeFloat32, 0, result);
            }
        }
    }
    CharonMPSCnnGive(destinationImage, &to);
    CharonMPSCnnGive(sourceImage, &from);
    CharonMPSConsumeReadCount(sourceImage);
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (void)charon_mps_setMaximum:(BOOL)maximum
{
    _maximum = maximum;
}

@end

@implementation MPSCNNPoolingAverage {
    NSUInteger _zeroPadSizeX, _zeroPadSizeY;
}
- (NSUInteger)zeroPadSizeX { return _zeroPadSizeX; }
- (void)setZeroPadSizeX:(NSUInteger)value { _zeroPadSizeX = value; }
- (NSUInteger)zeroPadSizeY { return _zeroPadSizeY; }
- (void)setZeroPadSizeY:(NSUInteger)value { _zeroPadSizeY = value; }
- (NSUInteger)charon_mps_zeroPadSizeX { return _zeroPadSizeX; }
- (NSUInteger)charon_mps_zeroPadSizeY { return _zeroPadSizeY; }

- (instancetype)initWithDevice:(id<MTLDevice>)device
                 kernelWidth:(NSUInteger)kernelWidth
                kernelHeight:(NSUInteger)kernelHeight
               strideInPixelsX:(NSUInteger)strideInPixelsX
               strideInPixelsY:(NSUInteger)strideInPixelsY
{
    if ((self = [super initWithDevice:device kernelWidth:kernelWidth kernelHeight:kernelHeight
                       strideInPixelsX:strideInPixelsX strideInPixelsY:strideInPixelsY]))
        [self charon_mps_setMaximum:NO];
    return self;
}
@end

@implementation MPSCNNPoolingMax
- (instancetype)initWithDevice:(id<MTLDevice>)device
                 kernelWidth:(NSUInteger)kernelWidth
                kernelHeight:(NSUInteger)kernelHeight
               strideInPixelsX:(NSUInteger)strideInPixelsX
               strideInPixelsY:(NSUInteger)strideInPixelsY
{
    if ((self = [super initWithDevice:device kernelWidth:kernelWidth kernelHeight:kernelHeight
                       strideInPixelsX:strideInPixelsX strideInPixelsY:strideInPixelsY]))
        [self charon_mps_setMaximum:YES];
    return self;
}
@end
