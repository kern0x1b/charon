// The neural-network matrix kernels: MPSMatrixNeuron and its gradient, MPSMatrixFullyConnected and its
// gradient, MPSMatrixBatchNormalization and its gradient, and MPSMatrixSum.

#import "CharonMPS.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

// The state every one of these classes holds: the neuron its header names, the three scalars that go
// with it, the per-channel array a PReLU's A lives in, the feature vector and channel counts, and the
// scale. The categories above hand this to the shared arithmetic; the accessors are per class because
// each header declares its own members.
#define CHARON_MPS_NEURON_IVARS \
    MPSCNNNeuronType _neuronType; \
    float _neuronParameterA, _neuronParameterB, _neuronParameterC; \
    NSData *_neuronPrelu;

#define CHARON_MPS_NEURON_COMMON \
    - (CharonMPSNeuron)charon_mps_neuron \
    { \
        CharonMPSNeuron neuron; \
        neuron.type = _neuronType; \
        neuron.a = _neuronParameterA; \
        neuron.b = _neuronParameterB; \
        neuron.c = _neuronParameterC; \
        neuron.prelu = (const float *)_neuronPrelu.bytes; \
        neuron.channels = _neuronPrelu.length / sizeof(float); \
        return neuron; \
    } \
    - (void)setNeuronType:(MPSCNNNeuronType)neuronType parameterA:(float)parameterA parameterB:(float)parameterB parameterC:(float)parameterC \
    { \
        _neuronType = neuronType; \
        _neuronParameterA = parameterA; \
        _neuronParameterB = parameterB; \
        _neuronParameterC = parameterC; \
    } \
    - (void)setNeuronToPReLUWithParametersA:(NSData *)A \
    { \
        _neuronType = MPSCNNNeuronTypePReLU; \
        _neuronPrelu = [A copy]; \
    } \
    - (MPSCNNNeuronType)neuronType \
    { \
        return _neuronType; \
    } \
    - (float)neuronParameterA \
    { \
        return _neuronParameterA; \
    } \
    - (float)neuronParameterB \
    { \
        return _neuronParameterB; \
    } \
    - (float)neuronParameterC \
    { \
        return _neuronParameterC; \
    }

@implementation MPSMatrixNeuron {
    CHARON_MPS_NEURON_IVARS
    NSUInteger _sourceNumberOfFeatureVectors, _sourceInputFeatureChannels;
    double _alpha;
    MTLOrigin _sourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

CHARON_MPS_NEURON_COMMON

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _neuronType = MPSCNNNeuronTypeNone;
        _sourceNumberOfFeatureVectors = NSUIntegerMax;
        _sourceInputFeatureChannels = NSUIntegerMax;
        _alpha = 1.0;
    }
    return self;
}

- (NSUInteger)sourceNumberOfFeatureVectors
{
    return _sourceNumberOfFeatureVectors;
}

- (void)setSourceNumberOfFeatureVectors:(NSUInteger)count
{
    _sourceNumberOfFeatureVectors = count;
}

- (NSUInteger)sourceInputFeatureChannels
{
    return _sourceInputFeatureChannels;
}

- (void)setSourceInputFeatureChannels:(NSUInteger)channels
{
    _sourceInputFeatureChannels = channels;
}

- (double)alpha
{
    return _alpha;
}

- (void)setAlpha:(double)alpha
{
    _alpha = alpha;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  inputMatrix:(MPSMatrix *)inputMatrix
                   biasVector:(MPSVector *)biasVector
                 resultMatrix:(MPSMatrix *)resultMatrix
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView in = CharonMPSMatrixViewOf(inputMatrix), out = CharonMPSMatrixViewOf(resultMatrix);
    if (!CharonMPSDataTypeIsElement(in.dataType) || !CharonMPSDataTypeIsElement(out.dataType)) {
        CharonMPSRefuse(@"MPSMatrixNeuron: a matrix of a data type that is not one of the eight element types was given");
        return;
    }
    // y = neuron(alpha * x + bias), the bias broadcast across the rows and indexed by the column, which
    // is the channel. The counts are the header's: as many feature vectors and channels as the matrix
    // holds from the source origin, and no more than the caller asked for.
    NSUInteger available = in.rows - _sourceMatrixOrigin.x;
    NSUInteger vectors = _sourceNumberOfFeatureVectors < available ? _sourceNumberOfFeatureVectors : available;
    NSUInteger columns = in.columns - _sourceMatrixOrigin.y;
    NSUInteger channels = _sourceInputFeatureChannels < columns ? _sourceInputFeatureChannels : columns;
    CharonMPSVectorView bias = {0, 0, 0, 0, 0, 0};
    if (biasVector)
        bias = CharonMPSVectorViewOf(biasVector);
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, in.matrices, &start, &count);
    count = count < out.matrices ? count : out.matrices;
    for (NSUInteger b = start; b < start + count; b++) {
        if (!CharonMPSMatrixHolds(&in, b, _sourceMatrixOrigin.x, _sourceMatrixOrigin.y, vectors, channels) ||
            !CharonMPSMatrixHolds(&out, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, vectors, channels)) {
            CharonMPSRefuse(@"MPSMatrixNeuron: a matrix of the batch [%lu, %lu) does not hold the %lux%lu region its origin names", (unsigned long)start, (unsigned long)(start + count), (unsigned long)vectors, (unsigned long)channels);
            return;
        }
    }
    CharonMPSNeuron neuron = [self charon_mps_neuron];
    for (NSUInteger b = start; b < start + count; b++) {
        for (NSUInteger row = 0; row < vectors; row++) {
            for (NSUInteger column = 0; column < channels; column++) {
                double x = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _sourceMatrixOrigin.x + row, _sourceMatrixOrigin.y + column), in.dataType, 0);
                double b0 = bias.length > column ? CharonMPSLoad(CharonMPSVectorElement(&bias, 0, column), bias.dataType, 0) : 0.0;
                double y = CharonMPSApplyNeuron(neuron.type, _alpha * x + b0, neuron.a, neuron.b, neuron.c, CharonMPSNeuronA(&neuron, column));
                CharonMPSStore(CharonMPSMatrixElement(&out, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + column), out.dataType, 0, y);
            }
        }
    }
    CharonMPSConsumeReadCount(inputMatrix);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (instancetype)copyWithZone:(NSZone *)zone device:(id<MTLDevice>)device
{
    MPSMatrixNeuron *copy = [super copyWithZone:zone device:device];
    copy->_neuronType = _neuronType;
    copy->_neuronParameterA = _neuronParameterA;
    copy->_neuronParameterB = _neuronParameterB;
    copy->_neuronParameterC = _neuronParameterC;
    copy->_neuronPrelu = _neuronPrelu;
    copy->_sourceNumberOfFeatureVectors = _sourceNumberOfFeatureVectors;
    copy->_sourceInputFeatureChannels = _sourceInputFeatureChannels;
    copy->_alpha = _alpha;
    return copy;
}

