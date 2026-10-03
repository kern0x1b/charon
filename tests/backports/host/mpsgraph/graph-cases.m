// graph-cases.m - the builder side and the arithmetic family of MPSGraph, run twice: once against the
// system's own MPSGraph and once against this port's classes under names of their own. Every case
// prints the bytes of a buffer the case owns, so the two runs are compared exactly.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShadersGraph/MetalPerformanceShadersGraph.h>


// A case has to compile against both sides, and the SDK the port builds against - the iPhoneOS 16.4 one -
// predates some of the methods the framework on this host has. They are declared here so the same call
// is on both sides of the comparison; the spellings are the 26.2 headers', and the host's own framework
// answers them.
@interface MPSGraph (MPSGraph26)
- (MPSGraphTensor *)squareWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name;
- (MPSGraphTensor *)reciprocalWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name;
- (MPSGraphTensor *)squareRootWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name;
- (MPSGraphTensor *)reverseSquareRootWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name;
- (MPSGraphTensor *)logarithmWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name;
- (MPSGraphTensor *)absoluteWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name;
- (MPSGraphTensor *)signWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name;
- (MPSGraphTensor *)identityWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name;
- (MPSGraphTensor *)constantWithShape:(MPSShape *)shape
                            dataType:(MPSDataType)dataType
                              values:(NSData *)values
                                name:(NSString *)name;
// The four of 15.0 and the four of 15.3, which the iPhoneOS 16.4 SDK this package compiles against
// already declares (MPSGraphReductionOps.h and MPSGraphArithmeticOps.h, ios(15.0) and ios(15.3)).
- (MPSGraphTensor *)reductionArgMaximumWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)reductionArgMinimumWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)reductionAndWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)reductionAndWithTensor:(MPSGraphTensor *)tensor axes:(NSArray<NSNumber *> *)axes name:(NSString *)name;
- (MPSGraphTensor *)reductionOrWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)reductionOrWithTensor:(MPSGraphTensor *)tensor axes:(NSArray<NSNumber *> *)axes name:(NSString *)name;
- (MPSGraphTensor *)minimumWithNaNPropagationWithPrimaryTensor:(MPSGraphTensor *)primary
                                             secondaryTensor:(MPSGraphTensor *)secondary
                                                        name:(NSString *)name;
- (MPSGraphTensor *)maximumWithNaNPropagationWithPrimaryTensor:(MPSGraphTensor *)primary
                                             secondaryTensor:(MPSGraphTensor *)secondary
                                                        name:(NSString *)name;
// The cumulative family of 16.0 (MPSGraphCumulativeOps.h, ios(16.0)), sixteen methods over four
// operations: an axis written down, and an axis fed at run time, each with and without the two flags.
- (MPSGraphTensor *)cumulativeSumWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)cumulativeSumWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis exclusive:(BOOL)exclusive reverse:(BOOL)reverse name:(NSString *)name;
- (MPSGraphTensor *)cumulativeSumWithTensor:(MPSGraphTensor *)tensor axisTensor:(MPSGraphTensor *)axisTensor name:(NSString *)name;
- (MPSGraphTensor *)cumulativeSumWithTensor:(MPSGraphTensor *)tensor axisTensor:(MPSGraphTensor *)axisTensor exclusive:(BOOL)exclusive reverse:(BOOL)reverse name:(NSString *)name;
- (MPSGraphTensor *)cumulativeProductWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)cumulativeProductWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis exclusive:(BOOL)exclusive reverse:(BOOL)reverse name:(NSString *)name;
- (MPSGraphTensor *)cumulativeProductWithTensor:(MPSGraphTensor *)tensor axisTensor:(MPSGraphTensor *)axisTensor name:(NSString *)name;
- (MPSGraphTensor *)cumulativeProductWithTensor:(MPSGraphTensor *)tensor axisTensor:(MPSGraphTensor *)axisTensor exclusive:(BOOL)exclusive reverse:(BOOL)reverse name:(NSString *)name;
- (MPSGraphTensor *)cumulativeMaximumWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)cumulativeMaximumWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis exclusive:(BOOL)exclusive reverse:(BOOL)reverse name:(NSString *)name;
- (MPSGraphTensor *)cumulativeMaximumWithTensor:(MPSGraphTensor *)tensor axisTensor:(MPSGraphTensor *)axisTensor name:(NSString *)name;
- (MPSGraphTensor *)cumulativeMaximumWithTensor:(MPSGraphTensor *)tensor axisTensor:(MPSGraphTensor *)axisTensor exclusive:(BOOL)exclusive reverse:(BOOL)reverse name:(NSString *)name;
- (MPSGraphTensor *)cumulativeMinimumWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)cumulativeMinimumWithTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis exclusive:(BOOL)exclusive reverse:(BOOL)reverse name:(NSString *)name;
- (MPSGraphTensor *)cumulativeMinimumWithTensor:(MPSGraphTensor *)tensor axisTensor:(MPSGraphTensor *)axisTensor name:(NSString *)name;
- (MPSGraphTensor *)cumulativeMinimumWithTensor:(MPSGraphTensor *)tensor axisTensor:(MPSGraphTensor *)axisTensor exclusive:(BOOL)exclusive reverse:(BOOL)reverse name:(NSString *)name;
// The shape and axis operations: 14.0's two-axis transpose, 15.0's flattens, broadcasts and reverses, 15.4's
// squeezes and expanded dimensions, and 16.0's permutation transpose (MPSGraphTensorShapeOps.h).
- (MPSGraphTensor *)transposeTensor:(MPSGraphTensor *)tensor dimension:(NSUInteger)dimension withDimension:(NSUInteger)withDimension name:(NSString *)name;
- (MPSGraphTensor *)transposeTensor:(MPSGraphTensor *)tensor permutation:(NSArray<NSNumber *> *)permutation name:(NSString *)name;
- (MPSGraphTensor *)flatten2DTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)flatten2DTensor:(MPSGraphTensor *)tensor axisTensor:(MPSGraphTensor *)axisTensor name:(NSString *)name;
- (MPSGraphTensor *)broadcastTensor:(MPSGraphTensor *)tensor toShape:(NSArray<NSNumber *> *)toShape name:(NSString *)name;
- (MPSGraphTensor *)broadcastTensor:(MPSGraphTensor *)tensor toShapeTensor:(MPSGraphTensor *)toShapeTensor name:(NSString *)name;
- (MPSGraphTensor *)reverseTensor:(MPSGraphTensor *)tensor name:(NSString *)name;
- (MPSGraphTensor *)reverseTensor:(MPSGraphTensor *)tensor axes:(NSArray<NSNumber *> *)axes name:(NSString *)name;
- (MPSGraphTensor *)reverseTensor:(MPSGraphTensor *)tensor axesTensor:(MPSGraphTensor *)axesTensor name:(NSString *)name;
- (MPSGraphTensor *)squeezeTensor:(MPSGraphTensor *)tensor name:(NSString *)name;
- (MPSGraphTensor *)squeezeTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)squeezeTensor:(MPSGraphTensor *)tensor axes:(NSArray<NSNumber *> *)axes name:(NSString *)name;
- (MPSGraphTensor *)squeezeTensor:(MPSGraphTensor *)tensor axesTensor:(MPSGraphTensor *)axesTensor name:(NSString *)name;
- (MPSGraphTensor *)expandDimsOfTensor:(MPSGraphTensor *)tensor axis:(NSInteger)axis name:(NSString *)name;
- (MPSGraphTensor *)expandDimsOfTensor:(MPSGraphTensor *)tensor axes:(NSArray<NSNumber *> *)axes name:(NSString *)name;
- (MPSGraphTensor *)expandDimsOfTensor:(MPSGraphTensor *)tensor axesTensor:(MPSGraphTensor *)axesTensor name:(NSString *)name;
@end

static id<MTLDevice> gDevice;
static MPSGraphDevice *gGraphDevice;

// Every matrix a case builds from a C array, and the result buffer it reads back out of. Sixty-four was
// enough for the twenty-four cases this file had; there are a hundred and more now, so the table is
// sized by the case count and not by the number of cases there were when it was written - a table one
// entry short writes past its own end, which is a crash in the middle of a run and not a failed
// comparison.
typedef struct { id<MTLBuffer> buffer; void *source; size_t bytes; } Source;
static Source gSources[512];
static NSUInteger gSourceCount;
static void remember(id<MTLBuffer> buffer, void *source, size_t bytes)
{
    gSources[gSourceCount].buffer = buffer; gSources[gSourceCount].source = source; gSources[gSourceCount].bytes = bytes; gSourceCount++;
}
static void pullResults(void)
{
    for (NSUInteger i = 0; i < gSourceCount; i++) {
        if (gSources[i].buffer) memcpy(gSources[i].source, [gSources[i].buffer contents], gSources[i].bytes);
    }
}
// Every line of a case carries the marker "#case ", because the framework this file runs against writes
// diagnostics of its own to the same standard output: building one of the predicates prints a warning
// about the operand the comparison kernel was handed ("ConvertBinaryCompareToZero expects the second
// operand to be zero", MPSGraphUtilities.mm:254), and a boolean result printed through the same stream
// makes it print another ("ANE I/O op can only do F16 MemRef <-> F32 Tensor cast"). Those are the
// framework talking to itself and not a case, so run.sh compares only the marked lines and the count it
// compares is the count of cases rather than of lines of output.
static void put(const char *name, const void *bytes, size_t length)
{
    pullResults();
    printf("#case %s %zu ", name, length);
    const unsigned char *p = (const unsigned char *)bytes;
    for (size_t i = 0; i < length; i++) printf("%02x", p[i]);
    printf("\n");
}
static MPSGraphTensorData *feed(const void *values, NSArray<NSNumber *> *shape, MPSDataType type)
{
    NSUInteger count = 1;
    for (NSNumber *dimension in shape) count *= (NSUInteger)dimension.integerValue;
    size_t bytes = count * MPSSizeofMPSDataType(type);
    id<MTLBuffer> buffer = [gDevice newBufferWithBytes:values length:bytes options:MTLResourceStorageModeShared];
    // The feed is not remembered: a case's input array stays what the case put in it, and only the
    // result buffer is read back. Remembering the feed as well meant the first put() overwrote every
    // input array with what the run had left in that buffer, and both sides then agreed on the wrong
    // numbers.
    return [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:shape dataType:type];
}

