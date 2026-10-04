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
- (MPSGraphTensor *)sliceTensor:(MPSGraphTensor *)tensor dimension:(NSUInteger)dimensionIndex start:(NSInteger)start length:(NSInteger)length name:(NSString *)name;
- (MPSGraphTensor *)sliceTensor:(MPSGraphTensor *)tensor starts:(NSArray<NSNumber *> *)starts ends:(NSArray<NSNumber *> *)ends strides:(NSArray<NSNumber *> *)strides name:(NSString *)name;
- (MPSGraphTensor *)reshapeTensor:(MPSGraphTensor *)tensor withShape:(NSArray<NSNumber *> *)withShape name:(NSString *)name;
- (MPSGraphTensor *)reshapeTensor:(MPSGraphTensor *)tensor withShapeTensor:(MPSGraphTensor *)withShapeTensor name:(NSString *)name;
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
- (MPSGraphTensor *)sliceTensor:(MPSGraphTensor *)tensor starts:(NSArray<NSNumber *> *)starts ends:(NSArray<NSNumber *> *)ends strides:(NSArray<NSNumber *> *)strides startMask:(uint32_t)startMask endMask:(uint32_t)endMask squeezeMask:(uint32_t)squeezeMask name:(NSString *)name;
- (MPSGraphTensor *)sliceTensor:(MPSGraphTensor *)tensor startTensor:(MPSGraphTensor *)startTensor endTensor:(MPSGraphTensor *)endTensor strideTensor:(MPSGraphTensor *)strideTensor startMask:(uint32_t)startMask endMask:(uint32_t)endMask squeezeMask:(uint32_t)squeezeMask name:(NSString *)name;
- (MPSGraphTensor *)sliceTensor:(MPSGraphTensor *)tensor startTensor:(MPSGraphTensor *)startTensor sizeTensor:(MPSGraphTensor *)sizeTensor squeezeMask:(uint32_t)squeezeMask name:(NSString *)name;
- (MPSGraphTensor *)sliceGradientTensor:(MPSGraphTensor *)inputGradientTensor fwdInShapeTensor:(MPSGraphTensor *)fwdInShapeTensor starts:(NSArray<NSNumber *> *)starts ends:(NSArray<NSNumber *> *)ends strides:(NSArray<NSNumber *> *)strides name:(NSString *)name;
- (MPSGraphTensor *)sliceGradientTensor:(MPSGraphTensor *)inputGradientTensor fwdInShapeTensor:(MPSGraphTensor *)fwdInShapeTensor starts:(NSArray<NSNumber *> *)starts ends:(NSArray<NSNumber *> *)ends strides:(NSArray<NSNumber *> *)strides startMask:(uint32_t)startMask endMask:(uint32_t)endMask squeezeMask:(uint32_t)squeezeMask name:(NSString *)name;
- (MPSGraphTensor *)sliceGradientTensor:(MPSGraphTensor *)inputGradientTensor fwdInShapeTensor:(MPSGraphTensor *)fwdInShapeTensor startTensor:(MPSGraphTensor *)startTensor endTensor:(MPSGraphTensor *)endTensor strideTensor:(MPSGraphTensor *)strideTensor startMask:(uint32_t)startMask endMask:(uint32_t)endMask squeezeMask:(uint32_t)squeezeMask name:(NSString *)name;
- (MPSGraphTensor *)sliceUpdateDataTensor:(MPSGraphTensor *)dataTensor updateTensor:(MPSGraphTensor *)updateTensor starts:(NSArray<NSNumber *> *)starts ends:(NSArray<NSNumber *> *)ends strides:(NSArray<NSNumber *> *)strides startMask:(uint32_t)startMask endMask:(uint32_t)endMask squeezeMask:(uint32_t)squeezeMask name:(NSString *)name;
- (MPSGraphTensor *)constantWithData:(NSData *)data shape:(MPSShape *)shape dataType:(MPSDataType)dataType;
@end

static id<MTLDevice> gDevice;
static MPSGraphDevice *gGraphDevice;

