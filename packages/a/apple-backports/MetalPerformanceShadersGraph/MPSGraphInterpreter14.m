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
    // Five more, all measured the same way and all of them the same kind of case: the release answers a
    // denormal with the denormal, because for these five its own answer for a tiny argument is the
    // argument. sin, sinh, arcsine, asinh and the hyperbolic arc-tangent of 0x00000001 are 0x00000001 and
    // of 0x80000001 are 0x80000001, where a kernel that read the operand as a zero would answer a zero.
    // arctangent, the hyperbolic tangent and erf do not: measured, each of the three answers 0x00000000
    // for 0x00000001 and 0x80000001 for 0x80000001, and they are left out of this list for that reason.
    case CharonMPSGraphOperationKindSin:
    case CharonMPSGraphOperationKindSinh:
    case CharonMPSGraphOperationKindAsin:
    case CharonMPSGraphOperationKindAsinh:
    case CharonMPSGraphOperationKindAtanh:
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
// What a kind's answer is in MPSDataTypeFloat16 when an operand is a NaN, measured for each of them over
// the case file's thirty-two classes and written down in facts/MetalPerformanceShadersGraph/Core.md. The
// release's half kernels do not agree with each other here, which is the whole of what this table is: the
// arithmetic family answers an infinity of the NaN's own sign, the sine and the cosine answer a zero, the
// inverse hyperbolics answer the canonical positive NaN, the error function and the hyperbolic tangent
// saturate at the sign of the NaN, a power saturates at one whatever the sign, and a sigmoid answers one
// for a positive NaN and a zero for a negative one.
typedef NS_ENUM(NSInteger, CharonMPSGraphHalfNaN) {
    CharonMPSGraphHalfNaNNone = 0,
    // An infinity of the NaN's own sign: the arithmetic family's own rule, and the one `ceil`, `floor`,
    // `round`, `select` and a ReLU's gradient follow. Measured: each of 0x7e00 and 0xfe00 answers an
    // infinity of that sign, 0x7c00 and 0xfc00.
    CharonMPSGraphHalfNaNInfinityOfSign,
    // The same with the sign of the operand turned over first, which is what a negation does to a NaN
    // before it becomes an infinity: measured, the negation of 0x7e00 is 0xfc00 and of 0xfe00 is 0x7c00.
    CharonMPSGraphHalfNaNInfinityOfFlippedSign,
    // A zero. Measured: the sine and the cosine of 0x7e00 and of 0xfe00 are each 0x0000, and so is each
    // of them of an infinity of either sign.
    CharonMPSGraphHalfNaNZero,
    // The canonical positive NaN, 0x7e00, whichever sign the operand carried: measured, the arcsine, the
    // hyperbolic arc-sine and the hyperbolic arc-tangent of 0xfe00 are 0x7e00.
    CharonMPSGraphHalfNaNCanonical,
    // A saturation at the sign of the NaN: the error function and the hyperbolic tangent answer 0x3c00
    // for 0x7e00 and 0xbc00 for 0xfe00.
    CharonMPSGraphHalfNaNSaturates,
    // A saturation at one whatever the sign: a power of an infinity, a NaN or a negative number is
    // 0x3c00, measured, and so is a power of a negative ordinary value.
    CharonMPSGraphHalfNaNSaturatesAtOne,
    // One for a positive NaN and a zero for a negative one: measured, that is what a sigmoid answers.
    CharonMPSGraphHalfNaNSigmoid
};

static CharonMPSGraphHalfNaN CharonMPSGraphHalfNaNOf(CharonMPSGraphOperationKind kind)
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
    case CharonMPSGraphOperationKindCeil:
    case CharonMPSGraphOperationKindFloor:
    case CharonMPSGraphOperationKindRound:
    case CharonMPSGraphOperationKindSelect:
    case CharonMPSGraphOperationKindReLUGradient:
        return CharonMPSGraphHalfNaNInfinityOfSign;
    case CharonMPSGraphOperationKindNegate:
        return CharonMPSGraphHalfNaNInfinityOfFlippedSign;
    case CharonMPSGraphOperationKindSin:
    case CharonMPSGraphOperationKindCos:
    case CharonMPSGraphOperationKindLogBase2:
        return CharonMPSGraphHalfNaNZero;
    case CharonMPSGraphOperationKindAsin:
    case CharonMPSGraphOperationKindAcos:
    case CharonMPSGraphOperationKindAsinh:
    case CharonMPSGraphOperationKindAcosh:
    case CharonMPSGraphOperationKindAtanh:
        return CharonMPSGraphHalfNaNCanonical;
    case CharonMPSGraphOperationKindErf:
    case CharonMPSGraphOperationKindTanh:
        return CharonMPSGraphHalfNaNSaturates;
    case CharonMPSGraphOperationKindPower:
        return CharonMPSGraphHalfNaNSaturatesAtOne;
    case CharonMPSGraphOperationKindSigmoid:
        return CharonMPSGraphHalfNaNSigmoid;
    case CharonMPSGraphOperationKindReLU:
        // Measured, and it is neither of the two above: a ReLU of 0x7e00 is 0x7c00 and of 0xfe00 is
        // 0x0000, so a positive NaN is a positive infinity and a negative one is a zero.
        return CharonMPSGraphHalfNaNInfinityOfSign;
    default:
        return CharonMPSGraphHalfNaNNone;
    }
}

static int CharonMPSGraphHalfRule(CharonMPSGraphOperationKind kind)
{
    return CharonMPSGraphHalfNaNOf(kind) != CharonMPSGraphHalfNaNNone;
}

// One element of an arithmetic operation. The data type of the operands decides the arithmetic, as it
// does everywhere else in this framework: an integer type rounds on store and a floating point one
// rounds on store too, through the same store both families use. The store is asked for the release's
// own rounding of a halfway half - CharonMPSStoreRounded with the last argument set - which is this
// family's measured behaviour and no other family's: see CharonMPSFloatToHalfRounded.
//
// The third operand is 0.0 for a kind that takes fewer than three: a select and a clamp are the only
// kinds that read it, and passing a zero for the rest keeps one signature for the whole family.
//
// `latch` is the one rule that is not the kind's own: an operation that latches a NaN answers a NaN if
// any operand is one, and the arithmetic below otherwise. It is read out of the operation's parameters
// rather than out of its kind for the same reason the fold table is - the method that asks for it
// arrived in a later release than the object this is, and what it asks for is "this arithmetic, and a
// NaN on either side wins", which is two things this object can say without naming that release.
static double CharonMPSGraphApply(CharonMPSGraphOperationKind kind, double a, double b, double c,
                                  MPSDataType operandType, MPSDataType resultType, int latch)
{
    if (latch && (isnan(a) || isnan(b) || isnan(c)))
        return CharonMPSGraphOwnNaN(NAN);
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
        if (isnan(a) || isnan(b) || isnan(c)) {
            double sign = isnan(a) ? a : (isnan(b) ? b : c);
            switch (CharonMPSGraphHalfNaNOf(kind)) {
            case CharonMPSGraphHalfNaNInfinityOfSign:
                result = copysign(INFINITY, sign);
                break;
            case CharonMPSGraphHalfNaNInfinityOfFlippedSign:
                result = copysign(INFINITY, -sign);
                break;
            case CharonMPSGraphHalfNaNZero:
                result = 0.0;
                break;
            case CharonMPSGraphHalfNaNCanonical:
                result = NAN;
                break;
            case CharonMPSGraphHalfNaNSaturates:
                result = copysign(1.0, sign);
                break;
            case CharonMPSGraphHalfNaNSaturatesAtOne:
                result = 1.0;
                break;
            case CharonMPSGraphHalfNaNSigmoid:
                result = signbit(sign) ? 0.0 : 1.0;
                break;
            default:
                // The two the arithmetic family has and the table above does not: the square and the
                // absolute value answer a positive infinity for a NaN of either sign, and a reciprocal
                // answers a zero of either sign.
                result = (kind == CharonMPSGraphOperationKindReciprocal) ? 0.0 : INFINITY;
                break;
            }
            // The square root and the sign are the two the table cannot hold, because their answer is
            // read off the bit and not off the class: measured, the square root of a positive NaN is
            // 0x7c00 and of a negative one 0x0000, and the sign of a NaN is the sign of the NaN.
            if (kind == CharonMPSGraphOperationKindSqrt)
                result = signbit(sign) ? 0.0 : INFINITY;
            else if (kind == CharonMPSGraphOperationKindSign)
                result = copysign(1.0, sign);
            if (kind == CharonMPSGraphOperationKindSquare || kind == CharonMPSGraphOperationKindAbs)
                result = INFINITY;
        } else if (isinf(a) && (kind == CharonMPSGraphOperationKindSin || kind == CharonMPSGraphOperationKindCos)) {
            // Measured: the sine and the cosine of an infinity of either sign are 0x0000, where the
            // arithmetic of an infinity is a NaN.
            result = 0.0;
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
    }
    // A zero is a positive zero in half as it is in the float types, and it is one rule for every kind
    // rather than one per operation: measured, the ceiling of a positive zero, the floor of a positive
    // zero, the sine of a positive zero, a product of a negative zero, the negation of a negative zero, a
    // maximum of -1.0 and -0.0, a select whose value is a negative zero, a ReLU's gradient of a negative
    // ordinary source and an error function of a positive zero are each 0x0000, where IEEE answers a
    // zero of the operand's own sign.
    //
    // The one kernel of this family that does not have it is the latching one of 15.0, and that is
    // measured rather than assumed: over the same sixteen classes in float16, its maximum of -1.0 and
    // -0.0 answers 0x8000 and its maximum of +0.0 and -inf answers 0x8000, where the kernel above answers
    // 0x0000 for the same two pairs and where the port's float32 answer is -0.0 for both. So the rule
    // belongs to the kernel that has it, and which kernel an operation is comes out of its parameters.
    if (resultType == MPSDataTypeFloat16 && result == 0.0 && !latch)
        result = 0.0;
    // A boolean is a truth and not a number, so a predicate's result goes through the store as the one
    // or the zero it is and the two rules above - the release's own NaN and the flush - do not touch it.
    if (resultType == MPSDataTypeBool)
        return result != 0.0 ? 1.0 : 0.0;
    // A zero is a positive zero for two of the transcendentals, which is a rule and not IEEE's: measured
    // over the same sixteen classes, the arctangent and the hyperbolic tangent of -0.0 are 0x00000000
    // where IEEE answers -0.0, and the hyperbolic tangent of a negative denormal is 0x00000000 as well.
    // It is applied after the flush, so a denormal that flushed to a zero of either sign comes out
    // positive, and only for those two: the identity, a reciprocal, a square root, a remainder and a
    // minimum all answer -0.0 for a negative zero on this host, measured, and are left alone.
    if ((kind == CharonMPSGraphOperationKindAtan || kind == CharonMPSGraphOperationKindTanh) &&
        result == 0.0)
        result = 0.0;
    if (CharonMPSGraphCopiesTheOperand(kind))
        return stored ? result : CharonMPSGraphAsZero(result, resultType);
    double narrowed = stored ? result : CharonMPSGraphAsZero(result, resultType);
    // A kind that keeps the NaN it was given keeps it only when it WAS given one: the arcsine of a NaN
    // is that NaN, measured, and the arcsine of -inf is 0x7fc00000 and not a NaN of a negative sign.
    if (CharonMPSGraphKeepsTheNaNItWasGiven(kind) && (isnan(a) || isnan(b)))
        return narrowed;
    return CharonMPSGraphOwnNaN(narrowed);
}

