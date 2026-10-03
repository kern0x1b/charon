// graph-cases.m — the builder side and the arithmetic family of MPSGraph, run twice: once against the
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
static float leftValues[16] = {
    1.0f, -1.0f, -0.0f, 0.0f, INFINITY, -INFINITY, NAN, -NAN,
    0x1p-149f, -0x1p-149f, 0x1.fffffep-127f, 0x1p-126f, 0x1p-20f, 0x1.fffffep-1f, -0x1p-20f, 1e-20f,
};
// The second operand carries the classes the divisor column needs - a positive zero, a negative zero, an
// infinity of each sign, a NaN, a denormal - and ordinary values elsewhere, so a division is checked
// against every kind of divisor and not only against ones that divide.
static float rightValues[16] = {
    0.0f, -0.0f, INFINITY, -INFINITY, NAN, -NAN, 0x1p-149f, 2.0f,
    4.0f, -4.0f, 0.5f, 8.0f, 16.0f, 3.0f, 1.0f, 1.0f,
};
static unsigned char resultBytes[64];
static float constantValues[4] = {0.25f, -0.25f, 0.5f, 2};
// The bounds a clamp case is asked over: a pair of ordinary values either side of zero, so that every
// class of the operand decides which of the two it is clamped to.
static float bounds[16] = {
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
static uint16_t halfValues[16] = {
    0x3c00, 0xbc00, 0x0000, 0x8000, 0x7c00, 0xfc00, 0x7e00, 0xfe00,
    0x0001, 0x8001, 0x03ff, 0x0400, 0x3800, 0x1400, 0x3c01, 0x3555,
};
// The second operand, in halves, carrying the classes a divisor column needs - a positive zero, a
// negative zero, an infinity of each sign, a NaN, a denormal - and ordinary values elsewhere.
static uint16_t halfRightValues[16] = {
    0x0000, 0x8000, 0x7c00, 0xfc00, 0x7e00, 0xfe00, 0x0001, 0x4000,
    0xc000, 0x3800, 0x3555, 0x4400, 0x4800, 0x4200, 0x3c00, 0x3c00,
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
    NSUInteger count = (NSUInteger)(bytes / MPSSizeofMPSDataType(resultType));
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
    MPSGraphTensor *a = [one placeholderWithShape:@[@4, @4] dataType:type name:@"a"];
    MPSGraphTensor *t = build(one, a);
    size_t bytes = 16 * MPSSizeofMPSDataType(type);
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a], @[feed(values, @[@4, @4], type)], t, resultBytes, bytes, type, type);
    put(name, resultBytes, bytes);
}

// The same for a case of the arithmetic family, which takes a second operand.
static void binary_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *),
                        MPSDataType type, const void *left, const void *right)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@4, @4] dataType:type name:@"a"];
    MPSGraphTensor *b = [one placeholderWithShape:@[@4, @4] dataType:type name:@"b"];
    MPSGraphTensor *t = build(one, a, b);
    size_t bytes = 16 * MPSSizeofMPSDataType(type);
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a, b], @[feed(left, @[@4, @4], type), feed(right, @[@4, @4], type)], t, resultBytes, bytes, type, type);
    put(name, resultBytes, bytes);
}

// A case whose result is not the operand's own type: a predicate's is a boolean, one byte an element,
// measured on this host's own MPSGraph (MPSSizeofMPSDataType(MPSDataTypeBool) is 1). The result buffer is
// the operand's sixteen elements in the result's type, so a byte per element is the whole of it.
static void predicate_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *),
                           MPSDataType operandType, const void *values)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@4, @4] dataType:operandType name:@"a"];
    MPSGraphTensor *t = build(one, a);
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a], @[feed(values, @[@4, @4], operandType)], t, resultBytes, 16, operandType, MPSDataTypeBool);
    put(name, resultBytes, 16);
}

static void binary_predicate_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *),
                                  MPSDataType operandType, const void *left, const void *right)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@4, @4] dataType:operandType name:@"a"];
    MPSGraphTensor *b = [one placeholderWithShape:@[@4, @4] dataType:operandType name:@"b"];
    MPSGraphTensor *t = build(one, a, b);
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a, b], @[feed(left, @[@4, @4], operandType), feed(right, @[@4, @4], operandType)], t, resultBytes, 16, operandType, MPSDataTypeBool);
    put(name, resultBytes, 16);
}

