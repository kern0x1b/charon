// The interpreter: what each operation kind does to its operands, and the walk that runs them.
//
// It is here rather than in MPSGraph14.m because the operations of a family are one kind each and a
// family lands by adding a case and a function; the graph itself is only the list of them and the walk.

#import "CharonMPSGraph.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

// A value that is a denormal in the type it is stored as is a value the release's arithmetic never sees:
// it reads one as a zero of the same sign, and it leaves no denormal behind. Measured on macOS 27.0
// build 26A428 (M4 Pro, Metal 4) over the sixteen classes tests/backports/host/mpsgraph/graph-cases.m
// feeds, against -[MPSGraph squareRootWithTensor:name:] and its siblings on this host's own MPSGraph:
// square root of 0x00000001 is 0x00000000 and of 0x80000001 is 0x80000000, sign of 0x00000001 is 0,
// division of 0x00000001 by 0x00000001 is a NaN because both sides are read as zeros, and square of
// 0x00800000 - whose square is a denormal - is 0x00000000 while square of 0x3f7fffff is 0x3f7ffffe.
// A half is not flushed: the same host answers the sign of a half 0x0001 with 0x3c00 and its square root
// with 0x0c00, which is why this is the float type's answer and the other floating point type's is left
// as it is. facts/MetalPerformanceShadersGraph/Core.md carries the tables.
static double CharonMPSGraphAsZero(double value, MPSDataType type)
{
    if (type != MPSDataTypeFloat32)
        return value;
    float narrowed = (float)value;
    if (narrowed != 0.0f && fabsf(narrowed) < FLT_MIN)
        return copysign(0.0, narrowed);
    return value;
}

// A NaN that leaves the release's arithmetic is the arithmetic's own NaN and not the one it was given: a
// propagated sign and a propagated payload are both gone, and every kind that computes does it. Measured
// on the same host and the same sixteen classes, over a feed carrying 0xffc00000 and 0x7f800001: addition
// answers 0x7fc00000 for each of them, and so does every other kind that computes, while the two kinds
// that copy are the two that keep them - identity answers 0x7f800001 with 0x7f800001.
static double CharonMPSGraphOwnNaN(double value)
{
    return isnan(value) ? NAN : value;
}

