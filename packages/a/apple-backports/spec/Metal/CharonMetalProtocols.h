// CharonMetalProtocols.h - the Metal protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <Metal/Metal.h> for that body, and
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>
#import "CharonMetal26Types.h"

@class MTL4BinaryFunctionDescriptor;
@class MTL4ComputePipelineDescriptor;
@class MTL4PipelineDescriptor;
@class MTL4PipelineStageDynamicLinkingDescriptor;
@class MTL4RenderPipelineDynamicLinkingDescriptor;
API_AVAILABLE(ios(26.0))
@protocol MTL4Archive <NSObject>
@property (atomic, readwrite, copy) NSString * _Nullable label;
- (id<MTLComputePipelineState> _Nullable)newComputePipelineStateWithDescriptor:(MTL4ComputePipelineDescriptor * _Nonnull)descriptor error:(NSError *  _Nullable * _Nullable)error;
- (id<MTLComputePipelineState> _Nullable)newComputePipelineStateWithDescriptor:(MTL4ComputePipelineDescriptor * _Nonnull)descriptor dynamicLinkingDescriptor:(MTL4PipelineStageDynamicLinkingDescriptor * _Nonnull)dynamicLinkingDescriptor error:(NSError *  _Nullable * _Nullable)error;
- (id<MTLRenderPipelineState> _Nullable)newRenderPipelineStateWithDescriptor:(MTL4PipelineDescriptor * _Nonnull)descriptor error:(NSError *  _Nullable * _Nullable)error;
- (id<MTLRenderPipelineState> _Nullable)newRenderPipelineStateWithDescriptor:(MTL4PipelineDescriptor * _Nonnull)descriptor dynamicLinkingDescriptor:(MTL4RenderPipelineDynamicLinkingDescriptor * _Nonnull)dynamicLinkingDescriptor error:(NSError *  _Nullable * _Nullable)error;
- (id<MTL4BinaryFunction> _Nullable)newBinaryFunctionWithDescriptor:(MTL4BinaryFunctionDescriptor * _Nonnull)descriptor error:(NSError *  _Nullable * _Nullable)error;
@end

@class MTLGPUAddress;
API_AVAILABLE(ios(26.0))
@protocol MTL4ArgumentTable <NSObject>
- (void)setAddress:(MTLGPUAddress)gpuAddress atIndex:(NSUInteger)bindingIndex;
- (void)setAddress:(MTLGPUAddress)gpuAddress attributeStride:(NSUInteger)stride atIndex:(NSUInteger)bindingIndex;
- (void)setResource:(MTLResourceID)resourceID atBufferIndex:(NSUInteger)bindingIndex;
- (void)setTexture:(MTLResourceID)resourceID atIndex:(NSUInteger)bindingIndex;
- (void)setSamplerState:(MTLResourceID)resourceID atIndex:(NSUInteger)bindingIndex;
@property (atomic, readonly) id<MTLDevice> _Nonnull device;
@property (nonatomic, readonly) NSString * _Nullable label;
@end

@protocol MTL4BinaryFunction;

API_AVAILABLE(ios(26.0))
@protocol MTL4CommandAllocator <NSObject>
@property (atomic, readonly) id<MTLDevice> _Nonnull device;
@property (atomic, readonly) NSString * _Nullable label;
- (uint64_t)allocatedSize;
- (void)reset;
@end

typedef struct MTL4BufferRange MTL4BufferRange;
@class MTL4CommandBufferOptions;
typedef enum MTL4RenderEncoderOptions MTL4RenderEncoderOptions;
@class MTL4RenderPassDescriptor;
API_AVAILABLE(ios(26.0))
@protocol MTL4CommandBuffer <NSObject>
@property (atomic, readonly) id<MTLDevice> _Nonnull device;
@property (atomic, readwrite, copy) NSString * _Nullable label;
- (void)beginCommandBufferWithAllocator:(id<MTL4CommandAllocator>  _Nonnull)allocator;
- (void)beginCommandBufferWithAllocator:(id<MTL4CommandAllocator>  _Nonnull)allocator options:(MTL4CommandBufferOptions * _Nonnull)options;
- (void)endCommandBuffer;
- (id<MTL4RenderCommandEncoder> _Nullable)renderCommandEncoderWithDescriptor:(MTL4RenderPassDescriptor * _Nonnull)descriptor;
- (id<MTL4RenderCommandEncoder> _Nullable)renderCommandEncoderWithDescriptor:(MTL4RenderPassDescriptor * _Nonnull)descriptor options:(MTL4RenderEncoderOptions)options;
- (id<MTL4ComputeCommandEncoder> _Nullable)computeCommandEncoder;
- (id<MTL4MachineLearningCommandEncoder> _Nullable)machineLearningCommandEncoder;
- (void)useResidencySet:(id<MTLResidencySet>  _Nonnull)residencySet;
- (void)useResidencySets:(id<MTLResidencySet>  _Nonnull const * _Nonnull)residencySets count:(NSUInteger)count;
- (void)pushDebugGroup:(NSString * _Nonnull)string;
- (void)popDebugGroup;
- (void)writeTimestampIntoHeap:(id<MTL4CounterHeap>  _Nonnull)counterHeap atIndex:(NSUInteger)index;
- (void)resolveCounterHeap:(id<MTL4CounterHeap>  _Nonnull)counterHeap withRange:(NSRange)range intoBuffer:(MTL4BufferRange)bufferRange waitFence:(id<MTLFence>  _Nullable)fenceToWait updateFence:(id<MTLFence>  _Nullable)fenceToUpdate;
@end

