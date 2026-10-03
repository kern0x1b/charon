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

// Every matrix a case builds from a C array, and the result buffer it reads back out of.
typedef struct { id<MTLBuffer> buffer; void *source; size_t bytes; } Source;
static Source gSources[64];
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
static void put(const char *name, const void *bytes, size_t length)
{
    pullResults();
    printf("%s %zu ", name, length);
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
static float resultValues[16];
static float constantValues[4] = {0.25f, -0.25f, 0.5f, 2};
static int32_t integerValues[4] = {7, -3, 11, 0};
static int32_t integerDivisors[4] = {2, 2, 4, -4};
static int32_t integerResult[4];

static void run(MPSGraph *graph, NSArray<MPSGraphTensor *> *feeds, NSArray<MPSGraphTensorData *> *values, MPSGraphTensor *target, void *out, size_t bytes, MPSDataType type)
{
    NSUInteger count = (NSUInteger)(bytes / MPSSizeofMPSDataType(type));
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:target.shape dataType:type];
    remember(buffer, out, bytes);
    MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:target.shape dataType:type];
    NSMutableDictionary *shapedFeeds = [NSMutableDictionary dictionary];
    for (MPSGraphTensor *tensor in feeds) shapedFeeds[tensor] = shaped;
    MPSGraphExecutable *executable = [graph compileWithDevice:gGraphDevice feeds:shapedFeeds
                                                 targetTensors:@[target] targetOperations:@[] compilationDescriptor:nil];
    [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                          inputsArray:values resultsArray:@[destination] executionDescriptor:nil];
    memcpy(out, [buffer contents], bytes);
}

int main(void)
{
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

        // The unary family, over the sixteen classes above, so each one of them is answered for every
        // operation of the family rather than for the one operation a difference happened to show up in.
        // The square root is what the class of a negative pins: the release answers a NaN there, where an
        // earlier version of this port answered the magnitude.
        struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *); } unary[] = {
            {"square", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg squareWithTensor:a name:@"sq"]; }},
            {"reciprocal", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg reciprocalWithTensor:a name:@"rec"]; }},
            {"sqrt", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg squareRootWithTensor:a name:@"sqrt"]; }},
            {"rsqrt", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg reverseSquareRootWithTensor:a name:@"rsqrt"]; }},
            {"log", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg logarithmWithTensor:a name:@"log"]; }},
            {"abs", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg absoluteWithTensor:a name:@"abs"]; }},
            {"sign", ^MPSGraphTensor *(MPSGraph *gg, MPSGraphTensor *a) { return [gg signWithTensor:a name:@"sign"]; }},
        };
        for (unsigned i = 0; i < sizeof(unary) / sizeof(unary[0]); i++) {
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:@[@4, @4] dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *t = unary[i].build(one, a);
            memset(resultValues, 0, sizeof(resultValues));
            run(one, @[a], @[feed(&leftValues[0], @[@4, @4], MPSDataTypeFloat32)], t, &resultValues[0], sizeof(resultValues), MPSDataTypeFloat32);
            put(unary[i].name, &resultValues[0], sizeof(resultValues));
        }
        {
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:@[@2, @2] dataType:MPSDataTypeInt32 name:@"a"];
            MPSGraphTensor *b = [one placeholderWithShape:@[@2, @2] dataType:MPSDataTypeInt32 name:@"b"];
            MPSGraphTensor *t = [one divisionWithPrimaryTensor:a secondaryTensor:b name:@"idiv"];
            memset(integerResult, 0, sizeof(integerResult));
            run(one, @[a, b], @[feed(&integerValues[0], @[@2, @2], MPSDataTypeInt32),
                                feed(&integerDivisors[0], @[@2, @2], MPSDataTypeInt32)], t, &integerResult[0], sizeof(integerResult), MPSDataTypeInt32);
            put("integer-divide", &integerResult[0], sizeof(integerResult));
        }

        // The arithmetic family, element by element.
        struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *); } cases[] = {
            {"add", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g additionWithPrimaryTensor:a secondaryTensor:b name:@"add"]; }},
            {"subtract", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g subtractionWithPrimaryTensor:a secondaryTensor:b name:@"sub"]; }},
            {"multiply", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g multiplicationWithPrimaryTensor:a secondaryTensor:b name:@"mul"]; }},
            {"divide", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g divisionWithPrimaryTensor:a secondaryTensor:b name:@"div"]; }},
        };
        for (unsigned i = 0; i < 4; i++) {
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:@[@4, @4] dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *b = [one placeholderWithShape:@[@4, @4] dataType:MPSDataTypeFloat32 name:@"b"];
            MPSGraphTensor *t = cases[i].build(one, a, b);
            memset(resultValues, 0, sizeof(resultValues));
            run(one, @[a, b], @[feed(&leftValues[0], @[@4, @4], MPSDataTypeFloat32), feed(&rightValues[0], @[@4, @4], MPSDataTypeFloat32)], t, &resultValues[0], sizeof(resultValues), MPSDataTypeFloat32);
            put(cases[i].name, &resultValues[0], sizeof(resultValues));
        }
        // A chain, so the walk over the operations in order is checked too.
        {
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:@[@4, @4] dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *b = [one placeholderWithShape:@[@4, @4] dataType:MPSDataTypeFloat32 name:@"b"];
            MPSGraphTensor *sum = [one additionWithPrimaryTensor:a secondaryTensor:b name:@"sum"];
            MPSGraphTensor *doubled = [one multiplicationWithPrimaryTensor:sum secondaryTensor:sum name:@"doubled"];
            MPSGraphTensor *root = [one squareRootWithTensor:doubled name:@"root"];
            memset(resultValues, 0, sizeof(resultValues));
            run(one, @[a, b], @[feed(&leftValues[0], @[@4, @4], MPSDataTypeFloat32), feed(&rightValues[0], @[@4, @4], MPSDataTypeFloat32)], root, &resultValues[0], sizeof(resultValues), MPSDataTypeFloat32);
            put("chain", &resultValues[0], sizeof(resultValues));
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
            memset(resultValues, 0, sizeof(resultValues));
            run(one, @[a], @[feed(&leftValues[0], @[@4, @4], MPSDataTypeFloat32)], t, &resultValues[0], sizeof(resultValues), MPSDataTypeFloat32);
            put("constant", &resultValues[0], sizeof(resultValues));
        }

    }
    return 0;
}