// One element per input class the arithmetic has to distinguish, so every case in this file covers the
// whole space rather than the handful of values that first showed a difference: a positive and a
// negative, a negative zero and a positive zero, both infinities, a NaN of each sign, a NaN carrying a
// payload, a denormal of each sign, the largest denormal, the smallest normal just above it, an ordinary
// small value, an ordinary value below one and one above it. The hex float literals are how a denormal
// is written; no decimal literal below 1.2e-38 is one.
// Measured against this host's own MPSGraph, macOS 27.0 build 26A428 (M4 Pro, Metal 4):
// 1, -1, -0.0, 0.0, +inf, -inf, qNaN, -qNaN, 0x1p-149, -0x1p-149, 0x1.fffffep-127, 0x1p-126, 0x1p-20,
// 0x1.fffffep-1, -0x1p-20, 1e-20. facts/MetalPerformanceShadersGraph/Core.md carries what each
// operation answers for each of them.
static float leftValues[32] = {
    1.0f, -1.0f, -0.0f, 0.0f, INFINITY, -INFINITY, NAN, -NAN,
    0x1p-149f, -0x1p-149f, 0x1.fffffep-127f, 0x1p-126f, 0x1p-20f, 0x1.fffffep-1f, -0x1p-20f, 1e-20f,
    // Sixteen ordinary values after the sixteen classes, because a tolerance is measured over inputs and
    // sixteen inputs are not enough to measure one: they are the inputs whose answer was looked at once.
    // These are a fixed walk - 2^(-16 + i/2) and its negative, then the same with 1 added - so the sweep is
    // the same on every machine and every run and does not need a seed.
    0x1p-16f, -0x1p-16f, 0x1.8p-16f, -0x1.8p-16f, 0x1p-15f, -0x1p-15f, 0x1.8p-15f, -0x1.8p-15f,
    1.0f + 0x1p-16f, 1.0f + 0x1.8p-16f, 1.0f + 0x1p-15f, 1.0f + 0x1.8p-15f,
    -(1.0f + 0x1p-16f), -(1.0f + 0x1.8p-16f), -(1.0f + 0x1p-15f), -(1.0f + 0x1.8p-15f),
};
// The second operand carries the classes the divisor column needs - a positive zero, a negative zero, an
// infinity of each sign, a NaN, a denormal - and ordinary values elsewhere, so a division is checked
// against every kind of divisor and not only against ones that divide.
static float rightValues[32] = {
    0.0f, -0.0f, INFINITY, -INFINITY, NAN, -NAN, 0x1p-149f, 2.0f,
    4.0f, -4.0f, 0.5f, 8.0f, 16.0f, 3.0f, 1.0f, 1.0f,
    0x1p-16f, -0x1p-16f, 0x1.8p-16f, -0x1.8p-16f, 0x1p-15f, -0x1p-15f, 0x1.8p-15f, -0x1.8p-15f,
    2.0f + 0x1p-16f, -(2.0f + 0x1p-15f), 1.0f / 3.0f, 7.0f,
};
static unsigned char resultBytes[256];
// The feeds of the reduction family, one per data type and each of eight elements in a 2x4. They are
// ordinary values rather than the sixteen classes above because a reduction is a question about a set and
// a set of infinities and denormals answers a sum and a product that are both infinite or both zero, which
// tells a reader nothing about the axis arithmetic; the sixteen classes are asked of every reduction too,
// through leftValues in reduction_families below.
static float rowFeed[8] = { 1.0f, 2.0f, 3.0f, 4.0f, 10.0f, 20.0f, 30.0f, 40.0f };
static float meanFeed[2] = { 2.5f, 25.0f };
static float nanFeed[8] = { NAN, NAN, NAN, NAN, NAN, NAN, NAN, NAN };
static int32_t intFeed[8] = { -3, -2, -1, 0, 1, 2, 3, 4 };
static int32_t intMeanFeed[2] = { -1, 2 };
static uint16_t halfFeed[8] = { 0x3c00, 0x4000, 0x4200, 0x4400, 0x4500, 0x4600, 0x4700, 0x4800 };
static float constantValues[4] = {0.25f, -0.25f, 0.5f, 2};
// The bounds a clamp case is asked over: a pair of ordinary values either side of zero, so that every
// class of the operand decides which of the two it is clamped to.
static float bounds[32] = {
    -0.5f, -0.5f, -0.5f, -0.5f, 0.5f, 0.5f, 0.5f, 0.5f,
    -0.5f, -0.5f, -0.5f, -0.5f, 0.5f, 0.5f, 0.5f, 0.5f,
    -0.5f, -0.5f, -0.5f, -0.5f, 0.5f, 0.5f, 0.5f, 0.5f,
    -0.5f, -0.5f, -0.5f, -0.5f, 0.5f, 0.5f, 0.5f, 0.5f,
};
static int32_t integerValues[4] = {7, -3, 11, 0};
static int32_t integerDivisors[4] = {2, 2, 4, -4};
static int32_t integerResult[4];

// The sixteen classes as MPSDataTypeFloat16 stores them: a positive and a negative, a positive zero
// and a negative zero, both infinities, a NaN of each sign, a denormal of each sign, the largest
// denormal, the smallest normal, and four ordinary values - 1, 1/2, 2^-10 and 1 + 2^-10, which is
// close enough to one for an approximation to show. The type of a class is what decides the shape of
// its writing, so it is written as bits here and as a value above.
// Measured against this host's own MPSGraph, macOS 27.0 build 26A428 (M4 Pro, Metal 4). The buffer
// is sixteen halves, which is 32 bytes: MPSNDArray refuses a shorter one ("buffer is not large
// enough. Must be 32 bytes", MPSNDArray.mm:893), so a half tensor here cannot be smaller.
static uint16_t halfValues[32] = {
    0x3c00, 0xbc00, 0x0000, 0x8000, 0x7c00, 0xfc00, 0x7e00, 0xfe00,
    0x0001, 0x8001, 0x03ff, 0x0400, 0x3800, 0x1400, 0x3c01, 0x3555,
    // The same sixteen ordinary values as the float vector, narrowed to a half. They are written as bits
    // because the rounding of each is the question: the sixteen values either side of 1.0 are the ones a
    // kernel's last bit is decided on.
    0x2800, 0xa800, 0x2c00, 0xac00, 0x3000, 0xb000, 0x3400, 0xb400,
    0x3c01, 0x3c02, 0x3c04, 0x3c08, 0xbc01, 0xbc02, 0xbc04, 0xbc08,
};
// The second operand, in halves, carrying the classes a divisor column needs - a positive zero, a
// negative zero, an infinity of each sign, a NaN, a denormal - and ordinary values elsewhere.
static uint16_t halfRightValues[32] = {
    0x0000, 0x8000, 0x7c00, 0xfc00, 0x7e00, 0xfe00, 0x0001, 0x4000,
    0xc000, 0x3800, 0x3555, 0x4400, 0x4800, 0x4200, 0x3c00, 0x3c00,
    0x2800, 0xa800, 0x2c00, 0xac00, 0x3000, 0xb000, 0x3400, 0xb400,
    0x4001, 0xc004, 0x3555, 0x4700,
};

// The unary family, over the classes above, so each one of them is answered for every operation of
// the family rather than for the one operation a difference happened to show up in. The square root
// is what the class of a negative pins: the release answers a NaN in float32 and a zero in float16,
// and both are measured rather than one being a bug.
static struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *); } unary[] = {
    {"square", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg squareWithTensor:a name:@"sq"]; }},
    {"reciprocal", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg reciprocalWithTensor:a name:@"rec"]; }},
    {"sqrt", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg squareRootWithTensor:a name:@"sqrt"]; }},
    {"rsqrt", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg reverseSquareRootWithTensor:a name:@"rsqrt"]; }},
    {"log", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg logarithmWithTensor:a name:@"log"]; }},
    {"abs", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg absoluteWithTensor:a name:@"abs"]; }},
    {"sign", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg signWithTensor:a name:@"sign"]; }},
    {"identity", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg identityWithTensor:a name:@"id"]; }},
};

// The arithmetic family, element by element.
static struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *); } binary[] = {
    {"add", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g additionWithPrimaryTensor:a secondaryTensor:b name:@"add"]; }},
    {"subtract", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g subtractionWithPrimaryTensor:a secondaryTensor:b name:@"sub"]; }},
    {"multiply", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g multiplicationWithPrimaryTensor:a secondaryTensor:b name:@"mul"]; }},
    {"divide", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g divisionWithPrimaryTensor:a secondaryTensor:b name:@"div"]; }},
    {"modulo", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g moduloWithPrimaryTensor:a secondaryTensor:b name:@"mod"]; }},
    {"floorModulo", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g floorModuloWithPrimaryTensor:a secondaryTensor:b name:@"fmod"]; }},
    {"power", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g powerWithPrimaryTensor:a secondaryTensor:b name:@"pow"]; }},
    {"atan2", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g atan2WithPrimaryTensor:a secondaryTensor:b name:@"atan2"]; }},
    {"divisionNoNaN", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g divisionNoNaNWithPrimaryTensor:a secondaryTensor:b name:@"divn"]; }},
    {"minimum", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g minimumWithPrimaryTensor:a secondaryTensor:b name:@"min"]; }},
    {"maximum", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g maximumWithPrimaryTensor:a secondaryTensor:b name:@"max"]; }},
    {"logicalAND", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g logicalANDWithPrimaryTensor:a secondaryTensor:b name:@"and"]; }},
    {"logicalOR", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g logicalORWithPrimaryTensor:a secondaryTensor:b name:@"or"]; }},
    {"logicalNAND", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g logicalNANDWithPrimaryTensor:a secondaryTensor:b name:@"nand"]; }},
    {"logicalNOR", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g logicalNORWithPrimaryTensor:a secondaryTensor:b name:@"nor"]; }},
    {"logicalXOR", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g logicalXORWithPrimaryTensor:a secondaryTensor:b name:@"xor"]; }},
    {"logicalXNOR", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g logicalXNORWithPrimaryTensor:a secondaryTensor:b name:@"xnor"]; }},
};

// The family of unary operations that are a rounding or a transcendental, asked over the same sixteen
// classes as the arithmetic above: each of them is a different question of a NaN, a zero and an
// infinity, and a case that only ever saw ordinary values would say nothing about the classes that
// decide the answer.
static struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *); } transcendental[] = {
    {"expBase2", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g exponentBase2WithTensor:a name:@"e2"]; }},
    {"expBase10", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g exponentBase10WithTensor:a name:@"e10"]; }},
    {"logBase2", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g logarithmBase2WithTensor:a name:@"l2"]; }},
    {"logBase10", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g logarithmBase10WithTensor:a name:@"l10"]; }},
    {"negative", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g negativeWithTensor:a name:@"neg"]; }},
    {"signbit", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g signbitWithTensor:a name:@"sb"]; }},
    {"ceil", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g ceilWithTensor:a name:@"ceil"]; }},
    {"floor", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g floorWithTensor:a name:@"floor"]; }},
    {"round", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g roundWithTensor:a name:@"round"]; }},
    {"rint", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g rintWithTensor:a name:@"rint"]; }},
    {"sin", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g sinWithTensor:a name:@"sin"]; }},
    {"cos", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g cosWithTensor:a name:@"cos"]; }},
    {"tan", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g tanWithTensor:a name:@"tan"]; }},
    {"sinh", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g sinhWithTensor:a name:@"sinh"]; }},
    {"cosh", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g coshWithTensor:a name:@"cosh"]; }},
    {"tanh", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g tanhWithTensor:a name:@"tanh"]; }},
    {"asin", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g asinWithTensor:a name:@"asin"]; }},
    {"acos", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g acosWithTensor:a name:@"acos"]; }},
    {"atan", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g atanWithTensor:a name:@"atan"]; }},
    {"asinh", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g asinhWithTensor:a name:@"asinh"]; }},
    {"acosh", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g acoshWithTensor:a name:@"acosh"]; }},
    {"atanh", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g atanhWithTensor:a name:@"atanh"]; }},
    {"erf", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g erfWithTensor:a name:@"erf"]; }},
    {"not", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g notWithTensor:a name:@"not"]; }},
    {"reLU", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reLUWithTensor:a name:@"relu"]; }},
    {"sigmoid", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g sigmoidWithTensor:a name:@"sig"]; }},
};