typedef enum MTL4VisibilityOptions MTL4VisibilityOptions;
typedef enum MTLStages MTLStages;
API_AVAILABLE(ios(26.0))
@protocol MTL4CommandEncoder <NSObject>
@property (atomic, readwrite, copy) NSString * _Nullable label;
@property (nonatomic, readonly) id<MTL4CommandBuffer> _Nullable commandBuffer;
- (void)barrierAfterQueueStages:(MTLStages)afterQueueStages beforeStages:(MTLStages)beforeStages visibilityOptions:(MTL4VisibilityOptions)visibilityOptions;
- (void)barrierAfterStages:(MTLStages)afterStages beforeQueueStages:(MTLStages)beforeQueueStages visibilityOptions:(MTL4VisibilityOptions)visibilityOptions;
- (void)barrierAfterEncoderStages:(MTLStages)afterEncoderStages beforeEncoderStages:(MTLStages)beforeEncoderStages visibilityOptions:(MTL4VisibilityOptions)visibilityOptions;
- (void)updateFence:(id<MTLFence>  _Nonnull)fence afterEncoderStages:(MTLStages)afterEncoderStages;
- (void)waitForFence:(id<MTLFence>  _Nonnull)fence beforeEncoderStages:(MTLStages)beforeEncoderStages;
- (void)insertDebugSignpost:(NSString * _Nonnull)string;
- (void)pushDebugGroup:(NSString * _Nonnull)string;
- (void)popDebugGroup;
- (void)endEncoding;
@end

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

API_AVAILABLE(ios(26.0))
@protocol MTL4CommitFeedback <NSObject>
@property (nonatomic, readonly) NSError * _Nullable error;
@property (nonatomic, readonly) CFTimeInterval GPUStartTime;
@property (nonatomic, readonly) CFTimeInterval GPUEndTime;
@end