// The reduction family is not element by element. Every element of the operand contributes to one
// element of the result, and which one is the operand's shape with the reduced axes taken out, so the
// walk here is over the OPERAND and folds into the result, which is the one place in this interpreter
// where that is true.
//
// The walk is a TABLE, and the table is keyed by the operation's own parameters rather than by which
// kind of operation it is. That is what lets every release's reduction - 14.0's eight here, 15.0's two
// argument reductions and two binary NaN-propagating extremes, 15.3's two truth folds - share one walk
// while every one of those objects names only its own SDK methods: an operation says which fold it is
// (@"combination"), whether a NaN latches (@"propagateNaN"), whether the answer is an index rather than
// a value (@"index"), and none of those words is a name of any release's framework.
//
// The result buffer is the accumulator, so every fold is written back through the type the result is
// stored as and each partial answer is the value that type can hold - which is what a reduction that
// accumulates in its own storage type does. Measured on this host's own MPSGraph over the feeds
// .agent-work/runs/probe-reduction.out carries: the sum of (1, 2, 3, 4) in float16 is 0x4900 = 10 and
// in float32 0x41200000 = 10, and the mean of the same four in float16 is 0x4100 = 2.5.
//
// One fold, and its seed and the shape of its step. The seeds are measured rather than reasoned: a sum
// starts at the zero of the type and a product at its one, the two extremes start at the infinities (a
// maximum at negative infinity and a minimum at positive), and the two truth folds start at the identity
// of their own fold - one for the "and" and zero for the "or" - which is why a fold over any number of
// elements is right and which is measured over rows that hold a zero and rows that do not.
typedef struct {
    const char *combination;
    double seed;
    int isExtreme;   // a comparison decides each fold, so a NaN loses it
    int isLesser;    // the minimum rather than the maximum
    int isTruth;     // the operand is a question about nonzeroness, not a number to add up
    int isOr;        // within a truth fold: any element rather than every one
    int multiplies;  // the step is a product rather than a sum
    int divides;     // the answer is over the count of the reduced set
} CharonMPSGraphFold;

static const CharonMPSGraphFold CharonMPSGraphFolds[] = {
    // seed, isExtreme, isLesser, isTruth, isOr, multiplies, divides
    {"sum", 0.0, 0, 0, 0, 0, 0, 0},
    {"product", 1.0, 0, 0, 0, 0, 1, 0},
    {"maximum", -INFINITY, 1, 0, 0, 0, 0, 0},
    {"minimum", INFINITY, 1, 1, 0, 0, 0, 0},
    {"and", 1.0, 0, 0, 1, 0, 0, 0},
    {"or", 0.0, 0, 0, 1, 1, 0, 0},
    // The mean and the variance are the sum over the reduced set and the sum of the squared deviations
    // about it, both taken over the count: the difference between them is in the second walk, not in the
    // fold, so the two share the sum's row here.
    {"mean", 0.0, 0, 0, 0, 0, 0, 1},
    {"variance", 0.0, 0, 0, 0, 0, 0, 1},
};

static const CharonMPSGraphFold *CharonMPSGraphFoldNamed(const char *combination)
{
    if (combination == NULL)
        return NULL;
    for (unsigned i = 0; i < sizeof(CharonMPSGraphFolds) / sizeof(CharonMPSGraphFolds[0]); i++)
        if (strcmp(CharonMPSGraphFolds[i].combination, combination) == 0)
            return &CharonMPSGraphFolds[i];
    return NULL;
}

// Which output element one input element folds into. A tensor is row-major with its FIRST axis the
// slowest moving, so the coordinates come out by dividing from the LAST axis backwards - reading them the
// other way is what made this port answer the transpose of every reduction at first, because the
// coordinates of a 2x4's elements 0 and 2 were read as one row and one column when they are both of the
// first row. `stride` is each kept axis's own stride in the RESULT, computed once by the caller, so that
// the coordinates can be folded into an index as they are met.
static NSUInteger CharonMPSGraphReductionIndex(NSArray<NSNumber *> *shape, const unsigned char *dropped,
                                               const unsigned long long *stride, NSUInteger element)
{
    NSUInteger rank = shape.count;
    NSUInteger index = element, out = 0;
    for (NSUInteger axis = rank; axis-- > 0;) {
        NSUInteger extent = (NSUInteger)shape[axis].unsignedIntegerValue;
        NSUInteger coordinate = extent ? index % extent : 0;
        if (extent)
            index /= extent;
        if (!dropped[axis])
            out += (NSUInteger)(coordinate * stride[axis]);
    }
    return out;
}

// The coordinate of one element along one axis, which is the index an argument reduction answers. The
// same dividing from the last axis backwards, read out for the axis itself.
static long CharonMPSGraphCoordinate(NSArray<NSNumber *> *shape, NSUInteger axis, NSUInteger element)
{
    NSUInteger rank = shape.count, index = element;
    for (NSUInteger i = rank; i-- > 0;) {
        NSUInteger extent = (NSUInteger)shape[i].unsignedIntegerValue;
        if (i == axis)
            return (long)(extent ? index % extent : 0);
        if (extent)
            index /= extent;
    }
    return 0;
}

