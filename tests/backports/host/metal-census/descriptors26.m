/* descriptors26.m - the Metal 4 descriptors, compared PROPERTY BY PROPERTY against Apple's own
 * objects.
 *
 * NO DEVICE IS CREATED and none is needed: every side of every comparison is `[[X alloc] init]`, and
 * a descriptor asks a device nothing - facts/Metal/DeviceOnThisMachine.md measures that, on a machine
 * that HAS one. The host object is APPLE'S, made by Apple's class, and it is the oracle: the port's
 * value is compared against what Apple's own object answers for the same property on the same fresh
 * object. A round trip of the port's object against ITSELF would prove only that the port agrees with
 * the port, and that is the round trip that let three reviews through.
 *
 * The port's sixteen classes are compiled under other names, so both copies are in one binary and each
 * side is asked by its own name; a case that read the host's class and called it the port's would
 * agree with itself. The binary is asked for the renamed symbols and the run stops if they are absent.
 *
 * Identity is only ever compared WITHIN one side: two objects have no address in common.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

/* The port's classes, under the names the harness compiles them with. */
/* The base the three subclasses below extend: Apple's own declaration gives it no members, so the case
 * declares it the same way and what it compares is that a fresh one is an object, that two are equal and
 * that a copy equals its source. */
@interface charonHost_MTL4FunctionDescriptor : NSObject <NSCopying>
@end
@interface charonHost_MTL4SpecializedFunctionDescriptor : charonHost_MTL4FunctionDescriptor
@property (nonatomic, copy) id functionDescriptor;
@property (nonatomic, copy) id specializedName;
@property (nonatomic, copy) id constantValues;
@end
@interface charonHost_MTL4StitchedFunctionDescriptor : charonHost_MTL4FunctionDescriptor
@property (nonatomic, copy) id functionGraph;
@property (nonatomic, copy) NSArray *functionDescriptors;
@end
@interface charonHost_MTL4LibraryFunctionDescriptor : charonHost_MTL4FunctionDescriptor
@property (nonatomic, copy) id name;
@property (nonatomic, retain) id library;
@end
@interface charonHost_MTL4PipelineOptions : NSObject
@property (nonatomic) MTLShaderValidation shaderValidation;
@property (nonatomic) MTL4ShaderReflection shaderReflection;
@end
@interface charonHost_MTL4StaticLinkingDescriptor : NSObject
@property (nonatomic, copy) NSArray *functionDescriptors;
@property (nonatomic, copy) NSArray *privateFunctionDescriptors;
@property (nonatomic, copy) NSDictionary *groups;
@end
@interface charonHost_MTL4PipelineStageDynamicLinkingDescriptor : NSObject
@property (nonatomic) NSUInteger maxCallStackDepth;
@property (nonatomic, copy) NSArray *binaryLinkedFunctions;
@property (nonatomic, copy) NSArray *preloadedLibraries;
@end
@interface charonHost_MTL4RenderPipelineDynamicLinkingDescriptor : NSObject
@property (readonly) charonHost_MTL4PipelineStageDynamicLinkingDescriptor *vertexLinkingDescriptor;
@property (readonly) charonHost_MTL4PipelineStageDynamicLinkingDescriptor *fragmentLinkingDescriptor;
@property (readonly) charonHost_MTL4PipelineStageDynamicLinkingDescriptor *tileLinkingDescriptor;
@property (readonly) charonHost_MTL4PipelineStageDynamicLinkingDescriptor *objectLinkingDescriptor;
@property (readonly) charonHost_MTL4PipelineStageDynamicLinkingDescriptor *meshLinkingDescriptor;
@end
@interface charonHost_MTL4RenderPipelineBinaryFunctionsDescriptor : NSObject
@property (nonatomic, copy) NSArray *vertexAdditionalBinaryFunctions;
@property (nonatomic, copy) NSArray *fragmentAdditionalBinaryFunctions;
@property (nonatomic, copy) NSArray *tileAdditionalBinaryFunctions;
@property (nonatomic, copy) NSArray *objectAdditionalBinaryFunctions;
@property (nonatomic, copy) NSArray *meshAdditionalBinaryFunctions;
- (void)reset;
@end
@interface charonHost_MTL4RenderPipelineColorAttachmentDescriptor : NSObject
@property (nonatomic) MTLPixelFormat pixelFormat;
@property (nonatomic) MTL4BlendState blendingState;
@property (nonatomic) MTLBlendFactor sourceRGBBlendFactor;
@property (nonatomic) MTLBlendFactor destinationRGBBlendFactor;
@property (nonatomic) MTLBlendOperation rgbBlendOperation;
@property (nonatomic) MTLBlendFactor sourceAlphaBlendFactor;
@property (nonatomic) MTLBlendFactor destinationAlphaBlendFactor;
@property (nonatomic) MTLBlendOperation alphaBlendOperation;
@property (nonatomic) MTLColorWriteMask writeMask;
- (void)reset;
@end
@interface charonHost_MTL4RenderPipelineColorAttachmentDescriptorArray : NSObject
- (charonHost_MTL4RenderPipelineColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(charonHost_MTL4RenderPipelineColorAttachmentDescriptor *)attachment atIndexedSubscript:(NSUInteger)index;
- (void)reset;
@end
@interface charonHost_MTL4PipelineDescriptor : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, retain) id options;
@end
@interface charonHost_MTL4RenderPipelineDescriptor : charonHost_MTL4PipelineDescriptor
@property (nonatomic, copy) id vertexFunctionDescriptor;
@property (nonatomic, copy) id fragmentFunctionDescriptor;
@property (nonatomic, copy) id vertexDescriptor;
@property (nonatomic) NSUInteger rasterSampleCount;
@property (nonatomic) MTL4AlphaToCoverageState alphaToCoverageState;
@property (nonatomic) MTL4AlphaToOneState alphaToOneState;
@property (nonatomic, getter=isRasterizationEnabled) BOOL rasterizationEnabled;
@property (nonatomic) NSUInteger maxVertexAmplificationCount;
@property (readonly) charonHost_MTL4RenderPipelineColorAttachmentDescriptorArray *colorAttachments;
@property (nonatomic) MTLPrimitiveTopologyClass inputPrimitiveTopology;
@property (nonatomic, copy) id vertexStaticLinkingDescriptor;
@property (nonatomic, copy) id fragmentStaticLinkingDescriptor;
@property (nonatomic) BOOL supportVertexBinaryLinking;
@property (nonatomic) BOOL supportFragmentBinaryLinking;
@property (nonatomic) MTL4LogicalToPhysicalColorAttachmentMappingState colorAttachmentMappingState;
@property (nonatomic) MTL4IndirectCommandBufferSupportState supportIndirectCommandBuffers;
- (void)reset;
@end
@interface charonHost_MTL4ComputePipelineDescriptor : charonHost_MTL4PipelineDescriptor
@property (nonatomic, copy) id computeFunctionDescriptor;
@property (nonatomic) BOOL threadGroupSizeIsMultipleOfThreadExecutionWidth;
@property (nonatomic) NSUInteger maxTotalThreadsPerThreadgroup;
@property (nonatomic) MTLSize requiredThreadsPerThreadgroup;
@property (nonatomic) BOOL supportBinaryLinking;
@property (nonatomic, copy) id staticLinkingDescriptor;
@property (nonatomic) MTL4IndirectCommandBufferSupportState supportIndirectCommandBuffers;
- (void)reset;
@end
@interface charonHost_MTL4TileRenderPipelineDescriptor : charonHost_MTL4PipelineDescriptor
@property (nonatomic, copy) id tileFunctionDescriptor;
@property (nonatomic) NSUInteger rasterSampleCount;
@property (readonly) MTLTileRenderPipelineColorAttachmentDescriptorArray *colorAttachments;
@property (nonatomic) BOOL threadgroupSizeMatchesTileSize;
@property (nonatomic) NSUInteger maxTotalThreadsPerThreadgroup;
@property (nonatomic) MTLSize requiredThreadsPerThreadgroup;
@property (nonatomic, copy) id staticLinkingDescriptor;
@property (nonatomic) BOOL supportBinaryLinking;
- (void)reset;
@end
@interface charonHost_MTL4MeshRenderPipelineDescriptor : charonHost_MTL4PipelineDescriptor
@property (nonatomic, copy) id objectFunctionDescriptor;
@property (nonatomic, copy) id meshFunctionDescriptor;
@property (nonatomic, copy) id fragmentFunctionDescriptor;
@property (nonatomic) NSUInteger maxTotalThreadsPerObjectThreadgroup;
@property (nonatomic) NSUInteger maxTotalThreadsPerMeshThreadgroup;
@property (nonatomic) MTLSize requiredThreadsPerObjectThreadgroup;
@property (nonatomic) MTLSize requiredThreadsPerMeshThreadgroup;
@property (nonatomic) BOOL objectThreadgroupSizeIsMultipleOfThreadExecutionWidth;
@property (nonatomic) BOOL meshThreadgroupSizeIsMultipleOfThreadExecutionWidth;
@property (nonatomic) NSUInteger payloadMemoryLength;
@property (nonatomic) NSUInteger maxTotalThreadgroupsPerMeshGrid;
@property (nonatomic) NSUInteger rasterSampleCount;
@property (nonatomic) MTL4AlphaToCoverageState alphaToCoverageState;
@property (nonatomic) MTL4AlphaToOneState alphaToOneState;
@property (nonatomic, getter=isRasterizationEnabled) BOOL rasterizationEnabled;
@property (nonatomic) NSUInteger maxVertexAmplificationCount;
@property (readonly) charonHost_MTL4RenderPipelineColorAttachmentDescriptorArray *colorAttachments;
@property (nonatomic, copy) id objectStaticLinkingDescriptor;
@property (nonatomic, copy) id meshStaticLinkingDescriptor;
@property (nonatomic, copy) id fragmentStaticLinkingDescriptor;
@property (nonatomic) BOOL supportObjectBinaryLinking;
@property (nonatomic) BOOL supportMeshBinaryLinking;
@property (nonatomic) BOOL supportFragmentBinaryLinking;
@property (nonatomic) MTL4LogicalToPhysicalColorAttachmentMappingState colorAttachmentMappingState;
@property (nonatomic) MTL4IndirectCommandBufferSupportState supportIndirectCommandBuffers;
- (void)reset;
@end