@class MTL4BinaryFunctionDescriptor;
@class MTL4CompilerTaskOptions;
@class MTL4ComputePipelineDescriptor;
@class MTL4LibraryDescriptor;
@class MTL4MachineLearningPipelineDescriptor;
@class MTL4NewBinaryFunctionCompletionHandler;
@class MTL4NewMachineLearningPipelineStateCompletionHandler;
@class MTL4PipelineDescriptor;
@class MTL4PipelineStageDynamicLinkingDescriptor;
@class MTL4RenderPipelineDynamicLinkingDescriptor;
@class MTLNewDynamicLibraryCompletionHandler;
API_AVAILABLE(ios(26.0))
@protocol MTL4Compiler <NSObject>
@property (atomic, readonly) id<MTLDevice> _Nonnull device;
@property (atomic, readonly) NSString * _Nullable label;
@property (atomic, readonly, strong) id<MTL4PipelineDataSetSerializer> _Nullable pipelineDataSetSerializer;
- (id<MTLLibrary> _Nullable)newLibraryWithDescriptor:(MTL4LibraryDescriptor * _Nonnull)descriptor error:(NSError *  _Nullable * _Nullable)error;
- (id<MTLDynamicLibrary> _Nullable)newDynamicLibrary:(id<MTLLibrary>  _Nonnull)library error:(NSError *  _Nullable * _Nullable)error;
- (id<MTLDynamicLibrary> _Nullable)newDynamicLibraryWithURL:(NSURL * _Nonnull)url error:(NSError *  _Nullable * _Nullable)error;
- (id<MTLComputePipelineState> _Nullable)newComputePipelineStateWithDescriptor:(MTL4ComputePipelineDescriptor * _Nonnull)descriptor compilerTaskOptions:(MTL4CompilerTaskOptions * _Nullable)compilerTaskOptions error:(NSError *  _Nullable * _Nullable)error;
- (id<MTLComputePipelineState> _Nullable)newComputePipelineStateWithDescriptor:(MTL4ComputePipelineDescriptor * _Nonnull)descriptor dynamicLinkingDescriptor:(MTL4PipelineStageDynamicLinkingDescriptor * _Nullable)dynamicLinkingDescriptor compilerTaskOptions:(MTL4CompilerTaskOptions * _Nullable)compilerTaskOptions error:(NSError *  _Nullable * _Nullable)error;
- (id<MTLRenderPipelineState> _Nullable)newRenderPipelineStateWithDescriptor:(MTL4PipelineDescriptor * _Nonnull)descriptor compilerTaskOptions:(MTL4CompilerTaskOptions * _Nullable)compilerTaskOptions error:(NSError *  _Nullable * _Nullable)error;
- (id<MTLRenderPipelineState> _Nullable)newRenderPipelineStateWithDescriptor:(MTL4PipelineDescriptor * _Nonnull)descriptor dynamicLinkingDescriptor:(MTL4RenderPipelineDynamicLinkingDescriptor * _Nullable)dynamicLinkingDescriptor compilerTaskOptions:(MTL4CompilerTaskOptions * _Nullable)compilerTaskOptions error:(NSError *  _Nullable * _Nullable)error;
- (id<MTLRenderPipelineState> _Nullable)newRenderPipelineStateBySpecializationWithDescriptor:(MTL4PipelineDescriptor * _Nonnull)descriptor pipeline:(id<MTLRenderPipelineState>  _Nonnull)pipeline error:(NSError *  _Nullable * _Nullable)error;
- (id<MTL4BinaryFunction> _Nullable)newBinaryFunctionWithDescriptor:(MTL4BinaryFunctionDescriptor * _Nonnull)descriptor compilerTaskOptions:(MTL4CompilerTaskOptions * _Nullable)compilerTaskOptions error:(NSError *  _Nullable * _Nullable)error;
- (id<MTL4CompilerTask> _Nonnull)newLibraryWithDescriptor:(MTL4LibraryDescriptor * _Nonnull)descriptor completionHandler:(MTLNewLibraryCompletionHandler  _Nonnull)completionHandler;
- (id<MTL4CompilerTask> _Nonnull)newDynamicLibrary:(id<MTLLibrary>  _Nonnull)library completionHandler:(MTLNewDynamicLibraryCompletionHandler  _Nonnull)completionHandler;
- (id<MTL4CompilerTask> _Nonnull)newDynamicLibraryWithURL:(NSURL * _Nonnull)url completionHandler:(MTLNewDynamicLibraryCompletionHandler  _Nonnull)completionHandler;
- (id<MTL4CompilerTask> _Nonnull)newComputePipelineStateWithDescriptor:(MTL4ComputePipelineDescriptor * _Nonnull)descriptor compilerTaskOptions:(MTL4CompilerTaskOptions * _Nullable)compilerTaskOptions completionHandler:(MTLNewComputePipelineStateCompletionHandler  _Nonnull)completionHandler;
- (id<MTL4CompilerTask> _Nonnull)newComputePipelineStateWithDescriptor:(MTL4ComputePipelineDescriptor * _Nonnull)descriptor dynamicLinkingDescriptor:(MTL4PipelineStageDynamicLinkingDescriptor * _Nullable)dynamicLinkingDescriptor compilerTaskOptions:(MTL4CompilerTaskOptions * _Nullable)compilerTaskOptions completionHandler:(MTLNewComputePipelineStateCompletionHandler  _Nonnull)completionHandler;
- (id<MTL4CompilerTask> _Nonnull)newRenderPipelineStateWithDescriptor:(MTL4PipelineDescriptor * _Nonnull)descriptor compilerTaskOptions:(MTL4CompilerTaskOptions * _Nullable)compilerTaskOptions completionHandler:(MTLNewRenderPipelineStateCompletionHandler  _Nonnull)completionHandler;
- (id<MTL4CompilerTask> _Nonnull)newRenderPipelineStateWithDescriptor:(MTL4PipelineDescriptor * _Nonnull)descriptor dynamicLinkingDescriptor:(MTL4RenderPipelineDynamicLinkingDescriptor * _Nullable)dynamicLinkingDescriptor compilerTaskOptions:(MTL4CompilerTaskOptions * _Nullable)compilerTaskOptions completionHandler:(MTLNewRenderPipelineStateCompletionHandler  _Nonnull)completionHandler;
- (id<MTL4CompilerTask> _Nonnull)newRenderPipelineStateBySpecializationWithDescriptor:(MTL4PipelineDescriptor * _Nonnull)descriptor pipeline:(id<MTLRenderPipelineState>  _Nonnull)pipeline completionHandler:(MTLNewRenderPipelineStateCompletionHandler  _Nonnull)completionHandler;
- (id<MTL4CompilerTask> _Nonnull)newBinaryFunctionWithDescriptor:(MTL4BinaryFunctionDescriptor * _Nonnull)descriptor compilerTaskOptions:(MTL4CompilerTaskOptions * _Nullable)compilerTaskOptions completionHandler:(MTL4NewBinaryFunctionCompletionHandler  _Nonnull)completionHandler;
- (id<MTL4MachineLearningPipelineState> _Nullable)newMachineLearningPipelineStateWithDescriptor:(MTL4MachineLearningPipelineDescriptor * _Nonnull)descriptor error:(NSError *  _Nullable * _Nullable)error;
- (id<MTL4CompilerTask> _Nonnull)newMachineLearningPipelineStateWithDescriptor:(MTL4MachineLearningPipelineDescriptor * _Nonnull)descriptor completionHandler:(MTL4NewMachineLearningPipelineStateCompletionHandler  _Nonnull)completionHandler;
@end