// One step of a fold: the held answer and the value that has just been read, and the answer after it. It
// is one function because the reduction walk and the cumulative walk fold with the same four steps and the
// same seeds, and a second copy of these rules would be a second thing to keep measured - the NaN that
// loses a comparison and therefore skips, the truth fold's test against zero, and the arithmetic's own NaN
// for the sum and the product.
// `propagates` and `tiesToValue` are the two rules that belong to a kernel rather than to a fold, and both
// are measured: the two propagating reductions of 14.0 latch a NaN and every other fold skips one, and the
// reduction family's comparison is strict - a row of (0, -0, 0, -0) answers 0 for a maximum, the first of
// the equal elements - where a scan's is not: over the same row scanned in reverse, the release answers a
// NEGATIVE zero where a strict comparison keeps the zero it already held, and answers a positive zero where
// a strict comparison would take the negative one it was handed. So the reduction passes (1, 0) here and
// the scan (0, 1).
static double CharonMPSGraphFoldStep(const CharonMPSGraphFold *fold, double held, double value, int propagates,
                                     int tiesToValue)
{
    if (fold->isExtreme) {
        // One comparison, and every rule of the four extremes is in it. A NaN loses the comparison against
        // anything including another NaN, so it is skipped - which is how a maximum that does not propagate
        // ignores one, and which is every cumulative extreme (measured: a NaN in a scan of either extreme is
        // skipped in both directions). The propagating variant latches instead: a NaN that has reached this
        // element is its answer, a NaN that arrives puts it there, and nothing after it can move it, because
        // a comparison against a NaN also loses. Only the two reductions of 14.0 latch.
        if (isnan(value))
            return propagates ? CharonMPSGraphOwnNaN(NAN) : held;
        if (propagates && isnan(held))
            return held;
        if (fold->isLesser)
            return tiesToValue ? (value <= held ? value : held) : (value < held ? value : held);
        return tiesToValue ? (value >= held ? value : held) : (value > held ? value : held);
    }
    if (fold->isTruth) {
        // The two truth folds, which are a question about every element rather than an arithmetic over it,
        // and the answer is written in the operand's own type: measured, an "and" of a row holding a zero
        // answers 0 and of a row of nothing but NaNs answers 1, so the test is against zero and a NaN is a
        // nonzero like any other value. The held answer is the one or the zero the buffer holds.
        int truth = value != 0.0;
        int was = held != 0.0;
        return (fold->isOr ? (truth || was) : (truth && was)) ? 1.0 : 0.0;
    }
    // A NaN that leaves the sum or the product is the arithmetic's own NaN and not the one it was handed,
    // as everywhere else in this interpreter: measured, the product of a row of (infinity, -infinity, NaN,
    // -NaN) is 0x7fc00000 on this host and was a negative NaN here until the fold was put through this rule.
    return CharonMPSGraphOwnNaN(fold->multiplies ? held * value : held + value);
}

static void CharonMPSGraphReduce(MPSGraphOperation *operation, MPSGraphTensorData *source,
                                  MPSGraphTensorData *meanGiven, MPSGraphTensorData *result)
{
    NSDictionary *parameters = operation.charon_mps_parameters;
    NSArray<NSNumber *> *shape = source.shape;
    NSArray<NSNumber *> *axes = parameters[@"axes"];
    NSUInteger sourceCount = [source charon_mps_elementCount];
    NSUInteger resultCount = [result charon_mps_elementCount];
    NSUInteger rank = shape.count;
    MPSDataType type = source.dataType;
    MPSDataType resultType = result.dataType;
    size_t resultSize = MPSSizeofMPSDataType(resultType);
    void *in = [source charon_mps_bytes];
    void *out = [result charon_mps_bytes];
    const CharonMPSGraphFold *fold = CharonMPSGraphFoldNamed([parameters[@"combination"] UTF8String]);
    if (fold == NULL || !axes || sourceCount == 0 || resultCount == 0)
        return;

    // A reduction over no axis at all is the identity: the operand, byte for byte, and no fold. Measured
    // on this host's own MPSGraph over the sixteen classes, axes:@[] answers the 2x4 the operand already
    // was for a sum, for a product, and for the two truth folds of 15.3 - and the last two are what say
    // so, because a sum and a product of the identity are the identity either way: an "and" of the set of
    // elements a single element contributes would answer 1 and 0, and answers -1.0 and +inf instead.
    if (axes.count == 0) {
        size_t elementSize = MPSSizeofMPSDataType(type);
        for (NSUInteger i = 0; i < resultCount && i < sourceCount; i++)
            memcpy((char *)out + i * resultSize, (const char *)in + i * elementSize,
                   MIN(resultSize, elementSize));
        return;
    }

    unsigned char *dropped = calloc(rank ? rank : 1, 1);
    unsigned long long *stride = calloc(rank ? rank : 1, sizeof(unsigned long long));
    double count = 1.0;
    for (NSUInteger i = 0; i < axes.count; i++) {
        NSUInteger axis = (NSUInteger)axes[i].integerValue;
        dropped[axis] = 1;
        count *= (double)shape[axis].unsignedIntegerValue;
    }
    // Each kept axis's own stride in the result, which is the product of the kept extents after it.
    {
        unsigned long long running = 1;
        for (NSUInteger axis = rank; axis-- > 0;) {
            if (!dropped[axis]) {
                stride[axis] = running;
                running *= (unsigned long long)shape[axis].unsignedIntegerValue;
            }
        }
    }

    // Everything the walk needs to know about the operation is in these three, and none of them is a
    // name of any release's framework: whether a NaN latches (the two propagating extremes of 14.0, and
    // nothing else in the family), whether the answer is an index rather than a value (the two argument
    // reductions of 15.0), and which fold to run.
    int propagates = [parameters[@"propagateNaN"] boolValue];
    int isIndex = [parameters[@"index"] boolValue];

    if (isIndex) {
        // THE ARGUMENT REDUCTIONS. What is measured, over the sixteen classes of the arithmetic cases in
        // this file and over rows chosen for their ties, in float32, float16 and int32 alike:
        //
        //  - the answer is the index of the FIRST element holding the extreme, so a row of (4, 4, 4, 9)
        //    answers 3 for a maximum and a row of (9, 9, 1, 1) answers 0 and 2, and a comparison that
        //    replaced on equality would answer the last of them.
        //  - a NaN loses every comparison and so is never the answer, wherever it sits: (nan, 1, 2, 3)
        //    answers 3 for a maximum and 1 for a minimum, (1, 2, 3, nan) answers 2 and 0, and a row of
        //    nine with a NaN at either end answers 8 and 7 for a maximum.
        //  - a reduced set of nothing but NaNs answers -1 in both, which is the "nothing was found"
        //    answer rather than an index into an empty set.
        //  - the result is stored as MPSDataTypeInt32 whatever the operand's own type is, and the two
        //    signed zeros compare equal, so (0, -0, 0, -0) answers 0 for both.
        //
        // The held extreme is kept beside the result rather than read back out of it, because the result
        // holds an index rather than a value and the comparison needs the value it belongs to.
        double *held = calloc(resultCount, sizeof(double));
        long *found = calloc(resultCount, sizeof(long));
        // The axis whose coordinate an index is a coordinate of: the argument reductions of 15.0 take one
        // axis, which is what the release's own methods hand over, so there is one to read.
        NSUInteger reducedAxis = (NSUInteger)axes.firstObject.integerValue;
        for (NSUInteger i = 0; i < resultCount; i++)
            found[i] = -1;
        for (NSUInteger i = 0; i < sourceCount; i++) {
            NSUInteger index = CharonMPSGraphReductionIndex(shape, dropped, stride, i);
            if (index >= resultCount)
                continue;
            double value = CharonMPSLoad(in, type, i);
            if (isnan(value))
                continue;
            if (found[index] < 0 || (fold->isLesser ? value < held[index] : value > held[index])) {
                found[index] = CharonMPSGraphCoordinate(shape, reducedAxis, i);
                held[index] = value;
            }
        }
        for (NSUInteger i = 0; i < resultCount; i++)
            CharonMPSStoreRounded(out, resultType, i, (double)found[i], 1);
        free(found);
        free(held);
        free(stride);
        free(dropped);
        return;
    }

    // What each fold starts from, and this is measured rather than reasoned: the seeds are the table's
    // own, and the two extremes' infinities are what says what a reduced set of nothing but NaNs answers
    // last: measured on this host's own MPSGraph over a 2x4 whose eight elements are all NaN, over the
    // sixteen classes of the arithmetic cases in this file, reductionMaximumWithTensor:axis:1 answers
    // (0xff800000, 0xff800000) - negative infinity of each - and reductionMinimumWithTensor:axis:1 answers
    // (0x7f800000, 0x7f800000). So the kernel seeds an infinity and lets a comparison decide the rest,
    // and a NaN loses every comparison and is therefore skipped: a maximum over a row of (1, NaN, 3, 4)
    // answers 4, measured, and one over a row of nothing but NaNs answers what it was seeded with.
    //
    // The buffer is written before the walk rather than read from: a sum that began from whatever the
    // result buffer happened to hold would answer that plus the sum, which is how this port answered
    // 3 for a sum of 11 until the seed was measured.
    memset(out, 0, resultCount * resultSize);
    // The seed is written wherever it is not the zero the buffer was just cleared to, which is the
    // product's one, the two extremes' infinities and the two truth folds' identities. A sum's zero, the
    // mean's and the variance's are what the clearing already wrote.
    if (fold->multiplies || fold->isExtreme || fold->isTruth)
        for (NSUInteger i = 0; i < resultCount; i++)
            CharonMPSStoreRounded(out, resultType, i, fold->seed, 1);
    for (NSUInteger i = 0; i < sourceCount; i++) {
        NSUInteger index = CharonMPSGraphReductionIndex(shape, dropped, stride, i);
        if (index >= resultCount)
            continue;
        double value = CharonMPSLoad(in, type, i);
        double held = CharonMPSLoad(out, resultType, index);
        CharonMPSStoreRounded(out, resultType, index, CharonMPSGraphFoldStep(fold, held, value, propagates, 0), 1);
    }
    if (fold->divides) {
        // The mean of the reduced set. Where it came from is the only difference between the two
        // variance forms and none at all for the mean: the sum above is already in the result buffer, so
        // the mean is that over the count, written back through the type so that an integer mean is the
        // truncated quotient - measured on this host's own MPSGraph, the mean of (-3, -2, -1, 0) as int32
        // is -1 and not -2, and the mean of (1, 2, 3, 4) as float16 is 0x4100 = 2.5.
        // It goes into a buffer of its own rather than into the result, because the variance needs it
        // again after the sum is no longer there.
        int isVariance = strcmp(fold->combination, "variance") == 0;
        unsigned char *mean = meanGiven ? (unsigned char *)[meanGiven charon_mps_bytes]
                                        : malloc(resultCount * resultSize);
        if (!meanGiven) {
            for (NSUInteger i = 0; i < resultCount; i++)
                CharonMPSStoreRounded(mean, resultType, i, CharonMPSLoad(out, resultType, i) / count, 1);
        }
        MPSDataType meanType = meanGiven ? meanGiven.dataType : resultType;
        if (isVariance) {
            // The mean of the squared deviations, taken about that mean: a second walk over the operand,
            // because a result element's mean is only known once the first has been through every axis of
            // the element it belongs to.
            memset(out, 0, resultCount * resultSize);
            for (NSUInteger i = 0; i < sourceCount; i++) {
                NSUInteger index = CharonMPSGraphReductionIndex(shape, dropped, stride, i);
                if (index >= resultCount)
                    continue;
                double deviation = CharonMPSLoad(in, type, i) - CharonMPSLoad(mean, meanType, index);
                CharonMPSStoreRounded(out, resultType, index,
                                      CharonMPSLoad(out, resultType, index) + deviation * deviation, 1);
            }
            // Over the count, written back through the type, as the mean is: the variance is a mean of
            // the squared deviations and not their sum. Measured on this host's own MPSGraph, the
            // variance of a row of (1, 2, 3, 4) is 0x3fa00000 = 1.25 and the sum of the squares about the
            // mean is five times that.
            for (NSUInteger i = 0; i < resultCount; i++)
                CharonMPSStoreRounded(out, resultType, i, CharonMPSLoad(out, resultType, i) / count, 1);
        }
        // The mean itself is the result of the mean; for the variance the result is what the second walk
        // above wrote, and copying the mean over it would answer the mean for a variance.
        if (!isVariance)
            for (NSUInteger i = 0; i < resultCount; i++)
                CharonMPSStoreRounded(out, resultType, i, CharonMPSLoad(mean, meanType, i), 1);
        if (!meanGiven)
            free(mean);
    }
    free(stride);
    free(dropped);
}

