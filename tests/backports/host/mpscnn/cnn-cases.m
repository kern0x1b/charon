// cnn-cases.m — the convolutional kernels, run twice: once against the system's own MPS and once
// against this port's classes under names of their own. Every case prints the bytes of a result the
// case owns, so the two runs are compared exactly for the results that are exact, and against a
// written-down float tolerance for the ones that are not.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

static id<MTLDevice> gDevice;

static void put(const char *name, const void *bytes, size_t count, size_t element)
{
    printf("%s %zu\n", name, count);
    const float *values = (const float *)bytes;
    for (size_t i = 0; i < count; i++)
        printf("%s%.9g", i ? " " : "", (double)values[i]);
    (void)element;
    printf("\n");
}

// A 3x3 single precision image, and the plane its values live in.
static MPSImage *image3x3(const float *values)
{
    MPSImageDescriptor *descriptor = [MPSImageDescriptor imageDescriptorWithChannelFormat:MPSImageFeatureChannelFormatFloat32
                                                                                       width:3 height:3 featureChannels:1];
    MPSImage *image = [[MPSImage alloc] initWithDevice:gDevice imageDescriptor:descriptor];
    [[image texture] replaceRegion:MTLRegionMake2D(0, 0, 3, 3) mipmapLevel:0 withBytes:values bytesPerRow:3 * sizeof(float)];
    return image;
}

static float read3x3(MPSImage *image)
{
    float out[9] = {0};
    [[image texture] getBytes:out bytesPerRow:3 * sizeof(float) fromRegion:MTLRegionMake2D(0, 0, 3, 3) mipmapLevel:0];
    return 0;
}

static float sSource[9] = {1, 2, 3, 4, 5, 6, 7, 8, 9};

static void casesPooling(void)
{
    // The average: a 3x3 window over a 3x3 image with the zero edge mode, so the corner windows hang
    // half outside. The answer says what the divisor is.
    for (NSUInteger pad = 0; pad < 2; pad++) {
        MPSImage *source = image3x3(sSource);
        MPSImageDescriptor *descriptor = [MPSImageDescriptor imageDescriptorWithChannelFormat:MPSImageFeatureChannelFormatFloat32
                                                                                       width:3 height:3 featureChannels:1];
        MPSImage *destination = [[MPSImage alloc] initWithDevice:gDevice imageDescriptor:descriptor];
        MPSCNNPoolingAverage *kernel = [[MPSCNNPoolingAverage alloc] initWithDevice:gDevice kernelWidth:3 kernelHeight:3
                                                                     strideInPixelsX:1 strideInPixelsY:1];
        kernel.edgeMode = MPSImageEdgeModeZero;
        if (pad) { kernel.zeroPadSizeX = 1; kernel.zeroPadSizeY = 1; }
        id<MTLCommandQueue> queue = [gDevice newCommandQueue];
        id<MTLCommandBuffer> buffer = [queue commandBufferWithUnretainedReferences];
        [kernel encodeToCommandBuffer:buffer sourceImage:source destinationImage:destination];
        [buffer commit];
        [buffer waitUntilCompleted];
        float out[9] = {0};
        [[destination texture] getBytes:out bytesPerRow:3 * sizeof(float) fromRegion:MTLRegionMake2D(0, 0, 3, 3) mipmapLevel:0];
        char name[64];
        snprintf(name, sizeof(name), "pooling-average-pad%lu", (unsigned long)pad);
        put(name, out, 9, sizeof(float));
    }
    // The maximum, same window.
    {
        MPSImage *source = image3x3(sSource);
        MPSImageDescriptor *descriptor = [MPSImageDescriptor imageDescriptorWithChannelFormat:MPSImageFeatureChannelFormatFloat32
                                                                                       width:3 height:3 featureChannels:1];
        MPSImage *destination = [[MPSImage alloc] initWithDevice:gDevice imageDescriptor:descriptor];
        MPSCNNPoolingMax *kernel = [[MPSCNNPoolingMax alloc] initWithDevice:gDevice kernelWidth:3 kernelHeight:3
                                                                   strideInPixelsX:1 strideInPixelsY:1];
        kernel.edgeMode = MPSImageEdgeModeZero;
        id<MTLCommandQueue> queue = [gDevice newCommandQueue];
        id<MTLCommandBuffer> buffer = [queue commandBufferWithUnretainedReferences];
        [kernel encodeToCommandBuffer:buffer sourceImage:source destinationImage:destination];
        [buffer commit];
        [buffer waitUntilCompleted];
        float out[9] = {0};
        [[destination texture] getBytes:out bytesPerRow:3 * sizeof(float) fromRegion:MTLRegionMake2D(0, 0, 3, 3) mipmapLevel:0];
        put("pooling-max", out, 9, sizeof(float));
    }
    // A 2x2 window with a stride of one, which has no window hanging outside: the divisor is
    // unambiguous there and pins the rule the corner case only suggests.
    {
        float s[9] = {1, 2, 3, 4, 5, 6, 7, 8, 9};
        MPSImage *source = image3x3(s);
        MPSImageDescriptor *descriptor = [MPSImageDescriptor imageDescriptorWithChannelFormat:MPSImageFeatureChannelFormatFloat32
                                                                                       width:2 height:2 featureChannels:1];
        MPSImage *destination = [[MPSImage alloc] initWithDevice:gDevice imageDescriptor:descriptor];
        MPSCNNPoolingAverage *kernel = [[MPSCNNPoolingAverage alloc] initWithDevice:gDevice kernelWidth:2 kernelHeight:2
                                                                     strideInPixelsX:1 strideInPixelsY:1];
        id<MTLCommandQueue> queue = [gDevice newCommandQueue];
        id<MTLCommandBuffer> buffer = [queue commandBufferWithUnretainedReferences];
        [kernel encodeToCommandBuffer:buffer sourceImage:source destinationImage:destination];
        [buffer commit];
        [buffer waitUntilCompleted];
        float out[4] = {0};
        [[destination texture] getBytes:out bytesPerRow:2 * sizeof(float) fromRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0];
        put("pooling-average-2x2", out, 4, sizeof(float));
    }
}