static int failures;
static int checks;

static void check(BOOL ok, NSString *what)
{
    checks++;
    if (ok) printf("  ok   %s\n", [what UTF8String]);
    else { printf("  FAIL %s\n", [what UTF8String]); failures++; }
}

static void same_l(long port, long host, NSString *what)
{
    check(port == host, ([NSString stringWithFormat:@"%@: the port %ld and Apple's own object %ld",
                          what, port, host]));
}

static void same_u(unsigned long port, unsigned long host, NSString *what)
{
    check(port == host, ([NSString stringWithFormat:@"%@: the port %lu and Apple's own object %lu",
                          what, port, host]));
}

/* A SLOT ASKED AT AN INDEX BOTH SIDES REFUSE MUST BE A CHECK AND NOT A TRAP: the port raises and Apple
 * fails an assertion, and an abort leaves no assertion line for the harness to read. Each reader below
 * is a real call, wrapped. */
static id hostSlot(id array, NSUInteger index)
{
    @try { return [(MTL4RenderPipelineColorAttachmentDescriptorArray *)array objectAtIndexedSubscript:index]; }
    @catch (NSException *why) { printf("       Apple's side raised at %lu: %s\n", (unsigned long)index, [[why reason] UTF8String]); return nil; }
}

static id portSlot(id array, NSUInteger index)
{
    @try { return [(charonHost_MTL4RenderPipelineColorAttachmentDescriptorArray *)array objectAtIndexedSubscript:index]; }
    @catch (NSException *why) { printf("       the port raised at %lu: %s\n", (unsigned long)index, [[why reason] UTF8String]); return nil; }
}