typedef enum MTL4CompilerTaskStatus MTL4CompilerTaskStatus;
API_AVAILABLE(ios(26.0))
@protocol MTL4CompilerTask <NSObject>
@property (atomic, readonly) id<MTL4Compiler> _Nonnull compiler;
@property (atomic, readonly) MTL4CompilerTaskStatus status;
- (void)waitUntilCompleted;
@end

@class MTL4AccelerationStructureDescriptor;
typedef struct MTL4BufferRange MTL4BufferRange;
typedef enum MTL4TimestampGranularity MTL4TimestampGranularity;
@class MTLGPUAddress;
typedef enum MTLStages MTLStages;
@class MTLTensorExtents;
API_AVAILABLE(ios(26.0))
@protocol MTL4ComputeCommandEncoder <MTL4CommandEncoder>
- (MTLStages)stages;
- (void)setComputePipelineState:(id<MTLComputePipelineState>  _Nonnull)state;
- (void)setThreadgroupMemoryLength:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)setImageblockWidth:(NSUInteger)width height:(NSUInteger)height;
- (void)dispatchThreads:(MTLSize)threadsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup;
- (void)dispatchThreadgroups:(MTLSize)threadgroupsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup;
- (void)dispatchThreadgroupsWithIndirectBuffer:(MTLGPUAddress)indirectBuffer threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup;
- (void)dispatchThreadsWithIndirectBuffer:(MTLGPUAddress)indirectBuffer;
- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>  _Nonnull)indirectCommandBuffer withRange:(NSRange)executionRange;
- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>  _Nonnull)indirectCommandbuffer indirectBuffer:(MTLGPUAddress)indirectRangeBuffer;
- (void)copyFromTexture:(id<MTLTexture>  _Nonnull)sourceTexture toTexture:(id<MTLTexture>  _Nonnull)destinationTexture;
- (void)copyFromTexture:(id<MTLTexture>  _Nonnull)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel toTexture:(id<MTLTexture>  _Nonnull)destinationTexture destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel sliceCount:(NSUInteger)sliceCount levelCount:(NSUInteger)levelCount;
- (void)copyFromTexture:(id<MTLTexture>  _Nonnull)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>  _Nonnull)destinationTexture destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin;
- (void)copyFromTexture:(id<MTLTexture>  _Nonnull)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toBuffer:(id<MTLBuffer>  _Nonnull)destinationBuffer destinationOffset:(NSUInteger)destinationOffset destinationBytesPerRow:(NSUInteger)destinationBytesPerRow destinationBytesPerImage:(NSUInteger)destinationBytesPerImage;
- (void)copyFromTexture:(id<MTLTexture>  _Nonnull)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toBuffer:(id<MTLBuffer>  _Nonnull)destinationBuffer destinationOffset:(NSUInteger)destinationOffset destinationBytesPerRow:(NSUInteger)destinationBytesPerRow destinationBytesPerImage:(NSUInteger)destinationBytesPerImage options:(MTLBlitOption)options;
- (void)copyFromBuffer:(id<MTLBuffer>  _Nonnull)sourceBuffer sourceOffset:(NSUInteger)sourceOffset toBuffer:(id<MTLBuffer>  _Nonnull)destinationBuffer destinationOffset:(NSUInteger)destinationOffset size:(NSUInteger)size;
- (void)copyFromBuffer:(id<MTLBuffer>  _Nonnull)sourceBuffer sourceOffset:(NSUInteger)sourceOffset sourceBytesPerRow:(NSUInteger)sourceBytesPerRow sourceBytesPerImage:(NSUInteger)sourceBytesPerImage sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>  _Nonnull)destinationTexture destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin;
- (void)copyFromBuffer:(id<MTLBuffer>  _Nonnull)sourceBuffer sourceOffset:(NSUInteger)sourceOffset sourceBytesPerRow:(NSUInteger)sourceBytesPerRow sourceBytesPerImage:(NSUInteger)sourceBytesPerImage sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>  _Nonnull)destinationTexture destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin options:(MTLBlitOption)options;
- (void)copyFromTensor:(id<MTLTensor>  _Nonnull)sourceTensor sourceOrigin:(MTLTensorExtents * _Nonnull)sourceOrigin sourceDimensions:(MTLTensorExtents * _Nonnull)sourceDimensions toTensor:(id<MTLTensor>  _Nonnull)destinationTensor destinationOrigin:(MTLTensorExtents * _Nonnull)destinationOrigin destinationDimensions:(MTLTensorExtents * _Nonnull)destinationDimensions;
- (void)generateMipmapsForTexture:(id<MTLTexture>  _Nonnull)texture;
- (void)fillBuffer:(id<MTLBuffer>  _Nonnull)buffer range:(NSRange)range value:(uint8_t)value;
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>  _Nonnull)texture;
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>  _Nonnull)texture slice:(NSUInteger)slice level:(NSUInteger)level;
- (void)optimizeContentsForCPUAccess:(id<MTLTexture>  _Nonnull)texture;
- (void)optimizeContentsForCPUAccess:(id<MTLTexture>  _Nonnull)texture slice:(NSUInteger)slice level:(NSUInteger)level;
- (void)resetCommandsInBuffer:(id<MTLIndirectCommandBuffer>  _Nonnull)buffer withRange:(NSRange)range;
- (void)copyIndirectCommandBuffer:(id<MTLIndirectCommandBuffer>  _Nonnull)source sourceRange:(NSRange)sourceRange destination:(id<MTLIndirectCommandBuffer>  _Nonnull)destination destinationIndex:(NSUInteger)destinationIndex;
- (void)optimizeIndirectCommandBuffer:(id<MTLIndirectCommandBuffer>  _Nonnull)indirectCommandBuffer withRange:(NSRange)range;
- (void)setArgumentTable:(id<MTL4ArgumentTable>  _Nullable)argumentTable;
- (void)buildAccelerationStructure:(id<MTLAccelerationStructure>  _Nonnull)accelerationStructure descriptor:(MTL4AccelerationStructureDescriptor * _Nonnull)descriptor scratchBuffer:(MTL4BufferRange)scratchBuffer;
- (void)refitAccelerationStructure:(id<MTLAccelerationStructure>  _Nonnull)sourceAccelerationStructure descriptor:(MTL4AccelerationStructureDescriptor * _Nonnull)descriptor destination:(id<MTLAccelerationStructure>  _Nullable)destinationAccelerationStructure scratchBuffer:(MTL4BufferRange)scratchBuffer;
- (void)refitAccelerationStructure:(id<MTLAccelerationStructure>  _Nonnull)sourceAccelerationStructure descriptor:(MTL4AccelerationStructureDescriptor * _Nonnull)descriptor destination:(id<MTLAccelerationStructure>  _Nullable)destinationAccelerationStructure scratchBuffer:(MTL4BufferRange)scratchBuffer options:(MTLAccelerationStructureRefitOptions)options;
- (void)copyAccelerationStructure:(id<MTLAccelerationStructure>  _Nonnull)sourceAccelerationStructure toAccelerationStructure:(id<MTLAccelerationStructure>  _Nonnull)destinationAccelerationStructure;
- (void)writeCompactedAccelerationStructureSize:(id<MTLAccelerationStructure>  _Nonnull)accelerationStructure toBuffer:(MTL4BufferRange)buffer;
- (void)copyAndCompactAccelerationStructure:(id<MTLAccelerationStructure>  _Nonnull)sourceAccelerationStructure toAccelerationStructure:(id<MTLAccelerationStructure>  _Nonnull)destinationAccelerationStructure;
- (void)writeTimestampWithGranularity:(MTL4TimestampGranularity)granularity intoHeap:(id<MTL4CounterHeap>  _Nonnull)counterHeap atIndex:(NSUInteger)index;
@end