// The unary predicates, whose result is a boolean and not a number: measured on this host's own MPSGraph,
// isNaN of a rank-3 float32 operand is MPSDataTypeBool where not of the same operand is MPSDataTypeFloat32.
// Their results are therefore one byte an element, and the case name carries that as its own data type.
static struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *); } unaryPredicate[] = {
    {"isNaN", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g isNaNWithTensor:a name:@"nan"]; }},
    {"isFinite", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g isFiniteWithTensor:a name:@"fin"]; }},
    {"isInfinite", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g isInfiniteWithTensor:a name:@"inf"]; }},
};

// The two predicates over two operands, which are booleans on the same measurement.
static struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *); } binaryPredicate[] = {
    {"equal", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g equalWithPrimaryTensor:a secondaryTensor:b name:@"eq"]; }},
    {"notEqual", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g notEqualWithPrimaryTensor:a secondaryTensor:b name:@"ne"]; }},
    {"lessThan", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g lessThanWithPrimaryTensor:a secondaryTensor:b name:@"lt"]; }},
    {"lessThanOrEqualTo", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g lessThanOrEqualToWithPrimaryTensor:a secondaryTensor:b name:@"le"]; }},
    {"greaterThan", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g greaterThanWithPrimaryTensor:a secondaryTensor:b name:@"gt"]; }},
    {"greaterThanOrEqualTo", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g greaterThanOrEqualToWithPrimaryTensor:a secondaryTensor:b name:@"ge"]; }},
};

// The operations with a third operand: a select takes the predicate, the value where it is true and the
// value where it is false, and a clamp takes the value and its two bounds. Both answer the first
// operand's type, measured on this host's own MPSGraph.
static struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *, MPSGraphTensor *); } ternary[] = {
    {"select", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b, MPSGraphTensor *c) { return [g selectWithPredicateTensor:a truePredicateTensor:b falsePredicateTensor:c name:@"sel"]; }},
    {"clamp", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b, MPSGraphTensor *c) { return [g clampWithTensor:a minValueTensor:b maxValueTensor:c name:@"clamp"]; }},
};

// The two activations that take the value that was activated as well as the incoming gradient. The
// source of a sigmoid's gradient is the sigmoid's own answer, so the third feed is what a sigmoid of the
// left operand is, computed here in C: that is an input both sides are given, not an expectation.
static struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *); } gradient[] = {
    {"reLUGradient", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g reLUGradientWithIncomingGradient:a sourceTensor:b name:@"drelu"]; }},
    {"sigmoidGradient", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g sigmoidGradientWithIncomingGradient:a sourceTensor:b name:@"dsig"]; }},
};

// The data type of a feed and the data type of a result are two questions, and a predicate's are two
// answers: the feed is the type its placeholder is, and the result is a boolean. The shaped type that
// describes a feed is the feed's own type, and the shaped type the result is read into is the result's.
static void run(MPSGraph *graph, NSArray<MPSGraphTensor *> *feeds, NSArray<MPSGraphTensorData *> *values,
                MPSGraphTensor *target, void *out, size_t bytes, MPSDataType feedType, MPSDataType resultType)
{
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:target.shape dataType:resultType];
    remember(buffer, out, bytes);
    MPSGraphShapedType *feedShape = [[MPSGraphShapedType alloc] initWithShape:target.shape dataType:feedType];
    NSMutableDictionary *shapedFeeds = [NSMutableDictionary dictionary];
    for (MPSGraphTensor *tensor in feeds) shapedFeeds[tensor] = feedShape;
    MPSGraphExecutable *executable = [graph compileWithDevice:gGraphDevice feeds:shapedFeeds
                                                 targetTensors:@[target] targetOperations:@[] compilationDescriptor:nil];
    [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                          inputsArray:values resultsArray:@[destination] executionDescriptor:nil];
    memcpy(out, [buffer contents], bytes);
}

// One case of the unary family, in the type asked for. The case's own name carries the type, because
// the same operation over the same sixteen classes is a different question in each of them.
static void unary_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *),
                       MPSDataType type, const void *values)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@8, @4] dataType:type name:@"a"];
    MPSGraphTensor *t = build(one, a);
    size_t bytes = 32 * MPSSizeofMPSDataType(type);
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a], @[feed(values, @[@8, @4], type)], t, resultBytes, bytes, type, type);
    put(name, resultBytes, bytes);
}

// The same for a case of the arithmetic family, which takes a second operand.
static void binary_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *),
                        MPSDataType type, const void *left, const void *right)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@8, @4] dataType:type name:@"a"];
    MPSGraphTensor *b = [one placeholderWithShape:@[@8, @4] dataType:type name:@"b"];
    MPSGraphTensor *t = build(one, a, b);
    size_t bytes = 32 * MPSSizeofMPSDataType(type);
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a, b], @[feed(left, @[@8, @4], type), feed(right, @[@8, @4], type)], t, resultBytes, bytes, type, type);
    put(name, resultBytes, bytes);
}

// A case whose result is not the operand's own type: a predicate's is a boolean, one byte an element,
// measured on this host's own MPSGraph (MPSSizeofMPSDataType(MPSDataTypeBool) is 1). The result buffer is
// the operand's sixteen elements in the result's type, so a byte per element is the whole of it.
static void predicate_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *),
                           MPSDataType operandType, const void *values)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@8, @4] dataType:operandType name:@"a"];
    MPSGraphTensor *t = build(one, a);
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a], @[feed(values, @[@8, @4], operandType)], t, resultBytes, 32, operandType, MPSDataTypeBool);
    put(name, resultBytes, 16);
}

static void binary_predicate_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *),
                                  MPSDataType operandType, const void *left, const void *right)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@8, @4] dataType:operandType name:@"a"];
    MPSGraphTensor *b = [one placeholderWithShape:@[@8, @4] dataType:operandType name:@"b"];
    MPSGraphTensor *t = build(one, a, b);
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a, b], @[feed(left, @[@8, @4], operandType), feed(right, @[@8, @4], operandType)], t, resultBytes, 32, operandType, MPSDataTypeBool);
    put(name, resultBytes, 16);
}

// A case with three operands, which the select and the clamp are.
static void ternary_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *, MPSGraphTensor *),
                         MPSDataType type, const void *first, const void *second, const void *third)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@8, @4] dataType:type name:@"a"];
    MPSGraphTensor *b = [one placeholderWithShape:@[@8, @4] dataType:type name:@"b"];
    MPSGraphTensor *c = [one placeholderWithShape:@[@8, @4] dataType:type name:@"c"];
    MPSGraphTensor *t = build(one, a, b, c);
    size_t bytes = 32 * MPSSizeofMPSDataType(type);
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a, b, c], @[feed(first, @[@8, @4], type), feed(second, @[@8, @4], type),
                          feed(third, @[@8, @4], type)], t, resultBytes, bytes, type, type);
    put(name, resultBytes, bytes);
}

// THE REDUCTION FAMILY, and the one thing about it that the arithmetic cases above never had to answer:
// the result is not the operand's shape. A reduction over an axis of a 2x4 answers a 2x1 or a 1x4 and the
// feed is still the 2x4, so the case below gives the compile a feed of the operand's own shape and a
// destination of the result's own shape - run() above uses the target's shape for both, which is right for
// an elementwise operation and wrong for every one of these.
static void reduction_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *),
                           MPSDataType type, const void *values, NSArray<NSNumber *> *shape)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:shape dataType:type name:@"a"];
    MPSGraphTensor *t = build(one, a);
    NSUInteger count = 1;
    for (NSNumber *dimension in t.shape) count *= (NSUInteger)dimension.integerValue;
    size_t bytes = count * MPSSizeofMPSDataType(t.dataType);
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer
                                                                              shape:t.shape
                                                                            dataType:t.dataType];
    remember(buffer, resultBytes, bytes);
    MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:a.shape dataType:type];
    MPSGraphExecutable *executable = [one compileWithDevice:gGraphDevice feeds:@{a: shaped}
                                              targetTensors:@[t] targetOperations:@[] compilationDescriptor:nil];
    [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                          inputsArray:@[feed(values, shape, type)]
                           resultsArray:@[destination] executionDescriptor:nil];
    put(name, resultBytes, bytes);
}

// The same over a mean that was computed first, which is the form varianceOfTensor:meanTensor:axes: takes:
// the mean is a second placeholder of the graph that consumes it and the caller hands over what it has.
// The mean fed here is the one the framework itself answered for the same feed, read out of a run of the
// meanOfTensor case - it is an input to the case, not an expectation, and facts/MetalPerformanceShadersGraph/
// Core.md carries what both sides answer for it.
static void variance_with_mean_case(const char *name, MPSDataType type, const void *values,
                                    NSArray<NSNumber *> *shape, NSArray<NSNumber *> *axes,
                                    const void *meanValues)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:shape dataType:type name:@"a"];
    MPSGraphTensor *m = [one placeholderWithShape:@[@2, @1] dataType:type name:@"mean"];
    MPSGraphTensor *t = [one varianceOfTensor:a meanTensor:m axes:axes name:@"variance"];
    size_t bytes = 2 * MPSSizeofMPSDataType(type);
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer
                                                                              shape:@[@2, @1]
                                                                            dataType:type];
    remember(buffer, resultBytes, bytes);
    NSMutableDictionary *shaped = [NSMutableDictionary dictionary];
    shaped[a] = [[MPSGraphShapedType alloc] initWithShape:shape dataType:type];
    shaped[m] = [[MPSGraphShapedType alloc] initWithShape:@[@2, @1] dataType:type];
    MPSGraphExecutable *executable = [one compileWithDevice:gGraphDevice feeds:shaped
                                              targetTensors:@[t] targetOperations:@[] compilationDescriptor:nil];
    [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                          inputsArray:@[feed(values, shape, type), feed(meanValues, @[@2, @1], type)]
                           resultsArray:@[destination] executionDescriptor:nil];
    put(name, resultBytes, bytes);
}