@end

@implementation MPSMatrixNeuronGradient {
    CHARON_MPS_NEURON_IVARS
    NSUInteger _sourceNumberOfFeatureVectors, _sourceInputFeatureChannels;
    double _alpha;
    MTLOrigin _primarySourceMatrixOrigin, _secondarySourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

CHARON_MPS_NEURON_COMMON

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _neuronType = MPSCNNNeuronTypeNone;
        _sourceNumberOfFeatureVectors = NSUIntegerMax;
        _sourceInputFeatureChannels = NSUIntegerMax;
        _alpha = 1.0;
    }
    return self;
}

- (NSUInteger)sourceNumberOfFeatureVectors
{
    return _sourceNumberOfFeatureVectors;
}

- (void)setSourceNumberOfFeatureVectors:(NSUInteger)count
{
    _sourceNumberOfFeatureVectors = count;
}

- (NSUInteger)sourceInputFeatureChannels
{
    return _sourceInputFeatureChannels;
}

- (void)setSourceInputFeatureChannels:(NSUInteger)channels
{
    _sourceInputFeatureChannels = channels;
}

- (double)alpha
{
    return _alpha;
}

- (void)setAlpha:(double)alpha
{
    _alpha = alpha;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                gradientMatrix:(MPSMatrix *)gradientMatrix
                   inputMatrix:(MPSMatrix *)inputMatrix
                    biasVector:(MPSVector *)biasVector
  resultGradientForDataMatrix:(MPSMatrix *)resultGradientForDataMatrix
  resultGradientForBiasVector:(MPSVector *)resultGradientForBiasVector
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView gradient = CharonMPSMatrixViewOf(gradientMatrix), in = CharonMPSMatrixViewOf(inputMatrix), out = CharonMPSMatrixViewOf(resultGradientForDataMatrix);
    if (!CharonMPSDataTypeIsElement(gradient.dataType) || !CharonMPSDataTypeIsElement(in.dataType) || !CharonMPSDataTypeIsElement(out.dataType)) {
        CharonMPSRefuse(@"MPSMatrixNeuronGradient: a matrix of a data type that is not one of the eight element types was given");
        return;
    }
    // The gradient of y = neuron(alpha * x + bias) with respect to x is the neuron's own derivative at
    // the intermediate value, times alpha; with respect to the bias it is the incoming gradient itself.
    NSUInteger available = in.rows - _secondarySourceMatrixOrigin.x;
    NSUInteger vectors = _sourceNumberOfFeatureVectors < available ? _sourceNumberOfFeatureVectors : available;
    NSUInteger columns = in.columns - _secondarySourceMatrixOrigin.y;
    NSUInteger channels = _sourceInputFeatureChannels < columns ? _sourceInputFeatureChannels : columns;
    CharonMPSVectorView bias = {0, 0, 0, 0, 0, 0}, biasGradient = {0, 0, 0, 0, 0, 0};
    if (biasVector)
        bias = CharonMPSVectorViewOf(biasVector);
    if (resultGradientForBiasVector)
        biasGradient = CharonMPSVectorViewOf(resultGradientForBiasVector);
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, in.matrices, &start, &count);
    count = count < gradient.matrices ? count : gradient.matrices;
    count = count < out.matrices ? count : out.matrices;
    for (NSUInteger b = start; b < start + count; b++) {
        if (!CharonMPSMatrixHolds(&gradient, b, _primarySourceMatrixOrigin.x, _primarySourceMatrixOrigin.y, vectors, channels) ||
            !CharonMPSMatrixHolds(&in, b, _secondarySourceMatrixOrigin.x, _secondarySourceMatrixOrigin.y, vectors, channels) ||
            !CharonMPSMatrixHolds(&out, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, vectors, channels)) {
            CharonMPSRefuse(@"MPSMatrixNeuronGradient: a matrix of the batch [%lu, %lu) does not hold the %lux%lu region its origin names", (unsigned long)start, (unsigned long)(start + count), (unsigned long)vectors, (unsigned long)channels);
            return;
        }
    }
    CharonMPSNeuron neuron = [self charon_mps_neuron];
    for (NSUInteger b = start; b < start + count; b++) {
        for (NSUInteger column = 0; column < channels; column++) {
            double total = 0.0;
            for (NSUInteger row = 0; row < vectors; row++) {
                total += CharonMPSLoad(CharonMPSMatrixElement(&gradient, b, _primarySourceMatrixOrigin.x + row, _primarySourceMatrixOrigin.y + column), gradient.dataType, 0);
            }
            if (biasGradient.length > column)
                CharonMPSStore(CharonMPSVectorElement(&biasGradient, 0, column), biasGradient.dataType, 0, total);
        }
        for (NSUInteger row = 0; row < vectors; row++) {
            for (NSUInteger column = 0; column < channels; column++) {
                double g = CharonMPSLoad(CharonMPSMatrixElement(&gradient, b, _primarySourceMatrixOrigin.x + row, _primarySourceMatrixOrigin.y + column), gradient.dataType, 0);
                double x = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _secondarySourceMatrixOrigin.x + row, _secondarySourceMatrixOrigin.y + column), in.dataType, 0);
                double b0 = bias.length > column ? CharonMPSLoad(CharonMPSVectorElement(&bias, 0, column), bias.dataType, 0) : 0.0;
                double intermediate = _alpha * x + b0;
                double y = CharonMPSApplyNeuron(neuron.type, intermediate, neuron.a, neuron.b, neuron.c, CharonMPSNeuronA(&neuron, column));
                double d = CharonMPSApplyNeuronGradient(neuron.type, intermediate, y, neuron.a, neuron.b, neuron.c, CharonMPSNeuronA(&neuron, column));
                CharonMPSStore(CharonMPSMatrixElement(&out, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + column), out.dataType, 0, g * d * _alpha);
            }
        }
    }
    CharonMPSConsumeReadCount(gradientMatrix);
    CharonMPSConsumeReadCount(inputMatrix);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (instancetype)copyWithZone:(NSZone *)zone device:(id<MTLDevice>)device
{
    MPSMatrixNeuronGradient *copy = [super copyWithZone:zone device:device];
    copy->_neuronType = _neuronType;
    copy->_neuronParameterA = _neuronParameterA;
    copy->_neuronParameterB = _neuronParameterB;
    copy->_neuronParameterC = _neuronParameterC;
    copy->_neuronPrelu = _neuronPrelu;
    copy->_alpha = _alpha;
    return copy;
}

