// CharonMetalProtocols.h — the Metal protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <Metal/Metal.h> for that body, and
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>
@protocol MTL4CommandBuffer;
@protocol MTLResidencySet;

@class MTL4CommitOptions;
@class MTL4CopySparseBufferMappingOperation;
@class MTL4CopySparseTextureMappingOperation;
@class MTL4UpdateSparseBufferMappingOperation;
@class MTL4UpdateSparseTextureMappingOperation;
API_AVAILABLE(ios(26.0))
@protocol MTL4CommandQueue <NSObject>
@property (atomic, readonly) id<MTLDevice> _Nonnull device;
@property (atomic, readonly) NSString * _Nullable label;
- (void)commit:(id<MTL4CommandBuffer>  _Nonnull const * _Nonnull)commandBuffers count:(NSUInteger)count;
- (void)commit:(id<MTL4CommandBuffer>  _Nonnull const * _Nonnull)commandBuffers count:(NSUInteger)count options:(MTL4CommitOptions * _Nonnull)options;
- (void)signalEvent:(id<MTLEvent>  _Nonnull)event value:(uint64_t)value;
- (void)waitForEvent:(id<MTLEvent>  _Nonnull)event value:(uint64_t)value;
- (void)signalDrawable:(id<MTLDrawable>  _Nonnull)drawable;
- (void)waitForDrawable:(id<MTLDrawable>  _Nonnull)drawable;
- (void)addResidencySet:(id<MTLResidencySet>  _Nonnull)residencySet;
- (void)addResidencySets:(id<MTLResidencySet>  _Nonnull const * _Nonnull)residencySets count:(NSUInteger)count;
- (void)removeResidencySet:(id<MTLResidencySet>  _Nonnull)residencySet;
- (void)removeResidencySets:(id<MTLResidencySet>  _Nonnull const * _Nonnull)residencySets count:(NSUInteger)count;
- (void)updateTextureMappings:(id<MTLTexture>  _Nonnull)texture heap:(id<MTLHeap>  _Nullable)heap operations:(const MTL4UpdateSparseTextureMappingOperation * _Nonnull)operations count:(NSUInteger)count;
- (void)copyTextureMappingsFromTexture:(id<MTLTexture>  _Nonnull)sourceTexture toTexture:(id<MTLTexture>  _Nonnull)destinationTexture operations:(const MTL4CopySparseTextureMappingOperation * _Nonnull)operations count:(NSUInteger)count;
- (void)updateBufferMappings:(id<MTLBuffer>  _Nonnull)buffer heap:(id<MTLHeap>  _Nullable)heap operations:(const MTL4UpdateSparseBufferMappingOperation * _Nonnull)operations count:(NSUInteger)count;
- (void)copyBufferMappingsFromBuffer:(id<MTLBuffer>  _Nonnull)sourceBuffer toBuffer:(id<MTLBuffer>  _Nonnull)destinationBuffer operations:(const MTL4CopySparseBufferMappingOperation * _Nonnull)operations count:(NSUInteger)count;
@end

@protocol MTLAccelerationStructure;

@protocol MTLAccelerationStructureCommandEncoder;

@protocol MTLBinaryArchive;

@protocol MTLBinding;

@protocol MTLBlitCommandEncoder;

@protocol MTLBufferBinding;

@protocol MTLCaptureScope;

@protocol MTLCommandBufferEncoderInfo;

@protocol MTLComputeCommandEncoder;

@protocol MTLComputePipelineState;

@protocol MTLCounter;

@protocol MTLCounterSampleBuffer;

@protocol MTLCounterSet;

@protocol MTLDepthStencilState;

@protocol MTLDrawable;

@protocol MTLDynamicLibrary;

@protocol MTLFunction;

@protocol MTLFunctionHandle;

@protocol MTLFunctionLog;

@protocol MTLFunctionLogDebugLocation;

@protocol MTLFunctionStitchingAttribute;

@protocol MTLFunctionStitchingNode;

@protocol MTLHeap;

@protocol MTLIntersectionFunctionTable;

@protocol MTLLogContainer;

@protocol MTLObjectPayloadBinding;

@protocol MTLResource;

@protocol MTLSamplerState;

@protocol MTLSharedEvent;

@protocol MTLTextureBinding;

@protocol MTLThreadgroupBinding;

@protocol MTLVisibleFunctionTable;
