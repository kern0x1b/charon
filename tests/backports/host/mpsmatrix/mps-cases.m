// mps-cases.m — the matrix and vector operations of Metal Performance Shaders, run twice: once
// against the system's own MPS and once against this port's classes compiled under names of their own.
// Every operation writes its result into a buffer, and the program prints those buffers as bytes, so
// the two runs are compared exactly rather than through a tolerance this file chooses.
//
// The port build is compiled with -include rename.h, which maps every MPS class name this library
// carries to a Charon name, and with prefix_selectors.py's prefixed declarations, so the port's
// implementations are reached through names of their own and do not replace the system's.
//
// Every case's data is at file scope, because a block cannot capture a C array.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

static id<MTLDevice> gDevice;

static void put(const char *name, const void *bytes, size_t length)
{
    printf("%s %zu ", name, length);
    const unsigned char *p = (const unsigned char *)bytes;
    for (size_t i = 0; i < length; i++)
        printf("%02x", p[i]);
    printf("\n");
}

static MPSMatrix *matrixOf(const void *values, MPSDataType type, NSUInteger rows, NSUInteger columns, NSUInteger matrices, size_t rowBytes, size_t matrixBytes)
{
    size_t element = MPSSizeofMPSDataType(type);
    size_t bytes = (matrices - 1) * matrixBytes + (rows - 1) * rowBytes + columns * element;
    id<MTLBuffer> buffer = [gDevice newBufferWithBytes:values length:bytes options:MTLResourceStorageModeShared];
    MPSMatrixDescriptor *descriptor = [MPSMatrixDescriptor matrixDescriptorWithRows:rows columns:columns matrices:matrices rowBytes:rowBytes matrixBytes:matrixBytes dataType:type];
    return [[MPSMatrix alloc] initWithBuffer:buffer descriptor:descriptor];
}

static MPSVector *vectorOf(const void *values, MPSDataType type, NSUInteger length, NSUInteger vectors, size_t vectorBytes)
{
    size_t element = MPSSizeofMPSDataType(type);
    size_t bytes = (vectors - 1) * vectorBytes + length * element;
    id<MTLBuffer> buffer = [gDevice newBufferWithBytes:values length:bytes options:MTLResourceStorageModeShared];
    MPSVectorDescriptor *descriptor = [MPSVectorDescriptor vectorDescriptorWithLength:length vectors:vectors vectorBytes:vectorBytes dataType:type];
    return [[MPSVector alloc] initWithBuffer:buffer descriptor:descriptor];
}

// A command buffer from a queue, not from the device: on macOS 26.5 -newCommandBuffer answers an
// MTL4 command buffer, and the MPS of that release asks it for a method it does not carry, so the
// oracle would be the host's own crash rather than the host's own arithmetic. The queue's
// -commandBufferWithUnretainedReferences answers the classic one every MTLCommandBuffer conforms to.
static id<MTLCommandBuffer> freshCommandBuffer(void)
{
    static id<MTLCommandQueue> queue;
    if (!queue)
        queue = [gDevice newCommandQueue];
    return [queue commandBufferWithUnretainedReferences];
}

static void run(void (^encode)(id<MTLCommandBuffer>))
{
    id<MTLCommandBuffer> buffer = freshCommandBuffer();
    encode(buffer);
    [buffer commit];
    [buffer waitUntilCompleted];
}

#pragma mark - the device questions

static void casesDevice(void)
{
    printf("supports %d\n", (int)MPSSupportsMTLDevice(gDevice));
    printf("preferred %d\n", MPSGetPreferredDevice(MPSDeviceOptionsDefault) != nil);
    printf("rect %lld %lld %lld %lld %lld\n", (long long)MPSRectNoClip.origin.x, (long long)MPSRectNoClip.origin.y,
           (long long)MPSRectNoClip.size.width, (long long)MPSRectNoClip.size.height, (long long)MPSRectNoClip.size.depth);
}

#pragma mark - the descriptors

static void casesDescriptors(void)
{
    MPSDataType types[] = {MPSDataTypeFloat32, MPSDataTypeFloat16, MPSDataTypeInt8, MPSDataTypeInt16,
                           MPSDataTypeInt32, MPSDataTypeUInt8, MPSDataTypeUInt16, MPSDataTypeUInt32};
    for (unsigned t = 0; t < 8; t++) {
        for (NSUInteger columns = 0; columns < 70; columns++)
            printf("rowBytes %u %lu %zu\n", (unsigned)types[t], (unsigned long)columns,
                   [MPSMatrixDescriptor rowBytesForColumns:columns dataType:types[t]]);
        for (NSUInteger length = 0; length < 70; length++)
            printf("vectorBytes %u %lu %zu\n", (unsigned)types[t], (unsigned long)length,
                   [MPSVectorDescriptor vectorBytesForLength:length dataType:types[t]]);
    }
    MPSMatrixDescriptor *m = [MPSMatrixDescriptor matrixDescriptorWithRows:2 columns:3 rowBytes:8 dataType:MPSDataTypeFloat32];
    printf("descriptor %lu %lu %lu %lu %lu %u\n", (unsigned long)m.rows, (unsigned long)m.columns,
           (unsigned long)m.matrices, (unsigned long)m.rowBytes, (unsigned long)m.matrixBytes, (unsigned)m.dataType);
    m.rowBytes = 16;
    m.rows = 5;
    m.columns = 4;
    m.dataType = MPSDataTypeFloat16;
    printf("descriptor-mutated %lu %lu %lu %lu %lu %u\n", (unsigned long)m.rows, (unsigned long)m.columns,
           (unsigned long)m.matrices, (unsigned long)m.rowBytes, (unsigned long)m.matrixBytes, (unsigned)m.dataType);
    MPSMatrixDescriptor *batched = [MPSMatrixDescriptor matrixDescriptorWithRows:2 columns:2 matrices:3 rowBytes:8 matrixBytes:24 dataType:MPSDataTypeFloat32];
    printf("descriptor-batched %lu %lu\n", (unsigned long)batched.matrices, (unsigned long)batched.matrixBytes);
    MPSVectorDescriptor *v = [MPSVectorDescriptor vectorDescriptorWithLength:4 dataType:MPSDataTypeFloat32];
    printf("vector-descriptor %lu %lu %lu\n", (unsigned long)v.length, (unsigned long)v.vectors, (unsigned long)v.vectorBytes);
    v.length = 9;
    printf("vector-descriptor-mutated %lu %lu %lu\n", (unsigned long)v.length, (unsigned long)v.vectors, (unsigned long)v.vectorBytes);
    MPSVectorDescriptor *batchedVector = [MPSVectorDescriptor vectorDescriptorWithLength:4 vectors:3 vectorBytes:32 dataType:MPSDataTypeFloat32];
    printf("vector-descriptor-batched %lu %lu\n", (unsigned long)batchedVector.vectors, (unsigned long)batchedVector.vectorBytes);
}