@end

@implementation MPSMatrixFullyConnected {
    CHARON_MPS_NEURON_IVARS
    NSUInteger _sourceNumberOfFeatureVectors, _sourceInputFeatureChannels, _sourceOutputFeatureChannels;
    double _alpha;
    MTLOrigin _primarySourceMatrixOrigin, _secondarySourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

CHARON_MPS_NEURON_COMMON

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _neuronType = MPSCNNNeuronTypeNone;
        _sourceNumberOfFeatureVectors = NSUIntegerMax;
        _sourceInputFeatureChannels = NSUIntegerMax;
        _sourceOutputFeatureChannels = NSUIntegerMax;
        _alpha = 1.0;
    }
    return self;
}

- (NSUInteger)sourceNumberOfFeatureVectors { return _sourceNumberOfFeatureVectors; }
- (void)setSourceNumberOfFeatureVectors:(NSUInteger)count { _sourceNumberOfFeatureVectors = count; }
- (NSUInteger)sourceInputFeatureChannels { return _sourceInputFeatureChannels; }
- (void)setSourceInputFeatureChannels:(NSUInteger)channels { _sourceInputFeatureChannels = channels; }
- (NSUInteger)sourceOutputFeatureChannels { return _sourceOutputFeatureChannels; }
- (void)setSourceOutputFeatureChannels:(NSUInteger)channels { _sourceOutputFeatureChannels = channels; }
- (double)alpha { return _alpha; }
- (void)setAlpha:(double)alpha { _alpha = alpha; }

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  inputMatrix:(MPSMatrix *)inputMatrix
                 weightMatrix:(MPSMatrix *)weightMatrix
                   biasVector:(MPSVector *)biasVector
                 resultMatrix:(MPSMatrix *)resultMatrix
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView in = CharonMPSMatrixViewOf(inputMatrix), weights = CharonMPSMatrixViewOf(weightMatrix), out = CharonMPSMatrixViewOf(resultMatrix);
    if (!CharonMPSDataTypeIsElement(in.dataType) || !CharonMPSDataTypeIsElement(weights.dataType) || !CharonMPSDataTypeIsElement(out.dataType)) {
        CharonMPSRefuse(@"MPSMatrixFullyConnected: a matrix of a data type that is not one of the eight element types was given");
        return;
    }
    // y = neuron(alpha * x * W + bias). The input holds one feature vector per row, the weight matrix
    // is inputFeatureChannels x outputFeatureChannels, and the bias is indexed by the output channel.
    NSUInteger vectorsAvailable = in.rows - _primarySourceMatrixOrigin.x;
    NSUInteger vectors = _sourceNumberOfFeatureVectors < vectorsAvailable ? _sourceNumberOfFeatureVectors : vectorsAvailable;
    NSUInteger inputsAvailable = in.columns - _primarySourceMatrixOrigin.y;
    NSUInteger inputs = _sourceInputFeatureChannels < inputsAvailable ? _sourceInputFeatureChannels : inputsAvailable;
    NSUInteger outputs = _sourceOutputFeatureChannels < weights.columns ? _sourceOutputFeatureChannels : weights.columns;
    CharonMPSVectorView bias = {0, 0, 0, 0, 0, 0};
    if (biasVector)
        bias = CharonMPSVectorViewOf(biasVector);
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, in.matrices, &start, &count);
    count = count < out.matrices ? count : out.matrices;
    for (NSUInteger b = start; b < start + count; b++) {
        if (!CharonMPSMatrixHolds(&in, b, _primarySourceMatrixOrigin.x, _primarySourceMatrixOrigin.y, vectors, inputs) ||
            !CharonMPSMatrixHolds(&weights, b, _secondarySourceMatrixOrigin.x, _secondarySourceMatrixOrigin.y, inputs, outputs) ||
            !CharonMPSMatrixHolds(&out, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, vectors, outputs)) {
            CharonMPSRefuse(@"MPSMatrixFullyConnected: a matrix of the batch [%lu, %lu) does not hold the %lux%lu, %lux%lu, %lux%lu region its origin names", (unsigned long)start, (unsigned long)(start + count), (unsigned long)vectors, (unsigned long)inputs, (unsigned long)inputs, (unsigned long)outputs, (unsigned long)vectors, (unsigned long)outputs);
            return;
        }
    }
    CharonMPSNeuron neuron = [self charon_mps_neuron];
    for (NSUInteger b = start; b < start + count; b++) {
        for (NSUInteger row = 0; row < vectors; row++) {
            for (NSUInteger column = 0; column < outputs; column++) {
                double sum = 0.0;
                for (NSUInteger k = 0; k < inputs; k++) {
                    double x = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _primarySourceMatrixOrigin.x + row, _primarySourceMatrixOrigin.y + k), in.dataType, 0);
                    double w = CharonMPSLoad(CharonMPSMatrixElement(&weights, b, _secondarySourceMatrixOrigin.x + k, _secondarySourceMatrixOrigin.y + column), weights.dataType, 0);
                    sum += x * w;
                }
                double b0 = bias.length > column ? CharonMPSLoad(CharonMPSVectorElement(&bias, 0, column), bias.dataType, 0) : 0.0;
                double y = CharonMPSApplyNeuron(neuron.type, _alpha * sum + b0, neuron.a, neuron.b, neuron.c, CharonMPSNeuronA(&neuron, column));
                CharonMPSStore(CharonMPSMatrixElement(&out, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + column), out.dataType, 0, y);
            }
        }
    }
    CharonMPSConsumeReadCount(inputMatrix);
    CharonMPSConsumeReadCount(weightMatrix);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (instancetype)copyWithZone:(NSZone *)zone device:(id<MTLDevice>)device
{
    MPSMatrixFullyConnected *copy = [super copyWithZone:zone device:device];
    copy->_neuronType = _neuronType;
    copy->_neuronPrelu = _neuronPrelu;
    copy->_alpha = _alpha;
    copy->_sourceNumberOfFeatureVectors = _sourceNumberOfFeatureVectors;
    copy->_sourceInputFeatureChannels = _sourceInputFeatureChannels;
    copy->_sourceOutputFeatureChannels = _sourceOutputFeatureChannels;
    return copy;
}

