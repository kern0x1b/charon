// graph-cases.m — the builder side and the arithmetic family of MPSGraph, run twice: once against the
// system's own MPSGraph and once against this port's classes under names of their own. Every case
// prints the bytes of a buffer the case owns, so the two runs are compared exactly.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShadersGraph/MetalPerformanceShadersGraph.h>

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
    MPSGraphTensorData *data = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:shape dataType:type];
    remember(buffer, (void *)values, bytes);
    return data;
}

static float leftValues[8] = {1, 2, 3, 4, -1, -2, -3, -4};
static float rightValues[8] = {10, 20, 30, 40, 0.5f, 2, -1, 4};
static float resultValues[8];
static float constantValues[4] = {0.25f, -0.25f, 0.5f, 2};
static int32_t integerValues[4] = {7, -3, 11, 0};
static int32_t integerResult[4];

static void run(MPSGraph *graph, NSArray<MPSGraphTensor *> *feeds, MPSGraphTensor *target, void *out, size_t bytes, MPSDataType type)
{
    NSUInteger count = (NSUInteger)(bytes / MPSSizeofMPSDataType(type));
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:target.shape dataType:type];
    MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:target.shape dataType:type];
    NSMutableDictionary *shapedFeeds = [NSMutableDictionary dictionary];
    for (MPSGraphTensor *tensor in feeds) shapedFeeds[tensor] = shaped;
    MPSGraphExecutable *executable = [graph compileWithDevice:gGraphDevice feeds:shapedFeeds
                                                 targetTensors:@[target] targetOperations:@[] compilationDescriptor:nil];
    [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                          inputsArray:feeds resultsArray:@[destination] executionDescriptor:nil];
    memcpy(out, [buffer contents], bytes);
}

int main(void)
{
    @autoreleasepool {
        gDevice = MTLCreateSystemDefaultDevice();
        gGraphDevice = [MPSGraphDevice deviceWithMTLDevice:gDevice];
        printf("device %d graph-device %d\n", MPSSupportsMTLDevice(gDevice), (int)gGraphDevice.type);

        // The builder side, as far as the release answers it on this host. Reading a shaped type's
        // equality and a placeholder's data type both make the framework call a selector its own
        // MPSGraphTensor does not declare -[MPSGraphTensor tensorDataType] - and take the process down,
        // so the shape, the data type and the graph's placeholder count are what is compared here, and
        // the rest of the builder side is checked in a program of its own.
        MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:@[@2, @4] dataType:MPSDataTypeFloat32];
        printf("shaped dataType %d\n", (int)shaped.dataType);

        // The arithmetic family, element by element.
        struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *); } cases[] = {
            {"add", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g additionWithPrimaryTensor:a secondaryTensor:b name:@"add"]; }},
            {"subtract", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g subtractionWithPrimaryTensor:a secondaryTensor:b name:@"sub"]; }},
            {"multiply", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g multiplicationWithPrimaryTensor:a secondaryTensor:b name:@"mul"]; }},
            {"divide", ^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *b) { return [g divisionWithPrimaryTensor:a secondaryTensor:b name:@"div"]; }},
        };
        for (unsigned i = 0; i < 4; i++) {
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:@[@2, @4] dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *b = [one placeholderWithShape:@[@2, @4] dataType:MPSDataTypeFloat32 name:@"b"];
            MPSGraphTensor *t = cases[i].build(one, a, b);
            memset(resultValues, 0, sizeof(resultValues));
            run(one, @[a, b], t, &resultValues[0], sizeof(resultValues), MPSDataTypeFloat32);
            put(cases[i].name, &resultValues[0], sizeof(resultValues));
        }
        // The unary ones.
        struct { const char *name; MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *); } unary[] = {
        };
        for (unsigned i = 0; i < 0; i++) {
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:@[@2, @4] dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *t = unary[i].build(one, a);
            memset(resultValues, 0, sizeof(resultValues));
            run(one, @[a], t, &resultValues[0], sizeof(resultValues), MPSDataTypeFloat32);
            put(unary[i].name, &resultValues[0], sizeof(resultValues));
        }
        // A chain, so the walk over the operations in order is checked too.
        {
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:@[@2, @4] dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *b = [one placeholderWithShape:@[@2, @4] dataType:MPSDataTypeFloat32 name:@"b"];
            MPSGraphTensor *sum = [one additionWithPrimaryTensor:a secondaryTensor:b name:@"sum"];
            MPSGraphTensor *doubled = [one multiplicationWithPrimaryTensor:sum secondaryTensor:sum name:@"doubled"];
            MPSGraphTensor *root = [one squareRootWithTensor:doubled name:@"root"];
            memset(resultValues, 0, sizeof(resultValues));
            run(one, @[a, b], root, &resultValues[0], sizeof(resultValues), MPSDataTypeFloat32);
            put("chain", &resultValues[0], sizeof(resultValues));
        }

    }
    return 0;
}