// THE CUMULATIVE FAMILY, which is the fold above walked along an axis instead of across a set: the result
// is the operand's own shape, and each element holds a fold of the elements on one side of it. Everything
// the walk needs is in the operation's parameters - which fold, which axis, which way, and whether an
// element is in its own answer - so 16.0's sixteen methods share this one walk and name none of it.
//
// The rule is one sentence and every part of it is measured on this host's own MPSGraph over rows of
// ordinary values, over rows chosen for their ties, over the sixteen classes and over a row of nothing but
// NaNs, in float32, int32 and float16 alike:
//
//   the accumulator is the result buffer and starts at the fold's own seed, the walk goes along the axis in
//   the direction the flag says, and at each position the element is folded into the answer BEFORE that
//   answer is written - unless the answer is exclusive, in which case the answer is written first and the
//   element is folded into the position after it.
//
// Measured over the 2x4 of (1, 2, 3, 4 | 10, 20, 30, 40), axis 1: a cumulative sum answers
// (1, 3, 6, 10 | 10, 30, 60, 100), a reverse one (10, 9, 7, 4 | 100, 90, 70, 40) and an exclusive reverse one
// (9, 7, 4, 0 | 90, 70, 40, 0); a cumulative product answers (1, 2, 6, 24 | 10, 200, 6000, 240000) and a
// reverse one (24, 24, 12, 4 | 240000, 24000, 1200, 40), which is the same rule and not a second one; a
// cumulative maximum is the row itself, (1, 2, 3, 4 | 10, 20, 30, 40), and an exclusive reverse maximum is
// (4, 4, 4, -inf | 40, 40, 40, -inf) - the seed where the walk starts, and the mirror of a forward
// exclusive maximum's (-inf, 1, 2, 3). A negative axis is the axis counted from the end, measured: axis:-1
// answers what axis:1 answers.
//
// A NaN loses every comparison and is skipped, as in the reduction family, so the position whose whole side
// of the walk is NaN answers the seed: measured over a row of (1, 2, 3, NaN), a reverse exclusive maximum
// answers (3, 3, -inf, -inf) and a reverse exclusive minimum (2, 3, +inf, +inf), and a forward exclusive
// maximum over the same row answers (-inf, 1, 2, 3). The accumulator is the result's own storage, so every
// partial answer is the value that type can hold: measured, the cumulative sum of (1, 2, 3, 4) in float16
// is 0x4900 = 10 and the cumulative product of four halves of 65504 is an infinity from the second step.
// The seed a scan of the two extremes starts from, and it is NOT the reduction family's infinity: measured,
// an exclusive cumulative maximum of a 2x4 answers 0xff7fffff at the position the walk starts and an
// exclusive cumulative minimum answers 0x7f7fffff there, in float32; in float16 they are 0xfbff and 0x7bff,
// the largest finite half of each sign, and in int32 they are INT32_MIN and INT32_MAX. So the seed is the
// type's own extreme FINITE value - the identity of a comparison over the values that type can hold - while
// the reduction family of 14.0 seeds an infinity, which is a different kernel and a different measurement and
// is left as it is. A sum's seed is the zero of the type and a product's its one, in every type measured.
static double CharonMPSGraphScanSeed(const CharonMPSGraphFold *fold, MPSDataType type)
{
    if (!fold->isExtreme)
        return fold->seed;
    double magnitude = 0.0;
    switch (type) {
    case MPSDataTypeFloat32:
        magnitude = (double)FLT_MAX;
        break;
    case MPSDataTypeFloat16:
        magnitude = 65504.0;          // 0x7bff, the largest finite half
        break;
    case MPSDataTypeInt8:
        magnitude = fold->isLesser ? 127.0 : 128.0;
        break;
    case MPSDataTypeInt16:
        magnitude = fold->isLesser ? 32767.0 : 32768.0;
        break;
    case MPSDataTypeInt32:
        magnitude = fold->isLesser ? 2147483647.0 : 2147483648.0;
        break;
    case MPSDataTypeInt64:
        magnitude = fold->isLesser ? 9223372036854775807.0 : 9223372036854775808.0;
        break;
    case MPSDataTypeUInt8:
        magnitude = 255.0;
        break;
    case MPSDataTypeUInt16:
        magnitude = 65535.0;
        break;
    case MPSDataTypeUInt32:
        magnitude = 4294967295.0;
        break;
    case MPSDataTypeUInt64:
        magnitude = 18446744073709551615.0;
        break;
    default:
        // A boolean has no ordering to seed: it is the same answer whatever the walk starts from, and the
        // zero is the false that a fold of nothing over it is.
        magnitude = 1.0;
        break;
    }
    return fold->isLesser ? magnitude : -magnitude;
}

