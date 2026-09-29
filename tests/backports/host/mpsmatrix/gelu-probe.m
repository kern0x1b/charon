// gelu-probe.m - does the release's own batch-normalisation kernel crash on GeLU by itself?
//
// The differential's oracle dies at the eleventh neuron type, batch normalisation with GeLU, and the
// harness used to name the crash site with the last line the oracle printed, which was a philox case
// in a different family entirely. So the question this file answers is the one the differential cannot:
// is the crash a property of that one case, or does it need the cases before it.
//
// One file, one case, run directly. It takes the number of preceding cases to run first, so the same
// binary bisects: 0 is the case alone, and k is the case after the k cases that come before it.
#import <Foundation/Foundation.h>
#include <unistd.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

static id<MTLDevice> gDevice = nil;

static float normSource[4][3] = {{0.5f, 1.5f, 2.5f}, {3.5f, 4.5f, 5.5f}, {6.5f, 7.5f, 8.5f}, {9.5f, 0.5f, 1.5f}};
static float normOut[4][3];
static float normGivenMean[3] = {5.0f, 6.0f, 7.0f};
static float normGivenVariance[3] = {2.0f, 3.0f, 4.0f};
static float normGamma[3] = {1.5f, 0.75f, 2.5f};
static float normBeta[3] = {-1.0f, 0.5f, 1.0f};

static MPSMatrix *matrixOf(const void *values, MPSDataType type, NSUInteger rows, NSUInteger columns)
{
    return [[MPSMatrix alloc] initWithBuffer:[gDevice newBufferWithBytes:values
                                                                   length:rows * columns * sizeof(float)
                                                                  options:MTLResourceStorageModeShared]
                                descriptor:[MPSMatrixDescriptor matrixDescriptorWithRows:rows columns:columns matrices:1
                                                                               rowBytes:columns * sizeof(float)
                                                                           matrixBytes:rows * columns * sizeof(float)
                                                                                dataType:type]];
}

static MPSVector *vectorOf(const void *values, MPSDataType type, NSUInteger length)
{
    return [[MPSVector alloc] initWithBuffer:[gDevice newBufferWithBytes:values length:length * sizeof(float)
                                                                 options:MTLResourceStorageModeShared]
                                 descriptor:[MPSVectorDescriptor vectorDescriptorWithLength:length vectors:1
                                                                  vectorBytes:length * sizeof(float) dataType:type]];
}

static void say(const char *step)
{
    char line[128];
    int n = snprintf(line, sizeof(line), "STEP %s\n", step);
    write(2, line, (size_t)n);
}

static void oneCase(MPSCNNNeuronType type, const char *label)
{
    say("case begin");
    memset(normOut, 0, sizeof(normOut));
    say("buffers created");
    id<MTLCommandBuffer> buffer = [gDevice newCommandBuffer];
    MPSMatrix *in = matrixOf(&normSource[0][0], MPSDataTypeFloat32, 4, 3);
    MPSMatrix *out = matrixOf(&normOut[0][0], MPSDataTypeFloat32, 4, 3);
    MPSVector *m = vectorOf(normGivenMean, MPSDataTypeFloat32, 3);
    MPSVector *v = vectorOf(normGivenVariance, MPSDataTypeFloat32, 3);
    MPSVector *g = vectorOf(normGamma, MPSDataTypeFloat32, 3);
    MPSVector *b = vectorOf(normBeta, MPSDataTypeFloat32, 3);
    say("kernel alloc");
    MPSMatrixBatchNormalization *kernel = [[MPSMatrixBatchNormalization alloc] initWithDevice:gDevice];
    say("kernel allocated");
    [kernel setNeuronType:type parameterA:1.0f parameterB:1.0f parameterC:2.0f];
    kernel.epsilon = 0.001f;
    say("neuron set");
    [kernel encodeToCommandBuffer:buffer inputMatrix:in meanVector:m varianceVector:v
                      gammaVector:g betaVector:b resultMatrix:out];
    say("encoded");
    [buffer commit];
    say("committed");
    [buffer waitUntilCompleted];
    say("completed");
    printf("%-28s status %ld  out %g %g %g\n", label, (long)buffer.status, normOut[0][0], normOut[1][0], normOut[2][0]);
    fflush(stdout);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        gDevice = MTLCreateSystemDefaultDevice();
        if (!gDevice) { printf("no device\n"); return 2; }
        // the type before GeLU, run first when asked, to see whether the crash needs earlier state
        const unsigned kPreceding = (argc > 1) ? (unsigned)atoi(argv[1]) : 0;
        printf("device %s, preceding cases %u\n", [[gDevice name] UTF8String], kPreceding);
        fflush(stdout);
        (void)kPreceding;
        MPSCNNNeuronType type = MPSCNNNeuronTypeGeLU;
        if (argc > 2) type = (MPSCNNNeuronType)atoi(argv[2]);
        say("device ready");
        oneCase(type, "chosen type");
        printf("survived\n");
    }
    return 0;
}
