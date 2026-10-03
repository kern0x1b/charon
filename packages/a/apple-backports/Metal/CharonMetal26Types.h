// CharonMetal26Types.h - the Metal 4 declarations this package's own sources compile against,
// transcribed from the SDK that declares them.
//
// The backports of this package build against the SDK of iOS 16.4, which has no MTL4* type at all:
// Metal 4 arrived with the SDK of iOS 26. An @implementation declares the class it implements, so the
// body needs nothing from here - but @synthesize and a method signature above the definition need a
// DECLARATION, and that is what this file is: the class, its base, the members with their attributes
// and types, and API_AVAILABLE(ios(26.0)) so a band places the row by the release it arrived in.
//
// Facts only, the rule tools/transcribe-protocols.py works by: a name, a kind, a type, an attribute.
// No header text and no comment of Apple's is copied, and every enumeration case below is the value
// the 26.2 header gives.
//
// It also carries the ENUMERATIONS those members use, because a source cannot name a case of an
// enumeration the SDK it compiles against does not declare. MTLShaderValidation arrived with the SDK of
// iOS 18 and the MTL4* enumerations with the SDK of iOS 26; both are below with the values the header
// gives.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

// EVERY DECLARATION BELOW IS CONDITIONAL, and the condition is the SDK this file is compiled against
// rather than the release a row is about. The package builds against the SDK of iOS 16.4, which has
// none of these; a host differential builds against the SDK of macOS 26, which has ALL of them, and a
// header that redeclared what its own <Metal/Metal.h> already declares is a redefinition error - so
// the header says what it is for: "what the SDK this compiles against does not declare".
//
// The version is read from whichever of the two macros the target defines. A target that defines
// neither gets 0, which takes every block: declaring is the answer that lets a DEVICE build compile,
// and such a target is not one a host differential uses.
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED)
#define CHARON_METAL_SDK_MAX __IPHONE_OS_VERSION_MAX_ALLOWED
#elif defined(__MAC_OS_X_VERSION_MAX_ALLOWED)
#define CHARON_METAL_SDK_MAX __MAC_OS_X_VERSION_MAX_ALLOWED
#else
#define CHARON_METAL_SDK_MAX 0
#endif

#if CHARON_METAL_SDK_MAX < 260000
// ONE PROTOCOL IS HERE RATHER THAN IN CharonMetalProtocols.h, and the reason is which tool writes
// each: that file is written by tools/transcribe-protocols.py, so a protocol written into it by hand
// is one a regeneration would collide with. MTL4BinaryFunction is Metal 4's own
// (MTL4BinaryFunction.h:24), it is named by three of the members below, and no source in this folder
// reads its members - the descriptor family only holds arrays of id<MTL4BinaryFunction> - so the two
// members are here for the archive family to use and nothing here depends on them.
@protocol MTL4BinaryFunction <NSObject>
@property (nullable, readonly) NSString *name;
@property (readonly) MTLFunctionType functionType;
@end

// MTLPipeline.h:26 - whether Metal shader validation runs for the pipeline.
#if CHARON_METAL_SDK_MAX < 180000
API_AVAILABLE(ios(18.0))
typedef NS_ENUM(NSInteger, MTLShaderValidation) {
    MTLShaderValidationDefault  = 0,
    MTLShaderValidationEnabled  = 1,
    MTLShaderValidationDisabled = 2,
};
#endif

// MTL4PipelineState.h:21
#if CHARON_METAL_SDK_MAX < 260000
API_AVAILABLE(ios(26.0))
typedef NS_OPTIONS(NSUInteger, MTL4ShaderReflection) {
    MTL4ShaderReflectionNone           = 0,
    MTL4ShaderReflectionBindingInfo    = 1 << 0,
    MTL4ShaderReflectionBufferTypeInfo = 1 << 1,
};

// MTL4PipelineState.h:34
API_AVAILABLE(ios(26.0))
typedef NS_ENUM(NSInteger, MTL4AlphaToOneState) {
    MTL4AlphaToOneStateDisabled = 0,
    MTL4AlphaToOneStateEnabled  = 1,
};