static void CharonMPSGraphScan(MPSGraphOperation *operation, MPSGraphTensorData *source,
                               MPSGraphTensorData *axisData, MPSGraphTensorData *result)
{
    NSDictionary *parameters = operation.charon_mps_parameters;
    const CharonMPSGraphFold *fold = CharonMPSGraphFoldNamed([parameters[@"scanCombination"] UTF8String]);
    NSArray<NSNumber *> *shape = source.shape;
    NSUInteger rank = shape.count;
    NSUInteger count = rank ? [source charon_mps_elementCount] : 0;
    if (fold == NULL || count == 0)
        return;
    MPSDataType type = source.dataType;
    MPSDataType resultType = result.dataType;
    void *in = [source charon_mps_bytes];
    void *out = [result charon_mps_bytes];

    // The axis is the caller's or the feed's, and both go through the same normalisation: negative counted
    // from the end, and an axis outside the rank refused. The refusal is the same one the reduction family
    // raises when its graph is built - the release destroys the process over one (MPSGraphNDArrayScan.mm:253
    // asserts "This class only supports axis = 0, 1, 2, 3" and the process is gone), so this is the one form
    // of "this graph cannot run" a caller can handle. A fed axis is only known here, at run time.
    NSInteger axis;
    if (parameters[@"scanAxisTensor"]) {
        if (axisData == nil || ![axisData isKindOfClass:[MPSGraphTensorData class]]) {
            CharonMPSGraphRefuse(@"MPSGraph: the cumulative operation named %@ was fed no value for its "
                                 @"axis, so nothing was written to its output", [operation name]);
            return;
        }
        NSInteger fed = (NSInteger)CharonMPSLoad([axisData charon_mps_bytes], axisData.dataType, 0);
        axis = fed < 0 ? fed + (NSInteger)rank : fed;
        if (axis < 0 || axis >= (NSInteger)rank) {
            [NSException raise:NSInvalidArgumentException
                        format:@"MPSGraph: %@ was fed an axis of %ld for a rank-%lu tensor, and axis 0 to "
                               @"%lu is all it has",
                                [operation name], (long)fed, (unsigned long)rank, (unsigned long)rank];
        }
    } else {
        axis = [parameters[@"scanAxis"] integerValue];
    }
    int exclusive = [parameters[@"scanExclusive"] boolValue];
    int reverse = [parameters[@"scanReverse"] boolValue];

    // Each axis's own stride in the operand's layout, which is the result's layout too, and the extent of
    // the one being walked. A position of the scan axis is a whole run of the other axes, so the walk is
    // over the positions and each position owns one element per run - a lane - and the lanes are walked one
    // after another, which is what makes the whole of this O(elements) rather than O(elements * positions).
    unsigned long long *stride = calloc(rank, sizeof(unsigned long long));
    unsigned long long extent = 1;
    {
        unsigned long long running = 1;
        for (NSUInteger i = rank; i-- > 0;) {
            stride[i] = running;
            running *= (unsigned long long)shape[i].unsignedIntegerValue;
            if ((NSInteger)i == axis)
                extent = (unsigned long long)shape[i].unsignedIntegerValue;
        }
    }
    unsigned long long laneStride = stride[axis];
    double seed = CharonMPSGraphScanSeed(fold, type);
    for (NSUInteger base = 0; base < count; base++) {
        if (CharonMPSGraphCoordinate(shape, (NSUInteger)axis, base) != 0)
            continue;                       // one lane: the elements whose axis coordinate is zero
        double accumulator = seed;
        for (unsigned long long step = 0; step < extent; step++) {
            unsigned long long at = reverse ? extent - 1 - step : step;
            NSUInteger here = base + (NSUInteger)(at * laneStride);
            double value = CharonMPSLoad(in, type, here);
            // The element at this position joins the answer before the answer is written, unless the answer
            // is exclusive - and either way the answer goes out through the result's own type and is read
            // back from it, so the accumulator is that type and not a wider one.
            if (!exclusive)
                accumulator = CharonMPSGraphFoldStep(fold, accumulator, value, 0, 1);
            CharonMPSStoreRounded(out, resultType, here, accumulator, 1);
            accumulator = CharonMPSLoad(out, resultType, here);
            if (exclusive)
                accumulator = CharonMPSGraphFoldStep(fold, accumulator, value, 0, 1);
        }
    }
    free(stride);
}

// The integers out of a fed tensor of any integer type, which is how a flatten's axis, a reverse's axes, a
// broadcast's shape and a squeeze's or an expanded dimension's axes arrive when the caller fed them rather
// than writing them down. How many of them there are is the fed tensor's own element count, so nothing has to
// carry the count as well, and nil for no fed tensor at all is what tells the plan the parameter has not
// arrived yet.
static NSMutableArray<NSNumber *> *CharonMPSGraphGatherIntegers(MPSGraphTensorData *parameter)
{
    if (parameter == nil)
        return nil;
    NSUInteger count = CharonMPSGraphElementCount(parameter.shape);
    NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++)
        [values addObject:@((NSInteger)CharonMPSLoad([parameter charon_mps_bytes], parameter.dataType, i))];
    return values;
}