static void compare_size(MTLSize port, MTLSize host, NSString *what)
{
    check(port.width == host.width && port.height == host.height && port.depth == host.depth,
          ([NSString stringWithFormat:@"%@: the port %lux%lux%lu and Apple's own object %lux%lux%lu",
            what, (unsigned long)port.width, (unsigned long)port.height, (unsigned long)port.depth,
            (unsigned long)host.width, (unsigned long)host.height, (unsigned long)host.depth]));
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        printf("no device is created: a descriptor asks for none, and both sides are [[X alloc] init]\n");
        checks++;
        if (NSClassFromString(@"ZZZNoSuchNameCharonR16") == nil)
            printf("  ok   the control: ZZZNoSuchNameCharonR16 is not a class of this framework\n");
        else {
            printf("  FAIL the control: ZZZNoSuchNameCharonR16 exists, so this harness's answers mean nothing\n");
            failures++;
        }

        printf("MTL4PipelineOptions\n");
        {
            MTL4PipelineOptions *host = [[MTL4PipelineOptions alloc] init];
            charonHost_MTL4PipelineOptions *port = [[charonHost_MTL4PipelineOptions alloc] init];
            same_l((long)port.shaderValidation, (long)host.shaderValidation, @"fresh: shaderValidation");
            same_u((unsigned long)port.shaderReflection, (unsigned long)host.shaderReflection, @"fresh: shaderReflection");
            /* A COPY OF A DESCRIPTOR A CALLER CHANGED, not of a fresh one: two copies of two fresh
             * objects agree whatever the copy does, so a copy that dropped a member would pass. */
            [host setShaderValidation:MTLShaderValidationDisabled];
            [port setShaderValidation:MTLShaderValidationDisabled];
            [host setShaderReflection:MTL4ShaderReflectionBufferTypeInfo];
            [port setShaderReflection:MTL4ShaderReflectionBufferTypeInfo];
            same_l((long)port.shaderValidation, (long)host.shaderValidation, @"after a set: shaderValidation");
            same_u((unsigned long)port.shaderReflection, (unsigned long)host.shaderReflection, @"after a set: shaderReflection");
            MTL4PipelineOptions *hostCopy = [host copy];
            charonHost_MTL4PipelineOptions *portCopy = [port copy];
            same_l((long)portCopy.shaderValidation, (long)hostCopy.shaderValidation, @"copy of a changed one: shaderValidation");
            same_u((unsigned long)portCopy.shaderReflection, (unsigned long)hostCopy.shaderReflection, @"copy of a changed one: shaderReflection");
        }

        printf("MTL4StaticLinkingDescriptor\n");
        {
            MTL4StaticLinkingDescriptor *host = [[MTL4StaticLinkingDescriptor alloc] init];
            charonHost_MTL4StaticLinkingDescriptor *port = [[charonHost_MTL4StaticLinkingDescriptor alloc] init];
            check(host.functionDescriptors == nil && port.functionDescriptors == nil, @"fresh: functionDescriptors is nil on both sides");
            check(host.privateFunctionDescriptors == nil && port.privateFunctionDescriptors == nil, @"fresh: privateFunctionDescriptors is nil on both sides");
            check(host.groups == nil && port.groups == nil, @"fresh: groups is nil on both sides");
        }

        printf("MTL4PipelineStageDynamicLinkingDescriptor\n");
        {
            MTL4PipelineStageDynamicLinkingDescriptor *host = [[MTL4PipelineStageDynamicLinkingDescriptor alloc] init];
            charonHost_MTL4PipelineStageDynamicLinkingDescriptor *port = [[charonHost_MTL4PipelineStageDynamicLinkingDescriptor alloc] init];
            same_u((unsigned long)port.maxCallStackDepth, (unsigned long)host.maxCallStackDepth,
                   @"fresh: maxCallStackDepth, and it is Apple's own 1 and not a zero");
            check(host.binaryLinkedFunctions == nil && port.binaryLinkedFunctions == nil, @"fresh: binaryLinkedFunctions is nil on both sides");
            check(host.preloadedLibraries == nil && port.preloadedLibraries == nil, @"fresh: preloadedLibraries is nil on both sides");
            MTL4PipelineStageDynamicLinkingDescriptor *hostCopy = [host copy];
            charonHost_MTL4PipelineStageDynamicLinkingDescriptor *portCopy = [port copy];
            same_u((unsigned long)portCopy.maxCallStackDepth, (unsigned long)hostCopy.maxCallStackDepth, @"copy: maxCallStackDepth");
        }

        printf("MTL4RenderPipelineDynamicLinkingDescriptor\n");
        {
            MTL4RenderPipelineDynamicLinkingDescriptor *host = [[MTL4RenderPipelineDynamicLinkingDescriptor alloc] init];
            charonHost_MTL4RenderPipelineDynamicLinkingDescriptor *port = [[charonHost_MTL4RenderPipelineDynamicLinkingDescriptor alloc] init];
            check(host.vertexLinkingDescriptor != nil && port.vertexLinkingDescriptor != nil, @"fresh: vertexLinkingDescriptor is an object on both sides");
            check(host.fragmentLinkingDescriptor != nil && port.fragmentLinkingDescriptor != nil, @"fresh: fragmentLinkingDescriptor is an object on both sides");
            check(host.tileLinkingDescriptor != nil && port.tileLinkingDescriptor != nil, @"fresh: tileLinkingDescriptor is an object on both sides");
            check(host.objectLinkingDescriptor != nil && port.objectLinkingDescriptor != nil, @"fresh: objectLinkingDescriptor is an object on both sides");
            check(host.meshLinkingDescriptor != nil && port.meshLinkingDescriptor != nil, @"fresh: meshLinkingDescriptor is an object on both sides");
        }

        printf("MTL4RenderPipelineBinaryFunctionsDescriptor\n");
        {
            MTL4RenderPipelineBinaryFunctionsDescriptor *host = [[MTL4RenderPipelineBinaryFunctionsDescriptor alloc] init];
            charonHost_MTL4RenderPipelineBinaryFunctionsDescriptor *port = [[charonHost_MTL4RenderPipelineBinaryFunctionsDescriptor alloc] init];
            check(host.vertexAdditionalBinaryFunctions == nil && port.vertexAdditionalBinaryFunctions == nil, @"fresh: vertex is nil on both sides");
            check(host.fragmentAdditionalBinaryFunctions == nil && port.fragmentAdditionalBinaryFunctions == nil, @"fresh: fragment is nil on both sides");
            check(host.tileAdditionalBinaryFunctions == nil && port.tileAdditionalBinaryFunctions == nil, @"fresh: tile is nil on both sides");
            check(host.objectAdditionalBinaryFunctions == nil && port.objectAdditionalBinaryFunctions == nil, @"fresh: object is nil on both sides");
            check(host.meshAdditionalBinaryFunctions == nil && port.meshAdditionalBinaryFunctions == nil, @"fresh: mesh is nil on both sides");
            [host setVertexAdditionalBinaryFunctions:@[@"a"]];
            [port setVertexAdditionalBinaryFunctions:@[@"a"]];
            /* -copyWithZone: answers id, so each side's copy is asked through its OWN class: a cast of
             * one side's object to the other side's class would be a question about the cast. */
            check([(MTL4RenderPipelineBinaryFunctionsDescriptor *)[host copy] vertexAdditionalBinaryFunctions].count ==
                  [(charonHost_MTL4RenderPipelineBinaryFunctionsDescriptor *)[port copy] vertexAdditionalBinaryFunctions].count,
                  @"after a set: a copy carries the vertex array on both sides");
            [host reset]; [port reset];
            check(host.vertexAdditionalBinaryFunctions == nil && port.vertexAdditionalBinaryFunctions == nil,
                  @"after -reset: the vertex array is nil on both sides");
        }

        printf("MTL4RenderPipelineColorAttachmentDescriptor\n");
        {
            MTL4RenderPipelineColorAttachmentDescriptor *host = [[MTL4RenderPipelineColorAttachmentDescriptor alloc] init];
            charonHost_MTL4RenderPipelineColorAttachmentDescriptor *port = [[charonHost_MTL4RenderPipelineColorAttachmentDescriptor alloc] init];
            same_l((long)port.pixelFormat, (long)host.pixelFormat, @"fresh: pixelFormat, and it is MTLPixelFormatInvalid");
            same_l((long)port.blendingState, (long)host.blendingState, @"fresh: blendingState");
            same_l((long)port.sourceRGBBlendFactor, (long)host.sourceRGBBlendFactor, @"fresh: sourceRGBBlendFactor, and it is One");
            same_l((long)port.destinationRGBBlendFactor, (long)host.destinationRGBBlendFactor, @"fresh: destinationRGBBlendFactor, and it is Zero");
            same_l((long)port.rgbBlendOperation, (long)host.rgbBlendOperation, @"fresh: rgbBlendOperation");
            same_l((long)port.sourceAlphaBlendFactor, (long)host.sourceAlphaBlendFactor, @"fresh: sourceAlphaBlendFactor");
            same_l((long)port.destinationAlphaBlendFactor, (long)host.destinationAlphaBlendFactor, @"fresh: destinationAlphaBlendFactor");
            same_l((long)port.alphaBlendOperation, (long)host.alphaBlendOperation, @"fresh: alphaBlendOperation");
            same_u((unsigned long)port.writeMask, (unsigned long)host.writeMask, @"fresh: writeMask, and it is MTLColorWriteMaskAll");
            [host setPixelFormat:MTLPixelFormatRGBA8Unorm]; [port setPixelFormat:MTLPixelFormatRGBA8Unorm];
            [host setBlendingState:MTL4BlendStateEnabled]; [port setBlendingState:MTL4BlendStateEnabled];
            [host setWriteMask:MTLColorWriteMaskRed]; [port setWriteMask:MTLColorWriteMaskRed];
            same_l((long)port.pixelFormat, (long)host.pixelFormat, @"after a set: pixelFormat");
            same_l((long)port.blendingState, (long)host.blendingState, @"after a set: blendingState");
            same_u((unsigned long)port.writeMask, (unsigned long)host.writeMask, @"after a set: writeMask");
            [host reset]; [port reset];
            same_l((long)port.pixelFormat, (long)host.pixelFormat, @"after -reset: pixelFormat is back to the default");
            same_u((unsigned long)port.writeMask, (unsigned long)host.writeMask, @"after -reset: writeMask is back to All");
        }

        printf("MTL4RenderPipelineColorAttachmentDescriptorArray\n");
        {
            MTL4RenderPipelineColorAttachmentDescriptorArray *host = [[MTL4RenderPipelineColorAttachmentDescriptorArray alloc] init];
            charonHost_MTL4RenderPipelineColorAttachmentDescriptorArray *port = [[charonHost_MTL4RenderPipelineColorAttachmentDescriptorArray alloc] init];
            /* EIGHT SLOTS, and the bound is measured: indices 0 to 7 answer a descriptor on both sides.
             * Index 8 is NOT asked here - Apple's own assertion stops the process - so the bound out of
             * process is what says eight, and this says both sides agree over the legal range. */
            for (NSUInteger index = 0; index < 8; index++)
                check(hostSlot(host, index) != nil && portSlot(port, index) != nil,
                      ([NSString stringWithFormat:@"read %lu: both sides answer a descriptor", (unsigned long)index]));
            /* A WRITE COPIES, which the header states, and a NIL RESETS THE SLOT, which it states too. */
            MTL4RenderPipelineColorAttachmentDescriptor *hostAttachment = [[MTL4RenderPipelineColorAttachmentDescriptor alloc] init];
            charonHost_MTL4RenderPipelineColorAttachmentDescriptor *portAttachment = [[charonHost_MTL4RenderPipelineColorAttachmentDescriptor alloc] init];
            hostAttachment.pixelFormat = MTLPixelFormatRGBA8Unorm;
            portAttachment.pixelFormat = MTLPixelFormatRGBA8Unorm;
            [host setObject:hostAttachment atIndexedSubscript:2];
            [port setObject:portAttachment atIndexedSubscript:2];
            check(hostSlot(host, 2) != hostAttachment && portSlot(port, 2) != portAttachment,
                  @"a write copies: the slot holds a copy on both sides, not the object handed in");
            same_l((long)((MTL4RenderPipelineColorAttachmentDescriptor *)hostSlot(host, 2)).pixelFormat,
                   (long)((charonHost_MTL4RenderPipelineColorAttachmentDescriptor *)portSlot(port, 2)).pixelFormat,
                   @"a write copies: the copy carries the format");
            [host setObject:nil atIndexedSubscript:2];
            [port setObject:nil atIndexedSubscript:2];
            /* WHAT A NIL SHOWS, precisely: the slot is empty again, so the getter answers a fresh
             * descriptor and the format is the default on both sides. The getter is what makes it - a
             * slot emptied and a slot reset are the same thing through the only way in - which is why
             * the mutation for this family is the COPY above and not the reset. */
            same_l((long)((MTL4RenderPipelineColorAttachmentDescriptor *)hostSlot(host, 2)).pixelFormat,
                   (long)((charonHost_MTL4RenderPipelineColorAttachmentDescriptor *)portSlot(port, 2)).pixelFormat,
                   @"a nil empties the slot: the format is the default on both sides");
            [host reset]; [port reset];
            check(hostSlot(host, 2) != nil && portSlot(port, 2) != nil, @"after -reset: both sides still answer a descriptor");
        }

        printf("MTL4PipelineDescriptor\n");
        {
            MTL4PipelineDescriptor *host = [[MTL4PipelineDescriptor alloc] init];
            charonHost_MTL4PipelineDescriptor *port = [[charonHost_MTL4PipelineDescriptor alloc] init];
            check(host.label == nil && port.label == nil, @"fresh: label is nil on both sides");
            /* THE ONE A GUESS GETS WRONG: options is NIL on a fresh descriptor, not an object. */
            check(host.options == nil && port.options == nil,
                  @"fresh: options is nil on both sides, and NOT a fresh MTL4PipelineOptions");
            [host setLabel:@"h"]; [port setLabel:@"h"];
            same_u((unsigned long)[host.label length], (unsigned long)[port.label length], @"after a set: label");
        }

        printf("MTL4RenderPipelineDescriptor\n");
        {
            MTL4RenderPipelineDescriptor *host = [[MTL4RenderPipelineDescriptor alloc] init];
            charonHost_MTL4RenderPipelineDescriptor *port = [[charonHost_MTL4RenderPipelineDescriptor alloc] init];
            check(host.vertexFunctionDescriptor == nil && port.vertexFunctionDescriptor == nil, @"fresh: vertexFunctionDescriptor is nil on both sides");
            check(host.fragmentFunctionDescriptor == nil && port.fragmentFunctionDescriptor == nil, @"fresh: fragmentFunctionDescriptor is nil on both sides");
            /* AND ITS COUNTERPART: a vertex descriptor IS there, a fresh MTLVertexDescriptor. */
            check(host.vertexDescriptor != nil && port.vertexDescriptor != nil,
                  @"fresh: vertexDescriptor IS an object on both sides");
            /* The attribute array declares two indexed members and no -count, so "as many as Apple's
             * own" is asked over the legal range at indices both sides answer rather than at a number
             * neither header gives. */
            for (NSUInteger index = 0; index < 8; index++)
                check([host.vertexDescriptor.attributes objectAtIndexedSubscript:index] != nil &&
                      [((MTLVertexDescriptor *)port.vertexDescriptor).attributes objectAtIndexedSubscript:index] != nil,
                      ([NSString stringWithFormat:@"fresh: that vertex descriptor answers attribute %lu", (unsigned long)index]));
            same_u((unsigned long)port.rasterSampleCount, (unsigned long)host.rasterSampleCount, @"fresh: rasterSampleCount, and it is Apple's own 1");
            same_l((long)port.alphaToCoverageState, (long)host.alphaToCoverageState, @"fresh: alphaToCoverageState");
            same_l((long)port.alphaToOneState, (long)host.alphaToOneState, @"fresh: alphaToOneState");
            check(port.rasterizationEnabled == host.rasterizationEnabled && host.rasterizationEnabled,
                  @"fresh: isRasterizationEnabled is YES on both sides");
            same_u((unsigned long)port.maxVertexAmplificationCount, (unsigned long)host.maxVertexAmplificationCount,
                   @"fresh: maxVertexAmplificationCount, and it is Apple's own 1");
            check(host.colorAttachments != nil && port.colorAttachments != nil, @"fresh: colorAttachments is an object on both sides");
            same_l((long)port.inputPrimitiveTopology, (long)host.inputPrimitiveTopology, @"fresh: inputPrimitiveTopology");
            /* null_resettable: an object on a fresh descriptor on both sides. */
            check(host.vertexStaticLinkingDescriptor != nil && port.vertexStaticLinkingDescriptor != nil,
                  @"fresh: vertexStaticLinkingDescriptor is an object on both sides");
            check(host.fragmentStaticLinkingDescriptor != nil && port.fragmentStaticLinkingDescriptor != nil,
                  @"fresh: fragmentStaticLinkingDescriptor is an object on both sides");
            check(host.supportVertexBinaryLinking == port.supportVertexBinaryLinking, @"fresh: supportVertexBinaryLinking");
            check(host.supportFragmentBinaryLinking == port.supportFragmentBinaryLinking, @"fresh: supportFragmentBinaryLinking");
            same_l((long)port.colorAttachmentMappingState, (long)host.colorAttachmentMappingState, @"fresh: colorAttachmentMappingState");
            same_l((long)port.supportIndirectCommandBuffers, (long)host.supportIndirectCommandBuffers, @"fresh: supportIndirectCommandBuffers");

            [host setRasterSampleCount:4]; [port setRasterSampleCount:4];
            [host setMaxVertexAmplificationCount:7]; [port setMaxVertexAmplificationCount:7];
            [host setRasterizationEnabled:NO]; [port setRasterizationEnabled:NO];
            [host setInputPrimitiveTopology:MTLPrimitiveTopologyClassTriangle]; [port setInputPrimitiveTopology:MTLPrimitiveTopologyClassTriangle];
            same_u((unsigned long)port.rasterSampleCount, (unsigned long)host.rasterSampleCount, @"after a set: rasterSampleCount");
            same_u((unsigned long)port.maxVertexAmplificationCount, (unsigned long)host.maxVertexAmplificationCount, @"after a set: maxVertexAmplificationCount");
            check(port.rasterizationEnabled == host.rasterizationEnabled, @"after a set: isRasterizationEnabled");
            same_l((long)port.inputPrimitiveTopology, (long)host.inputPrimitiveTopology, @"after a set: inputPrimitiveTopology");

            [host reset]; [port reset];
            same_u((unsigned long)port.rasterSampleCount, (unsigned long)host.rasterSampleCount, @"after -reset: rasterSampleCount is 1 again");
            check(port.rasterizationEnabled == host.rasterizationEnabled && host.rasterizationEnabled, @"after -reset: isRasterizationEnabled is YES again");
            check(port.vertexStaticLinkingDescriptor != nil, @"after -reset: the null_resettable getter still answers an object");
        }

        printf("MTL4ComputePipelineDescriptor\n");
        {
            MTL4ComputePipelineDescriptor *host = [[MTL4ComputePipelineDescriptor alloc] init];
            charonHost_MTL4ComputePipelineDescriptor *port = [[charonHost_MTL4ComputePipelineDescriptor alloc] init];
            check(host.computeFunctionDescriptor == nil && port.computeFunctionDescriptor == nil, @"fresh: computeFunctionDescriptor is nil on both sides");
            check(host.threadGroupSizeIsMultipleOfThreadExecutionWidth == port.threadGroupSizeIsMultipleOfThreadExecutionWidth, @"fresh: threadGroupSizeIsMultipleOfThreadExecutionWidth");
            same_u((unsigned long)port.maxTotalThreadsPerThreadgroup, (unsigned long)host.maxTotalThreadsPerThreadgroup, @"fresh: maxTotalThreadsPerThreadgroup");
            compare_size(port.requiredThreadsPerThreadgroup, host.requiredThreadsPerThreadgroup, @"fresh: requiredThreadsPerThreadgroup");
            check(host.supportBinaryLinking == port.supportBinaryLinking, @"fresh: supportBinaryLinking");
            check(host.staticLinkingDescriptor != nil && port.staticLinkingDescriptor != nil, @"fresh: staticLinkingDescriptor is an object on both sides");
            same_l((long)port.supportIndirectCommandBuffers, (long)host.supportIndirectCommandBuffers, @"fresh: supportIndirectCommandBuffers");
        }

        printf("MTL4TileRenderPipelineDescriptor\n");
        {
            MTL4TileRenderPipelineDescriptor *host = [[MTL4TileRenderPipelineDescriptor alloc] init];
            charonHost_MTL4TileRenderPipelineDescriptor *port = [[charonHost_MTL4TileRenderPipelineDescriptor alloc] init];
            check(host.tileFunctionDescriptor == nil && port.tileFunctionDescriptor == nil, @"fresh: tileFunctionDescriptor is nil on both sides");
            same_u((unsigned long)port.rasterSampleCount, (unsigned long)host.rasterSampleCount, @"fresh: rasterSampleCount");
            check(host.colorAttachments != nil && port.colorAttachments != nil, @"fresh: colorAttachments is an object on both sides");
            check(host.threadgroupSizeMatchesTileSize == port.threadgroupSizeMatchesTileSize, @"fresh: threadgroupSizeMatchesTileSize");
            same_u((unsigned long)port.maxTotalThreadsPerThreadgroup, (unsigned long)host.maxTotalThreadsPerThreadgroup, @"fresh: maxTotalThreadsPerThreadgroup");
            compare_size(port.requiredThreadsPerThreadgroup, host.requiredThreadsPerThreadgroup, @"fresh: requiredThreadsPerThreadgroup");
            check(host.staticLinkingDescriptor != nil && port.staticLinkingDescriptor != nil, @"fresh: staticLinkingDescriptor is an object on both sides");
            check(host.supportBinaryLinking == port.supportBinaryLinking, @"fresh: supportBinaryLinking");
            /* The tile array is the 11.0 class the port carries, and it answers over the same eight
             * slots Apple's own does - so this asks the port's through Apple's own header. */
            for (NSUInteger index = 0; index < 8; index++)
                check([host.colorAttachments objectAtIndexedSubscript:index] != nil &&
                      [port.colorAttachments objectAtIndexedSubscript:index] != nil,
                      ([NSString stringWithFormat:@"tile colour attachment %lu: both sides answer a descriptor", (unsigned long)index]));
        }

        printf("MTL4MeshRenderPipelineDescriptor\n");
        {
            MTL4MeshRenderPipelineDescriptor *host = [[MTL4MeshRenderPipelineDescriptor alloc] init];
            charonHost_MTL4MeshRenderPipelineDescriptor *port = [[charonHost_MTL4MeshRenderPipelineDescriptor alloc] init];
            check(host.objectFunctionDescriptor == nil && port.objectFunctionDescriptor == nil, @"fresh: objectFunctionDescriptor is nil on both sides");
            check(host.meshFunctionDescriptor == nil && port.meshFunctionDescriptor == nil, @"fresh: meshFunctionDescriptor is nil on both sides");
            check(host.fragmentFunctionDescriptor == nil && port.fragmentFunctionDescriptor == nil, @"fresh: fragmentFunctionDescriptor is nil on both sides");
            same_u((unsigned long)port.maxTotalThreadsPerObjectThreadgroup, (unsigned long)host.maxTotalThreadsPerObjectThreadgroup, @"fresh: maxTotalThreadsPerObjectThreadgroup");
            same_u((unsigned long)port.maxTotalThreadsPerMeshThreadgroup, (unsigned long)host.maxTotalThreadsPerMeshThreadgroup, @"fresh: maxTotalThreadsPerMeshThreadgroup");
            compare_size(port.requiredThreadsPerObjectThreadgroup, host.requiredThreadsPerObjectThreadgroup, @"fresh: requiredThreadsPerObjectThreadgroup");
            compare_size(port.requiredThreadsPerMeshThreadgroup, host.requiredThreadsPerMeshThreadgroup, @"fresh: requiredThreadsPerMeshThreadgroup");
            check(host.objectThreadgroupSizeIsMultipleOfThreadExecutionWidth == port.objectThreadgroupSizeIsMultipleOfThreadExecutionWidth, @"fresh: objectThreadgroupSizeIsMultipleOfThreadExecutionWidth");
            check(host.meshThreadgroupSizeIsMultipleOfThreadExecutionWidth == port.meshThreadgroupSizeIsMultipleOfThreadExecutionWidth, @"fresh: meshThreadgroupSizeIsMultipleOfThreadExecutionWidth");
            same_u((unsigned long)port.payloadMemoryLength, (unsigned long)host.payloadMemoryLength, @"fresh: payloadMemoryLength");
            same_u((unsigned long)port.maxTotalThreadgroupsPerMeshGrid, (unsigned long)host.maxTotalThreadgroupsPerMeshGrid, @"fresh: maxTotalThreadgroupsPerMeshGrid");
            same_u((unsigned long)port.rasterSampleCount, (unsigned long)host.rasterSampleCount, @"fresh: rasterSampleCount");
            same_l((long)port.alphaToCoverageState, (long)host.alphaToCoverageState, @"fresh: alphaToCoverageState");
            same_l((long)port.alphaToOneState, (long)host.alphaToOneState, @"fresh: alphaToOneState");
            check(port.rasterizationEnabled == host.rasterizationEnabled && host.rasterizationEnabled, @"fresh: isRasterizationEnabled is YES on both sides");
            same_u((unsigned long)port.maxVertexAmplificationCount, (unsigned long)host.maxVertexAmplificationCount, @"fresh: maxVertexAmplificationCount");
            check(host.colorAttachments != nil && port.colorAttachments != nil, @"fresh: colorAttachments is an object on both sides");
            check(host.objectStaticLinkingDescriptor != nil && port.objectStaticLinkingDescriptor != nil, @"fresh: objectStaticLinkingDescriptor is an object on both sides");
            check(host.meshStaticLinkingDescriptor != nil && port.meshStaticLinkingDescriptor != nil, @"fresh: meshStaticLinkingDescriptor is an object on both sides");
            check(host.fragmentStaticLinkingDescriptor != nil && port.fragmentStaticLinkingDescriptor != nil, @"fresh: fragmentStaticLinkingDescriptor is an object on both sides");
            check(host.supportObjectBinaryLinking == port.supportObjectBinaryLinking, @"fresh: supportObjectBinaryLinking");
            check(host.supportMeshBinaryLinking == port.supportMeshBinaryLinking, @"fresh: supportMeshBinaryLinking");
            check(host.supportFragmentBinaryLinking == port.supportFragmentBinaryLinking, @"fresh: supportFragmentBinaryLinking");
            same_l((long)port.colorAttachmentMappingState, (long)host.colorAttachmentMappingState, @"fresh: colorAttachmentMappingState");
            same_l((long)port.supportIndirectCommandBuffers, (long)host.supportIndirectCommandBuffers, @"fresh: supportIndirectCommandBuffers");
        }

        printf("MTL4FunctionDescriptor and the three that extend it\n");
        {
            /* The base has no members of its own - MTL4FunctionDescriptor.h declares it and ends - so
             * what is compared is that a fresh one is an object on both sides and that it is the class
             * the three subclasses below inherit from. */
            MTL4FunctionDescriptor *host = [[MTL4FunctionDescriptor alloc] init];
            check(host != nil, @"fresh MTL4FunctionDescriptor is an object, and it has no members to compare");
            check([host isKindOfClass:[NSObject class]], @"and it is an NSObject, as its declaration says");
        }

        printf("%d checks, each one against Apple's own object\n", checks);
    }
    if (failures) { printf("%d failure(s)\n", failures); return 1; }
    printf("all checks passed\n");
    return 0;
}