#pragma mark - multiplication

static float multiplyLeft[2][3] = {{1, 2, 3}, {4, 5, 6}};
static float multiplyRight[3][2] = {{7, 8}, {9, 10}, {11, 12}};
static float multiplySeed[2][2] = {{0.5f, 0.25f}, {-1, -2}};
static float multiplyOut[3][3];
static uint16_t multiplyHalfLeft[2][4] = {{0x3C00, 0x4000, 0x4200, 0x4400}, {0x4500, 0x4600, 0x4700, 0x4800}};
static uint16_t multiplyHalfRight[4][2] = {{0x3C00, 0x3C00}, {0x3C00, 0x4000}, {0x4000, 0x4000}, {0x4000, 0x4200}};
static uint16_t multiplyHalfOut[4][4];
static float batchLeft[3][2][2] = {{{1, 2}, {3, 4}}, {{5, 6}, {7, 8}}, {{9, 10}, {11, 12}}};
static float batchRight[3][2][2] = {{{1, 0}, {0, 1}}, {{2, 0}, {0, 2}}, {{3, 0}, {0, 3}}};
static float batchOut[3][2][2];

static void casesMultiplication(void)
{
    for (int transposeLeft = 0; transposeLeft < 2; transposeLeft++) {
        for (int transposeRight = 0; transposeRight < 2; transposeRight++) {
            memcpy(multiplyOut, multiplySeed, sizeof(multiplyOut));
            memset(multiplyOut, 0, sizeof(multiplyOut));
            multiplyOut[0][0] = multiplySeed[0][0];
            multiplyOut[0][1] = multiplySeed[0][1];
            multiplyOut[1][0] = multiplySeed[1][0];
            multiplyOut[1][1] = multiplySeed[1][1];
            run(^(id<MTLCommandBuffer> commandBuffer) {
                // A 3x3 descriptor for all three, so the same matrices serve whichever way round they
                // are read: MPS refuses a matrix whose row stride cannot hold the columns asked of it.
                MPSMatrix *a = matrixOf(&multiplyLeft[0][0], MPSDataTypeFloat32, 3, 3, 1, 3 * sizeof(float), 9 * sizeof(float));
                MPSMatrix *b = matrixOf(&multiplyRight[0][0], MPSDataTypeFloat32, 3, 3, 1, 3 * sizeof(float), 9 * sizeof(float));
                MPSMatrix *c = matrixOf(&multiplyOut[0][0], MPSDataTypeFloat32, 3, 3, 1, 3 * sizeof(float), 9 * sizeof(float));
                MPSMatrixMultiplication *kernel = [[MPSMatrixMultiplication alloc] initWithDevice:gDevice
                                                                                      transposeLeft:transposeLeft
                                                                                     transposeRight:transposeRight
                                                                                         resultRows:2
                                                                                      resultColumns:2
                                                                                    interiorColumns:3
                                                                                              alpha:2.0
                                                                                               beta:0.5];
                [kernel encodeToCommandBuffer:commandBuffer leftMatrix:a rightMatrix:b resultMatrix:c];
            });
            char name[64];
            snprintf(name, sizeof(name), "multiply %d %d", transposeLeft, transposeRight);
            put(name, &multiplyOut[0][0], sizeof(multiplyOut));
        }
    }
    memset(multiplyHalfOut, 0, sizeof(multiplyHalfOut));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *a = matrixOf(&multiplyHalfLeft[0][0], MPSDataTypeFloat16, 4, 4, 1, 4 * sizeof(uint16_t), 16 * sizeof(uint16_t));
        MPSMatrix *b = matrixOf(&multiplyHalfRight[0][0], MPSDataTypeFloat16, 4, 4, 1, 4 * sizeof(uint16_t), 16 * sizeof(uint16_t));
        MPSMatrix *c = matrixOf(&multiplyHalfOut[0][0], MPSDataTypeFloat16, 4, 4, 1, 4 * sizeof(uint16_t), 16 * sizeof(uint16_t));
        MPSMatrixMultiplication *kernel = [[MPSMatrixMultiplication alloc] initWithDevice:gDevice resultRows:2 resultColumns:2 interiorColumns:4];
        [kernel encodeToCommandBuffer:commandBuffer leftMatrix:a rightMatrix:b resultMatrix:c];
    });
    put("multiply-half", &multiplyHalfOut[0][0], sizeof(multiplyHalfOut));

    memset(batchOut, 0, sizeof(batchOut));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *a = matrixOf(&batchLeft[0][0][0], MPSDataTypeFloat32, 2, 2, 3, 2 * sizeof(float), 4 * sizeof(float));
        MPSMatrix *b = matrixOf(&batchRight[0][0][0], MPSDataTypeFloat32, 2, 2, 3, 2 * sizeof(float), 4 * sizeof(float));
        MPSMatrix *c = matrixOf(&batchOut[0][0][0], MPSDataTypeFloat32, 2, 2, 3, 2 * sizeof(float), 4 * sizeof(float));
        MPSMatrixMultiplication *kernel = [[MPSMatrixMultiplication alloc] initWithDevice:gDevice resultRows:2 resultColumns:2 interiorColumns:2];
        // The origin's z names a matrix, which the release requires to be zero: the batch is the
        // batchStart/batchSize range, and the origin moves the window inside each matrix of it.
        kernel.leftMatrixOrigin = MTLOriginMake(0, 0, 0);
        kernel.batchStart = 1;
        kernel.batchSize = 2;
        [kernel encodeToCommandBuffer:commandBuffer leftMatrix:a rightMatrix:b resultMatrix:c];
    });
    put("multiply-batch", &batchOut[0][0][0], sizeof(batchOut));
}