// THE GATHER FAMILY: the operations whose result is the operand's elements in some other order or some other
// extent. Every one of them is one walk here, because every one of them is the same question - for each axis
// of the result, which axis of the operand feeds it, how many of the operand's axes it covers, and whether
// that one is reversed, and whether the coordinate has an element of the operand behind it at all - and the
// operation's parameters are the answer. This function is the plan: the result's shape and that mapping,
// both derived from the transformation the operation names, and asked both when the graph is built (through
// -[MPSGraph charon_mps_gatherShapeOfTensor:parameters:named:], so that a caller can read the result's shape
// off the tensor) and when the operation runs (where a parameter the caller fed can be read).
//
// Every rule is measured on this host's own MPSGraph over a 2x4 of (1, 2, 3, 4 | 10, 20, 30, 40):
//
//   - a transpose is the row-major transpose, in both forms: (1, 10, 2, 20, 3, 30, 4, 40) into a 4x2, and a
//     negative axis is counted from the end, so `dimension:-1 withDimension:0` answers what
//     `dimension:0 withDimension:1` answers. The two-axis form keeps the operand's RANK at a rank above two
//     - measured, `dimension:0 withDimension:2` of a 2x3x4 answers a 4x3x2 and `dimension:0 withDimension:0`
//     answers the operand itself - and the permutation form must have one entry per axis of the operand,
//     measured: a shorter one is refused by the release's own compiler ("perm tensor length must equal input
//     tensor rank, 1 != 3").
//   - a squeeze drops the unit axes it is given - every unit axis when it is given none - and an expanded
//     dimension adds an axis of extent one, whose negative axis is counted from the end AND MAY BE THE RANK
//     ITSELF (measured: axis -1 of a 2x4 is the trailing unit axis of a 2x4x1). All three answer the
//     operand's own bytes in the operand's own order, which is what makes them one gather with the axes left
//     alone: a 1x2x4 squeezed is a 2x4 of the same bytes, a 2x4 expanded at axis 0 is a 1x2x4 of the same
//     bytes, and a 2x3x4 flattened at axis 0 is a 1x24 of them.
//   - a reshape is the same walk with the axes left alone and the result's shape the caller's: a 2x4 into a
//     4x2 answers (1, 2, 3, 4, 10, 20, 30, 40) and a 2x4 into a 1x8 the operand's own eight values, neither of
//     which moves an element, and a dynamic extent (the header's -1) is the element count over the product of
//     the extents written down (measured: a 2x4 into @[@4, -1] answers a 4x2).
//   - a flatten collapses every axis from its axis on into one.
//   - a broadcast aligns the operand to the RIGHT of the shape given, takes the LARGER of the two extents on
//     every axis they share (measured: a 2x4 into a 4x4 answers a 4x4 and a 2x4 into a 1x4 answers the 2x4
//     itself), repeats the whole operand for each axis the shape adds at the front (measured: a 2x4 into a
//     2x2x4 answers the 2x4 twice) and DOES NOT WRAP: past the operand's own extent the result is a zero,
//     measured over a destination filled with a pattern, where a 2x4 into a 4x4 answers (1, 2, 3, 4, 10, 20,
//     30, 40) and then eight zeros rather than the pattern and rather than the row twice.
//   - a reverse flips the axes it is given and nothing else, counting a negative axis from the end (measured:
//     axes @[@-1] answers what axes @[@1] answers) and taking no axes at all as every axis.
//
// An axis or an extent the release refuses is refused here too, with NSInvalidArgumentException: a squeeze of
// an axis whose extent is not one is a graph it cannot build (measured: "squeezed axis must have length 1,
// input.shape[1] == 2", then "LLVM ERROR: Failed to infer result type(s)" takes the process down), an axis or
// a permutation outside the rank is the same refusal the reduction family raises (measured for the reverse:
// "invalid axis: 5, axis must be in range - rank <= axis < rank, rank = 2"), and an extent of zero is a shape
// with no elements in it.
//
// Two questions this function is asked twice, and both are the same code: the factory asks it when the graph
// is built so that the result tensor carries its shape before anything runs - which is what the release does,
// since it infers the result's type at build time and aborts there over an axis it cannot use - and the
// interpreter asks it when the operation runs, which is the only time a FED parameter can be read. A fed
// parameter, and an operand whose own shape is not known yet (a gather of a fed gather), give nil here, and
// the interpreter puts the shape on when it walks the operation.
static NSDictionary *CharonMPSGraphGatherPlan(NSString *name, NSArray<NSNumber *> *sourceShape,
                                              NSDictionary *parameters, NSArray<NSNumber *> *fed)
{
    const char *gather = [parameters[@"gather"] UTF8String];
    NSUInteger sourceRank = sourceShape.count;

    if (fed == nil && (parameters[@"gatherOperand"] != nil || sourceShape == nil))
        return nil;

    NSMutableArray<NSNumber *> *shape = [NSMutableArray array];
    NSMutableArray<NSNumber *> *sourceAxes = [NSMutableArray array];
    NSMutableArray<NSNumber *> *sourceCounts = [NSMutableArray array];
    NSMutableArray<NSNumber *> *reversed = [NSMutableArray array];

    if (gather == NULL || sourceRank == 0) {
        CharonMPSGraphRefuse(@"MPSGraph: the operation named %@ asked for a gather this interpreter does not "
                             @"know, so nothing was written to its output", name);
        return nil;
    }
    if (strcmp(gather, "squeeze") == 0 || strcmp(gather, "expand") == 0) {
        // The squeeze and the expanded dimension, which are the same gather with the axes left alone - every
        // one of the seven methods of 15.4 answers the operand's own bytes in the operand's own order. What
        // differs between them is which axes are dropped and which are added, and the factory is what knows
        // that: it names them in @gatherDrop and @gatherAdd, or says with @gatherOperand that the caller fed
        // them and they are read out of the operation's second input here.
        int expanding = strcmp(gather, "expand") == 0;
        NSArray<NSNumber *> *declared = [parameters[@"gatherOperand"] isEqual:@"axes"] ? fed
            : (expanding ? parameters[@"gatherAdd"] : parameters[@"gatherDrop"]);
        NSMutableIndexSet *named = [NSMutableIndexSet indexSet];
        for (NSNumber *axis in declared) {
            NSInteger where = axis.integerValue;
            // An expanded dimension's negative axis is counted from the end and MAY BE THE RANK ITSELF -
            // measured, axis -1 of a 2x4 is the trailing unit axis of a 2x4x1 - so its count from the end is
            // one past the last axis, while a squeeze drops an axis that is there and its count is the rank.
            if (where < 0)
                where += (NSInteger)sourceRank + (expanding ? 1 : 0);
            if (where < 0 || (NSUInteger)where > sourceRank || (!expanding && (NSUInteger)where >= sourceRank)) {
                [NSException raise:NSInvalidArgumentException
                            format:@"MPSGraph: %@ was asked to %@ axis %ld of a rank-%lu tensor, and %@",
                                name, expanding ? @"expand" : @"squeeze", (long)axis.integerValue,
                                (unsigned long)sourceRank,
                                expanding ? @"axis 0 to the rank is all it has"
                                          : @"only an axis of extent one can be squeezed"];
            }
            if (!expanding && sourceShape[(NSUInteger)where].integerValue != 1) {
                [NSException raise:NSInvalidArgumentException
                            format:@"MPSGraph: %@ was asked to squeeze axis %ld of a %s tensor, and only an "
                                   @"axis of extent one can be squeezed",
                                name, (long)axis.integerValue,
                                [[sourceShape componentsJoinedByString:@"x"] UTF8String]];
            }
            [named addIndex:(NSUInteger)where];
        }
        if (expanding) {
            // An axis of extent one goes AT EACH INDEX NAMED, so the result's axis at a position is the
            // operand's axis there unless that index was named - measured, axes @[@0, @2] of a 2x4 answers a
            // 1x2x1x4 and @[@0, @1] a 1x1x2x4, where adding one axis and then the next into the result of the
            // last would answer a 1x2x4x1 and a 1x1x2x4. The operand's own axis of a result axis is therefore
            // its position less the number of named indices before it, and an index past the last of the
            // operand's is the trailing axis of the release's own answer.
            NSUInteger added = 0;
            for (NSUInteger index = 0; index <= sourceRank; index++)
                if ([named containsIndex:index])
                    added++;
            for (NSUInteger position = 0; position < sourceRank + added; position++) {
                if ([named containsIndex:position]) {
                    [shape addObject:@1];
                    [sourceAxes addObject:@0];
                    [sourceCounts addObject:@0];
                    [reversed addObject:@0];
                    continue;
                }
                NSUInteger before = 0;
                for (NSUInteger index = 0; index < position; index++)
                    if ([named containsIndex:index])
                        before++;
                [shape addObject:sourceShape[position - before]];
                [sourceAxes addObject:@(position - before)];
                [sourceCounts addObject:@1];
                [reversed addObject:@0];
            }
        } else {
            // Every axis the caller did not name is kept, in order, and the extents are the operand's own.
            for (NSUInteger position = 0; position < sourceRank; position++) {
                if ([named containsIndex:position])
                    continue;
                [shape addObject:sourceShape[position]];
                [sourceAxes addObject:@(position)];
                [sourceCounts addObject:@1];
                [reversed addObject:@0];
            }
        }
    } else if (strcmp(gather, "flatten") == 0) {
        // A flatten's axis is NOT normalised the way the family's other axes are, and that is measured: the
        // release takes it as the unsigned number it is given, so axis:-1 of a 2x4 is a dimension length of
        // 4294967295 and the framework refuses it outright ("Error: NDArray dimension length > INT_MAX",
        // MPSNDArray.mm:831) and takes the process down. An expanded dimension and a transpose do count a
        // negative axis from the end - measured, both answer - so the rule is this operation's and not the
        // family's, and it is here rather than in a shared normaliser.
        NSInteger axis = [parameters[@"gatherOperand"] isEqual:@"axis"]
            ? (NSInteger)fed.firstObject.integerValue
            : [parameters[@"gatherAxis"] integerValue];
        if (axis < 0 || (NSUInteger)axis >= sourceRank) {
            [NSException raise:NSInvalidArgumentException
                        format:@"MPSGraph: %@ was asked to flatten at axis %ld of a rank-%lu tensor, and axis 0 "
                               @"to %lu is all it has: the release takes that axis as the unsigned number it "
                               @"is given, so a negative one is a dimension length past what it can build",
                                name, (long)axis, (unsigned long)sourceRank, (unsigned long)sourceRank];
        }
        // The result is of rank TWO, which is what the method's own name says and what the release answers:
        // measured, axis 0 of a 2x4 is a 1x8, axis 1 of a 2x3x4 is a 2x12 and axis 2 of a 2x3x4 is a 6x4 - so
        // the extents before the axis named collapse into one axis of their product and the rest into
        // another. The elements are the operand's own in order whichever way that is spelled, because the
        // product of the extents is a collapse in the operand's own row-major order, which is why only the
        // shape line of such a case can see it.
        NSUInteger from = (NSUInteger)axis;
        unsigned long long after = 1, before = 1;
        for (NSUInteger i = from; i < sourceRank; i++)
            after *= (unsigned long long)sourceShape[i].unsignedIntegerValue;
        for (NSUInteger i = 0; i < from; i++)
            before *= (unsigned long long)sourceShape[i].unsignedIntegerValue;
        [shape addObject:@(before)];
        [sourceAxes addObject:@0];
        [sourceCounts addObject:@(from)];
        [reversed addObject:@0];
        [shape addObject:@(after)];
        [sourceAxes addObject:@(from)];
        [sourceCounts addObject:@(sourceRank - from)];
        [reversed addObject:@0];
    } else if (strcmp(gather, "broadcast") == 0) {
        NSArray<NSNumber *> *declared = [parameters[@"gatherOperand"] isEqual:@"shape"] ? fed
                                                                                      : parameters[@"gatherShape"];
        for (NSUInteger k = 0; k < declared.count; k++) {
            NSInteger extent = declared[k].integerValue;
            if (extent < 1) {
                [NSException raise:NSInvalidArgumentException
                            format:@"MPSGraph: %@ was asked to broadcast into a shape holding %ld, and every "
                                   @"extent of a shape is one or more", name, (long)extent];
            }
            // The operand aligns to the right of the shape, so axis k of the result reads axis k - (the
            // difference in ranks) of the operand, and an axis the shape adds at the front repeats the whole
            // operand and so covers none of its axes. The extent is the LARGER of the two: the release takes
            // the operand's own extent where the shape asks for less (measured, a 2x4 into a 1x4 answers the
            // 2x4 itself) and the shape's where it asks for more.
            NSInteger which = (NSInteger)k - ((NSInteger)declared.count - (NSInteger)sourceRank);
            NSUInteger axis = which < 0 ? 0 : (NSUInteger)which;
            if (axis < sourceRank &&
                sourceShape[axis].unsignedIntegerValue > (NSUInteger)extent)
                extent = sourceShape[axis].integerValue;
            [shape addObject:@(extent)];
            [sourceAxes addObject:@(axis)];
            [sourceCounts addObject:@(which < 0 ? 0 : 1)];
            [reversed addObject:@0];
        }
    } else if (strcmp(gather, "reverse") == 0) {
        NSMutableIndexSet *flipped = [NSMutableIndexSet indexSet];
        NSArray<NSNumber *> *named = [parameters[@"gatherOperand"] isEqual:@"axes"] ? fed
                                                                                  : parameters[@"gatherAxes"];
        if (named.count)
            for (NSNumber *axis in named) {
                // A negative axis is counted from the end here as it is everywhere else in this family except
                // the flatten, and an axis outside the rank is the refusal the release's own compiler gives:
                // "invalid axis: 5, axis must be in range - rank <= axis < rank, rank = 2".
                NSInteger where = axis.integerValue;
                if (where < 0)
                    where += (NSInteger)sourceRank;
                if (where < 0 || (NSUInteger)where >= sourceRank) {
                    [NSException raise:NSInvalidArgumentException
                                format:@"MPSGraph: %@ was asked to reverse axis %ld of a rank-%lu tensor, and "
                                       @"axis 0 to %lu is all it has", name, (long)axis.integerValue,
                                        (unsigned long)sourceRank, (unsigned long)sourceRank];
                }
                [flipped addIndex:(NSUInteger)where];
            }
        else
            for (NSUInteger i = 0; i < sourceRank; i++)
                [flipped addIndex:i];
        for (NSUInteger i = 0; i < sourceRank; i++) {
            [shape addObject:sourceShape[i]];
            [sourceAxes addObject:@(i)];
            [sourceCounts addObject:@1];
            [reversed addObject:([flipped containsIndex:i] ? @YES : @NO)];
        }
    } else if (strcmp(gather, "reshape") == 0) {
        // A reshape is the same walk with the axes left alone and the result's shape the caller's: the operand
        // and the result hold the same elements in the same row-major order, so the result's axes consume the
        // operand's in turn - a 2x4 into a 4x2 answers (1, 2, 3, 4, 10, 20, 30, 40) and a 2x4 into a 1x8 the
        // operand's own eight values, and neither moves an element. An axis of the result covers the operand's
        // axes from the first one not yet consumed to the last one that fits inside it, which is the split the
        // walk already does for a flatten's collapse.
        //
        // A DYNAMIC extent, the header's -1, is resolved here: the shape is allowed to hold one when the
        // result type can be inferred unambiguously, so the product of the extents written down divides the
        // operand's element count and the answer is the quotient. Two of them, or a shape whose product does
        // not divide, is a shape this cannot answer and the port refuses it where the graph is built.
        NSArray<NSNumber *> *written = [parameters[@"gatherOperand"] isEqual:@"shape"] ? fed
                                                                                     : parameters[@"gatherShape"];
        if (written == nil)
            return nil;
        NSUInteger elementCount = CharonMPSGraphElementCount(sourceShape);
        NSMutableArray<NSNumber *> *declared = [NSMutableArray arrayWithCapacity:written.count];
        NSInteger dynamic = 0;
        unsigned long long writtenProduct = 1;
        for (NSNumber *extent in written) {
            NSInteger value = extent.integerValue;
            if (value == -1) {
                dynamic++;
                [declared addObject:@(-1)];
                continue;
            }
            if (value < 1) {
                [NSException raise:NSInvalidArgumentException
                            format:@"MPSGraph: %@ was asked to reshape into a shape holding %ld, and every "
                                   @"extent of a shape is one or more", name, (long)value];
            }
            writtenProduct *= (unsigned long long)value;
            [declared addObject:@(value)];
        }
        if (dynamic > 1) {
            [NSException raise:NSInvalidArgumentException
                        format:@"MPSGraph: %@ was asked to reshape into a shape with %ld dynamic extents, and "
                               @"the release's own header allows one only where the result type can be "
                               @"inferred unambiguously", name, (long)dynamic];
        }
        if (dynamic == 1) {
            if (writtenProduct == 0 || elementCount % writtenProduct != 0) {
                [NSException raise:NSInvalidArgumentException
                            format:@"MPSGraph: %@ was asked to reshape %lu elements into a shape whose written "
                                   @"extents are a product of %llu, which does not divide them", name,
                                    (unsigned long)elementCount, writtenProduct];
            }
            [declared replaceObjectAtIndex:[declared indexOfObject:@(-1)] withObject:@(elementCount / writtenProduct)];
        }
        unsigned long long total = 1;
        for (NSNumber *extent in declared)
            total *= (unsigned long long)extent.unsignedIntegerValue;
        if (total != (unsigned long long)elementCount) {
            [NSException raise:NSInvalidArgumentException
                        format:@"MPSGraph: %@ was asked to reshape %lu elements into %llu, and the release's "
                               @"own header wants the volumes to match", name, (unsigned long)elementCount, total];
        }
        // The result's element at a flat index is the operand's element at the SAME flat index, which is what
        // the two row-major orders and the volumes matching are, and which the per-axis mapping cannot express
        // when the two shapes share no boundary - a 2x4 into a 4x2 puts one axis of the result across half of
        // an axis of the operand. So the plan says the walk is flat and the walk reads the index, and the
        // measured answers are the operand's own bytes in order: a 2x4 into a 4x2 and into a 2x4 and into a 1x8
        // all answer (1, 2, 3, 4, 10, 20, 30, 40).
        return @{@"shape": declared, @"flat": @YES};
    } else if (strcmp(gather, "transpose") == 0) {
        NSArray<NSNumber *> *permutation = parameters[@"gatherPermutation"];
        if (permutation.count != sourceRank) {
            [NSException raise:NSInvalidArgumentException
                        format:@"MPSGraph: %@ was asked to transpose with a permutation of %lu entries for a "
                               @"rank-%lu tensor, and the release's own compiler wants one entry per axis: "
                               @"perm tensor length must equal input tensor rank, %lu != %lu",
                                name, (unsigned long)permutation.count, (unsigned long)sourceRank,
                                (unsigned long)permutation.count, (unsigned long)sourceRank];
        }
        for (NSUInteger k = 0; k < permutation.count; k++) {
            // The header's spelling of the two-axis transpose is NSUInteger and the release's permutation
            // form is an array of them, and it still counts a negative value from the end - measured,
            // dimension:(NSUInteger)-1 withDimension:0 answers what dimension:0 withDimension:1 answers - so
            // the value is read back as the signed number it was written as, which is what the header's own
            // type makes a caller of a negative axis write.
            NSInteger which = (NSInteger)(int32_t)permutation[k].unsignedIntegerValue;
            if (which < 0)
                which += (NSInteger)sourceRank;
            if (which < 0 || (NSUInteger)which >= sourceRank) {
                [NSException raise:NSInvalidArgumentException
                            format:@"MPSGraph: %@ was asked to transpose with axis %ld of a rank-%lu tensor, "
                                   @"and axis 0 to %lu is all it has",
                                name, (long)which, (unsigned long)sourceRank, (unsigned long)sourceRank];
            }
            [shape addObject:sourceShape[(NSUInteger)which]];
            [sourceAxes addObject:@(which)];
            [sourceCounts addObject:@1];
            [reversed addObject:@0];
        }
    } else {
        CharonMPSGraphRefuse(@"MPSGraph: the operation named %@ asked for a gather this interpreter does not "
                             @"know, so nothing was written to its output", name);
        return nil;
    }
    return @{@"shape": shape, @"sourceAxes": sourceAxes, @"sourceCounts": sourceCounts,
             @"reversed": reversed, @"flat": @NO};
}