// The reduction family, over a feed of eight values in a 2x4 and over the sixteen classes of the
// arithmetic cases, so every reduction is asked of the values that have shown every other difference:
// a NaN of each sign, both infinities, a denormal, and the ordinary values either side of one.
static void reduction_families(void)
{
    static NSArray<NSNumber *> *shape2x4;
    char name[64];
    unsigned i;
    struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *); } reducing[] = {
        {"reductionSum", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionSumWithTensor:a axis:1 name:@"sum"]; }},
        {"reductionProduct", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionProductWithTensor:a axis:1 name:@"prod"]; }},
        {"reductionMaximum", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionMaximumWithTensor:a axis:1 name:@"max"]; }},
        {"reductionMinimum", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionMinimumWithTensor:a axis:1 name:@"min"]; }},
        {"reductionMaximumPropagateNaN", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionMaximumPropagateNaNWithTensor:a axis:1 name:@"maxnan"]; }},
        {"reductionMinimumPropagateNaN", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionMinimumPropagateNaNWithTensor:a axis:1 name:@"minnan"]; }},
        {"mean", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g meanOfTensor:a axes:@[@1] name:@"mean"]; }},
        {"variance", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g varianceOfTensor:a axes:@[@1] name:@"var"]; }},
    };
    shape2x4 = @[@2, @4];
    // The eight over the sixteen classes of the arithmetic family, which is where a NaN, an infinity and
    // a denormal meet the sum and the product as well as the maximum and the mean.
    for (i = 0; i < sizeof(reducing) / sizeof(reducing[0]); i++) {
        snprintf(name, sizeof name, "%s float32", reducing[i].name);
        reduction_case(name, reducing[i].build, MPSDataTypeFloat32, leftValues, shape2x4);
    }
    // The shape questions, each its own case because each is a different rule about the set of axes. The
    // qualifier is part of the operation's own name and not a word of its own, because run.sh reads a case
    // line as exactly five fields - the marker, the operation, the data type, the length and the bytes -
    // and a sixth would move the length out from under it.
    reduction_case("reductionSum-axis0 float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionSumWithTensor:a axis:0 name:@"s0"]; },
                   MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("reductionSum-axisNeg1 float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionSumWithTensor:a axis:-1 name:@"sn1"]; },
                   MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("reductionSum-axisNeg2 float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionSumWithTensor:a axis:-2 name:@"sn2"]; },
                   MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("reductionSum-axesNil float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionSumWithTensor:a axes:nil name:@"snil"]; },
                   MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("reductionSum-axesEmpty float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionSumWithTensor:a axes:@[] name:@"sempty"]; },
                   MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("reductionSum-axesRepeated float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionSumWithTensor:a axes:@[@0, @0] name:@"sr"]; },
                   MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("reductionSum-axesDescending float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionSumWithTensor:a axes:@[@1, @0] name:@"sdesc"]; },
                   MPSDataTypeFloat32, rowFeed, shape2x4);
    // The other two data types, because a mean and a variance in integers are truncated quotients and a
    // half is a different accumulator: measured on this host's own MPSGraph, over the int32 feed the mean
    // of a row of four is the truncated sum over four and the variance the truncated mean of the squared
    // deviations.
    for (i = 0; i < sizeof(reducing) / sizeof(reducing[0]); i++) {
        snprintf(name, sizeof name, "%s int32", reducing[i].name);
        reduction_case(name, reducing[i].build, MPSDataTypeInt32, intFeed, shape2x4);
    }
    for (i = 0; i < sizeof(reducing) / sizeof(reducing[0]); i++) {
        snprintf(name, sizeof name, "%s float16", reducing[i].name);
        reduction_case(name, reducing[i].build, MPSDataTypeFloat16, halfFeed, shape2x4);
    }
    // The variance of a mean handed in, over the same feed and the mean of it.
    variance_with_mean_case("varianceOfMean float32", MPSDataTypeFloat32, rowFeed, shape2x4, @[@1],
                            meanFeed);
    variance_with_mean_case("varianceOfMean int32", MPSDataTypeInt32, intFeed, shape2x4, @[@1], intMeanFeed);
    // A reduced set of nothing but NaNs, which is the one answer of the four extremes that the arithmetic
    // cases cannot reach: every element of the row is a NaN, so what a maximum that skips them and one
    // that propagates them answer is decided here.
    reduction_case("reductionMaximum-allNaN float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionMaximumWithTensor:a axis:1 name:@"mx"]; },
                   MPSDataTypeFloat32, nanFeed, shape2x4);
    reduction_case("reductionMaximumPropagateNaN-allNaN float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionMaximumPropagateNaNWithTensor:a axis:1 name:@"mxn"]; },
                   MPSDataTypeFloat32, nanFeed, shape2x4);
    reduction_case("reductionMinimum-allNaN float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionMinimumWithTensor:a axis:1 name:@"mn"]; },
                   MPSDataTypeFloat32, nanFeed, shape2x4);
    reduction_case("reductionMinimumPropagateNaN-allNaN float32",
                   ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionMinimumPropagateNaNWithTensor:a axis:1 name:@"mnn"]; },
                   MPSDataTypeFloat32, nanFeed, shape2x4);
}

// The feeds the reduction family that arrived in 15.0 and 15.3 is asked over. The sixteen classes above
// are what an index reduction and a truth fold have to be asked of - a NaN of each sign, both infinities,
// both zeros, a denormal - and the ties are what decide whether an argument reduction answers the first
// or the last of several equal elements, so a row of (4, 4, 4, 9 | 9, 9, 1, 1) is asked as well: every
// element of it is in the answer twice.
static float tieFeed[8] = { 4.0f, 4.0f, 4.0f, 9.0f, 9.0f, 9.0f, 1.0f, 1.0f };

// THE CUMULATIVE FAMILY of 16.0, whose result is the operand's OWN shape - so unlike the reduction family
// this one needs no case helper of its own, and the elementwise run() above is right for it - and whose
// axis can be a number written down or a tensor fed at run time. The axis tensor is a second input of the
// same shape as the reduction family's operands are, so the case builds the compile with two feeds.
static void cumulative_axis_tensor_case(const char *name, MPSDataType type, NSArray<NSNumber *> *shape,
                                        const void *values, int32_t axis, int isMaximum, int isMinimum,
                                        BOOL exclusive, BOOL reverse)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:shape dataType:type name:@"a"];
    MPSGraphTensor *axisTensor = [one placeholderWithShape:@[@1] dataType:MPSDataTypeInt32 name:@"axis"];
    MPSGraphTensor *t;
    if (isMaximum)
        t = exclusive || reverse ? [one cumulativeMaximumWithTensor:a axisTensor:axisTensor
                                                          exclusive:exclusive reverse:reverse name:@"M"]
                                 : [one cumulativeMaximumWithTensor:a axisTensor:axisTensor name:@"M"];
    else if (isMinimum)
        t = exclusive || reverse ? [one cumulativeMinimumWithTensor:a axisTensor:axisTensor
                                                          exclusive:exclusive reverse:reverse name:@"m"]
                                 : [one cumulativeMinimumWithTensor:a axisTensor:axisTensor name:@"m"];
    else
        t = exclusive || reverse ? [one cumulativeSumWithTensor:a axisTensor:axisTensor
                                                      exclusive:exclusive reverse:reverse name:@"s"]
                                 : [one cumulativeSumWithTensor:a axisTensor:axisTensor name:@"s"];
    NSUInteger count = 1;
    for (NSNumber *dimension in t.shape) count *= (NSUInteger)dimension.integerValue;
    size_t bytes = count * MPSSizeofMPSDataType(t.dataType);
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:t.shape
                                                                            dataType:t.dataType];
    remember(buffer, resultBytes, bytes);
    NSMutableDictionary *shaped = [NSMutableDictionary dictionary];
    shaped[a] = [[MPSGraphShapedType alloc] initWithShape:shape dataType:type];
    shaped[axisTensor] = [[MPSGraphShapedType alloc] initWithShape:@[@1] dataType:MPSDataTypeInt32];
    MPSGraphExecutable *executable = [one compileWithDevice:gGraphDevice feeds:shaped
                                              targetTensors:@[t] targetOperations:@[] compilationDescriptor:nil];
    [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                          inputsArray:@[feed(values, shape, type), feed(&axis, @[@1], MPSDataTypeInt32)]
                           resultsArray:@[destination] executionDescriptor:nil];
    put(name, resultBytes, bytes);
}