typedef enum MTL4CounterHeapType MTL4CounterHeapType;
API_AVAILABLE(ios(26.0))
@protocol MTL4CounterHeap <NSObject>
@property (atomic, readwrite, copy) NSString * _Nullable label;
@property (atomic, readonly) NSUInteger count;
@property (atomic, readonly) MTL4CounterHeapType type;
- (NSData * _Nullable)resolveCounterRange:(NSRange)range;
- (void)invalidateCounterRange:(NSRange)range;
@end

API_AVAILABLE(ios(26.0))
@protocol MTL4MachineLearningCommandEncoder <MTL4CommandEncoder>
- (void)setPipelineState:(id<MTL4MachineLearningPipelineState>  _Nonnull)pipelineState;
- (void)setArgumentTable:(id<MTL4ArgumentTable>  _Nonnull)argumentTable;
- (void)dispatchNetworkWithIntermediatesHeap:(id<MTLHeap>  _Nonnull)heap;
@end

@class MTL4MachineLearningPipelineReflection;
API_AVAILABLE(ios(26.0))
@protocol MTL4MachineLearningPipelineState <MTLAllocation, NSObject>
@property (atomic, readonly) NSString * _Nullable label;
@property (atomic, readonly) id<MTLDevice> _Nonnull device;
@property (atomic, readonly) MTL4MachineLearningPipelineReflection * _Nullable reflection;
@property (atomic, readonly) NSUInteger intermediatesHeapSize;
@end