static float vectorMatrix[3][3] = {{1, 2, 3}, {4, 5, 6}, {0, 0, 0}};
static float vectorX[3] = {1, -1, 2};
static float vectorOut[2];

static void casesVectorMultiplication(void)
{
    for (int transpose = 0; transpose < 2; transpose++) {
        vectorOut[0] = 0;
        vectorOut[1] = 0;
        run(^(id<MTLCommandBuffer> commandBuffer) {
            MPSMatrix *a = matrixOf(&vectorMatrix[0][0], MPSDataTypeFloat32, 3, 3, 1, 3 * sizeof(float), 9 * sizeof(float));
            MPSVector *in = vectorOf(vectorX, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
            MPSVector *out = vectorOf(vectorOut, MPSDataTypeFloat32, 2, 1, 2 * sizeof(float));
            MPSMatrixVectorMultiplication *kernel = [[MPSMatrixVectorMultiplication alloc] initWithDevice:gDevice transpose:transpose rows:2 columns:3 alpha:1.5 beta:0.25];
            [kernel encodeToCommandBuffer:commandBuffer inputMatrix:a inputVector:in resultVector:out];
        });
        char name[64];
        snprintf(name, sizeof(name), "matrix-vector %d", transpose);
        put(name, vectorOut, sizeof(vectorOut));
    }
}

#pragma mark - copy

static float copySource[3][3] = {{1, 2, 3}, {4, 5, 6}, {7, 8, 9}};
static float copyDestination[3][3];
static float permuteSource[2][4] = {{1, 2, 3, 4}, {5, 6, 7, 8}};
static uint32_t permuteIndices[4] = {1, 0, 0, 0};
static uint32_t columnPermuteIndices[4] = {3, 2, 1, 0};
static float permuteDestination[2][4];

static void casesCopy(void)
{
    for (int transposeSource = 0; transposeSource < 2; transposeSource++) {
        for (int transposeDestination = 0; transposeDestination < 2; transposeDestination++) {
            memset(copyDestination, 0, sizeof(copyDestination));
            MPSMatrixCopyOffsets offsets = {1, 1, 0, 0};
            MPSMatrixCopy *kernel = [[MPSMatrixCopy alloc] initWithDevice:gDevice copyRows:2 copyColumns:2
                                                          sourcesAreTransposed:transposeSource
                                                     destinationsAreTransposed:transposeDestination];
            run(^(id<MTLCommandBuffer> commandBuffer) {
                MPSMatrix *a = matrixOf(&copySource[0][0], MPSDataTypeFloat32, 3, 3, 1, 3 * sizeof(float), 9 * sizeof(float));
                MPSMatrix *b = matrixOf(&copyDestination[0][0], MPSDataTypeFloat32, 3, 3, 1, 3 * sizeof(float), 9 * sizeof(float));
                MPSMatrixCopyDescriptor *descriptor = [MPSMatrixCopyDescriptor descriptorWithSourceMatrix:a destinationMatrix:b offsets:offsets];
                [kernel encodeToCommandBuffer:commandBuffer copyDescriptor:descriptor];
            });
            char name[64];
            snprintf(name, sizeof(name), "copy %d %d", transposeSource, transposeDestination);
            put(name, &copyDestination[0][0], sizeof(copyDestination));
        }
    }
    memset(permuteDestination, 0, sizeof(permuteDestination));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *a = matrixOf(&permuteSource[0][0], MPSDataTypeFloat32, 2, 4, 1, 4 * sizeof(float), 8 * sizeof(float));
        MPSMatrix *b = matrixOf(&permuteDestination[0][0], MPSDataTypeFloat32, 2, 4, 1, 4 * sizeof(float), 8 * sizeof(float));
        MPSMatrixCopyDescriptor *descriptor = [MPSMatrixCopyDescriptor descriptorWithSourceMatrix:a destinationMatrix:b offsets:(MPSMatrixCopyOffsets){0, 0, 0, 0}];
        MPSMatrixCopy *kernel = [[MPSMatrixCopy alloc] initWithDevice:gDevice copyRows:2 copyColumns:4 sourcesAreTransposed:NO destinationsAreTransposed:NO];
        MPSVector *rows = vectorOf(permuteIndices, MPSDataTypeUInt32, 2, 1, 2 * sizeof(uint32_t));
        MPSVector *columns = vectorOf(columnPermuteIndices, MPSDataTypeUInt32, 4, 1, 4 * sizeof(uint32_t));
        [kernel encodeToCommandBuffer:commandBuffer copyDescriptor:descriptor rowPermuteIndices:rows rowPermuteOffset:0 columnPermuteIndices:columns columnPermuteOffset:0];
    });
    put("copy-permute", &permuteDestination[0][0], sizeof(permuteDestination));
}

#pragma mark - softmax and top k