// The walk itself: each element of the result, its coordinates read from the last axis backwards (the operand
// is row-major with its FIRST axis the slowest moving), each coordinate turned into a coordinate of the
// operand's axes that axis of the result covers and weighted by that axis's stride. An element the plan maps
// to no element of the operand - which is what an axis the shape made wider than the operand's comes to - is
// left as the result buffer's own zero, which is what the release answers there.
static void CharonMPSGraphGather(MPSGraphOperation *operation, MPSGraphTensorData *source,
                                  MPSGraphTensorData *result, NSDictionary *plan)
{
    NSArray<NSNumber *> *sourceShape = source.shape;
    NSArray<NSNumber *> *resultShape = result.shape;
    NSArray<NSNumber *> *sourceAxes = plan[@"sourceAxes"];
    NSArray<NSNumber *> *sourceCounts = plan[@"sourceCounts"];
    NSArray<NSNumber *> *reversed = plan[@"reversed"];
    NSUInteger sourceRank = sourceShape.count;
    NSUInteger resultRank = resultShape.count;
    NSUInteger count = CharonMPSGraphElementCount(resultShape);
    NSUInteger sourceCount = CharonMPSGraphElementCount(sourceShape);
    if (count == 0)
        return;
    MPSDataType type = source.dataType;
    void *in = [source charon_mps_bytes];
    void *out = [result charon_mps_bytes];

    // A reshape, whose answer is the operand's elements at the same flat index - see the plan.
    if ([plan[@"flat"] boolValue]) {
        for (NSUInteger element = 0; element < count && element < sourceCount; element++)
            CharonMPSStoreRounded(out, result.dataType, element,
                                  CharonMPSLoad(in, type, element), 1);
        return;
    }

    // The last axis's stride is one and every earlier axis's is the next one's weighted by the next axis's
    // extent, which is the row-major order the operand's own bytes are in.
    unsigned long long *sourceStride = calloc(sourceRank ? sourceRank : 1, sizeof(unsigned long long));
    for (NSUInteger i = sourceRank; i-- > 0;)
        sourceStride[i] = (i + 1 < sourceRank
                           ? sourceStride[i + 1] * (unsigned long long)sourceShape[i + 1].unsignedIntegerValue
                           : 1);
    for (NSUInteger element = 0; element < count; element++) {
        unsigned long long rest = element, sourceIndex = 0;
        BOOL unsourced = NO;
        for (NSUInteger k = resultRank; k-- > 0;) {
            NSUInteger extent = (NSUInteger)resultShape[k].unsignedIntegerValue;
            unsigned long long coordinate = extent ? rest % extent : 0;
            if (extent)
                rest /= extent;
            NSUInteger first = (NSUInteger)sourceAxes[k].unsignedIntegerValue;
            NSUInteger covered = (NSUInteger)sourceCounts[k].unsignedIntegerValue;
            if (covered > 0) {
                // How many of the operand's coordinates this axis of the result covers. A coordinate past that
                // has NO element of the operand behind it, and there the release answers a zero rather than
                // wrapping round to the start - measured, a 2x4 into a 4x4 answers its own eight values and
                // then eight zeros where the destination was filled with a pattern, and not the row twice.
                // One available coordinate is the broadcast's own rule and is not that case: an operand axis of
                // extent one is REPEATED along a result axis of any extent, which is what a 1x2x4 broadcast into
                // a 2x2x4 answers as the operand twice (measured), and taking the modulo of one below reads
                // the operand's single element for every coordinate of it.
                unsigned long long available = 1;
                for (NSUInteger c = 0; c < covered && first + c < sourceRank; c++)
                    available *= (unsigned long long)sourceShape[first + c].unsignedIntegerValue;
                if (available > 1 && coordinate >= available) {
                    unsourced = YES;
                    break;
                }
            }
            // The covered axes are walked from the LAST of them, because the first of them is the slowest
            // moving: the coordinate of one axis of the result over several of the operand's is the coordinate
            // divided into them from the last, which is the same row-major order one axis carries.
            unsigned long long place = coordinate;
            for (NSUInteger c = covered; c-- > 0;) {
                NSUInteger axis = first + c;
                if (axis >= sourceRank)
                    break;
                unsigned long long extentOfSource = sourceShape[axis].unsignedIntegerValue;
                if (extentOfSource == 0)
                    continue;
                unsigned long long component = place % extentOfSource;
                place /= extentOfSource;
                if ([reversed[k] boolValue])
                    component = extentOfSource - 1 - component;
                sourceIndex += component * sourceStride[axis];
            }
        }
        if (!unsourced && sourceIndex < (unsigned long long)sourceCount)
            CharonMPSStoreRounded(out, result.dataType, element,
                                  CharonMPSLoad(in, type, (NSUInteger)sourceIndex), 1);
    }
    free(sourceStride);
}

