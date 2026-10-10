// CharonMetalPerformanceShadersGraphProtocols.h - the MetalPerformanceShadersGraph protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// Every protocol in this file is transcribed here, so it imports no framework header: their members name classes this header forward-declares. A file with a forward-declared protocol in it does import <MetalPerformanceShadersGraph/MetalPerformanceShadersGraph.h>, for that one body.
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

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