static float softMaxSource[2][4] = {{1, 2, 3, 4}, {-3, 0.5f, 0.5f, 0.5f}};
static float softMaxPlain[2][4];
static float softMaxLogarithmic[2][4];
static float softMaxIncoming[2][4] = {{1, 2, 3, 4}, {4, 3, 2, 1}};
static float softMaxGradient[2][4];
static float topKSource[2][6] = {{5, 1, 9, 9, 0, 7}, {1, 1, 1, 1, 1, 1}};
static uint32_t topKIndices[2][3];
static float topKValues[2][3];

static void casesSoftMax(void)
{
    memset(softMaxPlain, 0, sizeof(softMaxPlain));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *in = matrixOf(&softMaxSource[0][0], MPSDataTypeFloat32, 2, 4, 1, 4 * sizeof(float), 8 * sizeof(float));
        MPSMatrix *out = matrixOf(&softMaxPlain[0][0], MPSDataTypeFloat32, 2, 4, 1, 4 * sizeof(float), 8 * sizeof(float));
        MPSMatrixSoftMax *kernel = [[MPSMatrixSoftMax alloc] initWithDevice:gDevice];
        [kernel encodeToCommandBuffer:commandBuffer inputMatrix:in resultMatrix:out];
    });
    put("softmax", &softMaxPlain[0][0], sizeof(softMaxPlain));
    memset(softMaxLogarithmic, 0, sizeof(softMaxLogarithmic));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *in = matrixOf(&softMaxSource[0][0], MPSDataTypeFloat32, 2, 4, 1, 4 * sizeof(float), 8 * sizeof(float));
        MPSMatrix *out = matrixOf(&softMaxLogarithmic[0][0], MPSDataTypeFloat32, 2, 4, 1, 4 * sizeof(float), 8 * sizeof(float));
        MPSMatrixLogSoftMax *kernel = [[MPSMatrixLogSoftMax alloc] initWithDevice:gDevice];
        [kernel encodeToCommandBuffer:commandBuffer inputMatrix:in resultMatrix:out];
    });
    put("logsoftmax", &softMaxLogarithmic[0][0], sizeof(softMaxLogarithmic));
    memset(softMaxGradient, 0, sizeof(softMaxGradient));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *g = matrixOf(&softMaxIncoming[0][0], MPSDataTypeFloat32, 2, 4, 1, 4 * sizeof(float), 8 * sizeof(float));
        MPSMatrix *y = matrixOf(&softMaxPlain[0][0], MPSDataTypeFloat32, 2, 4, 1, 4 * sizeof(float), 8 * sizeof(float));
        MPSMatrix *out = matrixOf(&softMaxGradient[0][0], MPSDataTypeFloat32, 2, 4, 1, 4 * sizeof(float), 8 * sizeof(float));
        MPSMatrixSoftMaxGradient *kernel = [[MPSMatrixSoftMaxGradient alloc] initWithDevice:gDevice];
        [kernel encodeToCommandBuffer:commandBuffer gradientMatrix:g forwardOutputMatrix:y resultMatrix:out];
    });
    put("softmax-gradient", &softMaxGradient[0][0], sizeof(softMaxGradient));
    memset(topKIndices, 0, sizeof(topKIndices));
    memset(topKValues, 0, sizeof(topKValues));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *in = matrixOf(&topKSource[0][0], MPSDataTypeFloat32, 2, 6, 1, 6 * sizeof(float), 12 * sizeof(float));
        MPSMatrix *i = matrixOf(&topKIndices[0][0], MPSDataTypeUInt32, 2, 3, 1, 3 * sizeof(uint32_t), 6 * sizeof(uint32_t));
        MPSMatrix *v = matrixOf(&topKValues[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
        MPSMatrixFindTopK *kernel = [[MPSMatrixFindTopK alloc] initWithDevice:gDevice numberOfTopKValues:3];
        [kernel encodeToCommandBuffer:commandBuffer inputMatrix:in resultIndexMatrix:i resultValueMatrix:v];
    });
    put("findtopk-indices", &topKIndices[0][0], sizeof(topKIndices));
    put("findtopk-values", &topKValues[0][0], sizeof(topKValues));
}

#pragma mark - the neuron family

static MPSCNNNeuronType gTypes[] = {
    MPSCNNNeuronTypeNone, MPSCNNNeuronTypeReLU, MPSCNNNeuronTypeLinear, MPSCNNNeuronTypeSigmoid,
    MPSCNNNeuronTypeHardSigmoid, MPSCNNNeuronTypeTanH, MPSCNNNeuronTypeAbsolute, MPSCNNNeuronTypeSoftPlus,
    MPSCNNNeuronTypeSoftSign, MPSCNNNeuronTypeELU, MPSCNNNeuronTypeReLUN, MPSCNNNeuronTypePower,
    MPSCNNNeuronTypeExponential, MPSCNNNeuronTypeLogarithm, MPSCNNNeuronTypeGeLU
};
static const unsigned gTypeCount = sizeof(gTypes) / sizeof(gTypes[0]);

static float neuronSource[3][4] = {{-2, -0.5f, 0, 0.5f}, {1, 2, 3, 4}, {-8, 8, 0.1f, 2}};
static float neuronBias[4] = {0.25f, -0.25f, 0.5f, -0.5f};
static float neuronIncoming[3][4] = {{1, 2, 3, 4}, {0.5f, 0.25f, 0.125f, 0.0625f}, {2, 2, 2, 2}};
static float neuronOut[3][4];
static float neuronGradientData[3][4];
static float neuronGradientBias[4];
static float neuronPreluA[4] = {0.1f, 0.2f, 0.3f, 0.4f};
static float neuronPreluOut[3][4];

