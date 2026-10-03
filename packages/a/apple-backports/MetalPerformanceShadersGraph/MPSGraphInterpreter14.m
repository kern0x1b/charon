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

// The kinds that read an operand as it is stored rather than as the release's float32 arithmetic reads
// it. Measured on this host's own MPSGraph over the sixteen classes the case file feeds, and each of
// these answers a denormal as itself: absolute of 0x00000001 is 0x00000001 and identity of 0x007fffff
// is 0x007fffff, the sign of an operand is its sign bit, the negation of 0x00000001 is 0x80000001,
// round of 0x00000001 is 0x00000000 and the sign of a zero result is dropped, modulo of 0x00000001 by
// -2.0 is 0x00000001, a minimum and a maximum of 0x00000001 and 0x7e00 is 0x00000001, a select whose
// predicate is a NaN takes the branch it takes for any other non-zero, and a clamp of a NaN is its
// bounds. Every other kind reads a denormal as a zero of the same sign, which is CharonMPSGraphAsZero.
static int CharonMPSGraphReadsOperandAsStored(CharonMPSGraphOperationKind kind)
{
    switch (kind) {
    case CharonMPSGraphOperationKindAbs:
    case CharonMPSGraphOperationKindIdentity:
    case CharonMPSGraphOperationKindSignBit:
    case CharonMPSGraphOperationKindNegate:
    case CharonMPSGraphOperationKindRound:
    case CharonMPSGraphOperationKindModulo:
    case CharonMPSGraphOperationKindFloorModulo:
    case CharonMPSGraphOperationKindMinimum:
    case CharonMPSGraphOperationKindMaximum:
    case CharonMPSGraphOperationKindSelect:
    case CharonMPSGraphOperationKindClamp3:
        return 1;
    default:
        return 0;
    }
}

// The three kinds that copy an operand's bits and therefore answer the NaN they were given: measured,
// the identity of 0xffc00000 is 0xffc00000 where the square of it is 0x7fc00000.
static int CharonMPSGraphCopiesTheOperand(CharonMPSGraphOperationKind kind)
{
    return kind == CharonMPSGraphOperationKindAbs || kind == CharonMPSGraphOperationKindIdentity ||
           kind == CharonMPSGraphOperationKindSignBit;
}

// The kinds that answer the NaN they were given rather than the arithmetic's own. Measured on the same
// host and the same classes: the negation of 0x7fc00000 is 0xffc00000 and of 0xffc00000 is 0x7fc00000,
// which is what a sign-bit flip answers; round, arcsine, arctangent, the hyperbolic arc-sine and the
// hyperbolic arc-tangent each answer a negative NaN with a negative NaN; and a select whose chosen
// operand is a NaN answers that NaN, so a select over a source of 0xffc00000 is 0xffc00000. Every other
// kind that computes answers 0x7fc00000 for either sign, which is CharonMPSGraphOwnNaN.
static int CharonMPSGraphKeepsTheNaNItWasGiven(CharonMPSGraphOperationKind kind)
{
    switch (kind) {
    case CharonMPSGraphOperationKindNegate:
    case CharonMPSGraphOperationKindRound:
    case CharonMPSGraphOperationKindSelect:
    case CharonMPSGraphOperationKindAsin:
    case CharonMPSGraphOperationKindAtan:
    case CharonMPSGraphOperationKindAsinh:
    case CharonMPSGraphOperationKindAtanh:
        return 1;
    default:
        return 0;
    }
}

// The kinds whose half answer this host gives itself rather than IEEE's. Measured over the sixteen
// classes in MPSDataTypeFloat16, and each of them is in the table in
// facts/MetalPerformanceShadersGraph/Core.md: a zero leaves the half path without its sign, a NaN is an
// infinity or a zero by kind, a negative argument to a square root or a reverse square root is a zero, a
// zero to a logarithm is -45440, and so on. A kind that is not in this list has no measured half rule of
// its own, so its result is the arithmetic's and the store narrows it - which is what the differential
// then measures, and what recorded-cells.txt records where the two still differ.
static int CharonMPSGraphHalfRule(CharonMPSGraphOperationKind kind)
{
    switch (kind) {
    case CharonMPSGraphOperationKindAbs:
    case CharonMPSGraphOperationKindIdentity:
    case CharonMPSGraphOperationKindAdd:
    case CharonMPSGraphOperationKindSubtract:
    case CharonMPSGraphOperationKindSquare:
    case CharonMPSGraphOperationKindReciprocal:
    case CharonMPSGraphOperationKindSqrt:
    case CharonMPSGraphOperationKindRsqrt:
    case CharonMPSGraphOperationKindLog:
    case CharonMPSGraphOperationKindSign:
        return 1;
    default:
        return 0;
    }
}