@end

@implementation MPSMatrixFullyConnectedGradient {
    CHARON_MPS_NEURON_IVARS
    NSUInteger _sourceNumberOfFeatureVectors, _sourceInputFeatureChannels, _sourceOutputFeatureChannels;
    double _alpha;
    MTLOrigin _primarySourceMatrixOrigin, _secondarySourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

CHARON_MPS_NEURON_COMMON

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _neuronType = MPSCNNNeuronTypeNone;
        _sourceNumberOfFeatureVectors = NSUIntegerMax;
        _sourceInputFeatureChannels = NSUIntegerMax;
        _sourceOutputFeatureChannels = NSUIntegerMax;
        _alpha = 1.0;
    }
    return self;
}

- (NSUInteger)sourceNumberOfFeatureVectors { return _sourceNumberOfFeatureVectors; }
- (void)setSourceNumberOfFeatureVectors:(NSUInteger)count { _sourceNumberOfFeatureVectors = count; }
- (NSUInteger)sourceInputFeatureChannels { return _sourceInputFeatureChannels; }
- (void)setSourceInputFeatureChannels:(NSUInteger)channels { _sourceInputFeatureChannels = channels; }
- (NSUInteger)sourceOutputFeatureChannels { return _sourceOutputFeatureChannels; }
- (void)setSourceOutputFeatureChannels:(NSUInteger)channels { _sourceOutputFeatureChannels = channels; }
- (double)alpha { return _alpha; }
- (void)setAlpha:(double)alpha { _alpha = alpha; }

- (void)encodeGradientForDataToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                              gradientMatrix:(MPSMatrix *)gradientMatrix
                                weightMatrix:(MPSMatrix *)weightMatrix
                 resultGradientForDataMatrix:(MPSMatrix *)resultGradientForDataMatrix
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView gradient = CharonMPSMatrixViewOf(gradientMatrix), weights = CharonMPSMatrixViewOf(weightMatrix), out = CharonMPSMatrixViewOf(resultGradientForDataMatrix);
    if (!CharonMPSDataTypeIsElement(gradient.dataType) || !CharonMPSDataTypeIsElement(weights.dataType) || !CharonMPSDataTypeIsElement(out.dataType)) {
        CharonMPSRefuse(@"MPSMatrixFullyConnectedGradient: a matrix of a data type that is not one of the eight element types was given");
        return;
    }
    // The gradient with respect to the input of y = alpha * x * W + bias is dX = alpha * dY * W^T: each
    // input channel's gradient is the incoming gradient of every output channel scaled by that weight.
    NSUInteger vectors = _sourceNumberOfFeatureVectors < gradient.rows ? _sourceNumberOfFeatureVectors : gradient.rows;
    NSUInteger outputs = _sourceOutputFeatureChannels < gradient.columns ? _sourceOutputFeatureChannels : gradient.columns;
    NSUInteger inputs = _sourceInputFeatureChannels < weights.rows ? _sourceInputFeatureChannels : weights.rows;
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, gradient.matrices, &start, &count);
    count = count < out.matrices ? count : out.matrices;
    for (NSUInteger b = start; b < start + count; b++) {
        if (!CharonMPSMatrixHolds(&gradient, b, _primarySourceMatrixOrigin.x, _primarySourceMatrixOrigin.y, vectors, outputs) ||
            !CharonMPSMatrixHolds(&weights, b, _secondarySourceMatrixOrigin.x, _secondarySourceMatrixOrigin.y, inputs, outputs) ||
            !CharonMPSMatrixHolds(&out, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, vectors, inputs)) {
            CharonMPSRefuse(@"MPSMatrixFullyConnectedGradient: a matrix of the batch [%lu, %lu) does not hold the region its origin names", (unsigned long)start, (unsigned long)(start + count));
            return;
        }
    }
    for (NSUInteger b = start; b < start + count; b++) {
        for (NSUInteger row = 0; row < vectors; row++) {
            for (NSUInteger k = 0; k < inputs; k++) {
                double sum = 0.0;
                for (NSUInteger column = 0; column < outputs; column++) {
                    double g = CharonMPSLoad(CharonMPSMatrixElement(&gradient, b, _primarySourceMatrixOrigin.x + row, _primarySourceMatrixOrigin.y + column), gradient.dataType, 0);
                    double w = CharonMPSLoad(CharonMPSMatrixElement(&weights, b, _secondarySourceMatrixOrigin.x + k, _secondarySourceMatrixOrigin.y + column), weights.dataType, 0);
                    sum += g * w;
                }
                CharonMPSStore(CharonMPSMatrixElement(&out, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + k), out.dataType, 0, _alpha * sum);
            }
        }
    }
    CharonMPSConsumeReadCount(gradientMatrix);
    CharonMPSConsumeReadCount(weightMatrix);
}

- (void)encodeGradientForWeightsAndBiasToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                        gradientMatrix:(MPSMatrix *)gradientMatrix
                                           inputMatrix:(MPSMatrix *)inputMatrix
                         resultGradientForWeightMatrix:(MPSMatrix *)resultGradientForWeightMatrix
                           resultGradientForBiasVector:(MPSVector *)resultGradientForBiasVector
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView gradient = CharonMPSMatrixViewOf(gradientMatrix), in = CharonMPSMatrixViewOf(inputMatrix), weights = CharonMPSMatrixViewOf(resultGradientForWeightMatrix);
    if (!CharonMPSDataTypeIsElement(gradient.dataType) || !CharonMPSDataTypeIsElement(in.dataType) || !CharonMPSDataTypeIsElement(weights.dataType)) {
        CharonMPSRefuse(@"MPSMatrixFullyConnectedGradient: a matrix of a data type that is not one of the eight element types was given");
        return;
    }
    // The gradient with respect to the weights is dW = alpha * X^T * dY, one row of the input per
    // feature vector, and the gradient with respect to the bias is the column sums of dY.
    NSUInteger vectors = _sourceNumberOfFeatureVectors < gradient.rows ? _sourceNumberOfFeatureVectors : gradient.rows;
    NSUInteger outputs = _sourceOutputFeatureChannels < gradient.columns ? _sourceOutputFeatureChannels : gradient.columns;
    NSUInteger inputs = _sourceInputFeatureChannels < in.columns ? _sourceInputFeatureChannels : in.columns;
    CharonMPSVectorView bias = {0, 0, 0, 0, 0, 0};
    if (resultGradientForBiasVector)
        bias = CharonMPSVectorViewOf(resultGradientForBiasVector);
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, gradient.matrices, &start, &count);
    count = count < weights.matrices ? count : weights.matrices;
    for (NSUInteger b = start; b < start + count; b++) {
        if (!CharonMPSMatrixHolds(&gradient, b, _primarySourceMatrixOrigin.x, _primarySourceMatrixOrigin.y, vectors, outputs) ||
            !CharonMPSMatrixHolds(&in, b, _secondarySourceMatrixOrigin.x, _secondarySourceMatrixOrigin.y, vectors, inputs) ||
            !CharonMPSMatrixHolds(&weights, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, inputs, outputs)) {
            CharonMPSRefuse(@"MPSMatrixFullyConnectedGradient: a matrix of the batch [%lu, %lu) does not hold the region its origin names", (unsigned long)start, (unsigned long)(start + count));
            return;
        }
    }
    for (NSUInteger b = start; b < start + count; b++) {
        for (NSUInteger k = 0; k < inputs; k++) {
            for (NSUInteger column = 0; column < outputs; column++) {
                double sum = 0.0;
                for (NSUInteger row = 0; row < vectors; row++) {
                    double x = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _secondarySourceMatrixOrigin.x + row, _secondarySourceMatrixOrigin.y + k), in.dataType, 0);
                    double g = CharonMPSLoad(CharonMPSMatrixElement(&gradient, b, _primarySourceMatrixOrigin.x + row, _primarySourceMatrixOrigin.y + column), gradient.dataType, 0);
                    sum += x * g;
                }
                CharonMPSStore(CharonMPSMatrixElement(&weights, b, _resultMatrixOrigin.x + k, _resultMatrixOrigin.y + column), weights.dataType, 0, _alpha * sum);
            }
        }
        for (NSUInteger column = 0; column < outputs; column++) {
            if (bias.length <= column)
                continue;
            double sum = 0.0;
            for (NSUInteger row = 0; row < vectors; row++)
                sum += CharonMPSLoad(CharonMPSMatrixElement(&gradient, b, _primarySourceMatrixOrigin.x + row, _primarySourceMatrixOrigin.y + column), gradient.dataType, 0);
            CharonMPSStore(CharonMPSVectorElement(&bias, 0, column), bias.dataType, 0, sum);
        }
    }
    CharonMPSConsumeReadCount(gradientMatrix);
    CharonMPSConsumeReadCount(inputMatrix);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (instancetype)copyWithZone:(NSZone *)zone device:(id<MTLDevice>)device
{
    MPSMatrixFullyConnectedGradient *copy = [super copyWithZone:zone device:device];
    copy->_alpha = _alpha;
    copy->_sourceNumberOfFeatureVectors = _sourceNumberOfFeatureVectors;
    copy->_sourceInputFeatureChannels = _sourceInputFeatureChannels;
    copy->_sourceOutputFeatureChannels = _sourceOutputFeatureChannels;
    return copy;
}

@end

@implementation MPSMatrixBatchNormalization {
    CHARON_MPS_NEURON_IVARS
    NSUInteger _sourceNumberOfFeatureVectors, _sourceInputFeatureChannels;
    float _epsilon;
    BOOL _computeStatistics;
    MTLOrigin _sourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

CHARON_MPS_NEURON_COMMON

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _neuronType = MPSCNNNeuronTypeNone;
        _sourceNumberOfFeatureVectors = NSUIntegerMax;
        _sourceInputFeatureChannels = NSUIntegerMax;
        // The header's own default: the smallest positive normal single precision value, so a variance
        // of zero does not divide by zero in a caller who has not chosen one.
        _epsilon = 1.17549435e-38f;
        _computeStatistics = NO;
    }
    return self;
}

