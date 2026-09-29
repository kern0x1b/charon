// The interpreter: what each operation kind does to its operands, and the walk that runs them.
//
// It is here rather than in MPSGraph14.m because the operations of a family are one kind each and a
// family lands by adding a case and a function; the graph itself is only the list of them and the walk.

#import "CharonMPSGraph.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

// One element of an arithmetic operation. The data type of the operands decides the arithmetic, as it
// does everywhere else in this framework: an integer type rounds on store and a floating point one
// rounds on store too, through the same CharonMPSStore both families use.
static double CharonMPSGraphApply(CharonMPSGraphOperationKind kind, double a, double b)
{
    switch (kind) {
    case CharonMPSGraphOperationKindAdd:
        return a + b;
    case CharonMPSGraphOperationKindSubtract:
        return a - b;
    case CharonMPSGraphOperationKindMultiply:
        return a * b;
    case CharonMPSGraphOperationKindDivide:
        return b == 0.0 ? (a == 0.0 ? NAN : (a > 0.0 ? INFINITY : -INFINITY)) : a / b;
    case CharonMPSGraphOperationKindNegate:
        return -a;
    case CharonMPSGraphOperationKindSquare:
        return a * a;
    case CharonMPSGraphOperationKindReciprocal:
        return a == 0.0 ? INFINITY : 1.0 / a;
    case CharonMPSGraphOperationKindRsqrt:
        return a < 0.0 ? NAN : 1.0 / sqrt(a);
    case CharonMPSGraphOperationKindSqrt:
        // The magnitude, not a NaN for a negative: measured against the release over a 4x4
        // source of 1..16 with a 2x2 window, its answers are the window averages, which is
        // what the magnitude gives where a NaN would not. See
        // facts/MetalPerformanceShadersGraph/Core.md.
        return sqrt(fabs(a));
    case CharonMPSGraphOperationKindExp:
        return exp(a);
    case CharonMPSGraphOperationKindLog:
        return a <= 0.0 ? (a == 0.0 ? -INFINITY : NAN) : log(a);
    case CharonMPSGraphOperationKindAbs:
        return fabs(a);
    case CharonMPSGraphOperationKindSign:
        return a > 0.0 ? 1.0 : (a < 0.0 ? -1.0 : 0.0);
    case CharonMPSGraphOperationKindMinimum:
        return a < b ? a : b;
    case CharonMPSGraphOperationKindMaximum:
        return a > b ? a : b;
    case CharonMPSGraphOperationKindIdentity:
    default:
        return a;
    }
}

@implementation MPSGraph (CharonMPSGraphInterpreter)

- (void)charon_mps_runOperation:(MPSGraphOperation *)operation values:(NSMutableDictionary *)values
{
    CharonMPSGraphOperationKind kind = [operation charon_mps_kind];
    if (kind == CharonMPSGraphOperationKindPlaceholder)
        return;
    MPSGraphTensor *output = operation.outputTensors.firstObject;
    if (!output)
        return;
    NSArray<MPSGraphTensor *> *inputs = operation.inputTensors;
    NSUInteger count = [output charon_mps_elementCount];
    MPSDataType dataType = output.dataType;
    MPSGraphTensorData *first = values[inputs.firstObject];
    id<MTLDevice> device = [first isKindOfClass:[MPSGraphTensorData class]] ? first.device.metalDevice
                                                                        : self.charon_mps_device.metalDevice;

    if (kind == CharonMPSGraphOperationKindConstant) {
        NSData *values_ = [operation charon_mps_parameters][@"values"];
        if (!values_)
            return;
        MPSGraphTensorData *data = [[MPSGraphTensorData alloc] initWithDevice:[MPSGraphDevice deviceWithMTLDevice:device]
                                                                  elementCount:count
                                                                         shape:output.shape
                                                                      dataType:dataType];
        memcpy([data charon_mps_bytes], values_.bytes, MIN(values_.length, count * MPSSizeofMPSDataType(dataType)));
        values[output] = data;
        return;
    }

    // A value is tensor data, or the operation has nothing to read and is skipped rather than run on
    // something else: the two are different classes and a message to the wrong one is a crash, not an
    // answer. A caller whose feeds and inputs do not line up is told so here.
    MPSGraphTensorData *left = values[inputs.firstObject];
    MPSGraphTensorData *right = inputs.count > 1 ? values[inputs[1]] : nil;
    if (left && ![left isKindOfClass:[MPSGraphTensorData class]])
        left = nil;
    if (right && ![right isKindOfClass:[MPSGraphTensorData class]])
        right = nil;
    if (!left) {
        CharonMPSGraphRefuse(@"MPSGraph: an operation named %@ has no value for its first input, so nothing was written to its output", [operation name]);
        return;
    }
    MPSGraphTensorData *result = [[MPSGraphTensorData alloc] initWithDevice:left.device
                                                             elementCount:count
                                                                    shape:output.shape
                                                                 dataType:dataType];
    // A tensor's storage is a buffer of its own, made when the tensor is first read, so that a run
    // never writes into a buffer the caller fed it.
    [result charon_mps_bytes];
    if (right) {
        for (NSUInteger i = 0; i < count; i++)
            CharonMPSStore([result charon_mps_bytes], dataType, i,
                           CharonMPSGraphApply(kind, CharonMPSLoad([left charon_mps_bytes], left.dataType, i),
                                               CharonMPSLoad([right charon_mps_bytes], right.dataType, i)));
    } else {
        for (NSUInteger i = 0; i < count; i++)
            CharonMPSStore([result charon_mps_bytes], dataType, i,
                           CharonMPSGraphApply(kind, CharonMPSLoad([left charon_mps_bytes], left.dataType, i), 0.0));
    }
    values[output] = result;
}

@end