// The four operations over the ordinary feed, each in all four flag combinations, in the type asked for.
// The ordinary feed is what tests the rule and the classes are what test the seeds: an exclusive answer
// starts at the seed, and a NaN, an infinity and a zero are what say which seed each operation has.
static void cumulative_families(MPSDataType type, const void *values, const char *label)
{
    NSArray<NSNumber *> *shape2x4 = @[@2, @4];
    static float ordinary[8] = { 1.0f, 2.0f, 3.0f, 4.0f, 10.0f, 20.0f, 30.0f, 40.0f };
    static int32_t integers[8] = { -3, -2, -1, 0, 1, 2, 3, 4 };
    static uint16_t halves[8] = { 0x3c00, 0x4000, 0x4200, 0x4400, 0x4500, 0x4600, 0x4700, 0x4800 };
    static float classes[8] = { 1.0f, -1.0f, -0.0f, 0.0f, INFINITY, -INFINITY, NAN, -NAN };
    static float allNaN[8] = { NAN, NAN, NAN, NAN, NAN, NAN, NAN, NAN };
    // The feed this case asks over, chosen by the data type so that each type reads the numbers it can hold.
    const void *fed = type == MPSDataTypeInt32 ? (const void *)integers
                     : type == MPSDataTypeFloat16 ? (const void *)halves : values;
    struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, NSInteger, BOOL, BOOL); } ops[] = {
        {"cumulativeSum", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, NSInteger axis, BOOL e, BOOL r) {
            return e || r ? [g cumulativeSumWithTensor:a axis:axis exclusive:e reverse:r name:@"s"]
                          : [g cumulativeSumWithTensor:a axis:axis name:@"s"]; }},
        {"cumulativeProduct", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, NSInteger axis, BOOL e, BOOL r) {
            return e || r ? [g cumulativeProductWithTensor:a axis:axis exclusive:e reverse:r name:@"p"]
                          : [g cumulativeProductWithTensor:a axis:axis name:@"p"]; }},
        {"cumulativeMaximum", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, NSInteger axis, BOOL e, BOOL r) {
            return e || r ? [g cumulativeMaximumWithTensor:a axis:axis exclusive:e reverse:r name:@"M"]
                          : [g cumulativeMaximumWithTensor:a axis:axis name:@"M"]; }},
        {"cumulativeMinimum", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, NSInteger axis, BOOL e, BOOL r) {
            return e || r ? [g cumulativeMinimumWithTensor:a axis:axis exclusive:e reverse:r name:@"m"]
                          : [g cumulativeMinimumWithTensor:a axis:axis name:@"m"]; }},
    };
    char name[96];
    unsigned i, f;
    for (i = 0; i < sizeof(ops) / sizeof(ops[0]); i++) {
        for (f = 0; f < 4; f++) {
            BOOL exclusive = (f & 1) != 0, reverse = (f & 2) != 0;
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:shape2x4 dataType:type name:@"a"];
            MPSGraphTensor *t = ops[i].build(one, a, 1, exclusive, reverse);
            size_t bytes = 8 * MPSSizeofMPSDataType(type);
            id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
            MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:t.shape
                                                                                    dataType:t.dataType];
            remember(buffer, resultBytes, bytes);
            MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:shape2x4 dataType:type];
            MPSGraphExecutable *executable = [one compileWithDevice:gGraphDevice feeds:@{a: shaped}
                                                      targetTensors:@[t] targetOperations:@[] compilationDescriptor:nil];
            [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                                  inputsArray:@[feed(fed, shape2x4, type)]
                                   resultsArray:@[destination] executionDescriptor:nil];
            snprintf(name, sizeof name, "%s-e%d-r%d %s", ops[i].name, exclusive, reverse, label);
            put(name, resultBytes, bytes);
        }
    }
    // The other axis of the operand and a negative one, over the ordinary feed, which is where the two
    // answers have to be the two the reduction family's negative axis answers are read against.
    for (i = 0; i < 2; i++) {
        NSInteger axis = i == 0 ? 0 : -1;
        MPSGraph *one = [MPSGraph new];
        MPSGraphTensor *a = [one placeholderWithShape:shape2x4 dataType:type name:@"a"];
        MPSGraphTensor *t = i == 0 ? [one cumulativeSumWithTensor:a axis:0 name:@"s0"]
                                   : [one cumulativeSumWithTensor:a axis:-1 name:@"sn1"];
        size_t bytes = 8 * MPSSizeofMPSDataType(type);
        id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
        MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:t.shape
                                                                                dataType:t.dataType];
        remember(buffer, resultBytes, bytes);
        MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:shape2x4 dataType:type];
        MPSGraphExecutable *executable = [one compileWithDevice:gGraphDevice feeds:@{a: shaped}
                                                  targetTensors:@[t] targetOperations:@[] compilationDescriptor:nil];
        [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                              inputsArray:@[feed(ordinary, shape2x4, type)]
                               resultsArray:@[destination] executionDescriptor:nil];
        snprintf(name, sizeof name, "cumulativeSum-axis%ld %s", (long)axis, label);
        put(name, resultBytes, bytes);
    }
    // The axis fed at run time, over the same feed and the same four flag combinations of one operation
    // each: the sum's plain form, the sum's flags, the maximum's plain form and the minimum's flags, which
    // between them are the two forms of the axis with and without the flags for three of the four.
    cumulative_axis_tensor_case("cumulativeSum-axisTensor-e0-r0 float32", MPSDataTypeFloat32, shape2x4,
                                 ordinary, 1, 0, 0, NO, NO);
    cumulative_axis_tensor_case("cumulativeSum-axisTensor-e1-r1 float32", MPSDataTypeFloat32, shape2x4,
                                 ordinary, 1, 0, 0, YES, YES);
    cumulative_axis_tensor_case("cumulativeProduct-axisTensor-e0-r0 float32", MPSDataTypeFloat32, shape2x4,
                                 ordinary, 1, 0, 0, NO, NO);
    cumulative_axis_tensor_case("cumulativeProduct-axisTensor-e0-r1 float32", MPSDataTypeFloat32, shape2x4,
                                 ordinary, 1, 0, 0, NO, YES);
    cumulative_axis_tensor_case("cumulativeMaximum-axisTensor-e0-r0 float32", MPSDataTypeFloat32, shape2x4,
                                 ordinary, 1, 1, 0, NO, NO);
    cumulative_axis_tensor_case("cumulativeMaximum-axisTensor-e1-r1 float32", MPSDataTypeFloat32, shape2x4,
                                 ordinary, 1, 1, 0, YES, YES);
    cumulative_axis_tensor_case("cumulativeMinimum-axisTensor-e0-r0 float32", MPSDataTypeFloat32, shape2x4,
                                 ordinary, 1, 0, 1, NO, NO);
    cumulative_axis_tensor_case("cumulativeMinimum-axisTensor-e1-r0 float32", MPSDataTypeFloat32, shape2x4,
                                 ordinary, 1, 0, 1, YES, NO);
    cumulative_axis_tensor_case("cumulativeMaximum-axisTensor-axis0 float32", MPSDataTypeFloat32, shape2x4,
                                 ordinary, 0, 1, 0, NO, NO);
    // The sixteen classes and a row of nothing but NaNs, which is where the seeds and the NaN rule are:
    // a NaN loses every comparison in a scan as it does in a reduction, so the position whose whole side of
    // the walk is NaN answers the seed rather than a NaN.
    for (i = 0; i < 2; i++) {
        for (f = 0; f < 4; f++) {
            BOOL exclusive = (f & 1) != 0, reverse = (f & 2) != 0;
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:shape2x4 dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *t = (i == 0 ? [one cumulativeMaximumWithTensor:a axis:1 exclusive:exclusive reverse:reverse name:@"M"]
                                        : [one cumulativeMinimumWithTensor:a axis:1 exclusive:exclusive reverse:reverse name:@"m"]);
            id<MTLBuffer> buffer = [gDevice newBufferWithLength:32 options:MTLResourceStorageModeShared];
            MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:@[@2, @4]
                                                                                    dataType:MPSDataTypeFloat32];
            remember(buffer, resultBytes, 32);
            MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:shape2x4
                                                                            dataType:MPSDataTypeFloat32];
            MPSGraphExecutable *executable = [one compileWithDevice:gGraphDevice feeds:@{a: shaped}
                                                      targetTensors:@[t] targetOperations:@[] compilationDescriptor:nil];
            [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                                  inputsArray:@[feed(i == 0 ? (const void *)classes : (const void *)allNaN,
                                                     shape2x4, MPSDataTypeFloat32)]
                                   resultsArray:@[destination] executionDescriptor:nil];
            snprintf(name, sizeof name, "%s-e%d-r%d %s", i == 0 ? "cumulativeMaximum" : "cumulativeMinimum",
                     exclusive, reverse, i == 0 ? "float32" : "allNaN");
            put(name, resultBytes, 32);
        }
    }
}

// THE GATHER FAMILY - the sixteen methods whose result is the operand's elements in some other order or
// another extent - is six families here, and one process each, because within one process the release's own
// gather operations assert over the SECOND flatten even when the process holds nothing else: "Error: NDArray
// dimension length > INT_MAX" (MPSNDArray.mm:831). What is measured for each form is written down in
// facts/MetalPerformanceShadersGraph/Core.md, and the rules the walk in MPSGraphInterpreter14.m answers
// are:
//
//   - a transpose is the row-major transpose, in both forms and with a permutation, and a negative axis is
//     counted from the end;
//   - the squeeze, the expanded dimension and the flatten are ONE gather with the axes left alone - each
//     answers the operand's own bytes in the operand's own order;
//   - a broadcast aligns to the RIGHT of the shape given and wraps each axis the shape makes wider;
//   - a reverse flips the axes it is given and nothing else.
//
// The five FED forms - the flatten's axis, the broadcast's shape and the reverse's, the squeeze's and the
// expanded dimension's set of axes - are NOT cases here: asked in a process of its own each of them takes
// the release down (facts/MetalPerformanceShadersGraph/Core.md carries each one's own assertion), so
// there is no answer of the release for a case to compare against and the port's answer is its header's.

// Every family below ends with the chain, which is defined with the rest of the cases at the end of this
// file - the six gather families come before it in the file's order because they come before the table of
// families in the run order, and a declaration here is what lets them end with it.
static void chain_case(void);

// The feeds the gather families are asked over. The ordinary one is the case file's own 2x4 of (1, 2, 3, 4 |
// 10, 20, 30, 40), whose answers a reader can work out by hand; the rank-3 one is the 1 to 24 a 2x3x4 holds
// in row-major order, which is the same: every answer below is either the operand's own bytes in another
// order or the same bytes at another extent, so the feed is what makes the answer readable rather than the
// shape alone.
static float cubeFeed[24] = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
};
// The sixteen input classes' first row, as a 2x4: a positive and a negative, both zeros, both infinities and
// a NaN of each sign. A gather copies, so these are what says it copies - a NaN's sign and a negative zero's
// sign are the two things a walk that recomputes a value would lose.
static float gatherClasses[8] = { 1.0f, -1.0f, -0.0f, 0.0f, INFINITY, -INFINITY, NAN, -NAN };

// A gather's case: the compile is given a feed of the OPERAND's shape and a destination of the RESULT's,
// which the elementwise run() above cannot do - a reduction_case's arrangement, with the operand and the
// result named apart because a gather's result is a different shape at least as often as the same one.
//
// Two lines a case. The shape is printed as well as the bytes, because a gather's answer is its SHAPE as much
// as its elements and the two do not go together: dropping a unit axis never moves an element, so a squeeze's
// bytes cannot say whether the axis was dropped, and adding one neither. Reading a shaped type's EQUALITY takes
// the release down (it calls a selector its own MPSGraphTensor does not declare), but reading the shape off
// the tensor is what every other case here already does and it answers.
//
// `fill` is a byte the destination is filled with before the run, 0 for a fresh buffer. One case asks for it
// because the release writes zeros where a broadcast has no element to read, and a destination the caller had
// already filled is what tells a written zero from one that was simply never written.
static void gather_case_filled(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *),
                               MPSDataType type, NSArray<NSNumber *> *shape, const void *values,
                               unsigned char fill)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:shape dataType:type name:@"a"];
    MPSGraphTensor *t = build(one, a);
    NSUInteger count = 1;
    for (NSNumber *dimension in t.shape) count *= (NSUInteger)dimension.integerValue;
    size_t bytes = count * MPSSizeofMPSDataType(t.dataType);
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    if (fill) memset([buffer contents], fill, bytes);
    printf("#case %s-shape %s\n", name, [[t.shape componentsJoinedByString:@"x"] UTF8String]);
    MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:t.shape
                                                                             dataType:t.dataType];
    remember(buffer, resultBytes, bytes);
    MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:shape dataType:type];
    MPSGraphExecutable *executable = [one compileWithDevice:gGraphDevice feeds:@{a: shaped}
                                              targetTensors:@[t] targetOperations:@[] compilationDescriptor:nil];
    [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                          inputsArray:@[feed(values, shape, type)]
                           resultsArray:@[destination] executionDescriptor:nil];
    put(name, resultBytes, bytes);
}

static void gather_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *),
                        MPSDataType type, NSArray<NSNumber *> *shape, const void *values)
{
    gather_case_filled(name, build, type, shape, values, 0);
}

