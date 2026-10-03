// refusals.m - the gather family's questions that graph-cases.m cannot ask, one per process, run against the
// system's own MPSGraph only.
//
// Each question is asked in a process of its own because several of them take the release down, and what is
// being measured is exactly that: there is no answer of the release for a case to compare against, so the
// port's answer is its header's and the question belongs in the row of the method rather than among the
// cases. run.sh asks each of them, records the exit status and what was written to the error stream, and
// compares both against refusals.txt - so the measurement behind those rows is one a later reader re-runs
// rather than a line in a commit message, and a release that starts answering one of them fails this.
//
//   refusals.m <question>
//
// facts/MetalPerformanceShadersGraph/Core.md carries what each of them answers and which row it is in.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShadersGraph/MetalPerformanceShadersGraph.h>

@interface MPSGraph (MPSGraph26)
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

static void put(const char *name, id<MTLBuffer> buffer, size_t bytes)
{
    printf("%s %zu ", name, bytes);
    const unsigned char *p = (const unsigned char *)[buffer contents];
    for (size_t i = 0; i < bytes; i++) printf("%02x", p[i]);
    printf("\n");
}

// The destination's own bytes before the run are a question of their own, so the buffer is filled with one
// pattern before every case here: an element the release does not write keeps it, an element it writes
// zeroes or does not can be told apart from it.
static unsigned char gPattern = 0xbd;

static MPSGraphTensorData *feed(const void *values, NSArray<NSNumber *> *shape, MPSDataType type)
{
    NSUInteger count = 1;
    for (NSNumber *dimension in shape) count *= (NSUInteger)dimension.integerValue;
    size_t bytes = count * MPSSizeofMPSDataType(type);
    id<MTLBuffer> buffer = [gDevice newBufferWithBytes:values length:bytes options:MTLResourceStorageModeShared];
    return [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:shape dataType:type];
}

// The feed's shape is the OPERAND's and not the result's, which is the one thing this harness has to get
// right for a gather: the compile is told what the caller is handing it, and the result's shape is its own.
static void run(MPSGraph *graph, NSArray<MPSGraphTensor *> *feeds, NSArray<MPSGraphTensorData *> *values,
                MPSGraphTensor *target, MPSGraphTensorData *destination, NSArray<NSNumber *> *operandShape)
{
    MPSGraphShapedType *shaped = [[MPSGraphShapedType alloc] initWithShape:operandShape dataType:MPSDataTypeFloat32];
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    for (MPSGraphTensor *tensor in feeds) all[tensor] = shaped;
    MPSGraphExecutable *executable = [graph compileWithDevice:gGraphDevice feeds:all
                                              targetTensors:@[target] targetOperations:@[] compilationDescriptor:nil];
    [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                          inputsArray:values resultsArray:@[destination] executionDescriptor:nil];
}

static void one(MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *), NSArray<NSNumber *> *shape,
                const void *values, const char *name)
{
    MPSGraph *one_ = [MPSGraph new];
    MPSGraphTensor *a = [one_ placeholderWithShape:shape dataType:MPSDataTypeFloat32 name:@"a"];
    MPSGraphTensor *t = build(one_, a);
    if (t == nil) { printf("%s nil-tensor\n", name); return; }
    printf("%s-shape %s\n", name, [[t.shape componentsJoinedByString:@"x"] UTF8String]);
    NSUInteger count = 1;
    for (NSNumber *dimension in t.shape) count *= (NSUInteger)dimension.integerValue;
    size_t bytes = count * MPSSizeofMPSDataType(MPSDataTypeFloat32);
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    memset([buffer contents], gPattern, bytes);
    MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:t.shape
                                                                             dataType:MPSDataTypeFloat32];
    run(one_, @[a], @[feed(values, shape, MPSDataTypeFloat32)], t, destination, shape);
    put(name, buffer, bytes);
}