API_AVAILABLE(ios(26.0))
@protocol MTL4PipelineDataSetSerializer <NSObject>
- (BOOL)serializeAsArchiveAndFlushToURL:(NSURL * _Nonnull)url error:(NSError *  _Nullable * _Nullable)error;
- (NSData * _Nullable)serializeAsPipelinesScriptWithError:(NSError *  _Nullable * _Nullable)error;
@end

typedef enum MTL4TimestampGranularity MTL4TimestampGranularity;
@class MTLGPUAddress;
@class MTLLogicalToPhysicalColorAttachmentMap;
API_AVAILABLE(ios(26.0))
@protocol MTL4RenderCommandEncoder <MTL4CommandEncoder>
@property (atomic, readonly) NSUInteger tileWidth;
@property (atomic, readonly) NSUInteger tileHeight;
- (void)setColorAttachmentMap:(MTLLogicalToPhysicalColorAttachmentMap * _Nullable)mapping;
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>  _Nonnull)pipelineState;
- (void)setViewport:(MTLViewport)viewport;
- (void)setViewports:(const MTLViewport * _Nonnull)viewports count:(NSUInteger)count;
- (void)setVertexAmplificationCount:(NSUInteger)count viewMappings:(const MTLVertexAmplificationViewMapping * _Nullable)viewMappings;
- (void)setCullMode:(MTLCullMode)cullMode;
- (void)setDepthClipMode:(MTLDepthClipMode)depthClipMode;
- (void)setDepthBias:(float)depthBias slopeScale:(float)slopeScale clamp:(float)clamp;
- (void)setDepthTestMinBound:(float)minBound maxBound:(float)maxBound;
- (void)setScissorRect:(MTLScissorRect)rect;
- (void)setScissorRects:(const MTLScissorRect * _Nonnull)scissorRects count:(NSUInteger)count;
- (void)setTriangleFillMode:(MTLTriangleFillMode)fillMode;
- (void)setBlendColorRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha;
- (void)setDepthStencilState:(id<MTLDepthStencilState>  _Nullable)depthStencilState;
- (void)setStencilReferenceValue:(uint32_t)referenceValue;
- (void)setStencilFrontReferenceValue:(uint32_t)frontReferenceValue backReferenceValue:(uint32_t)backReferenceValue;
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)mode offset:(NSUInteger)offset;
- (void)setColorStoreAction:(MTLStoreAction)storeAction atIndex:(NSUInteger)colorAttachmentIndex;
- (void)setDepthStoreAction:(MTLStoreAction)storeAction;
- (void)setStencilStoreAction:(MTLStoreAction)storeAction;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount baseInstance:(NSUInteger)baseInstance;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(MTLGPUAddress)indexBuffer indexBufferLength:(NSUInteger)indexBufferLength;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(MTLGPUAddress)indexBuffer indexBufferLength:(NSUInteger)indexBufferLength instanceCount:(NSUInteger)instanceCount;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(MTLGPUAddress)indexBuffer indexBufferLength:(NSUInteger)indexBufferLength instanceCount:(NSUInteger)instanceCount baseVertex:(NSInteger)baseVertex baseInstance:(NSUInteger)baseInstance;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType indirectBuffer:(MTLGPUAddress)indirectBuffer;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexType:(MTLIndexType)indexType indexBuffer:(MTLGPUAddress)indexBuffer indexBufferLength:(NSUInteger)indexBufferLength indirectBuffer:(MTLGPUAddress)indirectBuffer;
- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>  _Nonnull)indirectCommandBuffer withRange:(NSRange)executionRange;
- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>  _Nonnull)indirectCommandBuffer indirectBuffer:(MTLGPUAddress)indirectRangeBuffer;
- (void)setObjectThreadgroupMemoryLength:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)drawMeshThreadgroups:(MTLSize)threadgroupsPerGrid threadsPerObjectThreadgroup:(MTLSize)threadsPerObjectThreadgroup threadsPerMeshThreadgroup:(MTLSize)threadsPerMeshThreadgroup;
- (void)drawMeshThreads:(MTLSize)threadsPerGrid threadsPerObjectThreadgroup:(MTLSize)threadsPerObjectThreadgroup threadsPerMeshThreadgroup:(MTLSize)threadsPerMeshThreadgroup;
- (void)drawMeshThreadgroupsWithIndirectBuffer:(MTLGPUAddress)indirectBuffer threadsPerObjectThreadgroup:(MTLSize)threadsPerObjectThreadgroup threadsPerMeshThreadgroup:(MTLSize)threadsPerMeshThreadgroup;
- (void)dispatchThreadsPerTile:(MTLSize)threadsPerTile;
- (void)setThreadgroupMemoryLength:(NSUInteger)length offset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setArgumentTable:(id<MTL4ArgumentTable>  _Nonnull)argumentTable atStages:(MTLRenderStages)stages;
- (void)setFrontFacingWinding:(MTLWinding)frontFacingWinding;
- (void)writeTimestampWithGranularity:(MTL4TimestampGranularity)granularity afterStage:(MTLRenderStages)stage intoHeap:(id<MTL4CounterHeap>  _Nonnull)counterHeap atIndex:(NSUInteger)index;
@end