// The transpose, in both of the forms the family has: 14.0's two axes and 16.0's permutation. The rank-3
// cases are here because a two-axis transpose of a rank above two is a different question from a rank of
// two - the result keeps the operand's rank with two of its axes exchanged, and a permutation of a whole
// ordering is the same question written the other way round.
static void family_gather_transpose(void)
{
    NSArray<NSNumber *> *twoByFour = @[@2, @4];
    NSArray<NSNumber *> *twoByThreeByFour = @[@2, @3, @4];
    gather_case("transpose-axes0-1 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g transposeTensor:a dimension:0 withDimension:1 name:@"t"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("transpose-axesNeg1-0 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g transposeTensor:a dimension:(NSUInteger)-1 withDimension:0 name:@"t"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("transpose-permutation10 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g transposeTensor:a permutation:@[@1, @0] name:@"t"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("transpose-permutation01 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g transposeTensor:a permutation:@[@0, @1] name:@"t"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("transpose-classes-permutation10 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g transposeTensor:a permutation:@[@1, @0] name:@"t"]; },
                MPSDataTypeFloat32, twoByFour, gatherClasses);
    // The 32 classes over a whole 8x4, where a NaN's sign and a denormal's bytes have to survive a walk of
    // the whole operand.
    gather_case("transpose-classes32-permutation10 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g transposeTensor:a permutation:@[@1, @0] name:@"t"]; },
                MPSDataTypeFloat32, @[@8, @4], leftValues);
    gather_case("transpose-axes0-2 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g transposeTensor:a dimension:0 withDimension:2 name:@"t"]; },
                MPSDataTypeFloat32, twoByThreeByFour, cubeFeed);
    gather_case("transpose-axes1-2 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g transposeTensor:a dimension:1 withDimension:2 name:@"t"]; },
                MPSDataTypeFloat32, twoByThreeByFour, cubeFeed);
    gather_case("transpose-permutation201 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g transposeTensor:a permutation:@[@2, @0, @1] name:@"t"]; },
                MPSDataTypeFloat32, twoByThreeByFour, cubeFeed);
    gather_case("transpose-permutation120 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g transposeTensor:a permutation:@[@1, @2, @0] name:@"t"]; },
                MPSDataTypeFloat32, twoByThreeByFour, cubeFeed);
    chain_case();
}

// The flatten, which collapses every axis from the one named on into a single axis. A rank of three is where
// the collapse covers more than one axis, so the axes of the result there read two and three of the operand's
// at once - which is the one thing in this family that is not a copy of the operand's bytes in order.
static void family_gather_flatten(void)
{
    NSArray<NSNumber *> *twoByFour = @[@2, @4];
    NSArray<NSNumber *> *twoByThreeByFour = @[@2, @3, @4];
    gather_case("flatten-axis0-2x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g flatten2DTensor:a axis:0 name:@"f"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("flatten-axis1-2x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g flatten2DTensor:a axis:1 name:@"f"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("flatten-axis0-2x3x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g flatten2DTensor:a axis:0 name:@"f"]; },
                MPSDataTypeFloat32, twoByThreeByFour, cubeFeed);
    gather_case("flatten-axis1-2x3x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g flatten2DTensor:a axis:1 name:@"f"]; },
                MPSDataTypeFloat32, twoByThreeByFour, cubeFeed);
    gather_case("flatten-axis2-2x3x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g flatten2DTensor:a axis:2 name:@"f"]; },
                MPSDataTypeFloat32, twoByThreeByFour, cubeFeed);
    gather_case("flatten-classes-axis0 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g flatten2DTensor:a axis:0 name:@"f"]; },
                MPSDataTypeFloat32, twoByFour, gatherClasses);
    chain_case();
}

// The broadcast, which aligns the operand to the RIGHT of the shape given and wraps each axis that shape
// makes wider. The three cases are the three shapes there are: wider on one axis, an axis added at the front,
// and the operand's own shape.
static void family_gather_broadcast(void)
{
    NSArray<NSNumber *> *twoByFour = @[@2, @4];
    gather_case("broadcast-4x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g broadcastTensor:a toShape:@[@4, @4] name:@"b"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("broadcast-2x2x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g broadcastTensor:a toShape:@[@2, @2, @4] name:@"b"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("broadcast-own-shape float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g broadcastTensor:a toShape:@[@2, @4] name:@"b"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("broadcast-classes-4x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g broadcastTensor:a toShape:@[@4, @4] name:@"b"]; },
                MPSDataTypeFloat32, twoByFour, gatherClasses);
    // A rank of three on both sides, where the axis the shape adds is the one the operand has no axis for.
    gather_case("broadcast-2x3x4-4x3x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g broadcastTensor:a toShape:@[@4, @3, @4] name:@"b"]; },
                MPSDataTypeFloat32, @[@2, @3, @4], cubeFeed);
    gather_case("broadcast-1x2x4-2x2x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g broadcastTensor:a toShape:@[@2, @2, @4] name:@"b"]; },
                MPSDataTypeFloat32, @[@1, @2, @4], cubeFeed);
    // The two axes the shape makes wider than the operand's are the ones the release answers a ZERO at, so
    // this case is asked over a destination filled with a pattern: the answer has to be the release's zeros and
    // not the bytes the caller happened to leave there.
    gather_case_filled("broadcast-4x4-prefilled float32",
                       ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                           return [g broadcastTensor:a toShape:@[@4, @4] name:@"b"]; },
                       MPSDataTypeFloat32, twoByFour, rowFeed, 0xbd);
    // And a broadcast that narrows, which is not a broadcast at all: the release keeps the operand's own extent
    // on that axis and answers the operand's bytes, so the result's shape is the case that says so.
    gather_case("broadcast-narrower float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g broadcastTensor:a toShape:@[@1, @4] name:@"b"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    chain_case();
}

// The reverse, which flips the axes it is given and nothing else. The cases are each axis on its own, both,
// neither (the form with no axes at all) and a nil, which is the same question asked the other way round.
static void family_gather_reverse(void)
{
    NSArray<NSNumber *> *twoByFour = @[@2, @4];
    gather_case("reverse-none float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g reverseTensor:a name:@"r"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("reverse-axesNil float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g reverseTensor:a axes:nil name:@"r"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("reverse-axis0 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g reverseTensor:a axes:@[@0] name:@"r"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("reverse-axis1 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g reverseTensor:a axes:@[@1] name:@"r"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("reverse-axes01 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g reverseTensor:a axes:@[@1, @0] name:@"r"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("reverse-negative-axis float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g reverseTensor:a axes:@[@-1] name:@"r"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("reverse-classes-none float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g reverseTensor:a name:@"r"]; },
                MPSDataTypeFloat32, twoByFour, gatherClasses);
    gather_case("reverse-rank3 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g reverseTensor:a name:@"r"]; },
                MPSDataTypeFloat32, @[@1, @2, @4], cubeFeed);
    chain_case();
}

// The squeeze, which drops the axes of extent one it is given - every unit axis when it is given none - and
// keeps the rest in order. The cases are the two forms with no axes (an operand that has a unit axis and one
// that has none), one axis, a set of axes, a negative axis and a nil.
static void family_gather_squeeze(void)
{
    NSArray<NSNumber *> *twoByFour = @[@2, @4];
    NSArray<NSNumber *> *oneByTwoByFour = @[@1, @2, @4];
    NSArray<NSNumber *> *oneByOneByFour = @[@1, @1, @4];
    NSArray<NSNumber *> *twoByFourByOne = @[@2, @4, @1];
    gather_case("squeeze-none-1x2x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a name:@"s"]; },
                MPSDataTypeFloat32, oneByTwoByFour, cubeFeed);
    gather_case("squeeze-none-2x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a name:@"s"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("squeeze-axis0 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a axis:0 name:@"s"]; },
                MPSDataTypeFloat32, oneByTwoByFour, cubeFeed);
    gather_case("squeeze-axes0 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a axes:@[@0] name:@"s"]; },
                MPSDataTypeFloat32, oneByTwoByFour, cubeFeed);
    gather_case("squeeze-axes01 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a axes:@[@0, @1] name:@"s"]; },
                MPSDataTypeFloat32, oneByOneByFour, cubeFeed);
    gather_case("squeeze-axesNil float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a axes:nil name:@"s"]; },
                MPSDataTypeFloat32, oneByTwoByFour, cubeFeed);
    gather_case("squeeze-negative-axis float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a axis:-1 name:@"s"]; },
                MPSDataTypeFloat32, twoByFourByOne, cubeFeed);
    gather_case("squeeze-classes float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a name:@"s"]; },
                MPSDataTypeFloat32, oneByTwoByFour, gatherClasses);
    // A unit axis in the MIDDLE, where dropping it moves no element: the eight values of a 2x1x4 read the same
    // whether the axis is there or not, so this case is about the shape line and about nothing else - which is
    // what the shape line is in this file for.
    gather_case("squeeze-none-2x1x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a name:@"s"]; },
                MPSDataTypeFloat32, @[@2, @1, @4], cubeFeed);
    gather_case("squeeze-axesNil-2x1x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a axes:nil name:@"s"]; },
                MPSDataTypeFloat32, @[@2, @1, @4], cubeFeed);
    gather_case("squeeze-axesEmpty-2x1x4 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g squeezeTensor:a axes:@[] name:@"s"]; },
                MPSDataTypeFloat32, @[@2, @1, @4], cubeFeed);
    chain_case();
}

// The expanded dimension, which adds an axis of extent one where it is asked for. A negative axis is counted
// from the end and may be the rank itself, which is the trailing unit axis, so the last case is that one.
static void family_gather_expand(void)
{
    NSArray<NSNumber *> *twoByFour = @[@2, @4];
    gather_case("expand-axis0 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g expandDimsOfTensor:a axis:0 name:@"e"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("expand-axis2 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g expandDimsOfTensor:a axis:2 name:@"e"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("expand-axisNeg1 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g expandDimsOfTensor:a axis:-1 name:@"e"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("expand-axes02 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g expandDimsOfTensor:a axes:@[@0, @2] name:@"e"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    // Two more sets of two axes, which is where "an axis at each index named" and "one axis inserted after
    // another" come apart: over a 2x4 the release answers a 1x1x2x4 and a 2x1x1x4, and inserting each axis
    // into the result of the last would answer a 1x1x2x4 and a 2x1x1x4 for the second and a different shape
    // again for the first.
    gather_case("expand-axes01 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g expandDimsOfTensor:a axes:@[@0, @1] name:@"e"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("expand-axes12 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g expandDimsOfTensor:a axes:@[@1, @2] name:@"e"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("expand-axesNil float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g expandDimsOfTensor:a axes:nil name:@"e"]; },
                MPSDataTypeFloat32, twoByFour, rowFeed);
    gather_case("expand-classes-axis0 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g expandDimsOfTensor:a axis:0 name:@"e"]; },
                MPSDataTypeFloat32, twoByFour, gatherClasses);
    gather_case("expand-rank3-axis1 float32",
                ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                    return [g expandDimsOfTensor:a axis:1 name:@"e"]; },
                MPSDataTypeFloat32, @[@2, @3, @4], cubeFeed);
    chain_case();
}

// The data types the two NaN-propagating binaries do not answer, and the feeds they are asked over: eight
// ascending bytes against eight descending ones, so every type here reads the same two numbers.
static unsigned char refusedBytes[8] = { 1, 2, 3, 4, 5, 6, 7, 8 };
static unsigned char reversedBytes[8] = { 8, 7, 6, 5, 4, 3, 2, 1 };
static struct { const char *name; MPSDataType type; } refused[] = {
    {"int8", MPSDataTypeInt8}, {"int16", MPSDataTypeInt16}, {"int32", MPSDataTypeInt32},
    {"int64", MPSDataTypeInt64}, {"uint8", MPSDataTypeUInt8}, {"uint16", MPSDataTypeUInt16},
    {"uint32", MPSDataTypeUInt32}, {"uint64", MPSDataTypeUInt64}, {"bool", MPSDataTypeBool},
};

// The refusal of the pair above, asked the way a differential asks one: the graph is built and run inside
// the @try, because that is where the release raises, and what is printed is the name of the exception
// rather than the framework's own message about its kernel table, which is not a contract.
//
// Every data type that is not a floating point one is asked, because the set the release refuses is the
// question and one type is not the set: measured on this host's own MPSGraph, int8, int16, int32, int64,
// uint8, uint16, uint32, uint64 and bool each raise, and float16 and float32 each answer. The kernel the
// release reaches for is named in the exception and it names the type - isNaN_i8, isNaN_i16_i8, isNaN_i_i8,
// isNaN_i64_i8, isNaN_u8_i8, isNaN_u16_i8, isNaN_u_i8, isNaN_u64_i8, and for a boolean isNaN_i8 again -
// which is the whole of what it is refusing: there is no NaN kernel for an integer type, and a boolean is
// an integer type to it. The feeds are eight ascending and eight descending bytes, which every one of
// those types can hold, so nothing in the answer is the feed's own fault.
static void nan_propagation_refusal_case(const char *label, const char *typeName, MPSDataType type,
                                         const void *left, const void *right)
{
    for (int isMaximum = 0; isMaximum < 2; isMaximum++) {
        char name[96];
        snprintf(name, sizeof name, "%sWithNaNPropagation-%s", isMaximum ? "maximum" : "minimum", typeName);
        @try {
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:@[@2, @4] dataType:type name:@"a"];
            MPSGraphTensor *b = [one placeholderWithShape:@[@2, @4] dataType:type name:@"b"];
            MPSGraphTensor *t = isMaximum
                ? [one maximumWithNaNPropagationWithPrimaryTensor:a secondaryTensor:b name:@"M"]
                : [one minimumWithNaNPropagationWithPrimaryTensor:a secondaryTensor:b name:@"m"];
            size_t bytes = 8 * MPSSizeofMPSDataType(type);
            id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
            MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:@[@2, @4]
                                                                                  dataType:type];
            remember(buffer, integerResult, sizeof(integerResult));
            MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:@[@2, @4] dataType:type];
            MPSGraphExecutable *executable = [one compileWithDevice:gGraphDevice feeds:@{a: shaped, b: shaped}
                                                      targetTensors:@[t] targetOperations:@[] compilationDescriptor:nil];
            [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                                  inputsArray:@[feed(left, @[@2, @4], type), feed(right, @[@2, @4], type)]
                                   resultsArray:@[destination] executionDescriptor:nil];
            printf("#case %s %s answered-rather-than-raised\n", name, label);
        } @catch (NSException *raised) {
            // One field for the answer and no spaces in it: run.sh reads a case line of five fields as a
            // case with a result buffer and this one has none, so the answer is printed as the third field
            // and the whole line is compared as it stands.
            printf("#case %s %s raised-%s\n", name, label, raised.name.UTF8String);
        }
    }
}

// The four reductions and the two binary extremes that arrived after 14.0, asked over the feeds of the
// reduction family above.
//
// The case name of an argument reduction carries the type its ANSWER is stored in and where that type
// came from, because the result is not the operand's type: measured, an argument reduction answers
// MPSDataTypeInt32 whatever the operand was, so "int32-from-float32" is four bytes an element in the
// result buffer and eight hex characters, which is what run.sh reads it at. A truth fold is the other
// way round - it answers the operand's own type, measured - so it is named for that type as the rest of
// this file is.
static void reduction_rest_families(void)
{
    NSArray<NSNumber *> *shape2x4 = @[@2, @4];
    // The two argument reductions, over the sixteen classes first: a row holding a NaN of each sign, both
    // infinities and both zeros, and over the ordinary row and the tied row beside it.
    reduction_case("argMaximum int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMaximumWithTensor:a axis:1 name:@"am"]; }, MPSDataTypeFloat32, leftValues, shape2x4);
    reduction_case("argMinimum int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMinimumWithTensor:a axis:1 name:@"an"]; }, MPSDataTypeFloat32, leftValues, shape2x4);
    reduction_case("argMaximum-rowFeed int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMaximumWithTensor:a axis:1 name:@"am"]; }, MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("argMinimum-rowFeed int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMinimumWithTensor:a axis:1 name:@"an"]; }, MPSDataTypeFloat32, rowFeed, shape2x4);
    // The tied row: every element of it is the answer twice, so this is the case that says whether the
    // release answers the first of the equal elements or the last.
    reduction_case("argMaximum-ties int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMaximumWithTensor:a axis:1 name:@"am"]; }, MPSDataTypeFloat32, tieFeed, shape2x4);
    reduction_case("argMinimum-ties int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMinimumWithTensor:a axis:1 name:@"an"]; }, MPSDataTypeFloat32, tieFeed, shape2x4);
    // A reduced set of nothing but NaNs, which is the one answer of the two that is not an index at all.
    reduction_case("argMaximum-allNaN int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMaximumWithTensor:a axis:1 name:@"am"]; }, MPSDataTypeFloat32, nanFeed, shape2x4);
    reduction_case("argMinimum-allNaN int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMinimumWithTensor:a axis:1 name:@"an"]; }, MPSDataTypeFloat32, nanFeed, shape2x4);
    // The other two data types, because an index is an index over an integer operand too: measured, an
    // argument reduction over an int32 and over a float16 answers the same int32 indices.
    reduction_case("argMaximum int32-from-int32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMaximumWithTensor:a axis:1 name:@"am"]; }, MPSDataTypeInt32, intFeed, shape2x4);
    reduction_case("argMinimum int32-from-int32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMinimumWithTensor:a axis:1 name:@"an"]; }, MPSDataTypeInt32, intFeed, shape2x4);
    reduction_case("argMaximum int32-from-float16", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMaximumWithTensor:a axis:1 name:@"am"]; }, MPSDataTypeFloat16, halfFeed, shape2x4);
    reduction_case("argMinimum int32-from-float16", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMinimumWithTensor:a axis:1 name:@"an"]; }, MPSDataTypeFloat16, halfFeed, shape2x4);
    // The two axis questions, which are the family's own and are measured over the ordinary row: an axis
    // of the other kind of the operand's, and a negative one counted from the end. Both answer a 1x4 of
    // four indices here, which is a different length from the 2x1 of two the axis-1 cases carry.
    reduction_case("argMaximum-axis0 int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMaximumWithTensor:a axis:0 name:@"am"]; }, MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("argMinimum-axis0 int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMinimumWithTensor:a axis:0 name:@"an"]; }, MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("argMaximum-axisNeg1 int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMaximumWithTensor:a axis:-1 name:@"am"]; }, MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("argMinimum-axisNeg1 int32-from-float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionArgMinimumWithTensor:a axis:-1 name:@"an"]; }, MPSDataTypeFloat32, rowFeed, shape2x4);

    // The two truth folds over the same feeds. An "and" of a row holding a zero answers 0 and an "or" of
    // it answers 1, and the sixteen classes hold a zero of each sign in the first row and none in the
    // second, so the two rows of the answer differ.
    unsigned i;
    struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *); } truth[] = {
        {"reductionAnd", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionAndWithTensor:a axis:1 name:@"a"]; }},
        {"reductionOr", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) { return [g reductionOrWithTensor:a axis:1 name:@"o"]; }},
    };
    char name[64];
    for (i = 0; i < sizeof(truth) / sizeof(truth[0]); i++) {
        snprintf(name, sizeof name, "%s float32", truth[i].name);
        reduction_case(name, truth[i].build, MPSDataTypeFloat32, leftValues, shape2x4);
        snprintf(name, sizeof name, "%s int32", truth[i].name);
        reduction_case(name, truth[i].build, MPSDataTypeInt32, intFeed, shape2x4);
        snprintf(name, sizeof name, "%s float16", truth[i].name);
        reduction_case(name, truth[i].build, MPSDataTypeFloat16, halfFeed, shape2x4);
    }
    // A reduced set of nothing but NaNs, where the two of them differ: a NaN is a nonzero like any other
    // value, so an "and" of one is true and an "or" of one is true too.
    reduction_case("reductionAnd-allNaN float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionAndWithTensor:a axis:1 name:@"a"]; }, MPSDataTypeFloat32, nanFeed, shape2x4);
    reduction_case("reductionOr-allNaN float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionOrWithTensor:a axis:1 name:@"o"]; }, MPSDataTypeFloat32, nanFeed, shape2x4);
    // The axes of the family over the two truth folds, which is what the second form of each of them
    // takes: nil reduces every axis and answers a 1x1, an empty array reduces none and answers the
    // operand byte for byte, and a descending set is still a set.
    reduction_case("reductionAnd-axesNil float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionAndWithTensor:a axes:nil name:@"an"]; }, MPSDataTypeFloat32, leftValues, shape2x4);
    reduction_case("reductionOr-axesNil float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionOrWithTensor:a axes:nil name:@"on"]; }, MPSDataTypeFloat32, leftValues, shape2x4);
    reduction_case("reductionAnd-axesEmpty float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionAndWithTensor:a axes:@[] name:@"ae"]; }, MPSDataTypeFloat32, leftValues, shape2x4);
    reduction_case("reductionOr-axesEmpty float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionOrWithTensor:a axes:@[] name:@"oe"]; }, MPSDataTypeFloat32, leftValues, shape2x4);
    reduction_case("reductionAnd-axesDescending float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionAndWithTensor:a axes:@[@1, @0] name:@"ad"]; }, MPSDataTypeFloat32, rowFeed, shape2x4);
    reduction_case("reductionOr-axesDescending float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
        return [g reductionOrWithTensor:a axes:@[@1, @0] name:@"od"]; }, MPSDataTypeFloat32, rowFeed, shape2x4);

    // The two binary extremes that propagate a NaN, over the same feeds the arithmetic family is asked
    // over and in both types it is asked in. These are the two cases where the 14.0 pair and this pair
    // differ, and they differ only where an operand is a NaN: over the sixteen classes the four NaN
    // positions of the propagating pair answer a NaN each, where the 14.0 pair answers the other side.
    binary_case("minimumWithNaNPropagation float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) {
        return [g minimumWithNaNPropagationWithPrimaryTensor:a secondaryTensor:b name:@"m"]; },
               MPSDataTypeFloat32, leftValues, rightValues);
    binary_case("maximumWithNaNPropagation float32", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) {
        return [g maximumWithNaNPropagationWithPrimaryTensor:a secondaryTensor:b name:@"M"]; },
               MPSDataTypeFloat32, leftValues, rightValues);
    binary_case("minimumWithNaNPropagation float16", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) {
        return [g minimumWithNaNPropagationWithPrimaryTensor:a secondaryTensor:b name:@"m"]; },
               MPSDataTypeFloat16, halfValues, halfRightValues);
    binary_case("maximumWithNaNPropagation float16", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) {
        return [g maximumWithNaNPropagationWithPrimaryTensor:a secondaryTensor:b name:@"M"]; },
               MPSDataTypeFloat16, halfValues, halfRightValues);
    // And the one operand the release does not answer at all: measured, an int32 operand raises out of the
    // framework's own kernel table, which has no NaN kernel for an integer type to ask with. Asked
    // through @try on both sides and printed as the exception's name, which is a differential like any
    // other answer: the 14.0 pair over the same feed answers numbers, and this one does not.
    for (i = 0; i < sizeof(refused) / sizeof(refused[0]); i++)
        nan_propagation_refusal_case("over", refused[i].name, refused[i].type, refusedBytes, reversedBytes);
}

static void families(MPSDataType type, const void *left, const void *right, const char *label)
{
    unsigned i;
    char name[64];
    for (i = 0; i < sizeof(unary) / sizeof(unary[0]); i++) {
        snprintf(name, sizeof name, "%s %s", unary[i].name, label);
        unary_case(name, unary[i].build, type, left);
    }
    for (i = 0; i < sizeof(transcendental) / sizeof(transcendental[0]); i++) {
        snprintf(name, sizeof name, "%s %s", transcendental[i].name, label);
        unary_case(name, transcendental[i].build, type, left);
    }
    for (i = 0; i < sizeof(binary) / sizeof(binary[0]); i++) {
        snprintf(name, sizeof name, "%s %s", binary[i].name, label);
        binary_case(name, binary[i].build, type, left, right);
    }
    // The predicates carry their own data type in the case name, because their result is not the
    // operand's: "equal bool-from-float32" is a boolean over the float32 classes above.
    for (i = 0; i < sizeof(unaryPredicate) / sizeof(unaryPredicate[0]); i++) {
        snprintf(name, sizeof name, "%s bool-from-%s", unaryPredicate[i].name, label);
        predicate_case(name, unaryPredicate[i].build, type, left);
    }
    for (i = 0; i < sizeof(binaryPredicate) / sizeof(binaryPredicate[0]); i++) {
        snprintf(name, sizeof name, "%s bool-from-%s", binaryPredicate[i].name, label);
        binary_predicate_case(name, binaryPredicate[i].build, type, left, right);
    }
    // The select and the clamp read a third operand, and the bounds of a clamp are a third tensor of the
    // operand's own shape here: a clamp over the classes above with the bounds at -0.5 and 0.5 answers
    // something for every class, and a select over the left operand as the predicate answers the right
    // operand where the class is true and the third where it is false.
    snprintf(name, sizeof name, "select %s", label);
    ternary_case(name, ternary[0].build, type, left, right, right);
    snprintf(name, sizeof name, "clamp %s", label);
    ternary_case(name, ternary[1].build, type, left, bounds, bounds);
    // The two gradients read the incoming gradient and the value that was activated, in that order, so
    // the class vectors are given as both operands: a ReLU's branch is decided by the source and a
    // sigmoid's by the source's own value, and every class of the second vector decides one of them.
    for (i = 0; i < sizeof(gradient) / sizeof(gradient[0]); i++) {
        snprintf(name, sizeof name, "%s %s", gradient[i].name, label);
        binary_case(name, gradient[i].build, type, left, right);
    }
}

// The three cases that are not a family of operations, each asked last by the family that holds it.
//
// THE CHAIN is three operations in the order they were added - an addition, its product with itself and
// a square root of the result - so it is the walk over the operations in order that every family runs its
// last case through. It is asked last on purpose: a family whose last case on either side is not the chain
// is a family whose process did not reach the end, and run.sh fails it. "misc" is the one family that
// cannot end with it, because the case below is asked after it.
//
// THE CONSTANT is -[MPSGraph constantWithShape:dataType:values:name:], which aborts the host of this
// machine, so it is asked after everything the host does answer - in one family of its own end, not in the
// middle of the unary family, where it was taking seven cases down with it.
static void chain_case(void)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@8, @4] dataType:MPSDataTypeFloat32 name:@"a"];
    MPSGraphTensor *b = [one placeholderWithShape:@[@8, @4] dataType:MPSDataTypeFloat32 name:@"b"];
    MPSGraphTensor *sum = [one additionWithPrimaryTensor:a secondaryTensor:b name:@"sum"];
    MPSGraphTensor *doubled = [one multiplicationWithPrimaryTensor:sum secondaryTensor:sum name:@"doubled"];
    MPSGraphTensor *root = [one squareRootWithTensor:doubled name:@"root"];
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a, b], @[feed(&leftValues[0], @[@8, @4], MPSDataTypeFloat32), feed(&rightValues[0], @[@8, @4], MPSDataTypeFloat32)], root, resultBytes, 32 * MPSSizeofMPSDataType(MPSDataTypeFloat32), MPSDataTypeFloat32, MPSDataTypeFloat32);
    put("chain", resultBytes, 16 * MPSSizeofMPSDataType(MPSDataTypeFloat32));
}