// A parameter fed at run time: the axis, the axes or the shape arrives as the operation's second input, and
// its own value is fed beside the operand's.
static void fed(MPSGraphTensor *(^build)(MPSGraph *, MPSGraphTensor *, MPSGraphTensor *),
               NSArray<NSNumber *> *shape, const void *values, int32_t fed0, MPSDataType fedType,
               NSArray<NSNumber *> *fedShape, const char *name)
{
    MPSGraph *one_ = [MPSGraph new];
    MPSGraphTensor *a = [one_ placeholderWithShape:shape dataType:MPSDataTypeFloat32 name:@"a"];
    MPSGraphTensor *p = [one_ placeholderWithShape:fedShape dataType:fedType name:@"p"];
    MPSGraphTensor *t = build(one_, a, p);
    NSUInteger count = 1;
    for (NSNumber *dimension in t.shape) count *= (NSUInteger)dimension.integerValue;
    size_t bytes = count * MPSSizeofMPSDataType(MPSDataTypeFloat32);
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    memset([buffer contents], gPattern, bytes);
    MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:t.shape
                                                                             dataType:MPSDataTypeFloat32];
    NSMutableDictionary *shaped = [NSMutableDictionary dictionary];
    shaped[a] = [[MPSGraphShapedType alloc] initWithShape:shape dataType:MPSDataTypeFloat32];
    shaped[p] = [[MPSGraphShapedType alloc] initWithShape:fedShape dataType:fedType];
    MPSGraphExecutable *executable = [one_ compileWithDevice:gGraphDevice feeds:shaped
                                              targetTensors:@[t] targetOperations:@[] compilationDescriptor:nil];
    [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                          inputsArray:@[feed(values, shape, MPSDataTypeFloat32), feed(&fed0, fedShape, fedType)]
                           resultsArray:@[destination] executionDescriptor:nil];
    put(name, buffer, bytes);
}

static float rowFeed[8] = { 1.0f, 2.0f, 3.0f, 4.0f, 10.0f, 20.0f, 30.0f, 40.0f };
static float twoByThreeByFour[24] = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
};