@implementation MPSGraph (CharonMPSGraphInterpreter)

// The shape of a gather's result, asked when the graph is BUILT so that the output tensor carries it before
// anything runs. The release infers the result's type when the graph is built - which is why an axis it
// cannot use aborts there rather than at the run - so a caller can read the shape off the tensor it was
// given, and this is where the port answers that. It is the same plan the interpreter walks, asked with the
// operand's own shape and with no fed parameter: a parameter the caller fed, or an operand whose own shape is
// not known yet (a gather of a fed gather), gives nil here and the interpreter puts the shape on when it runs.
- (NSArray<NSNumber *> *)charon_mps_gatherShapeOfTensor:(MPSGraphTensor *)tensor
                                             parameters:(NSDictionary *)parameters
                                                    named:(NSString *)name
{
    NSDictionary *plan = CharonMPSGraphGatherPlan(name, tensor.shape, parameters, nil);
    return plan[@"shape"];
}

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

    // The reduction family folds many elements into one, so it is walked before the loop below: the loop
    // reads the element of an operand that is written at the same index of the result, which is what an
    // elementwise operation wants and not what a reduction wants. Which family an operation belongs to is
    // read out of its own parameters and not out of its kind, because a kind names the release the
    // operation came from and the walk here is one walk for every release: a reduction says which fold it
    // is in @"combination", and nothing else in this interpreter knows that a fold exists by its name.
    if (operation.charon_mps_parameters[@"gather"]) {
        // The gather family, whose result is the operand's elements in another order or another extent. The
        // operation carries which transformation it is and the parameter of it the caller wrote down or fed;
        // see CharonMPSGraphGather.
        MPSGraphTensorData *source = values[inputs.firstObject];
        if (![source isKindOfClass:[MPSGraphTensorData class]]) {
            CharonMPSGraphRefuse(@"MPSGraph: the gather named %@ has no value for its first input, so "
                                 @"nothing was written to its output", [operation name]);
            return;
        }
        MPSGraphTensorData *parameter = inputs.count > 1 ? values[inputs[1]] : nil;
        NSDictionary *plan = CharonMPSGraphGatherPlan([operation name], source.shape,
                                                      operation.charon_mps_parameters,
                                                      CharonMPSGraphGatherIntegers(parameter));
        if (plan == nil)
            return;
        // The result's own shape can be the caller's to feed, so it comes out of the plan and is put on the
        // output tensor before anything is allocated for it. The factory put it there too when it could be
        // known at build time, which is what a caller reads off the tensor before it runs the graph.
        [output charon_mps_setShape:plan[@"shape"]];
        NSUInteger gathered_ = CharonMPSGraphElementCount(plan[@"shape"]);
        MPSGraphTensorData *gathered = [[MPSGraphTensorData alloc] initWithDevice:source.device
                                                                     elementCount:gathered_
                                                                            shape:plan[@"shape"]
                                                                         dataType:dataType];
        [gathered charon_mps_bytes];
        CharonMPSGraphGather(operation, source, gathered, plan);
        values[output] = gathered;
        return;
    }
    if (operation.charon_mps_parameters[@"scanCombination"]) {
        // The cumulative family, which is the reduction family's fold walked along an axis: the result is the
        // operand's own shape, so this cannot be the elementwise loop below either, and it is asked for the
        // same reason. Which fold, which axis, which way and whether an element is in its own answer are all
        // in the operation's parameters, so nothing here names 16.0 - see CharonMPSGraphScan.
        MPSGraphTensorData *source = values[inputs.firstObject];
        if (![source isKindOfClass:[MPSGraphTensorData class]]) {
            CharonMPSGraphRefuse(@"MPSGraph: a cumulative operation named %@ has no value for its first "
                                 @"input, so nothing was written to its output", [operation name]);
            return;
        }
        MPSGraphTensorData *axisData = inputs.count > 1 ? values[inputs[1]] : nil;
        MPSGraphTensorData *scanned = [[MPSGraphTensorData alloc] initWithDevice:source.device
                                                                     elementCount:count
                                                                            shape:output.shape
                                                                         dataType:dataType];
        [scanned charon_mps_bytes];
        CharonMPSGraphScan(operation, source, axisData, scanned);
        values[output] = scanned;
        return;
    }
    if (operation.charon_mps_parameters[@"combination"]) {
        MPSGraphTensorData *source = values[inputs.firstObject];
        MPSGraphTensor *meanTensor = operation.charon_mps_parameters[@"mean"];
        if (![source isKindOfClass:[MPSGraphTensorData class]]) {
            CharonMPSGraphRefuse(@"MPSGraph: a reduction named %@ has no value for its first input, so "
                                 @"nothing was written to its output", [operation name]);
            return;
        }
        MPSGraphTensorData *result = [[MPSGraphTensorData alloc] initWithDevice:source.device
                                                                    elementCount:count
                                                                           shape:output.shape
                                                                        dataType:dataType];
        [result charon_mps_bytes];
        MPSGraphTensorData *mean = [meanTensor isKindOfClass:[MPSGraphTensor class]] ? values[meanTensor]
                                                                                     : nil;
        CharonMPSGraphReduce(operation, source, [mean isKindOfClass:[MPSGraphTensorData class]] ? mean : nil,
                            result);
        values[output] = result;
        return;
    }

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
    // Whether this operation latches a NaN is its own parameter and not its kind: see
    // CharonMPSGraphApply above.
    int latch = [operation.charon_mps_parameters[@"latchNaN"] boolValue];
    if (right) {
        if (third) {
            for (NSUInteger i = 0; i < count; i++)
                CharonMPSStoreRounded(out, dataType, i,
                           CharonMPSGraphApply(kind, CharonMPSLoad([left charon_mps_bytes], operandType, i),
                                               CharonMPSLoad([right charon_mps_bytes], right.dataType, i),
                                               CharonMPSLoad([third charon_mps_bytes], third.dataType, i),
                                               operandType, dataType, latch), 1);
        } else {
            for (NSUInteger i = 0; i < count; i++)
                CharonMPSStoreRounded(out, dataType, i,
                           CharonMPSGraphApply(kind, CharonMPSLoad([left charon_mps_bytes], operandType, i),
                                               CharonMPSLoad([right charon_mps_bytes], right.dataType, i), 0.0,
                                               operandType, dataType, latch), 1);
        }
    } else {
        for (NSUInteger i = 0; i < count; i++)
            CharonMPSStoreRounded(out, dataType, i,
                       CharonMPSGraphApply(kind, CharonMPSLoad([left charon_mps_bytes], operandType, i), 0.0, 0.0,
                                           operandType, dataType, latch), 1);
    }
    values[output] = result;
}

@end