- (NSUInteger)sourceNumberOfFeatureVectors { return _sourceNumberOfFeatureVectors; }
- (void)setSourceNumberOfFeatureVectors:(NSUInteger)count { _sourceNumberOfFeatureVectors = count; }
- (NSUInteger)sourceInputFeatureChannels { return _sourceInputFeatureChannels; }
- (void)setSourceInputFeatureChannels:(NSUInteger)channels { _sourceInputFeatureChannels = channels; }
- (float)epsilon { return _epsilon; }
- (void)setEpsilon:(float)epsilon { _epsilon = epsilon; }
- (BOOL)computeStatistics { return _computeStatistics; }
- (void)setComputeStatistics:(BOOL)computeStatistics { _computeStatistics = computeStatistics; }

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  inputMatrix:(MPSMatrix *)inputMatrix
                   meanVector:(MPSVector *)meanVector
               varianceVector:(MPSVector *)varianceVector
                  gammaVector:(MPSVector *)gammaVector
                   betaVector:(MPSVector *)betaVector
                 resultMatrix:(MPSMatrix *)resultMatrix
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView in = CharonMPSMatrixViewOf(inputMatrix), out = CharonMPSMatrixViewOf(resultMatrix);
    if (!CharonMPSDataTypeIsElement(in.dataType) || !CharonMPSDataTypeIsElement(out.dataType)) {
        CharonMPSRefuse(@"MPSMatrixBatchNormalization: a matrix of a data type that is not one of the eight element types was given");
        return;
    }
    // y[i,j] = gamma[j] * (x[i,j] - mean(x[:,j])) / (variance(x[:,j]) + epsilon) + beta[j], the
    // normalisation along the columns of the input, each column a feature channel's values across the
    // feature vectors. computeStatistics asks for the mean and variance to be written back, which is
    // what a training pass needs; the mean and variance the call gives are used either way.
    NSUInteger available = in.rows - _sourceMatrixOrigin.x;
    NSUInteger vectors = _sourceNumberOfFeatureVectors < available ? _sourceNumberOfFeatureVectors : available;
    NSUInteger columns = in.columns - _sourceMatrixOrigin.y;
    NSUInteger channels = _sourceInputFeatureChannels < columns ? _sourceInputFeatureChannels : columns;
    CharonMPSVectorView mean = CharonMPSVectorViewOf(meanVector), variance = CharonMPSVectorViewOf(varianceVector);
    CharonMPSVectorView gamma = {0, 0, 0, 0, 0, 0}, beta = {0, 0, 0, 0, 0, 0};
    if (gammaVector)
        gamma = CharonMPSVectorViewOf(gammaVector);
    if (betaVector)
        beta = CharonMPSVectorViewOf(betaVector);
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, in.matrices, &start, &count);
    count = count < out.matrices ? count : out.matrices;
    for (NSUInteger b = start; b < start + count; b++) {
        if (!CharonMPSMatrixHolds(&in, b, _sourceMatrixOrigin.x, _sourceMatrixOrigin.y, vectors, channels) ||
            !CharonMPSMatrixHolds(&out, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, vectors, channels)) {
            CharonMPSRefuse(@"MPSMatrixBatchNormalization: a matrix of the batch [%lu, %lu) does not hold the %lux%lu region its origin names", (unsigned long)start, (unsigned long)(start + count), (unsigned long)vectors, (unsigned long)channels);
            return;
        }
    }
    CharonMPSNeuron neuron = [self charon_mps_neuron];
    for (NSUInteger b = start; b < start + count; b++) {
        for (NSUInteger column = 0; column < channels; column++) {
            double total = 0.0, squares = 0.0;
            for (NSUInteger row = 0; row < vectors; row++) {
                double x = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _sourceMatrixOrigin.x + row, _sourceMatrixOrigin.y + column), in.dataType, 0);
                total += x;
                squares += x * x;
            }
            double m = vectors ? total / (double)vectors : 0.0;
            double v = vectors ? squares / (double)vectors - m * m : 0.0;
            if (_computeStatistics && mean.length > column)
                CharonMPSStore(CharonMPSVectorElement(&mean, 0, column), mean.dataType, 0, m);
            if (_computeStatistics && variance.length > column)
                CharonMPSStore(CharonMPSVectorElement(&variance, 0, column), variance.dataType, 0, v);
            double given = variance.length > column ? CharonMPSLoad(CharonMPSVectorElement(&variance, 0, column), variance.dataType, 0) : v;
            double g = gamma.length > column ? CharonMPSLoad(CharonMPSVectorElement(&gamma, 0, column), gamma.dataType, 0) : 1.0;
            double b0 = beta.length > column ? CharonMPSLoad(CharonMPSVectorElement(&beta, 0, column), beta.dataType, 0) : 0.0;
            for (NSUInteger row = 0; row < vectors; row++) {
                double x = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _sourceMatrixOrigin.x + row, _sourceMatrixOrigin.y + column), in.dataType, 0);
                double y = CharonMPSApplyNeuron(neuron.type, g * (x - m) / (given + (double)_epsilon) + b0, neuron.a, neuron.b, neuron.c, CharonMPSNeuronA(&neuron, column));
                CharonMPSStore(CharonMPSMatrixElement(&out, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + column), out.dataType, 0, y);
            }
        }
    }
    CharonMPSConsumeReadCount(inputMatrix);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (instancetype)copyWithZone:(NSZone *)zone device:(id<MTLDevice>)device
{
    MPSMatrixBatchNormalization *copy = [super copyWithZone:zone device:device];
    copy->_neuronType = _neuronType;
    copy->_neuronParameterA = _neuronParameterA;
    copy->_neuronParameterB = _neuronParameterB;
    copy->_neuronParameterC = _neuronParameterC;
    copy->_epsilon = _epsilon;
    copy->_computeStatistics = _computeStatistics;
    return copy;
}

@end

@implementation MPSMatrixBatchNormalizationGradient {
    CHARON_MPS_NEURON_IVARS
    NSUInteger _sourceNumberOfFeatureVectors, _sourceInputFeatureChannels;
    float _epsilon;
    MTLOrigin _primarySourceMatrixOrigin, _secondarySourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

CHARON_MPS_NEURON_COMMON

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _neuronType = MPSCNNNeuronTypeNone;
        _sourceNumberOfFeatureVectors = NSUIntegerMax;
        _sourceInputFeatureChannels = NSUIntegerMax;
        _epsilon = 1.17549435e-38f;
    }
    return self;
}

