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
        return a <= 0.0 ? (a == 0.0 ? INFINITY : NAN) : 1.0 / sqrt(a);
    case CharonMPSGraphOperationKindSqrt:
        return a <= 0.0 ? NAN : sqrt(a);
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
    id<MTLDevice> device = ((MPSGraphTensorData *)values[inputs.firstObject]).device.metalDevice;

    if (kind == CharonMPSGraphOperationKindConstant) {
        NSData *values_ = [operation charon_mps_parameters][@"values"];
        if (!values_)
            return;
        MPSGraphTensorData *data = [[MPSGraphTensorData alloc] initWithDevice:[MPSGraphDevice deviceWithMTLDevice:device]
                                                                          data:values_
                                                                         shape:output.shape
                                                                      dataType:dataType];
        values[output] = data;
        return;
    }

    MPSGraphTensorData *left = values[inputs.firstObject];
    MPSGraphTensorData *right = inputs.count > 1 ? values[inputs[1]] : nil;
    if (!left)
        return;
    MPSGraphTensorData *result = [[MPSGraphTensorData alloc] initWithDevice:left.device
                                                                     data:[NSData data]
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