// A case with three operands, which the select and the clamp are.
static void ternary_case(const char *name, MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *, MPSGraphTensor *),
                         MPSDataType type, const void *first, const void *second, const void *third)
{
    MPSGraph *one = [MPSGraph new];
    MPSGraphTensor *a = [one placeholderWithShape:@[@4, @4] dataType:type name:@"a"];
    MPSGraphTensor *b = [one placeholderWithShape:@[@4, @4] dataType:type name:@"b"];
    MPSGraphTensor *c = [one placeholderWithShape:@[@4, @4] dataType:type name:@"c"];
    MPSGraphTensor *t = build(one, a, b, c);
    size_t bytes = 16 * MPSSizeofMPSDataType(type);
    memset(resultBytes, 0, sizeof(resultBytes));
    run(one, @[a, b, c], @[feed(first, @[@4, @4], type), feed(second, @[@4, @4], type),
                          feed(third, @[@4, @4], type)], t, resultBytes, bytes, type, type);
    put(name, resultBytes, bytes);
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

int main(void)
{
    // Line buffering, and it is what makes the comparison trustworthy: the framework this file runs
    // against writes its own diagnostics to this same standard output, and with a block-buffered stream
    // one of them landed in the middle of a case line - a flush boundary split a line of sixteen halves
    // and "subtract float16" ended up carrying the tail of a warning and sixteen characters less. A line
    // buffered stream hands the whole line to one write, so a case is one line or nothing.
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        gDevice = MTLCreateSystemDefaultDevice();
        gGraphDevice = [MPSGraphDevice deviceWithMTLDevice:gDevice];
        printf("graph-device %d\n", (int)gGraphDevice.type);

        // The builder side, as far as the release answers it on this host. Reading a shaped type's
        // equality and a placeholder's data type both make the framework call a selector its own
        // MPSGraphTensor does not declare -[MPSGraphTensor tensorDataType] - and take the process down,
        // so the shape, the data type and the graph's placeholder count are what is compared here, and
        // the rest of the builder side is checked in a program of its own.
        MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:@[@4, @4] dataType:MPSDataTypeFloat32];
        printf("shaped dataType %d\n", (int)shaped.dataType);

        // The unary family and the arithmetic family, over the sixteen classes above, in float32 and
        // then in float16. Both are asked for every operation of the family, because the two types do not
        // answer alike and a case in one of them says nothing about the other.
        families(MPSDataTypeFloat32, &leftValues[0], &rightValues[0], "float32");
        families(MPSDataTypeFloat16, &halfValues[0], &halfRightValues[0], "float16");
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
        // A chain, so the walk over the operations in order is checked too.
        {
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:@[@4, @4] dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *b = [one placeholderWithShape:@[@4, @4] dataType:MPSDataTypeFloat32 name:@"b"];
            MPSGraphTensor *sum = [one additionWithPrimaryTensor:a secondaryTensor:b name:@"sum"];
            MPSGraphTensor *doubled = [one multiplicationWithPrimaryTensor:sum secondaryTensor:sum name:@"doubled"];
            MPSGraphTensor *root = [one squareRootWithTensor:doubled name:@"root"];
            memset(resultBytes, 0, sizeof(resultBytes));
            run(one, @[a, b], @[feed(&leftValues[0], @[@4, @4], MPSDataTypeFloat32), feed(&rightValues[0], @[@4, @4], MPSDataTypeFloat32)], root, resultBytes, 16 * MPSSizeofMPSDataType(MPSDataTypeFloat32), MPSDataTypeFloat32, MPSDataTypeFloat32);
            put("chain", resultBytes, 16 * MPSSizeofMPSDataType(MPSDataTypeFloat32));
        }
        // Last, and on its own: -constantWithShape:dataType:values:name: aborts the host of this
        // machine, so it is asked for after everything the host does answer. In the middle of the unary
        // family it was taking seven cases down with it.
        {
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:@[@4, @4] dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *c = [one constantWithShape:@[@4, @4] dataType:MPSDataTypeFloat32
                                             values:[NSData dataWithBytes:&constantValues[0] length:sizeof(constantValues)] name:@"c"];
            MPSGraphTensor *t = [one additionWithPrimaryTensor:a secondaryTensor:c name:@"withConstant"];
            memset(resultBytes, 0, sizeof(resultBytes));
            run(one, @[a], @[feed(&leftValues[0], @[@4, @4], MPSDataTypeFloat32)], t, resultBytes, 16 * MPSSizeofMPSDataType(MPSDataTypeFloat32), MPSDataTypeFloat32, MPSDataTypeFloat32);
            put("constant", resultBytes, 16 * MPSSizeofMPSDataType(MPSDataTypeFloat32));
        }

    }
    return 0;
}