- (NSUInteger)sourceNumberOfFeatureVectors { return _sourceNumberOfFeatureVectors; }
- (void)setSourceNumberOfFeatureVectors:(NSUInteger)count { _sourceNumberOfFeatureVectors = count; }
- (NSUInteger)sourceInputFeatureChannels { return _sourceInputFeatureChannels; }
- (void)setSourceInputFeatureChannels:(NSUInteger)channels { _sourceInputFeatureChannels = channels; }
- (float)epsilon { return _epsilon; }
- (void)setEpsilon:(float)epsilon { _epsilon = epsilon; }

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
               gradientMatrix:(MPSMatrix *)gradientMatrix
                  inputMatrix:(MPSMatrix *)inputMatrix
                   meanVector:(MPSVector *)meanVector
               varianceVector:(MPSVector *)varianceVector
                  gammaVector:(MPSVector *)gammaVector
                   betaVector:(MPSVector *)betaVector
  resultGradientForDataMatrix:(MPSMatrix *)resultGradientForDataMatrix
 resultGradientForGammaVector:(MPSVector *)resultGradientForGammaVector
  resultGradientForBetaVector:(MPSVector *)resultGradientForBetaVector
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView gradient = CharonMPSMatrixViewOf(gradientMatrix), in = CharonMPSMatrixViewOf(inputMatrix), out = CharonMPSMatrixViewOf(resultGradientForDataMatrix);
    if (!CharonMPSDataTypeIsElement(gradient.dataType) || !CharonMPSDataTypeIsElement(in.dataType) || !CharonMPSDataTypeIsElement(out.dataType)) {
        CharonMPSRefuse(@"MPSMatrixBatchNormalizationGradient: a matrix of a data type that is not one of the eight element types was given");
        return;
    }
    // Backpropagating through y[j] = gamma[j] * (x[j] - m[j]) / (v[j] + epsilon) + beta[j], in the
    // header's own notation: the gradient with respect to gamma is the incoming gradient times the
    // normalised value, the gradient with respect to beta its column sums, and the gradient with
    // respect to the input the usual per-channel form
    //     gamma / (v + epsilon) * (dY - mean(dY) - yhat / n * sum(dY))
    // where yhat is the normalised value and n the number of feature vectors.
    NSUInteger available = in.rows - _secondarySourceMatrixOrigin.x;
    NSUInteger vectors = _sourceNumberOfFeatureVectors < available ? _sourceNumberOfFeatureVectors : available;
    NSUInteger columns = in.columns - _secondarySourceMatrixOrigin.y;
    NSUInteger channels = _sourceInputFeatureChannels < columns ? _sourceInputFeatureChannels : columns;
    CharonMPSVectorView mean = CharonMPSVectorViewOf(meanVector), variance = CharonMPSVectorViewOf(varianceVector);
    CharonMPSVectorView gamma = {0, 0, 0, 0, 0, 0};
    if (gammaVector)
        gamma = CharonMPSVectorViewOf(gammaVector);
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, in.matrices, &start, &count);
    count = count < gradient.matrices ? count : gradient.matrices;
    count = count < out.matrices ? count : out.matrices;
    for (NSUInteger b = start; b < start + count; b++) {
        if (!CharonMPSMatrixHolds(&gradient, b, _primarySourceMatrixOrigin.x, _primarySourceMatrixOrigin.y, vectors, channels) ||
            !CharonMPSMatrixHolds(&in, b, _secondarySourceMatrixOrigin.x, _secondarySourceMatrixOrigin.y, vectors, channels) ||
            !CharonMPSMatrixHolds(&out, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, vectors, channels)) {
            CharonMPSRefuse(@"MPSMatrixBatchNormalizationGradient: a matrix of the batch [%lu, %lu) does not hold the %lux%lu region its origin names", (unsigned long)start, (unsigned long)(start + count), (unsigned long)vectors, (unsigned long)channels);
            return;
        }
    }
    for (NSUInteger b = start; b < start + count; b++) {
        for (NSUInteger column = 0; column < channels; column++) {
            double m = mean.length > column ? CharonMPSLoad(CharonMPSVectorElement(&mean, 0, column), mean.dataType, 0) : 0.0;
            double v = variance.length > column ? CharonMPSLoad(CharonMPSVectorElement(&variance, 0, column), variance.dataType, 0) : 0.0;
            double g = gamma.length > column ? CharonMPSLoad(CharonMPSVectorElement(&gamma, 0, column), gamma.dataType, 0) : 1.0;
            double divisor = g / (v + (double)_epsilon);
            double sum = 0.0, gammaGradient = 0.0, betaGradient = 0.0;
            for (NSUInteger row = 0; row < vectors; row++) {
                double d = CharonMPSLoad(CharonMPSMatrixElement(&gradient, b, _primarySourceMatrixOrigin.x + row, _primarySourceMatrixOrigin.y + column), gradient.dataType, 0);
                double x = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _secondarySourceMatrixOrigin.x + row, _secondarySourceMatrixOrigin.y + column), in.dataType, 0);
                double normalised = (x - m) / (v + (double)_epsilon);
                sum += d;
                gammaGradient += d * normalised;
                betaGradient += d;
            }
            double meanGradient = vectors ? sum / (double)vectors : 0.0;
            double scaledSum = vectors ? sum / (double)vectors : 0.0;
            if (resultGradientForGammaVector) {
                CharonMPSVectorView view = CharonMPSVectorViewOf(resultGradientForGammaVector);
                if (view.length > column)
                    CharonMPSStore(CharonMPSVectorElement(&view, 0, column), view.dataType, 0, gammaGradient);
            }
            if (resultGradientForBetaVector) {
                CharonMPSVectorView view = CharonMPSVectorViewOf(resultGradientForBetaVector);
                if (view.length > column)
                    CharonMPSStore(CharonMPSVectorElement(&view, 0, column), view.dataType, 0, betaGradient);
            }
            for (NSUInteger row = 0; row < vectors; row++) {
                double d = CharonMPSLoad(CharonMPSMatrixElement(&gradient, b, _primarySourceMatrixOrigin.x + row, _primarySourceMatrixOrigin.y + column), gradient.dataType, 0);
                double x = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _secondarySourceMatrixOrigin.x + row, _secondarySourceMatrixOrigin.y + column), in.dataType, 0);
                double normalised = (x - m) / (v + (double)_epsilon);
                double gradientForData = divisor * (d - meanGradient - normalised * scaledSum);
                CharonMPSStore(CharonMPSMatrixElement(&out, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + column), out.dataType, 0, gradientForData);
            }
        }
    }
    CharonMPSConsumeReadCount(gradientMatrix);
    CharonMPSConsumeReadCount(inputMatrix);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (instancetype)copyWithZone:(NSZone *)zone device:(id<MTLDevice>)device
{
    MPSMatrixBatchNormalizationGradient *copy = [super copyWithZone:zone device:device];
    copy->_epsilon = _epsilon;
    copy->_neuronType = _neuronType;
    return copy;
}