// A feed whose buffer carries a SENTINEL immediately after the operand's own elements, which is the whole
// of how the tile's gradient is measured: an operation that reads one element past the end of the operand
// picks the sentinel up, and the bytes it answers with are then OURS and not the heap's. The sentinel is
// 1000 and up, so an answer holding 1013 is a read past the end and not an arithmetic result.
static MPSGraphTensorData *sentinelFeed(const float *values, NSArray<NSNumber *> *shape, NSUInteger wide,
                                         BOOL mark)
{
    NSUInteger count = 1;
    for (NSNumber *dimension in shape) count *= (NSUInteger)dimension.integerValue;
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:count * (wide ? 4 : 2) * sizeof(float)
                                              options:MTLResourceStorageModeShared];
    float *bytes = (float *)[buffer contents];
    for (NSUInteger i = 0; i < count; i++) bytes[i] = values[i];
    // How far past the end a read went is then readable off the answer: 1000 and up is one operand's length
    // past, 2000 and up is two, 3000 is three. An answer holding none of them read nothing it should not.
    for (NSUInteger i = count; i < count * (wide ? 4 : 2); i++)
        bytes[i] = mark ? 1000.0f * (float)((i - count) / count) + (float)((i - count) % count) : 0.0f;
    return [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:shape dataType:MPSDataTypeFloat32];
}

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

// An operation of MORE THAN ONE input, which is what the slice's gradient and the slice's update are: a
// gradient and the shape of its forward input, or a data tensor and an update, and beside them the index
// tensors of the fed forms. Each input is fed its own bytes, and the result is asked into a destination of
// the shape the CALLER gives - which is the only way to ask the questions whose result the release leaves
// unshaped, and it is what tells a written element from an unwritten one.
static void multi(MPSGraphTensor *(^build)(MPSGraph *, NSArray<MPSGraphTensor *> *),
                  NSArray<NSArray<NSNumber *> *> *shapes, NSArray<NSData *> *bytes,
                  NSArray<NSNumber *> *types, NSArray<NSNumber *> *resultShape, const char *name)
{
    MPSGraph *one_ = [MPSGraph new];
    NSMutableArray *operands = [NSMutableArray arrayWithCapacity:shapes.count];
    NSMutableDictionary *shaped = [NSMutableDictionary dictionary];
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:shapes.count];
    for (NSUInteger i = 0; i < shapes.count; i++) {
        MPSDataType type = (MPSDataType)[types[i] unsignedIntValue];
        MPSGraphTensor *operand = [one_ placeholderWithShape:shapes[i] dataType:type name:@"i"];
        [operands addObject:operand];
        shaped[operand] = [[MPSGraphShapedType alloc] initWithShape:shapes[i] dataType:type];
        [values addObject:[[MPSGraphTensorData alloc] initWithMTLBuffer:
                           [gDevice newBufferWithBytes:bytes[i].bytes length:bytes[i].length
                                                options:MTLResourceStorageModeShared]
                                                     shape:shapes[i] dataType:type]];
    }
    MPSGraphTensor *t = build(one_, operands);
    // What the release's own tensor says about the result's shape, printed whether or not it has one: a
    // result whose type the release could not infer is a measurement of its own and not of anything written.
    printf("%s result-shape %s\n", name, t.shape ? [[t.shape componentsJoinedByString:@"x"] UTF8String] : "nil");
    NSUInteger count = 1;
    for (NSNumber *dimension in resultShape) count *= (NSUInteger)dimension.integerValue;
    size_t howMany = count * MPSSizeofMPSDataType(MPSDataTypeFloat32);
    id<MTLBuffer> buffer = [gDevice newBufferWithLength:howMany options:MTLResourceStorageModeShared];
    memset([buffer contents], gPattern, howMany);
    MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:resultShape
                                                                             dataType:MPSDataTypeFloat32];
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    for (MPSGraphTensor *tensor in operands) all[tensor] = shaped[tensor];
    MPSGraphExecutable *executable = [one_ compileWithDevice:gGraphDevice feeds:all
                                              targetTensors:@[t] targetOperations:@[] compilationDescriptor:nil];
    [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                          inputsArray:values resultsArray:@[destination] executionDescriptor:nil];
    put(name, buffer, howMany);
}

// The shape of a slice's forward input as a CONSTANT, which is the only way the release can be asked for a
// gradient: the shape arrives as a tensor, and a tensor that is fed is one the release cannot build a graph
// over (measured: no shape on the result, before or after the run, and one element written).
static MPSGraphTensor *forwardShape(MPSGraph *g, int32_t a, int32_t b)
{
    int32_t extents[2] = { a, b };
    return [g constantWithData:[NSData dataWithBytes:extents length:sizeof extents]
                         shape:@[@2] dataType:MPSDataTypeInt32];
}