// One element of an arithmetic operation. The data type of the operands decides the arithmetic, as it
// does everywhere else in this framework: an integer type rounds on store and a floating point one
// rounds on store too, through the same CharonMPSStore both families use.
static double CharonMPSGraphApply(CharonMPSGraphOperationKind kind, double a, double b,
                                  MPSDataType operandType, MPSDataType resultType)
{
    // Absolute and identity copy rather than compute, and are the two kinds that keep a denormal: measured
    // on the same host, absolute of 0x00000001 is 0x00000001 and identity of 0x007fffff is 0x007fffff.
    // The half rules below are a different question and reach both of them.
    int copying = kind == CharonMPSGraphOperationKindAbs || kind == CharonMPSGraphOperationKindIdentity;
    if (!copying) {
        a = CharonMPSGraphAsZero(a, operandType);
        b = CharonMPSGraphAsZero(b, operandType);
    }
    double result;
    switch (kind) {
    case CharonMPSGraphOperationKindAbs:
        result = fabs(a);
        break;
    case CharonMPSGraphOperationKindIdentity:
        result = a;
        break;
    // A division, a reciprocal, a square root and a logarithm are the arithmetic itself and nothing
    // else: what the release answers for a zero, a negative and an infinity is what IEEE answers, so a
    // branch that decided it separately answered a negative zero with the wrong infinity.
    case CharonMPSGraphOperationKindAdd:
        result = a + b;
        break;
    case CharonMPSGraphOperationKindSubtract:
        result = a - b;
        break;
    case CharonMPSGraphOperationKindMultiply:
        result = a * b;
        break;
    case CharonMPSGraphOperationKindDivide:
        result = a / b;
        break;
    case CharonMPSGraphOperationKindNegate:
        result = -a;
        break;
    case CharonMPSGraphOperationKindSquare:
        result = a * a;
        break;
    case CharonMPSGraphOperationKindReciprocal:
        result = 1.0 / a;
        break;
    case CharonMPSGraphOperationKindRsqrt:
        result = 1.0 / sqrt(a);
        break;
    // The square root of a negative is a NaN, which is the whole of what the header's own operation
    // means and what the release answers: a feed of (1, 2, 3, 4, -1, -2, -3, -4) comes back as
    // 1, 1.41421, 1.73205, 2 and then four NaNs, byte for byte on this host.
    case CharonMPSGraphOperationKindSqrt:
        result = sqrt(a);
        break;
    case CharonMPSGraphOperationKindExp:
        result = exp(a);
        break;
    case CharonMPSGraphOperationKindLog:
        result = log(a);
        break;
    case CharonMPSGraphOperationKindSign:
        result = a > 0.0 ? 1.0 : (a < 0.0 ? -1.0 : 0.0);
        break;
    case CharonMPSGraphOperationKindMinimum:
        result = a < b ? a : b;
        break;
    case CharonMPSGraphOperationKindMaximum:
        result = a > b ? a : b;
        break;
    default:
        result = a;
        break;
    }
    if (resultType == MPSDataTypeFloat16) {
        /* A half is a different arithmetic on this host, and this is the half of it that is a rule
         * rather than an approximation. Measured on macOS 27.0 build 26A428 (M4 Pro, Metal 4) over
         * the sixteen classes tests/backports/host/mpsgraph/graph-cases.m feeds, against the same
         * operations on this host's own MPSGraph; facts/MetalPerformanceShadersGraph/Core.md carries
         * the whole table and what is left of it that no rule reaches.
         *
         * A zero leaves the half path without its sign: the identity of a half -0.0 is 0x0000, a
         * square root of -0.0 is 0x0000, and the reciprocal of -inf is 0x0000 where the reciprocal of
         * +inf is 0x0000 too. A NaN operand is an infinity of that NaN's own sign for the three kinds
         * that carry the sign - the identity, an addition and a subtraction - and a positive infinity
         * for the two that drop it, the square and the absolute value, while the square root answers
         * an infinity for a positive NaN and a zero for a negative one, the reverse square root and
         * the logarithm answer a zero for either, and the sign answers the NaN's sign. A negative
         * argument is a zero to a square root and to a reverse square root, a logarithm of a zero is
         * -45440 (0xf98c) and of anything else that is not a positive number is a zero.
         */
        if (isnan(a) || isnan(b)) {
            double sign = isnan(a) ? a : b;
            switch (kind) {
            case CharonMPSGraphOperationKindSquare:
            case CharonMPSGraphOperationKindAbs:
                result = INFINITY;
                break;
            case CharonMPSGraphOperationKindReciprocal:
                // Measured 0x0000 for a NaN of either sign, where the square and the absolute value
                // answer an infinity and the three that carry a sign answer one of that sign.
                result = 0.0;
                break;
            case CharonMPSGraphOperationKindIdentity:
            case CharonMPSGraphOperationKindAdd:
            case CharonMPSGraphOperationKindSubtract:
                result = copysign(INFINITY, sign);
                break;
            case CharonMPSGraphOperationKindSqrt:
                // The sign bit and not the value: a NaN compares false against everything, so the
                // sign of a NaN is read from its bit and a positive NaN is 0x7c00 here.
                result = signbit(sign) ? 0.0 : INFINITY;
                break;
            case CharonMPSGraphOperationKindSign:
                result = copysign(1.0, sign);
                break;
            default:
                result = 0.0;
                break;
            }
        } else {
            switch (kind) {
            case CharonMPSGraphOperationKindSqrt:
                // A negative argument is a zero, measured: the square root of a half -1.0 is 0x0000,
                // and of -inf and of a negative NaN and of a negative denormal too. A negative zero
                // is answered by the zero rule below.
                if (a < 0.0) {
                    result = 0.0;
                }
                break;
            case CharonMPSGraphOperationKindRsqrt:
                // The same zero for a negative argument, and a positive infinity for a zero of either
                // sign, where the reciprocal of one is a negative infinity and this is not: measured,
                // the reverse square root of a half -0.0 is 0x7c00 and of 0x0000 is 0x7c00.
                result = a < 0.0 ? 0.0 : (a == 0.0 ? INFINITY : result);
                break;
            case CharonMPSGraphOperationKindReciprocal:
                // A zero of either sign is a positive infinity, where the reciprocal of a negative zero
                // is a negative infinity in IEEE and 0x7c00 here.
                result = a == 0.0 ? INFINITY : result;
                break;
            case CharonMPSGraphOperationKindLog:
                // The measured -45440 of a logarithm of a zero, and a zero for everything else that
                // is not a positive number: -1, an infinity of either sign and a NaN all answer 0x0000.
                // An infinity is a zero here too, measured: the logarithm of a half +inf is 0x0000.
                result = a == 0.0 ? -45440.0 : (isinf(a) ? 0.0 : (a > 0.0 ? log(a) : 0.0));
                break;
            case CharonMPSGraphOperationKindSign:
                // The sign of the value and not a comparison of it: a NaN is answered with the sign
                // bit it carries, which is why the two NaN classes are 0x3c00 and 0xbc00 here and a
                // zero with either sign is 0x0000.
                result = a != 0.0 ? copysign(1.0, a) : 0.0;
                break;
            default:
                break;
            }
        }
        if (result == 0.0) {
            result = 0.0;
        }
    }
    if (copying) {
        return result;
    }
    return CharonMPSGraphOwnNaN(CharonMPSGraphAsZero(result, resultType));
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
                                               CharonMPSLoad([right charon_mps_bytes], right.dataType, i),
                                               left.dataType, dataType));
    } else {
        for (NSUInteger i = 0; i < count; i++)
            CharonMPSStore([result charon_mps_bytes], dataType, i,
                           CharonMPSGraphApply(kind, CharonMPSLoad([left charon_mps_bytes], left.dataType, i), 0.0,
                                               left.dataType, dataType));
    }
    values[output] = result;
}

@end