static void casesNeuron(void)
{
    for (unsigned t = 0; t < gTypeCount; t++) {
        memset(neuronOut, 0, sizeof(neuronOut));
        run(^(id<MTLCommandBuffer> commandBuffer) {
            MPSMatrix *in = matrixOf(&neuronSource[0][0], MPSDataTypeFloat32, 3, 4, 1, 4 * sizeof(float), 12 * sizeof(float));
            MPSMatrix *out = matrixOf(&neuronOut[0][0], MPSDataTypeFloat32, 3, 4, 1, 4 * sizeof(float), 12 * sizeof(float));
            MPSVector *b = vectorOf(neuronBias, MPSDataTypeFloat32, 4, 1, 4 * sizeof(float));
            MPSMatrixNeuron *kernel = [[MPSMatrixNeuron alloc] initWithDevice:gDevice];
            [kernel setNeuronType:gTypes[t] parameterA:1.5f parameterB:0.75f parameterC:2.5f];
            kernel.alpha = 0.5;
            [kernel encodeToCommandBuffer:commandBuffer inputMatrix:in biasVector:b resultMatrix:out];
        });
        char name[64];
        snprintf(name, sizeof(name), "neuron %d", (int)gTypes[t]);
        put(name, &neuronOut[0][0], sizeof(neuronOut));

        memset(neuronGradientData, 0, sizeof(neuronGradientData));
        memset(neuronGradientBias, 0, sizeof(neuronGradientBias));
        run(^(id<MTLCommandBuffer> commandBuffer) {
            MPSMatrix *g = matrixOf(&neuronIncoming[0][0], MPSDataTypeFloat32, 3, 4, 1, 4 * sizeof(float), 12 * sizeof(float));
            MPSMatrix *in = matrixOf(&neuronSource[0][0], MPSDataTypeFloat32, 3, 4, 1, 4 * sizeof(float), 12 * sizeof(float));
            MPSMatrix *out = matrixOf(&neuronGradientData[0][0], MPSDataTypeFloat32, 3, 4, 1, 4 * sizeof(float), 12 * sizeof(float));
            MPSVector *b = vectorOf(neuronBias, MPSDataTypeFloat32, 4, 1, 4 * sizeof(float));
            MPSVector *gb = vectorOf(neuronGradientBias, MPSDataTypeFloat32, 4, 1, 4 * sizeof(float));
            MPSMatrixNeuronGradient *kernel = [[MPSMatrixNeuronGradient alloc] initWithDevice:gDevice];
            [kernel setNeuronType:gTypes[t] parameterA:1.5f parameterB:0.75f parameterC:2.5f];
            kernel.alpha = 0.5;
            [kernel encodeToCommandBuffer:commandBuffer gradientMatrix:g inputMatrix:in biasVector:b
                 resultGradientForDataMatrix:out resultGradientForBiasVector:gb];
        });
        snprintf(name, sizeof(name), "neuron-gradient-data %d", (int)gTypes[t]);
        put(name, &neuronGradientData[0][0], sizeof(neuronGradientData));
        snprintf(name, sizeof(name), "neuron-gradient-bias %d", (int)gTypes[t]);
        put(name, neuronGradientBias, sizeof(neuronGradientBias));
    }
    memset(neuronPreluOut, 0, sizeof(neuronPreluOut));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *in = matrixOf(&neuronSource[0][0], MPSDataTypeFloat32, 3, 4, 1, 4 * sizeof(float), 12 * sizeof(float));
        MPSMatrix *out = matrixOf(&neuronPreluOut[0][0], MPSDataTypeFloat32, 3, 4, 1, 4 * sizeof(float), 12 * sizeof(float));
        MPSMatrixNeuron *kernel = [[MPSMatrixNeuron alloc] initWithDevice:gDevice];
        [kernel setNeuronToPReLUWithParametersA:[NSData dataWithBytes:neuronPreluA length:sizeof(neuronPreluA)]];
        [kernel encodeToCommandBuffer:commandBuffer inputMatrix:in biasVector:nil resultMatrix:out];
    });
    put("neuron-prelu", &neuronPreluOut[0][0], sizeof(neuronPreluOut));
}

#pragma mark - fully connected

static float fullyConnectedInput[3][2] = {{1, 2}, {3, 4}, {5, 6}};
static float fullyConnectedWeights[2][3] = {{1, -1, 0.5f}, {0.25f, 2, -3}};
static float fullyConnectedBias[3] = {0.1f, 0.2f, 0.3f};
static float fullyConnectedOut[3][3];
static float fullyConnectedIncoming[3][3] = {{1, 2, 3}, {4, 5, 6}, {7, 8, 9}};
static float fullyConnectedGradientData[3][2];
static float fullyConnectedGradientWeights[2][3];
static float fullyConnectedGradientBias[3];