static float rowFeed[8] = { 1.0f, 2.0f, 3.0f, 4.0f, 10.0f, 20.0f, 30.0f, 40.0f };
// The row of four the thin-axis pad questions are asked over: an axis of extent one is an axis a mirror
// reaches nothing into, which is what makes it the sharpest of the two mirror limits.
static float thinRow[4] = { 1.0f, 2.0f, 3.0f, 4.0f };
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
            "reshape-fed-shape", "reshape-volume-mismatch", "reshape-two-dynamic", "reshape-dynamic-only",
            "slice-length-zero", "slice-start-past-end", "slice-stride-zero", "slice-length-past-end",
            "fed-flatten-axis", "fed-broadcast-shape", "fed-reverse-axes", "fed-squeeze-axes",
            "fed-expand-axes", "squeeze-not-unit", "flatten-axis-outside", "expand-axis-outside",
            "transpose-axis-outside", "reverse-axis-outside", "reverse-axes-empty", "squeeze-axes-empty",
            "expand-axes-empty", "transpose-same-axis", "transpose-short-permutation",
            "slice-mask-start-empty", "slice-fed-ends", "slice-fed-sizes", "slice-fed-float32",
            "slice-gradient-fed-shape", "slice-gradient-fed", "slice-gradient-squeeze",
            "slice-gradient-stride2", "slice-gradient-shape-mismatch",
            "slice-update-end-mask", "slice-update-squeeze-mask", "slice-update-shape-wide",
            "slice-update-shape-narrow", "slice-update-fed-answer",
            "tilegrad-1x1", "tilegrad-1x2", "tilegrad-1x2-zero", "tilegrad-1x3", "tilegrad-1x5",
            "tilegrad-1x3-short",
            "pad-destination-narrower-rank3-clamp", "pad-destination-narrower-rank3-constant",
            "pad-destination-narrower-rank2",
            "pad-periodic", "pad-antiperiodic", "pad-reflect-past-extent",
            "pad-thin-reflect", "pad-thin-symmetric",
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
        if (strcmp(q, "slice-length-zero") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g sliceTensor:a dimension:1 start:0 length:0 name:@"s"]; }, twoByFour, rowFeed, "slice-length-zero");
            return 0;
        }
        if (strcmp(q, "slice-start-past-end") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g sliceTensor:a dimension:1 start:9 length:2 name:@"s"]; }, twoByFour, rowFeed, "slice-start-past-end");
            return 0;
        }
        if (strcmp(q, "slice-stride-zero") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g sliceTensor:a starts:@[@0, @0] ends:@[@2, @4] strides:@[@1, @0] name:@"s"]; }, twoByFour, rowFeed, "slice-stride-zero");
            return 0;
        }
        if (strcmp(q, "slice-length-past-end") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g sliceTensor:a dimension:1 start:2 length:9 name:@"s"]; }, twoByFour, rowFeed, "slice-length-past-end");
            return 0;
        }
        if (strcmp(q, "reshape-fed-shape") == 0) {
            fed(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a, MPSGraphTensor *p) {
                return [g reshapeTensor:a withShapeTensor:p name:@"r"]; }, twoByFour, rowFeed, 4, MPSDataTypeInt32, @[@1], "reshape-fed-shape");
            return 0;
        }
        if (strcmp(q, "reshape-volume-mismatch") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g reshapeTensor:a withShape:@[@1, @7] name:@"r"]; }, twoByFour, rowFeed, "reshape-volume-mismatch");
            return 0;
        }
        if (strcmp(q, "reshape-two-dynamic") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g reshapeTensor:a withShape:@[@-1, @-1] name:@"r"]; }, twoByFour, rowFeed, "reshape-two-dynamic");
            return 0;
        }
        if (strcmp(q, "reshape-dynamic-only") == 0) {
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g reshapeTensor:a withShape:@[@-1] name:@"r"]; }, twoByFour, rowFeed, "reshape-dynamic-only");
            return 0;
        }
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
        // THE SLICE FAMILY'S OWN QUESTIONS, which are the ones the eleven rows of the mask, gradient and
        // update forms carry. The data of the family is the data of the update cases above: the data tensor
        // is of (100, 200, 300, 400 | 500, 600, 700, 800) and the update of (-1, -2, -3, -4).
        if (strcmp(q, "slice-mask-start-empty") == 0) {
            // A masked start is zero, so a start of 9 with an end of 0 asks for a result of no elements -
            // which the release builds and then cannot make an NDArray for.
            one(^MPSGraphTensor *(MPSGraph *g, MPSGraphTensor *a) {
                return [g sliceTensor:a starts:@[@9, @0] ends:@[@0, @4] strides:@[@1, @1]
                          startMask:1 endMask:0 squeezeMask:0 name:@"s"]; }, twoByFour, rowFeed, "slice-mask-start-empty");
            return 0;
        }
        if (strcmp(q, "slice-fed-ends") == 0 || strcmp(q, "slice-fed-sizes") == 0
            || strcmp(q, "slice-fed-float32") == 0) {
            // The two FED slice forms of 18.2, and the floating point one besides them: the result's shape
            // comes out of the fed tensors, and a shape that is data is the one thing the release cannot
            // build a graph over.
            int32_t starts[2] = { 0, 0 };
            int32_t ends[2] = { 1, 4 };
            int32_t each[2] = { 1, 1 };
            float halves[2] = { 0.0f, 0.0f };
            MPSGraph *g = [MPSGraph new];
            MPSGraphTensor *a = [g placeholderWithShape:twoByFour dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *t;
            NSArray<NSArray<NSNumber *> *> *shapes;
            NSArray<NSData *> *bytes;
            NSArray<NSNumber *> *types;
            if (strcmp(q, "slice-fed-ends") == 0) {
                MPSGraphTensor *s = [g placeholderWithShape:@[@2] dataType:MPSDataTypeInt32 name:@"s"];
                MPSGraphTensor *e = [g placeholderWithShape:@[@2] dataType:MPSDataTypeInt32 name:@"e"];
                MPSGraphTensor *t2 = [g placeholderWithShape:@[@2] dataType:MPSDataTypeInt32 name:@"t"];
                t = [g sliceTensor:a startTensor:s endTensor:e strideTensor:t2
                      startMask:0 endMask:0 squeezeMask:0 name:@"s"];
                shapes = @[@[@2, @4], @[@2], @[@2], @[@2]];
                bytes = @[[NSData dataWithBytes:rowFeed length:32], [NSData dataWithBytes:starts length:sizeof starts],
                          [NSData dataWithBytes:ends length:sizeof ends], [NSData dataWithBytes:each length:sizeof each]];
                types = @[@(MPSDataTypeFloat32), @(MPSDataTypeInt32), @(MPSDataTypeInt32), @(MPSDataTypeInt32)];
            } else if (strcmp(q, "slice-fed-sizes") == 0) {
                MPSGraphTensor *s = [g placeholderWithShape:@[@2] dataType:MPSDataTypeInt32 name:@"s"];
                MPSGraphTensor *z = [g placeholderWithShape:@[@2] dataType:MPSDataTypeInt32 name:@"z"];
                t = [g sliceTensor:a startTensor:s sizeTensor:z squeezeMask:0 name:@"s"];
                shapes = @[@[@2, @4], @[@2], @[@2]];
                bytes = @[[NSData dataWithBytes:rowFeed length:32], [NSData dataWithBytes:starts length:sizeof starts],
                          [NSData dataWithBytes:ends length:sizeof ends]];
                types = @[@(MPSDataTypeFloat32), @(MPSDataTypeInt32), @(MPSDataTypeInt32)];
            } else {
                MPSGraphTensor *s = [g placeholderWithShape:@[@2] dataType:MPSDataTypeFloat32 name:@"s"];
                MPSGraphTensor *e = [g placeholderWithShape:@[@2] dataType:MPSDataTypeFloat32 name:@"e"];
                MPSGraphTensor *t2 = [g placeholderWithShape:@[@2] dataType:MPSDataTypeFloat32 name:@"t"];
                t = [g sliceTensor:a startTensor:s endTensor:e strideTensor:t2
                      startMask:0 endMask:0 squeezeMask:0 name:@"s"];
                shapes = @[@[@2, @4], @[@2], @[@2], @[@2]];
                bytes = @[[NSData dataWithBytes:rowFeed length:32], [NSData dataWithBytes:halves length:sizeof halves],
                          [NSData dataWithBytes:halves length:sizeof halves], [NSData dataWithBytes:halves length:sizeof halves]];
                types = @[@(MPSDataTypeFloat32), @(MPSDataTypeFloat32), @(MPSDataTypeFloat32), @(MPSDataTypeFloat32)];
            }
            multi(^MPSGraphTensor *(MPSGraph *graph, NSArray<MPSGraphTensor *> *in) { return t; },
                  shapes, bytes, types, twoByFour, q);
            return 0;
        }
        if (strcmp(q, "slice-gradient-fed-shape") == 0 || strcmp(q, "slice-gradient-fed") == 0) {
            // The gradient whose forward input's shape is FED rather than a constant: the release's own
            // result tensor carries no shape, before the run or after it, and the process writes the
            // gradient's element 0 into the destination's element 0 and nothing else.
            int32_t forward[2] = { 2, 4 };
            int32_t starts[2] = { 0, 1 };
            int32_t ends[2] = { 1, 3 };
            int32_t each[2] = { 1, 1 };
            float gradient[2] = { -1.0f, -2.0f };
            multi(^MPSGraphTensor *(MPSGraph *g, NSArray<MPSGraphTensor *> *in) {
                      if (strcmp(q, "slice-gradient-fed") == 0)
                          return [g sliceGradientTensor:in[0] fwdInShapeTensor:in[1] startTensor:in[2]
                                              endTensor:in[3] strideTensor:in[4] startMask:0 endMask:0
                                              squeezeMask:0 name:@"grad"];
                      return [g sliceGradientTensor:in[0] fwdInShapeTensor:in[1] starts:@[@0, @1]
                                          ends:@[@1, @3] strides:@[@1, @1] name:@"grad"]; },
                  @[@[@1, @2], @[@2], @[@2], @[@2], @[@2]],
                  @[[NSData dataWithBytes:gradient length:sizeof gradient],
                    [NSData dataWithBytes:forward length:sizeof forward],
                    [NSData dataWithBytes:starts length:sizeof starts],
                    [NSData dataWithBytes:ends length:sizeof ends],
                    [NSData dataWithBytes:each length:sizeof each]],
                  @[@(MPSDataTypeFloat32), @(MPSDataTypeInt32), @(MPSDataTypeInt32), @(MPSDataTypeInt32),
                    @(MPSDataTypeInt32)], twoByFour, q);
            return 0;
        }
        if (strcmp(q, "slice-gradient-squeeze") == 0 || strcmp(q, "slice-gradient-stride2") == 0
            || strcmp(q, "slice-gradient-shape-mismatch") == 0) {
            // Three gradients the release's own compiler will not build: a squeezeMask (with and without the
            // mask it pairs with), a stride above one, and a gradient whose shape is not the region's - the
            // last with the release's own words for it, which are the check the port makes at build time.
            float gradient[8] = { 1, 2, 3, 4, 5, 6, 7, 8 };
            float four[4] = { -1, -2, -3, -4 };
            multi(^MPSGraphTensor *(MPSGraph *g, NSArray<MPSGraphTensor *> *in) {
                      if (strcmp(q, "slice-gradient-squeeze") == 0)
                          return [g sliceGradientTensor:in[0] fwdInShapeTensor:forwardShape(g, 2, 4)
                                              starts:@[@0, @0] ends:@[@1, @4] strides:@[@1, @1]
                                              startMask:0 endMask:0 squeezeMask:1 name:@"grad"];
                      if (strcmp(q, "slice-gradient-stride2") == 0)
                          return [g sliceGradientTensor:in[0] fwdInShapeTensor:forwardShape(g, 2, 4)
                                              starts:@[@0, @0] ends:@[@1, @3] strides:@[@1, @2]
                                              startMask:0 endMask:0 squeezeMask:0 name:@"grad"];
                      // A gradient of one row where a startMask over axis 0 makes the region two rows, which
                      // is the release's own words for a gradient that is not the region's: "'mps.
                      // strided_slice_gradient' op `grad_input`[0] = 1 should match dimension size: 2
                      // deduced from `fwd_shape`".
                      return [g sliceGradientTensor:in[0] fwdInShapeTensor:forwardShape(g, 2, 4)
                                          starts:@[@1, @0] ends:@[@2, @4] strides:@[@1, @1]
                                          startMask:1 endMask:0 squeezeMask:0 name:@"grad"]; },
                  (strcmp(q, "slice-gradient-shape-mismatch") == 0) ? @[@[@1, @4]] : @[@[@2, @4]],
                  (strcmp(q, "slice-gradient-shape-mismatch") == 0)
                      ? @[[NSData dataWithBytes:four length:sizeof four]]
                      : @[[NSData dataWithBytes:gradient length:sizeof gradient]],
                  @[@(MPSDataTypeFloat32)], twoByFour, q);
            return 0;
        }
        if (strcmp(q, "slice-update-end-mask") == 0 || strcmp(q, "slice-update-squeeze-mask") == 0
            || strcmp(q, "slice-update-shape-wide") == 0 || strcmp(q, "slice-update-shape-narrow") == 0
            || strcmp(q, "slice-update-fed-answer") == 0) {
            // The update's own questions: the two masks the release refuses on it, the two shapes of update
            // that are not the region's, and the one fed form it DOES answer - which is the whole of what
            // separates 18.0's fed update from the five fed gather parameters the release cannot build over.
            float data[8] = { 100, 200, 300, 400, 500, 600, 700, 800 };
            float four[4] = { -1, -2, -3, -4 };
            float two[2] = { -1, -2 };
            int32_t starts[2] = { 0, 1 };
            int32_t ends[2] = { 1, 3 };
            int32_t each[2] = { 1, 1 };
            uint32_t masks[3] = { 0, 0, 0 };
            if (strcmp(q, "slice-update-end-mask") == 0) masks[1] = 2;
            if (strcmp(q, "slice-update-squeeze-mask") == 0) masks[2] = 2;
            NSArray<NSNumber *> *updateShape = (strcmp(q, "slice-update-shape-wide") == 0) ? @[@2, @4] : @[@1, @2];
            if (strcmp(q, "slice-update-shape-narrow") == 0) updateShape = @[@1, @1];
            // The one fed parameter of this family the release DOES answer, and it is asked here beside the
            // refusals because that is what makes it the interesting one: the result's shape is the data
            // tensor's own, which the graph knows when it is built, so the starts, the ends and the strides
            // can arrive as data.
            if (strcmp(q, "slice-update-fed-answer") == 0) {
                multi(^MPSGraphTensor *(MPSGraph *g, NSArray<MPSGraphTensor *> *in) {
                          return [g sliceUpdateDataTensor:in[0] updateTensor:in[1] startsTensor:in[2]
                                                  endsTensor:in[3] stridesTensor:in[4] name:@"upd"]; },
                      @[@[@2, @4], @[@1, @2], @[@2], @[@2], @[@2]],
                      @[[NSData dataWithBytes:data length:sizeof data],
                        [NSData dataWithBytes:two length:sizeof two],
                        [NSData dataWithBytes:starts length:sizeof starts],
                        [NSData dataWithBytes:ends length:sizeof ends],
                        [NSData dataWithBytes:each length:sizeof each]],
                      @[@(MPSDataTypeFloat32), @(MPSDataTypeFloat32), @(MPSDataTypeInt32), @(MPSDataTypeInt32),
                        @(MPSDataTypeInt32)], twoByFour, q);
                return 0;
            }
            uint32_t startMask = masks[0], endMask = masks[1], squeezeMask = masks[2];
            multi(^MPSGraphTensor *(MPSGraph *g, NSArray<MPSGraphTensor *> *in) {
                      return [g sliceUpdateDataTensor:in[0] updateTensor:in[1] starts:@[@0, @1] ends:@[@1, @3]
                                              strides:@[@1, @1] startMask:startMask endMask:endMask
                                              squeezeMask:squeezeMask name:@"upd"]; },
                  @[@[@2, @4], updateShape],
                  @[[NSData dataWithBytes:data length:sizeof data], [NSData dataWithBytes:four length:sizeof four]],
                  @[@(MPSDataTypeFloat32), @(MPSDataTypeFloat32)], twoByFour, q);
            (void)starts; (void)ends; (void)each;
            return 0;
        }
        // THE TILE'S GRADIENT over a SENTINEL-PADDED gradient, which is the only way to ask it at all: where
        // a window runs off the end of an axis the release READS PAST THE END of the caller's gradient buffer,
        // so its answer there is whatever memory follows it and two harnesses that ask the identical question
        // get different bytes. Measured with the sentinel: a 4x4 of (1 ... 16) with a multiplier of (1, 2)
        // answers the first three rows 6, 8, 10, 12 | 14, 16, 18, 20 | 22, 24, 26, 28 and the last row
        // 1013, 1015, 1017, 1019 - which is the last row of the gradient (13, 14, 15, 16) plus the sentinel
        // read one element past the operand (1000, 1001, 1002, 1003). Without the sentinel the same question
        // answers 13, 14, 15, 16 on this host and 30, 32, 34, 36 inside the differential, which is the heap.
        // So these are asked of the release with the sentinel in place and their bytes recorded here: the
        // answer is then made of the caller's own buffer and is the one measurement of this method that does
        // not depend on memory this repository does not own.
        if (strncmp(q, "tilegrad-", 8) == 0) {
            NSArray<NSNumber *> *shape = nil;
            NSArray<NSNumber *> *multiplier = nil;
            if (strcmp(q, "tilegrad-1x1") == 0) { shape = @[@4, @4]; multiplier = @[@1, @1]; }
            else if (strncmp(q, "tilegrad-1x2", 12) == 0) { shape = @[@4, @4]; multiplier = @[@1, @2]; }
            else if (strcmp(q, "tilegrad-1x3") == 0) { shape = @[@4, @4]; multiplier = @[@1, @3]; }
            else if (strcmp(q, "tilegrad-1x5") == 0) { shape = @[@4, @4]; multiplier = @[@1, @5]; }
            else if (strcmp(q, "tilegrad-4x3") == 0) { shape = @[@4, @4]; multiplier = @[@4, @3]; }
            else if (strcmp(q, "tilegrad-1x3-short") == 0) { shape = @[@2, @4]; multiplier = @[@1, @3]; }
            else { shape = @[@4, @4, @2]; multiplier = @[@1, @3, @3]; }
            NSUInteger count = 1;
            for (NSNumber *dimension in shape) count *= (NSUInteger)dimension.integerValue;
            float *gradient = malloc(count * sizeof(float));
            for (NSUInteger i = 0; i < count; i++) gradient[i] = (float)(i + 1);
            float *source = malloc(count * sizeof(float));
            for (NSUInteger i = 0; i < count; i++) source[i] = 1.0f;
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *g = [one placeholderWithShape:shape dataType:MPSDataTypeFloat32 name:@"g"];
            MPSGraphTensor *s = [one placeholderWithShape:shape dataType:MPSDataTypeFloat32 name:@"s"];
            MPSGraphTensor *t = [one tileGradientWithIncomingGradientTensor:g sourceTensor:s
                                                            withMultiplier:multiplier name:@"tg"];
            printf("%s result-shape %s\n", q,
                   t.shape ? [[t.shape componentsJoinedByString:@"x"] UTF8String] : "nil");
            size_t bytes = count * sizeof(float);
            id<MTLBuffer> buffer = [gDevice newBufferWithLength:bytes options:MTLResourceStorageModeShared];
            memset([buffer contents], gPattern, bytes);
            MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:shape
                                                                                 dataType:MPSDataTypeFloat32];
            NSMutableDictionary *shaped = [NSMutableDictionary dictionary];
            shaped[g] = [[MPSGraphShapedType alloc] initWithShape:shape dataType:MPSDataTypeFloat32];
            shaped[s] = [[MPSGraphShapedType alloc] initWithShape:shape dataType:MPSDataTypeFloat32];
            MPSGraphExecutable *executable = [one compileWithDevice:gGraphDevice feeds:shaped targetTensors:@[t]
                                                   targetOperations:@[] compilationDescriptor:nil];
            [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                                  inputsArray:@[sentinelFeed(gradient, shape, strstr(q, "wide") != NULL, strstr(q, "zero") == NULL),
                               feed(source, shape, MPSDataTypeFloat32)]
                                   resultsArray:@[destination] executionDescriptor:nil];
            put(q, buffer, bytes);
            free(gradient);
            free(source);
            return 0;
        }
        // THE PAD AND THE TILE'S OWN REFUSALS, each measured on this host's own MPSGraph: two modes the
        // release refuses by name, a mirror that reaches past the axis it mirrors - and the same mirror over
        // an axis ONE element long, which reaches nothing at all - and a destination whose shape is the
        // OPERAND's where the result's is a different one.
        //
        // What this branch no longer holds is a refusal of a rank of THREE. It used to hold one, and the two
        // entries it recorded - "Invalid KernelDAG, equalShape for destination failed" - were this file's own
        // question asked into the wrong shape: the destination below is the OPERAND's, and a 2x3x4 padded by
        // one at each end of every axis is a 4x5x6. Asked into a destination of the RESULT's shape the same
        // pad answers in every mode, which is what graph-cases.m's pad-rank3-clamp and pad-rank3-symmetric
        // compare. So the entry is renamed to what it measures, and the rank-3 pad is a case and not a
        // refusal.
        if (strncmp(q, "pad-", 4) == 0 || strcmp(q, "tile-rank3") == 0) {
            int rank3 = strstr(q, "rank3") != NULL;
            int thin = strstr(q, "thin") != NULL;
            int tile = strstr(q, "tile") != NULL;
            MPSGraphPaddingMode mode = MPSGraphPaddingModeConstant;
            if (strstr(q, "periodic")) mode = MPSGraphPaddingModePeriodic;
            else if (strstr(q, "antiperiodic")) mode = MPSGraphPaddingModeAntiPeriodic;
            else if (strstr(q, "symmetric")) mode = MPSGraphPaddingModeSymmetric;
            else if (strstr(q, "clamp")) mode = MPSGraphPaddingModeClampToEdge;
            else if (strstr(q, "reflect")) mode = MPSGraphPaddingModeReflect;
            NSArray<NSNumber *> *shape = rank3 ? @[@2, @3, @4] : thin ? @[@1, @4] : twoByFour;
            NSArray<NSNumber *> *left = rank3 ? @[@1, @1, @1] : thin ? @[@1, @0] : @[@1, @2];
            NSArray<NSNumber *> *right = rank3 ? @[@1, @1, @1] : thin ? @[@1, @0] : @[@1, @0];
            if (strstr(q, "past-extent")) { left = @[@3, @2]; right = @[@2, @0]; }
            // A mirror over an axis of ONE element long reaches nothing into it, so the padding that is one
            // past its own limit is one for the reflect and two for the symmetric - the symmetric reaches
            // the axis itself, which is the whole of the difference between the two limits.
            if (thin && mode == 2) { left = @[@2, @0]; right = @[@2, @0]; }
            const void *values = rank3 ? (const void *)twoByThreeByFour : thin ? (const void *)thinRow
                                                                : (const void *)rowFeed;
            NSUInteger count = rank3 ? 24 : thin ? 4 : 8;
            float *bytes = malloc(count * sizeof(float));
            memcpy(bytes, values, count * sizeof(float));
            MPSGraph *one = [MPSGraph new];
            MPSGraphTensor *a = [one placeholderWithShape:shape dataType:MPSDataTypeFloat32 name:@"a"];
            MPSGraphTensor *t = tile ? [one tileTensor:a withMultiplier:@[@2, @2, @2] name:@"t"]
                : [one padTensor:a withPaddingMode:mode leftPadding:left rightPadding:right
                     constantValue:99.0 name:@"p"];
            NSMutableDictionary *shaped = [NSMutableDictionary dictionary];
            shaped[a] = [[MPSGraphShapedType alloc] initWithShape:shape dataType:MPSDataTypeFloat32];
            MPSGraphExecutable *executable = [one compileWithDevice:gGraphDevice feeds:shaped targetTensors:@[t]
                                                   targetOperations:@[] compilationDescriptor:nil];
            // The result's own shape is printed whatever it is, and the destination is the OPERAND's shape,
            // because a process that is gone writes nothing this file can match and the shape line is what
            // the release did answer before it went.
            printf("%s result-shape %s\n", q, t.shape ? [[t.shape componentsJoinedByString:@"x"] UTF8String] : "nil");
            id<MTLBuffer> buffer = [gDevice newBufferWithLength:count * sizeof(float)
                                                      options:MTLResourceStorageModeShared];
            memset([buffer contents], gPattern, count * sizeof(float));
            MPSGraphTensorData *destination = [[MPSGraphTensorData alloc] initWithMTLBuffer:buffer shape:shape
                                                                                 dataType:MPSDataTypeFloat32];
            [executable runWithMTLCommandQueue:[gDevice newCommandQueue]
                                  inputsArray:@[feed(bytes, shape, MPSDataTypeFloat32)]
                                   resultsArray:@[destination] executionDescriptor:nil];
            put(q, buffer, count * sizeof(float));
            free(bytes);
            return 0;
        }
        fprintf(stderr, "unknown question '%s'\n", q);
        return 2;
    }
}
