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
        if (fold->isExtreme) {
            // One comparison, and every rule of the four extremes is in it. A NaN loses the comparison
            // against anything including another NaN, so it is skipped - which is how a maximum that does
            // not propagate ignores one. The propagating variant latches instead: a NaN that has reached
            // this element is its answer, and a NaN that arrives puts it there, and nothing after it can
            // move it, because a comparison against a NaN also loses.
            double held = CharonMPSLoad(out, resultType, index);
            if (isnan(value)) {
                if (propagates)
                    CharonMPSStoreRounded(out, resultType, index, CharonMPSGraphOwnNaN(NAN), 1);
                continue;
            }
            if (propagates && isnan(held))
                continue;
            CharonMPSStoreRounded(out, resultType, index,
                                  fold->isLesser ? (value < held ? value : held) : (value > held ? value : held), 1);
            continue;
        }
        if (fold->isTruth) {
            // The two truth folds, which are a question about every element of the reduced set rather
            // than an arithmetic over it, and the answer is written in the operand's own type: measured
            // on this host's own MPSGraph, an "and" of a row holding a zero answers 0 and of a row of
            // nothing but NaNs answers 1, so the test is against zero and a NaN is a nonzero like any
            // other value. An "or" of the same row answers 1.
            //
            // A reduced set of no elements at all is the identity rather than the seed of the fold, and
            // that is what axes:@[] measures over both of them - see the empty-axis case above - so the
            // two never reach here with nothing to fold.
            int truth = value != 0.0;
            int held = CharonMPSLoad(out, resultType, index) != 0.0;
            CharonMPSStoreRounded(out, resultType, index,
                                  (fold->isOr ? (truth || held) : (truth && held)) ? 1.0 : 0.0, 1);
            continue;
        }
        // The held answer is read back out of the result, so every fold is a store and a load of the
        // value the type can hold. A NaN that leaves this arithmetic is the arithmetic's own and not the
        // one it was handed, as everywhere else in this interpreter: measured, the product of a row of
        // (infinity, -infinity, NaN, -NaN) is 0x7fc00000 on this host and was a negative NaN here until
        // the fold was put through the same rule the arithmetic family uses.
        double held = CharonMPSLoad(out, resultType, index);
        CharonMPSStoreRounded(out, resultType, index,
                              CharonMPSGraphOwnNaN(fold->multiplies ? held * value : held + value), 1);
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

    // The reduction family folds many elements into one, so it is walked before the loop below: the loop
    // reads the element of an operand that is written at the same index of the result, which is what an
    // elementwise operation wants and not what a reduction wants. Which family an operation belongs to is
    // read out of its own parameters and not out of its kind, because a kind names the release the
    // operation came from and the walk here is one walk for every release: a reduction says which fold it
    // is in @"combination", and nothing else in this interpreter knows that a fold exists by its name.
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