// MTL4PipelineState.h:45
API_AVAILABLE(ios(26.0))
typedef NS_ENUM(NSInteger, MTL4AlphaToCoverageState) {
    MTL4AlphaToCoverageStateDisabled = 0,
    MTL4AlphaToCoverageStateEnabled  = 1,
};

// MTL4PipelineState.h:60
API_AVAILABLE(ios(26.0))
typedef NS_ENUM(NSInteger, MTL4BlendState) {
    MTL4BlendStateDisabled     = 0,
    MTL4BlendStateEnabled      = 1,
    MTL4BlendStateUnspecialized = 2,
};

// MTL4PipelineState.h:70
API_AVAILABLE(ios(26.0))
typedef NS_ENUM(NSInteger, MTL4IndirectCommandBufferSupportState) {
    MTL4IndirectCommandBufferSupportStateDisabled = 0,
    MTL4IndirectCommandBufferSupportStateEnabled  = 1,
};

// MTL4RenderPipeline.h:35
API_AVAILABLE(ios(26.0))
typedef NS_ENUM(NSInteger, MTL4LogicalToPhysicalColorAttachmentMappingState) {
    MTL4LogicalToPhysicalColorAttachmentMappingStateIdentity  = 0,
    MTL4LogicalToPhysicalColorAttachmentMappingStateInherited = 1,
};
#endif

// THE PROTOCOL AND THE CLASSES. Metal 4's own, so the same condition as the enumerations above; the
// protocol is inside the class block because it is only named by the members there.

// THE CLASSES, as the 26.2 headers declare them. MTL4FunctionDescriptor has no members of its own -
// MTL4FunctionDescriptor.h declares it and ends - so it is the base the three subclasses below extend
// and the port carries it as exactly that.

API_AVAILABLE(ios(26.0))
@interface MTL4FunctionDescriptor : NSObject <NSCopying>
@end

API_AVAILABLE(ios(26.0))
@interface MTL4PipelineOptions : NSObject <NSCopying>
@property (readwrite, nonatomic) MTLShaderValidation shaderValidation;
@property (readwrite, nonatomic) MTL4ShaderReflection shaderReflection;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4StaticLinkingDescriptor : NSObject <NSCopying>
@property (readwrite, nonatomic, copy, nullable) NSArray<MTL4FunctionDescriptor *> *functionDescriptors;
@property (readwrite, nonatomic, copy, nullable) NSArray<MTL4FunctionDescriptor *> *privateFunctionDescriptors;
@property (readwrite, nonatomic, copy, nullable) NSDictionary<NSString *, NSArray<MTL4FunctionDescriptor *> *> *groups;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4PipelineStageDynamicLinkingDescriptor : NSObject <NSCopying>
@property (readwrite, nonatomic) NSUInteger maxCallStackDepth;
@property (readwrite, nonatomic, copy, nullable) NSArray<id<MTL4BinaryFunction>> *binaryLinkedFunctions;
@property (readwrite, nonatomic, copy) NSArray<id<MTLDynamicLibrary>> *preloadedLibraries;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4RenderPipelineDynamicLinkingDescriptor : NSObject <NSCopying>
@property (readonly, nonatomic) MTL4PipelineStageDynamicLinkingDescriptor *vertexLinkingDescriptor;
@property (readonly, nonatomic) MTL4PipelineStageDynamicLinkingDescriptor *fragmentLinkingDescriptor;
@property (readonly, nonatomic) MTL4PipelineStageDynamicLinkingDescriptor *tileLinkingDescriptor;
@property (readonly, nonatomic) MTL4PipelineStageDynamicLinkingDescriptor *objectLinkingDescriptor;
@property (readonly, nonatomic) MTL4PipelineStageDynamicLinkingDescriptor *meshLinkingDescriptor;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4RenderPipelineBinaryFunctionsDescriptor : NSObject <NSCopying>
@property (nullable, nonatomic, copy) NSArray<id<MTL4BinaryFunction>> *vertexAdditionalBinaryFunctions;
@property (nullable, nonatomic, copy) NSArray<id<MTL4BinaryFunction>> *fragmentAdditionalBinaryFunctions;
@property (nullable, nonatomic, copy) NSArray<id<MTL4BinaryFunction>> *tileAdditionalBinaryFunctions;
@property (nullable, nonatomic, copy) NSArray<id<MTL4BinaryFunction>> *objectAdditionalBinaryFunctions;
@property (nullable, nonatomic, copy) NSArray<id<MTL4BinaryFunction>> *meshAdditionalBinaryFunctions;
- (void)reset;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4RenderPipelineColorAttachmentDescriptor : NSObject <NSCopying>
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