@protocol MTLAccelerationStructure;

@protocol MTLAccelerationStructureCommandEncoder;

API_AVAILABLE(ios(18.0))
@protocol MTLAllocation <NSObject>
@property (atomic, readonly) NSUInteger allocatedSize;
@end

@protocol MTLArgumentEncoder;

@protocol MTLBinaryArchive;

@protocol MTLBinding;

@protocol MTLBlitCommandEncoder;

@protocol MTLBuffer;

@protocol MTLBufferBinding;

@protocol MTLCaptureScope;

@protocol MTLCommandBuffer;

@protocol MTLCommandBufferEncoderInfo;

@protocol MTLCommandEncoder;

@protocol MTLCommandQueue;

@protocol MTLComputeCommandEncoder;

@protocol MTLComputePipelineState;

@protocol MTLCounter;

@protocol MTLCounterSampleBuffer;

@protocol MTLCounterSet;

@protocol MTLDepthStencilState;

@protocol MTLDevice;

@protocol MTLDrawable;

@protocol MTLDynamicLibrary;

@protocol MTLEvent;

@protocol MTLFence;

@protocol MTLFunction;

@protocol MTLFunctionHandle;

@protocol MTLFunctionLog;

@protocol MTLFunctionLogDebugLocation;

@protocol MTLFunctionStitchingAttribute;

@protocol MTLFunctionStitchingNode;

@protocol MTLHeap;

@protocol MTLIOCommandBuffer;

@protocol MTLIOCommandQueue;

@protocol MTLIOFileHandle;

@protocol MTLIOScratchBuffer;

@protocol MTLIOScratchBufferAllocator;

@protocol MTLIndirectCommandBuffer;

@protocol MTLIndirectComputeCommand;

@protocol MTLIndirectRenderCommand;

@protocol MTLIntersectionFunctionTable;

@protocol MTLLibrary;

@protocol MTLLogContainer;

typedef enum MTLLogLevel MTLLogLevel;
API_AVAILABLE(ios(18.0))
@protocol MTLLogState <NSObject>
- (void)addLogHandler:(void (^ _Nonnull)(NSString * _Nullable, NSString * _Nullable, MTLLogLevel, NSString * _Nonnull))block;
@end

@protocol MTLObjectPayloadBinding;

@protocol MTLParallelRenderCommandEncoder;

@protocol MTLRasterizationRateMap;

@protocol MTLRenderCommandEncoder;

@protocol MTLRenderPipelineState;