static void constant_case(void)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@8, @4] dataType:MPSDataTypeFloat32 name:@"a"];
    MPSGraphTensor *c = [one constantWithShape:@[@8, @4] dataType:MPSDataTypeFloat32
                                     values:[NSData dataWithBytes:&constantValues[0] length:sizeof(constantValues)] name:@"c"];
    MPSGraphTensor *t = [one additionWithPrimaryTensor:a secondaryTensor:c name:@"withConstant"];
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a], @[feed(&leftValues[0], @[@8, @4], MPSDataTypeFloat32)], t, resultBytes, 32 * MPSSizeofMPSDataType(MPSDataTypeFloat32), MPSDataTypeFloat32, MPSDataTypeFloat32);
    put("constant", resultBytes, 16 * MPSSizeofMPSDataType(MPSDataTypeFloat32));
}

// An integer division, which is the only case in this file whose feed is not a class vector: four
// integers over four divisors, so the truncated quotients and the zero divisor are both in it.
static void integer_divide_case(void)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@2, @2] dataType:MPSDataTypeInt32 name:@"a"];
    MPSGraphTensor *b = [one placeholderWithShape:@[@2, @2] dataType:MPSDataTypeInt32 name:@"b"];
    MPSGraphTensor *t = [one divisionWithPrimaryTensor:a secondaryTensor:b name:@"idiv"];
    memset(integerResult, 0, sizeof(integerResult));
    run(one, @[a, b], @[feed(&integerValues[0], @[@2, @2], MPSDataTypeInt32),
                        feed(&integerDivisors[0], @[@2, @2], MPSDataTypeInt32)], t, &integerResult[0], sizeof(integerResult), MPSDataTypeInt32, MPSDataTypeInt32);
    put("integer-divide", &integerResult[0], sizeof(integerResult));
}