// One element of an arithmetic operation. The data type of the operands decides the arithmetic, as it
// does everywhere else in this framework: an integer type rounds on store and a floating point one
// rounds on store too, through the same store both families use. The store is asked for the release's
// own rounding of a halfway half - CharonMPSStoreRounded with the last argument set - which is this
// family's measured behaviour and no other family's: see CharonMPSFloatToHalfRounded.
//
// The third operand is 0.0 for a kind that takes fewer than three: a select and a clamp are the only
// kinds that read it, and passing a zero for the rest keeps one signature for the whole family.
static double CharonMPSGraphApply(CharonMPSGraphOperationKind kind, double a, double b, double c,
                                  MPSDataType operandType, MPSDataType resultType)
{
    int stored = CharonMPSGraphReadsOperandAsStored(kind);
    if (!stored) {
        a = CharonMPSGraphAsZero(a, operandType);
        b = CharonMPSGraphAsZero(b, operandType);
        c = CharonMPSGraphAsZero(c, operandType);
    }
    // An integer type has no infinity and no NaN, so the three questions about a value are asked of the
    // integer as it is: an integer is finite, is not infinite and is not a NaN. Measured on this host's
    // own MPSGraph with an int32 operand, where isNaN answers false for every element including the
    // largest negative one.
    int integral = operandType != MPSDataTypeFloat32 && operandType != MPSDataTypeFloat16;
    double result;
    switch (kind) {
    case CharonMPSGraphOperationKindAbs:
        result = integral ? a : fabs(a);
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
        // fmin and fmax, which answer the operand that is not a NaN: measured on this host's own MPSGraph,
        // a minimum of +inf and a NaN is +inf and of a NaN and 0x00000001 is 0x00000001, where an operator
        // that only compares would answer a NaN for both.
        result = fmin(a, b);
        break;
    case CharonMPSGraphOperationKindMaximum:
        result = fmax(a, b);
        break;
    case CharonMPSGraphOperationKindClamp:
        result = a < b ? a : b;
        break;
    case CharonMPSGraphOperationKindExpBase2:
        result = exp2(a);
        break;
    case CharonMPSGraphOperationKindExpBase10:
        // pow(10, x) and not exp10(x): the C library declares no exp10 for this target (a syntax check
        // with -target armv7-apple-ios6.0 answers "call to undeclared function 'exp10'"), and pow is the
        // spelling every one of them agrees with. The differential measures whether it agrees to the
        // byte over the sixteen classes.
        result = pow(10.0, a);
        break;
    case CharonMPSGraphOperationKindLogBase2:
        result = log2(a);
        break;
    case CharonMPSGraphOperationKindLogBase10:
        result = log10(a);
        break;
    case CharonMPSGraphOperationKindSin:
        result = sin(a);
        break;
    case CharonMPSGraphOperationKindCos:
        result = cos(a);
        break;
    case CharonMPSGraphOperationKindTan:
        result = tan(a);
        break;
    case CharonMPSGraphOperationKindSinh:
        result = sinh(a);
        break;
    case CharonMPSGraphOperationKindCosh:
        result = cosh(a);
        break;
    case CharonMPSGraphOperationKindTanh:
        result = tanh(a);
        break;
    case CharonMPSGraphOperationKindAsin:
        result = asin(a);
        break;
    case CharonMPSGraphOperationKindAcos:
        result = acos(a);
        break;
    case CharonMPSGraphOperationKindAtan:
        result = atan(a);
        break;
    case CharonMPSGraphOperationKindAsinh:
        result = asinh(a);
        break;
    case CharonMPSGraphOperationKindAcosh:
        result = acosh(a);
        break;
    case CharonMPSGraphOperationKindAtanh:
        result = atanh(a);
        break;
    case CharonMPSGraphOperationKindErf:
        result = erf(a);
        break;
    // The sign bit, read as a bit: a NaN compares false against everything, so a comparison would answer
    // a NaN's sign as neither, and the release answers the bit it carries.
    case CharonMPSGraphOperationKindSignBit:
        result = signbit(a) ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindFloor:
        result = integral ? a : floor(a);
        break;
    case CharonMPSGraphOperationKindCeil:
        result = integral ? a : ceil(a);
        break;
    // The two roundings the header separates: round is the half away from zero and rint is the one the
    // C library rounds to even with, which is what the two names in MPSGraphArithmeticOps.h mean.
    case CharonMPSGraphOperationKindRound:
        result = integral ? a : round(a);
        // A round that lands on zero is a positive zero: measured, round of -0.0, of -0x1p-126 and of
        // -0x1p-20 are each 0x00000000 where round(-0.0) in C is -0.0.
        if (result == 0.0)
            result = 0.0;
        break;
    case CharonMPSGraphOperationKindRint:
        result = integral ? a : rint(a);
        break;
    case CharonMPSGraphOperationKindIsNaN:
        result = integral ? 0.0 : (isnan(a) ? 1.0 : 0.0);
        break;
    case CharonMPSGraphOperationKindIsFinite:
        result = integral ? 1.0 : (isfinite(a) ? 1.0 : 0.0);
        break;
    case CharonMPSGraphOperationKindIsInfinite:
        result = integral ? 0.0 : (isinf(a) ? 1.0 : 0.0);
        break;
    case CharonMPSGraphOperationKindLogicalNot:
        result = a == 0.0 ? 1.0 : 0.0;
        break;
    // A comparison against a NaN is false and a comparison against something equal is true: that is what
    // the operators are, and the release's six predicates over the sixteen classes agree with it cell by
    // cell, so no branch of its own is written for them.
    case CharonMPSGraphOperationKindEqual:
        result = a == b ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindNotEqual:
        result = a != b ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindLessThan:
        result = a < b ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindLessThanOrEqualTo:
        result = a <= b ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindGreaterThan:
        result = a > b ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindGreaterThanOrEqualTo:
        result = a >= b ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindLogicalAnd:
        result = (a != 0.0 && b != 0.0) ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindLogicalOr:
        result = (a != 0.0 || b != 0.0) ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindLogicalNand:
        result = !(a != 0.0 && b != 0.0) ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindLogicalNor:
        result = !(a != 0.0 || b != 0.0) ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindLogicalXor:
        result = (a != 0.0) != (b != 0.0) ? 1.0 : 0.0;
        break;
    case CharonMPSGraphOperationKindLogicalXnor:
        result = (a != 0.0) == (b != 0.0) ? 1.0 : 0.0;
        break;
    // C's two remainders: fmod truncates towards zero and the floor modulo answers the remainder of
    // the same sign as the divisor, which is what "floor" in the name means.
    case CharonMPSGraphOperationKindModulo:
        result = fmod(a, b);
        break;
    case CharonMPSGraphOperationKindFloorModulo:
        result = fmod(fmod(a, b) + b, b);
        break;
    case CharonMPSGraphOperationKindPower:
        result = pow(a, b);
        break;
    case CharonMPSGraphOperationKindAtan2:
        result = atan2(a, b);
        break;
    // A division that answers a zero where IEEE would answer a NaN, which is what the "NoNaN" in its own
    // name says. It is the divisor that decides, and a NaN divisor is not one of them: measured over the
    // sixteen classes on this host's own MPSGraph, a zero divisor answers 0x00000000 for every numerator
    // while a NaN divisor answers the arithmetic's NaN - an infinity over a NaN is 0x7fc00000 and a NaN
    // over 2.0 is 0x7fc00000 - and a NaN numerator over an ordinary divisor is that NaN.
    case CharonMPSGraphOperationKindDivisionNoNaN:
        result = b == 0.0 ? 0.0 : a / b;
        break;
    case CharonMPSGraphOperationKindSelect:
        result = a != 0.0 ? b : c;
        break;
    // fmin(fmax(a, lo), hi), which is what answers a NaN with a bound rather than with a NaN: measured,
    // a clamp of a NaN between two equal bounds is that bound.
    case CharonMPSGraphOperationKindClamp3:
        result = fmin(fmax(a, b), c);
        break;
    case CharonMPSGraphOperationKindReLU:
        result = a > 0.0 ? a : 0.0;
        break;
    // A gradient passes the incoming gradient through where the source is on the other side of the
    // activation's own branch and answers the gradient itself times a zero of the same sign where it is
    // not, which is what the two gradient operations are. Measured over the sixteen classes: a ReLU
    // gradient of an incoming gradient of 1.0 over a source of -0.0 is 0x80000000, so the sign is the
    // incoming gradient's and not a positive zero, and a source that is a NaN is a NaN rather than the
    // gradient - an infinity over a NaN is 0x7fc00000 where the gradient itself would be 0x7f800000.
    case CharonMPSGraphOperationKindReLUGradient:
        result = isnan(b) ? NAN : (b > 0.0 ? a : a * 0.0);
        break;
    case CharonMPSGraphOperationKindSigmoid:
        result = 1.0 / (1.0 + exp(-a));
        break;
    // A sigmoid's gradient reads the source as the value that was activated, not as its answer: measured
    // over the sixteen classes, a sigmoidGradient of an incoming gradient of 1.0 over a source of 0.0 is
    // 0x3e800000, which is 1.0 times the sigmoid of 0.0 times one minus the sigmoid of 0.0.
    case CharonMPSGraphOperationKindSigmoidGradient: {
        double s = 1.0 / (1.0 + exp(-b));
        result = a * s * (1.0 - s);
        break;
    }
    default:
        result = a;
        break;
    }
    if (resultType == MPSDataTypeFloat16 && CharonMPSGraphHalfRule(kind)) {
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
    // A boolean is a truth and not a number, so a predicate's result goes through the store as the one
    // or the zero it is and the two rules above - the release's own NaN and the flush - do not touch it.
    if (resultType == MPSDataTypeBool)
        return result != 0.0 ? 1.0 : 0.0;
    if (CharonMPSGraphCopiesTheOperand(kind) || CharonMPSGraphKeepsTheNaNItWasGiven(kind))
        return stored ? result : CharonMPSGraphAsZero(result, resultType);
    return CharonMPSGraphOwnNaN(stored ? result : CharonMPSGraphAsZero(result, resultType));
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
    MPSGraphTensorData *third = inputs.count > 2 ? values[inputs[2]] : nil;
    if (left && ![left isKindOfClass:[MPSGraphTensorData class]])
        left = nil;
    if (right && ![right isKindOfClass:[MPSGraphTensorData class]])
        right = nil;
    if (third && ![third isKindOfClass:[MPSGraphTensorData class]])
        third = nil;
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
    void *out = [result charon_mps_bytes];
    MPSDataType operandType = left.dataType;
    if (right) {
        if (third) {
            for (NSUInteger i = 0; i < count; i++)
                CharonMPSStoreRounded(out, dataType, i,
                           CharonMPSGraphApply(kind, CharonMPSLoad([left charon_mps_bytes], operandType, i),
                                               CharonMPSLoad([right charon_mps_bytes], right.dataType, i),
                                               CharonMPSLoad([third charon_mps_bytes], third.dataType, i),
                                               operandType, dataType), 1);
        } else {
            for (NSUInteger i = 0; i < count; i++)
                CharonMPSStoreRounded(out, dataType, i,
                           CharonMPSGraphApply(kind, CharonMPSLoad([left charon_mps_bytes], operandType, i),
                                               CharonMPSLoad([right charon_mps_bytes], right.dataType, i), 0.0,
                                               operandType, dataType), 1);
        }
    } else {
        for (NSUInteger i = 0; i < count; i++)
            CharonMPSStoreRounded(out, dataType, i,
                       CharonMPSGraphApply(kind, CharonMPSLoad([left charon_mps_bytes], operandType, i), 0.0, 0.0,
                                           operandType, dataType), 1);
    }
    values[output] = result;
}

@end