API_AVAILABLE(ios(18.0))
@protocol MTLResidencySet <NSObject>
@property (atomic, readonly) id<MTLDevice> _Nonnull device;
@property (atomic, readonly) NSString * _Nullable label;
@property (atomic, readonly) uint64_t allocatedSize;
- (void)requestResidency;
- (void)endResidency;
- (void)addAllocation:(id<MTLAllocation>  _Nonnull)allocation;
- (void)addAllocations:(id<MTLAllocation>  _Nonnull const * _Nonnull)allocations count:(NSUInteger)count;
- (void)removeAllocation:(id<MTLAllocation>  _Nonnull)allocation;
- (void)removeAllocations:(id<MTLAllocation>  _Nonnull const * _Nonnull)allocations count:(NSUInteger)count;
- (void)removeAllAllocations;
- (BOOL)containsAllocation:(id<MTLAllocation>  _Nonnull)anAllocation;
@property (atomic, readonly, copy) NSArray<id<MTLAllocation>> * _Nonnull allAllocations;
@property (atomic, readonly) NSUInteger allocationCount;
- (void)commit;
@end

@protocol MTLResource;

@protocol MTLResourceStateCommandEncoder;

API_AVAILABLE(ios(26.0))
@protocol MTLResourceViewPool <NSObject>
@property (nonatomic, readonly) MTLResourceID baseResourceID;
@property (nonatomic, readonly) NSUInteger resourceViewCount;
@property (atomic, readonly) id<MTLDevice> _Nonnull device;
@property (nonatomic, readonly) NSString * _Nullable label;
- (MTLResourceID)copyResourceViewsFromPool:(id<MTLResourceViewPool>  _Nonnull)sourcePool sourceRange:(NSRange)sourceRange destinationIndex:(NSUInteger)destinationIndex;
@end

@protocol MTLSamplerState;

@protocol MTLSharedEvent;

typedef enum MTLTensorDataType MTLTensorDataType;
@class MTLTensorExtents;
typedef enum MTLTensorUsage MTLTensorUsage;
API_AVAILABLE(ios(26.0))
@protocol MTLTensor <MTLResource>
@property (atomic, readonly) MTLResourceID gpuResourceID;
@property (atomic, readonly) id<MTLBuffer> _Nullable buffer;
@property (atomic, readonly) NSUInteger bufferOffset;
@property (atomic, readonly) MTLTensorExtents * _Nullable strides;
@property (atomic, readonly) MTLTensorExtents * _Nonnull dimensions;
@property (atomic, readonly) MTLTensorDataType dataType;
@property (atomic, readonly) MTLTensorUsage usage;
- (void)replaceSliceOrigin:(MTLTensorExtents * _Nonnull)sliceOrigin sliceDimensions:(MTLTensorExtents * _Nonnull)sliceDimensions withBytes:(const void * _Nonnull)bytes strides:(MTLTensorExtents * _Nonnull)strides;
- (void)getBytes:(void * _Nonnull)bytes strides:(MTLTensorExtents * _Nonnull)strides fromSliceOrigin:(MTLTensorExtents * _Nonnull)sliceOrigin sliceDimensions:(MTLTensorExtents * _Nonnull)sliceDimensions;
@end

typedef enum MTLTensorDataType MTLTensorDataType;
@class MTLTensorExtents;
API_AVAILABLE(ios(26.0))
@protocol MTLTensorBinding <MTLBinding>
@property (atomic, readonly) MTLTensorDataType tensorDataType;
@property (atomic, readonly) MTLDataType indexType;
@property (atomic, readonly) MTLTensorExtents * _Nullable dimensions;
@end

@protocol MTLTexture;

@protocol MTLTextureBinding;

@class MTLTextureViewDescriptor;
API_AVAILABLE(ios(26.0))
@protocol MTLTextureViewPool <MTLResourceViewPool>
- (MTLResourceID)setTextureView:(id<MTLTexture>  _Nonnull)texture atIndex:(NSUInteger)index;
- (MTLResourceID)setTextureView:(id<MTLTexture>  _Nonnull)texture descriptor:(MTLTextureViewDescriptor * _Nonnull)descriptor atIndex:(NSUInteger)index;
- (MTLResourceID)setTextureViewFromBuffer:(id<MTLBuffer>  _Nonnull)buffer descriptor:(MTLTextureDescriptor * _Nonnull)descriptor offset:(NSUInteger)offset bytesPerRow:(NSUInteger)bytesPerRow atIndex:(NSUInteger)index;
@end

@protocol MTLThreadgroupBinding;

@protocol MTLVisibleFunctionTable;