@end

@implementation MPSMatrixSum {
    CHARON_MPS_NEURON_IVARS
    NSUInteger _rows, _columns, _count;
    BOOL _transpose;
    MTLOrigin _resultMatrixOrigin;
}

CHARON_MPS_NEURON_COMMON

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    NSLog(@"MPSMatrixSum: -initWithDevice: names no shape; use -initWithDevice:count:rows:columns:transpose:");
    return nil;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device count:(NSUInteger)count rows:(NSUInteger)rows columns:(NSUInteger)columns transpose:(BOOL)transpose
{
    if ((self = [super initWithDevice:device])) {
        _neuronType = MPSCNNNeuronTypeNone;
        _count = count;
        _rows = rows;
        _columns = columns;
        _transpose = transpose;
        _resultMatrixOrigin = MTLOriginMake(0, 0, 0);
    }
    return self;
}

- (NSUInteger)rows { return _rows; }
- (NSUInteger)columns { return _columns; }
- (NSUInteger)count { return _count; }
- (BOOL)transpose { return _transpose; }

- (MTLOrigin)resultMatrixOrigin
{
    return _resultMatrixOrigin;
}

- (void)setResultMatrixOrigin:(MTLOrigin)origin
{
    _resultMatrixOrigin = origin;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
               sourceMatrices:(NSArray<MPSMatrix *> *)sourceMatrices
                 resultMatrix:(MPSMatrix *)resultMatrix
                  scaleVector:(MPSVector *)scaleVector
                 offsetVector:(MPSVector *)offsetVector
                   biasVector:(MPSVector *)biasVector
                   startIndex:(NSUInteger)startIndex
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView out = CharonMPSMatrixViewOf(resultMatrix);
    if (!CharonMPSDataTypeIsElement(out.dataType)) {
        CharonMPSRefuse(@"MPSMatrixSum: the result matrix has a data type that is not one of the eight element types");
        return;
    }
    // A = sum over the sources of alpha[i] * B[i], with alpha the scale vector's components from
    // startIndex, then the bias broadcast across each row, then the neuron, as MPSMatrixSum.h writes
    // the operation out. The offset vector is a packed array of MPSMatrixOffset, each naming where in
    // its source to start reading in rows and in columns.
    CharonMPSVectorView scales = {0, 0, 0, 0, 0, 0};
    if (scaleVector)
        scales = CharonMPSVectorViewOf(scaleVector);
    CharonMPSVectorView bias = {0, 0, 0, 0, 0, 0};
    if (biasVector)
        bias = CharonMPSVectorViewOf(biasVector);
    const MPSMatrixOffset *offsets = NULL;
    if (offsetVector)
        offsets = (const MPSMatrixOffset *)((const char *)[offsetVector.data contents] + offsetVector.offset);
    CharonMPSNeuron neuron = [self charon_mps_neuron];
    for (NSUInteger row = 0; row < _rows; row++) {
        for (NSUInteger column = 0; column < _columns; column++) {
            double sum = 0.0;
            for (NSUInteger index = 0; index < _count; index++) {
                if (index >= sourceMatrices.count) {
                    CharonMPSRefuse(@"MPSMatrixSum: %lu matrices were named and only %lu were given", (unsigned long)_count, (unsigned long)sourceMatrices.count);
                    return;
                }
                MPSMatrix *source = sourceMatrices[index];
                CharonMPSMatrixView view = CharonMPSMatrixViewOf(source);
                NSUInteger sourceRow = row, sourceColumn = column;
                if (offsets) {
                    sourceRow += offsets[startIndex + index].rowOffset;
                    sourceColumn += offsets[startIndex + index].columnOffset;
                }
                if (_transpose) {
                    NSUInteger swap = sourceRow;
                    sourceRow = sourceColumn;
                    sourceColumn = swap;
                }
                if (!CharonMPSDataTypeIsElement(view.dataType) || !CharonMPSMatrixHolds(&view, 0, sourceRow, sourceColumn, 1, 1)) {
                    CharonMPSRefuse(@"MPSMatrixSum: source %lu does not hold the element (%lu, %lu) the operation names", (unsigned long)index, (unsigned long)sourceRow, (unsigned long)sourceColumn);
                    return;
                }
                double value = CharonMPSLoad(CharonMPSMatrixElement(&view, 0, sourceRow, sourceColumn), view.dataType, 0);
                double scale = 1.0;
                if (scales.length > startIndex + index)
                    scale = CharonMPSLoad(CharonMPSVectorElement(&scales, startIndex + index, 0), scales.dataType, 0);
                sum += scale * value;
            }
            if (bias.length > column)
                sum += CharonMPSLoad(CharonMPSVectorElement(&bias, 0, column), bias.dataType, 0);
            double y = CharonMPSApplyNeuron(neuron.type, sum, neuron.a, neuron.b, neuron.c, CharonMPSNeuronA(&neuron, column));
            CharonMPSStore(CharonMPSMatrixElement(&out, 0, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + column), out.dataType, 0, y);
        }
    }
    for (MPSMatrix *source in sourceMatrices)
        CharonMPSConsumeReadCount(source);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

@end