static void casesFullyConnected(void)
{
    for (unsigned t = 0; t < gTypeCount; t++) {
        memset(fullyConnectedOut, 0, sizeof(fullyConnectedOut));
        run(^(id<MTLCommandBuffer> commandBuffer) {
            MPSMatrix *in = matrixOf(&fullyConnectedInput[0][0], MPSDataTypeFloat32, 3, 2, 1, 2 * sizeof(float), 6 * sizeof(float));
            MPSMatrix *w = matrixOf(&fullyConnectedWeights[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
            MPSMatrix *out = matrixOf(&fullyConnectedOut[0][0], MPSDataTypeFloat32, 3, 3, 1, 3 * sizeof(float), 9 * sizeof(float));
            MPSVector *b = vectorOf(fullyConnectedBias, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
            MPSMatrixFullyConnected *kernel = [[MPSMatrixFullyConnected alloc] initWithDevice:gDevice];
            [kernel setNeuronType:gTypes[t] parameterA:1.0f parameterB:1.0f parameterC:2.0f];
            kernel.alpha = 1.25;
            [kernel encodeToCommandBuffer:commandBuffer inputMatrix:in weightMatrix:w biasVector:b resultMatrix:out];
        });
        char name[64];
        snprintf(name, sizeof(name), "fully-connected %d", (int)gTypes[t]);
        put(name, &fullyConnectedOut[0][0], sizeof(fullyConnectedOut));
    }
    memset(fullyConnectedGradientData, 0, sizeof(fullyConnectedGradientData));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *g = matrixOf(&fullyConnectedIncoming[0][0], MPSDataTypeFloat32, 3, 3, 1, 3 * sizeof(float), 9 * sizeof(float));
        MPSMatrix *w = matrixOf(&fullyConnectedWeights[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
        MPSMatrix *out = matrixOf(&fullyConnectedGradientData[0][0], MPSDataTypeFloat32, 3, 2, 1, 2 * sizeof(float), 6 * sizeof(float));
        MPSMatrixFullyConnectedGradient *kernel = [[MPSMatrixFullyConnectedGradient alloc] initWithDevice:gDevice];
        kernel.alpha = 1.25;
        [kernel encodeGradientForDataToCommandBuffer:commandBuffer gradientMatrix:g weightMatrix:w resultGradientForDataMatrix:out];
    });
    put("fully-connected-gradient-data", &fullyConnectedGradientData[0][0], sizeof(fullyConnectedGradientData));

    memset(fullyConnectedGradientWeights, 0, sizeof(fullyConnectedGradientWeights));
    memset(fullyConnectedGradientBias, 0, sizeof(fullyConnectedGradientBias));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *g = matrixOf(&fullyConnectedIncoming[0][0], MPSDataTypeFloat32, 3, 3, 1, 3 * sizeof(float), 9 * sizeof(float));
        MPSMatrix *in = matrixOf(&fullyConnectedInput[0][0], MPSDataTypeFloat32, 3, 2, 1, 2 * sizeof(float), 6 * sizeof(float));
        MPSMatrix *gw = matrixOf(&fullyConnectedGradientWeights[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
        MPSVector *gb = vectorOf(fullyConnectedGradientBias, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
        MPSMatrixFullyConnectedGradient *kernel = [[MPSMatrixFullyConnectedGradient alloc] initWithDevice:gDevice];
        kernel.alpha = 1.25;
        [kernel encodeGradientForWeightsAndBiasToCommandBuffer:commandBuffer gradientMatrix:g inputMatrix:in
                              resultGradientForWeightMatrix:gw resultGradientForBiasVector:gb];
    });
    put("fully-connected-gradient-weights", &fullyConnectedGradientWeights[0][0], sizeof(fullyConnectedGradientWeights));
    put("fully-connected-gradient-bias", fullyConnectedGradientBias, sizeof(fullyConnectedGradientBias));
}

#pragma mark - batch normalization

static float normSource[4][3] = {{1, 2, 3}, {4, 5, 7}, {2, 8, 1}, {9, 1, 5}};
static float normMean[3];
static float normVariance[3];
static float normGamma[3] = {1.5f, 0.75f, 2.0f};
static float normBeta[3] = {0.5f, -0.5f, 1.0f};
static float normGivenMean[3] = {4, 5, 4};
static float normGivenVariance[3] = {8, 6, 6};
static float normOut[4][3];
static float normIncoming[4][3] = {{1, 2, 3}, {4, 5, 7}, {2, 8, 1}, {9, 1, 5}};
static float normGradientData[4][3];
static float normGradientGamma[3];
static float normGradientBeta[3];

static void casesBatchNormalization(void)
{
    for (unsigned t = 0; t < gTypeCount; t++) {
        memset(normOut, 0, sizeof(normOut));
        run(^(id<MTLCommandBuffer> commandBuffer) {
            MPSMatrix *in = matrixOf(&normSource[0][0], MPSDataTypeFloat32, 4, 3, 1, 3 * sizeof(float), 12 * sizeof(float));
            MPSMatrix *out = matrixOf(&normOut[0][0], MPSDataTypeFloat32, 4, 3, 1, 3 * sizeof(float), 12 * sizeof(float));
            MPSVector *m = vectorOf(normGivenMean, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
            MPSVector *v = vectorOf(normGivenVariance, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
            MPSVector *g = vectorOf(normGamma, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
            MPSVector *b = vectorOf(normBeta, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
            MPSMatrixBatchNormalization *kernel = [[MPSMatrixBatchNormalization alloc] initWithDevice:gDevice];
            [kernel setNeuronType:gTypes[t] parameterA:1.0f parameterB:1.0f parameterC:2.0f];
            kernel.epsilon = 0.001f;
            [kernel encodeToCommandBuffer:commandBuffer inputMatrix:in meanVector:m varianceVector:v gammaVector:g betaVector:b resultMatrix:out];
        });
        char name[64];
        snprintf(name, sizeof(name), "batch-normalization %d", (int)gTypes[t]);
        put(name, &normOut[0][0], sizeof(normOut));
    }
    memset(normMean, 0, sizeof(normMean));
    memset(normVariance, 0, sizeof(normVariance));
    memset(normOut, 0, sizeof(normOut));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *in = matrixOf(&normSource[0][0], MPSDataTypeFloat32, 4, 3, 1, 3 * sizeof(float), 12 * sizeof(float));
        MPSMatrix *out = matrixOf(&normOut[0][0], MPSDataTypeFloat32, 4, 3, 1, 3 * sizeof(float), 12 * sizeof(float));
        MPSVector *m = vectorOf(normMean, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
        MPSVector *v = vectorOf(normVariance, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
        MPSMatrixBatchNormalization *kernel = [[MPSMatrixBatchNormalization alloc] initWithDevice:gDevice];
        kernel.epsilon = 0.001f;
        kernel.computeStatistics = YES;
        [kernel encodeToCommandBuffer:commandBuffer inputMatrix:in meanVector:m varianceVector:v gammaVector:nil betaVector:nil resultMatrix:out];
    });
    put("batch-normalization-statistics-mean", normMean, sizeof(normMean));
    put("batch-normalization-statistics-variance", normVariance, sizeof(normVariance));
    put("batch-normalization-statistics-result", &normOut[0][0], sizeof(normOut));

    memset(normGradientData, 0, sizeof(normGradientData));
    memset(normGradientGamma, 0, sizeof(normGradientGamma));
    memset(normGradientBeta, 0, sizeof(normGradientBeta));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *g = matrixOf(&normIncoming[0][0], MPSDataTypeFloat32, 4, 3, 1, 3 * sizeof(float), 12 * sizeof(float));
        MPSMatrix *in = matrixOf(&normSource[0][0], MPSDataTypeFloat32, 4, 3, 1, 3 * sizeof(float), 12 * sizeof(float));
        MPSMatrix *out = matrixOf(&normGradientData[0][0], MPSDataTypeFloat32, 4, 3, 1, 3 * sizeof(float), 12 * sizeof(float));
        MPSVector *m = vectorOf(normGivenMean, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
        MPSVector *v = vectorOf(normGivenVariance, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
        MPSVector *gm = vectorOf(normGamma, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
        MPSVector *gg = vectorOf(normGradientGamma, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
        MPSVector *gb = vectorOf(normGradientBeta, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
        MPSMatrixBatchNormalizationGradient *kernel = [[MPSMatrixBatchNormalizationGradient alloc] initWithDevice:gDevice];
        kernel.epsilon = 0.001f;
        [kernel encodeToCommandBuffer:commandBuffer gradientMatrix:g inputMatrix:in meanVector:m varianceVector:v
                  gammaVector:gm betaVector:nil resultGradientForDataMatrix:out
             resultGradientForGammaVector:gg resultGradientForBetaVector:gb];
    });
    put("batch-normalization-gradient-data", &normGradientData[0][0], sizeof(normGradientData));
    put("batch-normalization-gradient-gamma", normGradientGamma, sizeof(normGradientGamma));
    put("batch-normalization-gradient-beta", normGradientBeta, sizeof(normGradientBeta));
}

#pragma mark - sum

static float sumFirst[3][4] = {{1, 2, 3, 10}, {4, 5, 6, 11}, {7, 8, 9, 12}};
static float sumSecond[3][4] = {{0.5f, -1, 2, 20}, {1, 1, 1, 21}, {-2, 0, 0.5f, 22}};
static float sumThird[3][3] = {{-2, 0, 0.5f}, {0, 0, 0}, {1, 1, 1}};
static float sumScale[3] = {1, 2, 0.5f};
static float sumBias[3] = {0.25f, -0.5f, 1};
static float sumOut[2][3];
static MPSMatrixOffset sumOffsets[2] = {{1, 0}, {0, 1}};

static void casesSum(void)
{
    for (unsigned t = 0; t < gTypeCount; t++) {
        memset(sumOut, 0, sizeof(sumOut));
        run(^(id<MTLCommandBuffer> commandBuffer) {
            MPSMatrix *a = matrixOf(&sumFirst[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
            MPSMatrix *b = matrixOf(&sumSecond[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
            MPSMatrix *c = matrixOf(&sumThird[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
            MPSMatrix *out = matrixOf(&sumOut[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
            MPSVector *s = vectorOf(sumScale, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
            MPSVector *bv = vectorOf(sumBias, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
            MPSMatrixSum *kernel = [[MPSMatrixSum alloc] initWithDevice:gDevice count:3 rows:2 columns:3 transpose:NO];
            [kernel setNeuronType:gTypes[t] parameterA:1.0f parameterB:1.0f parameterC:2.0f];
            [kernel encodeToCommandBuffer:commandBuffer sourceMatrices:@[a, b, c] resultMatrix:out
                                scaleVector:s offsetVector:nil biasVector:bv startIndex:0];
        });
        char name[64];
        snprintf(name, sizeof(name), "sum %d", (int)gTypes[t]);
        put(name, &sumOut[0][0], sizeof(sumOut));
    }
    memset(sumOut, 0, sizeof(sumOut));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *a = matrixOf(&sumFirst[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
        MPSMatrix *b = matrixOf(&sumSecond[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
        MPSMatrix *out = matrixOf(&sumOut[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
        MPSVector *s = vectorOf(sumScale, MPSDataTypeFloat32, 3, 1, 3 * sizeof(float));
        MPSMatrixSum *kernel = [[MPSMatrixSum alloc] initWithDevice:gDevice count:2 rows:2 columns:3 transpose:NO];
        [kernel encodeToCommandBuffer:commandBuffer sourceMatrices:@[a, b] resultMatrix:out scaleVector:s offsetVector:nil biasVector:nil startIndex:1];
    });
    put("sum-start-index", &sumOut[0][0], sizeof(sumOut));

    memset(sumOut, 0, sizeof(sumOut));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSMatrix *a = matrixOf(&sumFirst[0][0], MPSDataTypeFloat32, 3, 4, 1, 4 * sizeof(float), 12 * sizeof(float));
        MPSMatrix *out = matrixOf(&sumOut[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
        // The release requires at least two matrices to sum, so the transposed source is given twice.
        MPSMatrixSum *kernel = [[MPSMatrixSum alloc] initWithDevice:gDevice count:2 rows:2 columns:3 transpose:YES];
        [kernel encodeToCommandBuffer:commandBuffer sourceMatrices:@[a, a] resultMatrix:out scaleVector:nil offsetVector:nil biasVector:nil startIndex:0];
    });
    put("sum-transpose", &sumOut[0][0], sizeof(sumOut));

    memset(sumOut, 0, sizeof(sumOut));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        // A two by three window read from each of two four column sources, the second from column one,
        // which is where the offset vector's second entry puts it.
        MPSMatrix *a = matrixOf(&sumFirst[0][0], MPSDataTypeFloat32, 3, 4, 1, 4 * sizeof(float), 12 * sizeof(float));
        MPSMatrix *b = matrixOf(&sumSecond[0][0], MPSDataTypeFloat32, 3, 4, 1, 4 * sizeof(float), 12 * sizeof(float));
        MPSMatrix *out = matrixOf(&sumOut[0][0], MPSDataTypeFloat32, 2, 3, 1, 3 * sizeof(float), 6 * sizeof(float));
        MPSVector *o = vectorOf(sumOffsets, MPSDataTypeUInt32, 4, 1, 4 * sizeof(uint32_t));
        MPSMatrixSum *kernel = [[MPSMatrixSum alloc] initWithDevice:gDevice count:2 rows:2 columns:3 transpose:NO];
        [kernel encodeToCommandBuffer:commandBuffer sourceMatrices:@[a, b] resultMatrix:out scaleVector:nil offsetVector:o biasVector:nil startIndex:0];
    });
    put("sum-offsets", &sumOut[0][0], sizeof(sumOut));
}

#pragma mark - states, predicates and command buffers

static void casesState(void)
{
    MPSState *state = [[MPSState alloc] initWithResource:[gDevice newBufferWithLength:64 options:MTLResourceStorageModeShared]];
    printf("state %lu %d %lu\n", (unsigned long)state.resourceCount, (int)[state resourceTypeAtIndex:0], (unsigned long)[state bufferSizeAtIndex:0]);
    printf("state-is-temporary %d\n", (int)state.isTemporary);
    printf("divergent state-size %lu\n", (unsigned long)[state resourceSize]);
    MPSState *fromBuffer = [[MPSState alloc] initWithDevice:gDevice bufferSize:128];
    printf("state-buffer %lu %d %lu\n", (unsigned long)fromBuffer.resourceCount, (int)[fromBuffer resourceTypeAtIndex:0],
           (unsigned long)[fromBuffer bufferSizeAtIndex:0]);
    printf("state-lazy %d\n", [fromBuffer resourceAtIndex:0 allocateMemory:NO] == nil);
    printf("state-allocated %d\n", [fromBuffer resourceAtIndex:0 allocateMemory:YES] != nil);
    MPSStateResourceList *list = [MPSStateResourceList resourceListWithBufferSizes:32, 64, 128, nil];
    MPSState *fromList = [[MPSState alloc] initWithDevice:gDevice resourceList:list];
    printf("state-list %lu %lu %lu\n", (unsigned long)fromList.resourceCount, (unsigned long)[fromList bufferSizeAtIndex:0], (unsigned long)[fromList bufferSizeAtIndex:2]);
    NSArray<MPSState *> *batch = @[state, fromBuffer, fromList];
    printf("divergent state-batch-size %lu\n", MPSStateBatchResourceSize(batch));
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSStateBatchSynchronize(batch, commandBuffer);
    });
    printf("state-batch-synchronized 1\n");

    // The read count belongs to a temporary state: the release asserts on adjusting one that is not
    // temporary, so the batch's read counts are read from temporaries made against a command buffer.
    run(^(id<MTLCommandBuffer> commandBuffer) {
        MPSState *a = [MPSState temporaryStateWithCommandBuffer:commandBuffer bufferSize:32];
        MPSState *b = [MPSState temporaryStateWithCommandBuffer:commandBuffer bufferSize:64];
        MPSState *c = [MPSState temporaryStateWithCommandBuffer:commandBuffer bufferSize:96];
        printf("temporary %d %d %d\n", (int)a.isTemporary, (int)b.isTemporary, (int)c.isTemporary);
        printf("temporary-read-count %lu %lu %lu\n", (unsigned long)a.readCount, (unsigned long)b.readCount, (unsigned long)c.readCount);
        NSArray<MPSState *> *temporaries = @[a, b, c];
        // Up by two, then down by one: the release asserts on a decrement that would take a count
        // below zero, so the case stays inside the range a read count can take.
        // The function's answer is the size of the batch, whatever it did to the counts: three states
        // answer three both times. The counts themselves are printed around it.
        printf("temporary-batch-up %lu\n", MPSStateBatchIncrementReadCount(temporaries, 2));
        printf("temporary-counts-up %lu %lu %lu\n", (unsigned long)a.readCount, (unsigned long)b.readCount, (unsigned long)c.readCount);
        printf("temporary-batch-down %lu\n", MPSStateBatchIncrementReadCount(temporaries, -1));
        printf("temporary-counts-down %lu %lu %lu\n", (unsigned long)a.readCount, (unsigned long)b.readCount, (unsigned long)c.readCount);
        // Synchronizing a temporary is not a case the release accepts: a temporary's storage is not
        // readable from the CPU, which is the whole of what synchronizing is for.
    });

    uint32_t predicate = 7;
    id<MTLBuffer> predicateBuffer = [gDevice newBufferWithBytes:&predicate length:4 options:MTLResourceStorageModeShared];
    MPSPredicate *yes = [MPSPredicate predicateWithBuffer:predicateBuffer offset:0];
    printf("predicate %lu %lu\n", (unsigned long)yes.predicateOffset, (unsigned long)yes.predicateBuffer.length);
    id<MTLCommandBuffer> buffer = freshCommandBuffer();
    MPSCommandBuffer *wrapped = [MPSCommandBuffer commandBufferWithCommandBuffer:buffer];
    wrapped.predicate = yes;
    printf("command-buffer %d %d\n", wrapped.commandBuffer == buffer, wrapped.predicate == yes);
    printf("root-command-buffer %d\n", wrapped.rootCommandBuffer == buffer);
    [wrapped prefetchHeapForWorkloadSize:1024];
    [buffer commit];
    [buffer waitUntilCompleted];
}

int main(void)
{
    @autoreleasepool {
        gDevice = MTLCreateSystemDefaultDevice();
        if (!gDevice) {
            printf("no device\n");
            return 1;
        }
        printf("device %d\n", MPSSupportsMTLDevice(gDevice));
        casesDevice();
        casesDescriptors();
        casesMultiplication();
        casesVectorMultiplication();
        casesCopy();
        casesSoftMax();
        casesNeuron();
        casesFullyConnected();
        casesBatchNormalization();
        casesSum();
        casesState();
    }
    return 0;
}