// A data source over the four per-channel arrays batch normalisation folds.
@interface TestDataSource : NSObject <MPSCNNBatchNormalizationDataSource>
@end
@implementation TestDataSource {
    float *_gamma, *_beta, *_mean, *_variance;
    NSUInteger _channels;
}
- (instancetype)initWithChannels:(NSUInteger)channels
{
    if ((self = [super init])) {
        _channels = channels;
        _gamma = (float *)calloc(channels, sizeof(float));
        _beta = (float *)calloc(channels, sizeof(float));
        _mean = (float *)calloc(channels, sizeof(float));
        _variance = (float *)calloc(channels, sizeof(float));
    }
    return self;
}
- (void)setGamma:(const float *)v { memcpy(_gamma, v, _channels * sizeof(float)); }
- (void)setBeta:(const float *)v { memcpy(_beta, v, _channels * sizeof(float)); }
- (void)setMean:(const float *)v { memcpy(_mean, v, _channels * sizeof(float)); }
- (void)setVariance:(const float *)v { memcpy(_variance, v, _channels * sizeof(float)); }
- (NSUInteger)numberOfFeatureChannels { return _channels; }
- (float *)gamma { return _gamma; }
- (float *)beta { return _beta; }
- (float *)mean { return _mean; }
- (float *)variance { return _variance; }
- (BOOL)load { return YES; }
- (void)purge {}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

static void casesBatchNormalization(void)
{
    float s[9] = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    float gamma[1] = {2.0f}, beta[1] = {0.5f}, mean[1] = {4.0f}, variance[1] = {1.5f};
    TestDataSource *source = [[TestDataSource alloc] initWithChannels:1];
    [source setGamma:gamma]; [source setBeta:beta]; [source setMean:mean]; [source setVariance:variance];
    MPSImage *input = image3x3(s);
    MPSImageDescriptor *descriptor = [MPSImageDescriptor imageDescriptorWithChannelFormat:MPSImageFeatureChannelFormatFloat32
                                                                                       width:3 height:3 featureChannels:1];
    MPSImage *destination = [[MPSImage alloc] initWithDevice:gDevice imageDescriptor:descriptor];
    MPSCNNBatchNormalization *kernel = [[MPSCNNBatchNormalization alloc] initWithDevice:gDevice dataSource:source];
    kernel.epsilon = 0.25f;
    id<MTLCommandQueue> queue = [gDevice newCommandQueue];
    id<MTLCommandBuffer> buffer = [queue commandBufferWithUnretainedReferences];
    [kernel encodeToCommandBuffer:buffer sourceImage:input destinationImage:destination];
    [buffer commit];
    [buffer waitUntilCompleted];
    float out[9] = {0};
    [[destination texture] getBytes:out bytesPerRow:3 * sizeof(float) fromRegion:MTLRegionMake2D(0, 0, 3, 3) mipmapLevel:0];
    put("batch-normalization", out, 9, sizeof(float));
}

int main(void)
{
    @autoreleasepool {
        gDevice = MTLCreateSystemDefaultDevice();
        if (!gDevice) { printf("no device\n"); return 1; }
        casesPooling();
        casesBatchNormalization();
    }
    return 0;
}