API_AVAILABLE(ios(26.0))
@interface MTL4RenderPipelineColorAttachmentDescriptorArray : NSObject <NSCopying>
- (MTL4RenderPipelineColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)attachmentIndex;
- (void)setObject:(nullable MTL4RenderPipelineColorAttachmentDescriptor *)attachment atIndexedSubscript:(NSUInteger)attachmentIndex;
- (void)reset;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4PipelineDescriptor : NSObject <NSCopying>
@property (nullable, copy, nonatomic) NSString *label;
@property (nullable, readwrite, nonatomic, retain) MTL4PipelineOptions *options;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4RenderPipelineDescriptor : MTL4PipelineDescriptor
@property (nullable, readwrite, nonatomic, copy) MTL4FunctionDescriptor *vertexFunctionDescriptor;
@property (nullable, readwrite, nonatomic, copy) MTL4FunctionDescriptor *fragmentFunctionDescriptor;
@property (nullable, nonatomic, copy) MTLVertexDescriptor *vertexDescriptor;
@property (readwrite, nonatomic) NSUInteger rasterSampleCount;
@property (readwrite, nonatomic) MTL4AlphaToCoverageState alphaToCoverageState;
@property (readwrite, nonatomic) MTL4AlphaToOneState alphaToOneState;
@property (readwrite, nonatomic, getter=isRasterizationEnabled) BOOL rasterizationEnabled;
@property (readwrite, nonatomic) NSUInteger maxVertexAmplificationCount;
@property (readonly) MTL4RenderPipelineColorAttachmentDescriptorArray *colorAttachments;
@property (readwrite, nonatomic) MTLPrimitiveTopologyClass inputPrimitiveTopology;
@property (null_resettable, copy, nonatomic) MTL4StaticLinkingDescriptor *vertexStaticLinkingDescriptor;
@property (null_resettable, copy, nonatomic) MTL4StaticLinkingDescriptor *fragmentStaticLinkingDescriptor;
@property (readwrite, nonatomic) BOOL supportVertexBinaryLinking;
@property (readwrite, nonatomic) BOOL supportFragmentBinaryLinking;
@property (readwrite, nonatomic) MTL4LogicalToPhysicalColorAttachmentMappingState colorAttachmentMappingState;
@property (readwrite, nonatomic) MTL4IndirectCommandBufferSupportState supportIndirectCommandBuffers;
- (void)reset;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4ComputePipelineDescriptor : MTL4PipelineDescriptor
@property (nullable, readwrite, nonatomic, copy) MTL4FunctionDescriptor *computeFunctionDescriptor;
@property (readwrite, nonatomic) BOOL threadGroupSizeIsMultipleOfThreadExecutionWidth;
@property (readwrite, nonatomic) NSUInteger maxTotalThreadsPerThreadgroup;
@property (readwrite, nonatomic) MTLSize requiredThreadsPerThreadgroup;
@property (readwrite, nonatomic) BOOL supportBinaryLinking;
@property (nullable, copy, nonatomic) MTL4StaticLinkingDescriptor *staticLinkingDescriptor;
@property (readwrite, nonatomic) MTL4IndirectCommandBufferSupportState supportIndirectCommandBuffers;
- (void)reset;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4TileRenderPipelineDescriptor : MTL4PipelineDescriptor
@property (nullable, readwrite, nonatomic, copy) MTL4FunctionDescriptor *tileFunctionDescriptor;
@property (readwrite, nonatomic) NSUInteger rasterSampleCount;
@property (readonly) MTLTileRenderPipelineColorAttachmentDescriptorArray *colorAttachments;
@property (readwrite, nonatomic) BOOL threadgroupSizeMatchesTileSize;
@property (readwrite, nonatomic) NSUInteger maxTotalThreadsPerThreadgroup;
@property (readwrite, nonatomic) MTLSize requiredThreadsPerThreadgroup;
@property (null_resettable, copy, nonatomic) MTL4StaticLinkingDescriptor *staticLinkingDescriptor;
@property (readwrite, nonatomic) BOOL supportBinaryLinking;
- (void)reset;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4MeshRenderPipelineDescriptor : MTL4PipelineDescriptor
@property (nullable, readwrite, nonatomic, copy) MTL4FunctionDescriptor *objectFunctionDescriptor;
@property (nullable, readwrite, nonatomic, copy) MTL4FunctionDescriptor *meshFunctionDescriptor;
@property (nullable, readwrite, nonatomic, copy) MTL4FunctionDescriptor *fragmentFunctionDescriptor;
@property (readwrite, nonatomic) NSUInteger maxTotalThreadsPerObjectThreadgroup;
@property (readwrite, nonatomic) NSUInteger maxTotalThreadsPerMeshThreadgroup;
@property (readwrite, nonatomic) MTLSize requiredThreadsPerObjectThreadgroup;
@property (readwrite, nonatomic) MTLSize requiredThreadsPerMeshThreadgroup;
@property (readwrite, nonatomic) BOOL objectThreadgroupSizeIsMultipleOfThreadExecutionWidth;
@property (readwrite, nonatomic) BOOL meshThreadgroupSizeIsMultipleOfThreadExecutionWidth;
@property (readwrite, nonatomic) NSUInteger payloadMemoryLength;
@property (readwrite, nonatomic) NSUInteger maxTotalThreadgroupsPerMeshGrid;
@property (readwrite, nonatomic) NSUInteger rasterSampleCount;
@property (readwrite, nonatomic) MTL4AlphaToCoverageState alphaToCoverageState;
@property (readwrite, nonatomic) MTL4AlphaToOneState alphaToOneState;
@property (readwrite, nonatomic, getter=isRasterizationEnabled) BOOL rasterizationEnabled;
@property (readwrite, nonatomic) NSUInteger maxVertexAmplificationCount;
@property (readonly) MTL4RenderPipelineColorAttachmentDescriptorArray *colorAttachments;
@property (null_resettable, copy, nonatomic) MTL4StaticLinkingDescriptor *objectStaticLinkingDescriptor;
@property (null_resettable, copy, nonatomic) MTL4StaticLinkingDescriptor *meshStaticLinkingDescriptor;
@property (null_resettable, copy, nonatomic) MTL4StaticLinkingDescriptor *fragmentStaticLinkingDescriptor;
@property (readwrite, nonatomic) BOOL supportObjectBinaryLinking;
@property (readwrite, nonatomic) BOOL supportMeshBinaryLinking;
@property (readwrite, nonatomic) BOOL supportFragmentBinaryLinking;
@property (readwrite, nonatomic) MTL4LogicalToPhysicalColorAttachmentMappingState colorAttachmentMappingState;
@property (readwrite, nonatomic) MTL4IndirectCommandBufferSupportState supportIndirectCommandBuffers;
- (void)reset;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4SpecializedFunctionDescriptor : MTL4FunctionDescriptor
@property (nullable, copy, readwrite, nonatomic) MTL4FunctionDescriptor *functionDescriptor;
@property (nullable, copy, atomic) NSString *specializedName;
@property (nullable, copy, nonatomic) MTLFunctionConstantValues *constantValues;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4StitchedFunctionDescriptor : MTL4FunctionDescriptor
@property (nullable, copy, nonatomic) MTLFunctionStitchingGraph *functionGraph;
@property (nullable, copy, nonatomic) NSArray<MTL4FunctionDescriptor *> *functionDescriptors;
@end

API_AVAILABLE(ios(26.0))
@interface MTL4LibraryFunctionDescriptor : MTL4FunctionDescriptor
@property (nullable, copy, atomic) NSString *name;
@property (nullable, readwrite, nonatomic, retain) id<MTLLibrary> library;
@end
#endif

NS_ASSUME_NONNULL_END