// The builder side, as far as the release answers it on this host, and it is compared like every other
// answer here: two lines of no result buffer, each of them the whole of what the release answers.
// Reading a shaped type's equality and a placeholder's data type both make the framework call a selector
// its own MPSGraphTensor does not declare -[MPSGraphTensor tensorDataType] - and take the process down,
// so the device's type, the shape and the data type are what is compared, and the rest of the builder
// side is checked in a program of its own.
static void builder_side(void)
{
    printf("#case graph-device %d\n", (int)gGraphDevice.type);
    MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:@[@8, @4] dataType:MPSDataTypeFloat32];
    printf("#case shaped-dataType %d\n", (int)shaped.dataType);
}

// THE FAMILIES, each of which is a process of its own.
//
// One family per process because the release makes it necessary, and the measurement is in
// facts/MetalPerformanceShadersGraph/Core.md: in a process that holds three hundred graphs the release's
// own gather operations start asserting partway through the family - "Error: NDArray dimension length >
// INT_MAX" (MPSNDArray.mm:831) over a flatten of a 2x4 that answers in a program of its own - and every
// FED gather parameter takes the process down whatever else it holds. So this file is asked for one family
// at a time, run.sh runs and judges each of them separately, and the comparison of the recorded cells is
// scoped to the cases the family actually ran: a cell another family recorded is not in these two runs and
// is not a divergence that has gone away.
//
// Every family ends with the chain, so a family's two runs both reaching it is what says the process ran
// to the end of the family rather than dying at a case whose lines happened to be there.
static void family_misc(void)
{
    chain_case();
    constant_case();
}

static void family_arithmetic(void)
{
    // The unary family and the arithmetic family, over the sixteen classes above, in float32 and then in
    // float16. Both are asked for every operation of the family, because the two types do not answer alike
    // and a case in one of them says nothing about the other.
    families(MPSDataTypeFloat32, &leftValues[0], &rightValues[0], "float32");
    families(MPSDataTypeFloat16, &halfValues[0], &halfRightValues[0], "float16");
    integer_divide_case();
    chain_case();
}

// The reduction family of 14.0, which is the first thing in this file whose result is not the operand's
// shape, so it is asked of its own feeds and of the sixteen classes above.
static void family_reduction(void)
{
    reduction_families();
    chain_case();
}

// The rest of the reduction family: the two argument reductions and the two binary NaN-propagating
// extremes of 15.0, the two truth folds of 15.3 and the set of data types the propagating pair refuses.
static void family_reduction_rest(void)
{
    reduction_rest_families();
    chain_case();
}

// The cumulative family of 16.0, whose result is the operand's own shape, in float32 and float16 - and the
// seeds and the NaN rule are asked of the sixteen classes and a row of NaNs inside it.
static void family_cumulative(void)
{
    cumulative_families(MPSDataTypeFloat32, &leftValues[0], "float32");
    cumulative_families(MPSDataTypeFloat16, &halfValues[0], "float16");
    chain_case();
}

typedef struct { const char *name; void (*cases)(void); } Family;

// The table run.sh walks, and the one place a family is named: it prints the list on an unknown argument
// so a family that is renamed here is renamed there or nowhere.
static const Family kFamilies[] = {
    { "misc", family_misc },
    { "arithmetic", family_arithmetic },
    { "reduction", family_reduction },
    { "reduction_rest", family_reduction_rest },
    { "cumulative", family_cumulative },
    { "gather_transpose", family_gather_transpose },
    { "gather_flatten", family_gather_flatten },
    { "gather_broadcast", family_gather_broadcast },
    { "gather_reverse", family_gather_reverse },
    { "gather_squeeze", family_gather_squeeze },
    { "gather_expand", family_gather_expand },
};

static void family_names(void)
{
    unsigned i;
    for (i = 0; i < sizeof(kFamilies) / sizeof(kFamilies[0]); i++)
        fprintf(stderr, "%s ", kFamilies[i].name);
    fprintf(stderr, "\n");
}

int main(int argc, const char *argv[])
{
    // Line buffering, and it is what makes the comparison trustworthy: the framework this file runs
    // against writes its own diagnostics to this same standard output, and with a block-buffered stream
    // one of them landed in the middle of a case line - a flush boundary split a line of sixteen halves
    // and "subtract float16" ended up carrying the tail of a warning and sixteen characters less. A line
    // buffered stream hands the whole line to one write, so a case is one line or nothing.
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        unsigned i;
        gDevice = MTLCreateSystemDefaultDevice();
        gGraphDevice = [MPSGraphDevice deviceWithMTLDevice:gDevice];
        builder_side();
        if (argc < 2) {
            fprintf(stderr, "graph-cases.m: name the family to run; these are: ");
            family_names();
            return 2;
        }
        for (i = 0; i < sizeof(kFamilies) / sizeof(kFamilies[0]); i++) {
            if (strcmp(argv[1], kFamilies[i].name) != 0) continue;
            kFamilies[i].cases();
            return 0;
        }
        fprintf(stderr, "graph-cases.m: unknown family '%s'; these are: ", argv[1]);
        family_names();
        return 2;
    }
}