int main(int argc, const char *argv[])
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc < 2) {
        // The list is printed here so that a question added to the file and not to refusals.txt is a question
        // run.sh never asks, and refusals.txt is read against this list for the same reason.
        fprintf(stderr, "name the question; these are: ");
        static const char *const kQuestions[] = {
            "broadcast-wider", "broadcast-added", "broadcast-narrower", "broadcast-zero-extent",
            "fed-flatten-axis", "fed-broadcast-shape", "fed-reverse-axes", "fed-squeeze-axes",
            "fed-expand-axes", "squeeze-not-unit", "flatten-axis-outside", "expand-axis-outside",
            "transpose-axis-outside", "reverse-axis-outside", "reverse-axes-empty", "squeeze-axes-empty",
            "expand-axes-empty", "transpose-same-axis", "transpose-short-permutation",
        };
        unsigned i;
        for (i = 0; i < sizeof(kQuestions) / sizeof(kQuestions[0]); i++)
            fprintf(stderr, "%s ", kQuestions[i]);
        fprintf(stderr, "\n");
        return 2;
    }
    const char *q = argv[1];
    @autoreleasepool {
        gDevice = MTLCreateSystemDefaultDevice();
        gGraphDevice = [MPSGraphDevice deviceWithMTLDevice:gDevice];
        NSArray<NSNumber *> *twoByFour = @[@2, @4];
        NSArray<NSNumber *> *twoByThreeByFourShape = @[@2, @3, @4];

        // The broadcast of an axis the shape makes WIDER than the operand's, over a destination filled with a
        // pattern: what the release writes where it has no element to write is the whole of the question.
        if (strcmp(q, "broadcast-wider") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g broadcastTensor:a toShape:@[@4, @4] name:@"b"]; }, twoByFour, rowFeed, "broadcast-wider");
            return 0;
        }
        if (strcmp(q, "broadcast-added") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g broadcastTensor:a toShape:@[@2, @2, @4] name:@"b"]; }, twoByFour, rowFeed, "broadcast-added");
            return 0;
        }
        // An aligned axis NARROWER than the operand's, which is the other way round and is not a broadcast
        // at all: what the release does with it is what the row has to say.
        if (strcmp(q, "broadcast-narrower") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g broadcastTensor:a toShape:@[@1, @4] name:@"b"]; }, twoByFour, rowFeed, "broadcast-narrower");
            return 0;
        }
        if (strcmp(q, "broadcast-zero-extent") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g broadcastTensor:a toShape:@[@2, @0] name:@"b"]; }, twoByFour, rowFeed, "broadcast-zero");
            return 0;
        }
        // The five FED forms. Each of these is a parameter that arrives at run time rather than written down,
        // and each is asked in a process of its own because the release takes the process down.
        if (strcmp(q, "fed-flatten-axis") == 0) {
            fed(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *p) {
                return [g flatten2DTensor:a axisTensor:p name:@"f"]; }, twoByFour, rowFeed, 1, MPSDataTypeInt32, @[@1], "fed-flatten-axis");
            return 0;
        }
        if (strcmp(q, "fed-broadcast-shape") == 0) {
            fed(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *p) {
                return [g broadcastTensor:a toShapeTensor:p name:@"b"]; }, twoByFour, rowFeed, 4, MPSDataTypeInt32, @[@1], "fed-broadcast-shape");
            return 0;
        }
        if (strcmp(q, "fed-reverse-axes") == 0) {
            fed(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *p) {
                return [g reverseTensor:a axesTensor:p name:@"r"]; }, twoByFour, rowFeed, 0, MPSDataTypeInt32, @[@1], "fed-reverse-axes");
            return 0;
        }
        if (strcmp(q, "fed-squeeze-axes") == 0) {
            fed(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *p) {
                return [g squeezeTensor:a axesTensor:p name:@"s"]; }, @[@1, @2, @4], twoByThreeByFour, 0, MPSDataTypeInt32, @[@1], "fed-squeeze-axes");
            return 0;
        }
        if (strcmp(q, "fed-expand-axes") == 0) {
            fed(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *p) {
                return [g expandDimsOfTensor:a axesTensor:p name:@"e"]; }, twoByFour, rowFeed, 0, MPSDataTypeInt32, @[@1], "fed-expand-axes");
            return 0;
        }
        // The forms the port refuses and what the release does with each of them.
        if (strcmp(q, "squeeze-not-unit") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g squeezeTensor:a axis:1 name:@"s"]; }, twoByFour, rowFeed, "squeeze-not-unit");
            return 0;
        }
        if (strcmp(q, "flatten-axis-outside") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g flatten2DTensor:a axis:5 name:@"f"]; }, twoByFour, rowFeed, "flatten-axis-outside");
            return 0;
        }
        if (strcmp(q, "expand-axis-outside") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g expandDimsOfTensor:a axis:5 name:@"e"]; }, twoByFour, rowFeed, "expand-axis-outside");
            return 0;
        }
        if (strcmp(q, "transpose-axis-outside") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g transposeTensor:a dimension:0 withDimension:5 name:@"t"]; }, twoByFour, rowFeed, "transpose-axis-outside");
            return 0;
        }
        if (strcmp(q, "reverse-axis-outside") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g reverseTensor:a axes:@[@5] name:@"r"]; }, twoByFour, rowFeed, "reverse-axis-outside");
            return 0;
        }
        // An empty array of axes where the family takes one, and a nil, for the two families that take one.
        if (strcmp(q, "reverse-axes-empty") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g reverseTensor:a axes:@[] name:@"r"]; }, twoByFour, rowFeed, "reverse-axes-empty");
            return 0;
        }
        if (strcmp(q, "squeeze-axes-empty") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g squeezeTensor:a axes:@[] name:@"s"]; }, @[@1, @2, @4], twoByThreeByFour, "squeeze-axes-empty");
            return 0;
        }
        if (strcmp(q, "expand-axes-empty") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g expandDimsOfTensor:a axes:@[] name:@"e"]; }, twoByFour, rowFeed, "expand-axes-empty");
            return 0;
        }
        // A transpose naming the same axis twice, and a permutation that is not one - both are shapes the
        // result's own rank does not decide, so what the release answers is the row's to carry.
        if (strcmp(q, "transpose-same-axis") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g transposeTensor:a dimension:0 withDimension:0 name:@"t"]; }, twoByThreeByFourShape, twoByThreeByFour, "transpose-same-axis");
            return 0;
        }
        if (strcmp(q, "transpose-short-permutation") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g transposeTensor:a permutation:@[@1] name:@"t"]; }, twoByThreeByFourShape, twoByThreeByFour, "transpose-short-permutation");
            return 0;
        }
        fprintf(stderr, "unknown question '%s'\n", q);
        return 2;
    }
}
