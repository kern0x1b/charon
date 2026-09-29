#import "CharonMetal.h"
#import "CharonMetalProtocols.h"

// The DESCRIPTORS that arrived in iOS 14: the acceleration-structure family, the two ray-tracing
// function tables, the counter-sample descriptors, the pass descriptors and the binary archive.
//
// THEY ARE ALL PLAIN DATA HOLDERS, and that is the whole case for carrying them. A descriptor says
// what a pass or an acceleration structure is built FROM - offsets, strides, counts, a dispatch
// type, a label - and none of it asks the device anything. A port with no ray tracing still has to
// hand these back when a caller asks what it would build, and the values a caller reads back are
// the values it wrote.
//
// NOTHING HERE CREATES A DEVICE, and the host differential is built on that. Each side is
// `[[X alloc] init]` - the port's class and Apple's - and a descriptor needs no device to exist.
// `MTLCreateSystemDefaultDevice()` HANGS on a machine with no GPU, so no case in this family calls
// it, and the differential compares two objects that were never made by a device.
//
// THE PROPERTIES THAT HOLD A DEVICE-MADE OBJECT - the MTLBuffer, MTLCounterSet, MTLFunction and
// MTLAccelerationStructure references - ARE CARRIED AND NOT MEASURED, and the facts file names every
// one of them. The host's own default for each is nil and so is the port's, which is all a
// no-device comparison can say, and a round trip with a real buffer would need a device to make one.
//
// EVERY CLASS HERE IS A CLASS in the SDK, not a protocol: the twenty `MTL*Descriptor` and
// `MTLLinkedFunctions` rows are all `@interface`, and their superclasses are as the header has them
// - the geometry descriptor is a SIBLING of the acceleration-structure descriptor, not a subclass,
// and only the bounding-box and triangle geometry descriptors derive from it.

#pragma mark - the acceleration-structure family

@interface CharonMetalAccelerationStructureDescriptor : NSObject
{
    MTLAccelerationStructureUsage _usage;
}
@property (nonatomic) MTLAccelerationStructureUsage usage;
@end

// The header's own hierarchy: a sibling of the base above, not a subclass of it.
@interface CharonMetalAccelerationStructureGeometryDescriptor : NSObject
{
    NSUInteger _intersectionFunctionTableOffset, _primitiveDataBufferOffset;
    NSUInteger _primitiveDataStride, _primitiveDataElementSize;
    BOOL _opaque, _allowDuplicate;
    id <MTLBuffer> _primitiveDataBuffer;
    NSString *_label;
}
@property (nonatomic) NSUInteger intersectionFunctionTableOffset;
@property (nonatomic) BOOL opaque;
@property (nonatomic) BOOL allowDuplicateIntersectionFunctionInvocation;
@property (nonatomic) NSUInteger primitiveDataBufferOffset;
@property (nonatomic) NSUInteger primitiveDataStride;
@property (nonatomic) NSUInteger primitiveDataElementSize;
// primitiveDataBuffer is declared in the header and CARRIED: it is an MTLBuffer, which only a device
// makes, so it reads nil and is not measured. Declared so that a caller asking for it gets the
// port's nil rather than a doesNotRecognizeSelector crash.
@property (nonatomic, retain) id <MTLBuffer> primitiveDataBuffer;
@property (nonatomic, copy) NSString *label;
@end

@interface CharonMetalAccelerationStructureBoundingBoxGeometryDescriptor
    : CharonMetalAccelerationStructureGeometryDescriptor
{
    NSUInteger _boundingBoxBufferOffset, _boundingBoxStride, _boundingBoxCount;
}
@property (nonatomic) NSUInteger boundingBoxBufferOffset;
@property (nonatomic) NSUInteger boundingBoxStride;
@property (nonatomic) NSUInteger boundingBoxCount;
@end

@interface CharonMetalAccelerationStructureTriangleGeometryDescriptor
    : CharonMetalAccelerationStructureGeometryDescriptor
{
    NSUInteger _vertexBufferOffset, _vertexStride, _indexBufferOffset, _triangleCount;
    NSUInteger _transformationMatrixBufferOffset;
    MTLAttributeFormat _vertexFormat;
    MTLIndexType _indexType;
}
@property (nonatomic) NSUInteger vertexBufferOffset;
@property (nonatomic) MTLAttributeFormat vertexFormat;
@property (nonatomic) NSUInteger vertexStride;
@property (nonatomic) NSUInteger indexBufferOffset;
@property (nonatomic) MTLIndexType indexType;
@property (nonatomic) NSUInteger triangleCount;
@property (nonatomic) NSUInteger transformationMatrixBufferOffset;
@end

@interface CharonMetalPrimitiveAccelerationStructureDescriptor : CharonMetalAccelerationStructureDescriptor
{
    MTLMotionBorderMode _motionStartBorderMode, _motionEndBorderMode;
    float _motionStartTime, _motionEndTime;
    NSUInteger _motionKeyframeCount;
}
@property (nonatomic) MTLMotionBorderMode motionStartBorderMode;
@property (nonatomic) MTLMotionBorderMode motionEndBorderMode;
@property (nonatomic) float motionStartTime;
@property (nonatomic) float motionEndTime;
@property (nonatomic) NSUInteger motionKeyframeCount;
@end

@interface CharonMetalInstanceAccelerationStructureDescriptor : CharonMetalAccelerationStructureDescriptor
{
    NSUInteger _instanceDescriptorBufferOffset, _instanceDescriptorStride, _instanceCount;
    NSUInteger _motionTransformBufferOffset, _motionTransformCount;
    MTLAccelerationStructureInstanceDescriptorType _instanceDescriptorType;
}
@property (nonatomic) NSUInteger instanceDescriptorBufferOffset;
@property (nonatomic) NSUInteger instanceDescriptorStride;
@property (nonatomic) NSUInteger instanceCount;
@property (nonatomic) MTLAccelerationStructureInstanceDescriptorType instanceDescriptorType;
@property (nonatomic) NSUInteger motionTransformBufferOffset;
@property (nonatomic) NSUInteger motionTransformCount;
@end

@implementation CharonMetalAccelerationStructureDescriptor
// MTLAccelerationStructureUsageNone is 0, the enumeration's own zero, so a fresh descriptor reads
// back the case the header names first. The base's ONLY member is the usage; the geometry members
// belong to the sibling above, and this class answers none of them.
@synthesize usage = _usage;
@end

@implementation CharonMetalAccelerationStructureGeometryDescriptor
@synthesize intersectionFunctionTableOffset = _intersectionFunctionTableOffset;
@synthesize opaque = _opaque;
@synthesize allowDuplicateIntersectionFunctionInvocation = _allowDuplicate;
@synthesize primitiveDataBufferOffset = _primitiveDataBufferOffset;
@synthesize primitiveDataStride = _primitiveDataStride;
@synthesize primitiveDataElementSize = _primitiveDataElementSize;
@synthesize primitiveDataBuffer = _primitiveDataBuffer;
@synthesize label = _label;
@end

@implementation CharonMetalAccelerationStructureBoundingBoxGeometryDescriptor
@synthesize boundingBoxBufferOffset = _boundingBoxBufferOffset;
@synthesize boundingBoxStride = _boundingBoxStride;
@synthesize boundingBoxCount = _boundingBoxCount;
@end

@implementation CharonMetalAccelerationStructureTriangleGeometryDescriptor
@synthesize vertexBufferOffset = _vertexBufferOffset;
@synthesize vertexFormat = _vertexFormat;
@synthesize vertexStride = _vertexStride;
@synthesize indexBufferOffset = _indexBufferOffset;
@synthesize indexType = _indexType;
@synthesize triangleCount = _triangleCount;
@synthesize transformationMatrixBufferOffset = _transformationMatrixBufferOffset;
@end

@implementation CharonMetalPrimitiveAccelerationStructureDescriptor
@synthesize motionStartBorderMode = _motionStartBorderMode;
@synthesize motionEndBorderMode = _motionEndBorderMode;
@synthesize motionStartTime = _motionStartTime;
@synthesize motionEndTime = _motionEndTime;
@synthesize motionKeyframeCount = _motionKeyframeCount;
@end

@implementation CharonMetalInstanceAccelerationStructureDescriptor
@synthesize instanceDescriptorBufferOffset = _instanceDescriptorBufferOffset;
@synthesize instanceDescriptorStride = _instanceDescriptorStride;
@synthesize instanceCount = _instanceCount;
@synthesize instanceDescriptorType = _instanceDescriptorType;
@synthesize motionTransformBufferOffset = _motionTransformBufferOffset;
@synthesize motionTransformCount = _motionTransformCount;
@end

#pragma mark - the two ray-tracing function tables

@interface CharonMetalIntersectionFunctionTableDescriptor : NSObject
{
    NSUInteger _functionCount;
}
@property (nonatomic) NSUInteger functionCount;
@end

@interface CharonMetalVisibleFunctionTableDescriptor : NSObject
{
    NSUInteger _functionCount;
}
@property (nonatomic) NSUInteger functionCount;
@end

@implementation CharonMetalIntersectionFunctionTableDescriptor
@synthesize functionCount = _functionCount;
@end

@implementation CharonMetalVisibleFunctionTableDescriptor
@synthesize functionCount = _functionCount;
@end

#pragma mark - the counter-sample descriptors

@interface CharonMetalCounterSampleBufferDescriptor : NSObject
{
    NSString *_label;
    MTLStorageMode _storageMode;
    NSUInteger _sampleCount;
}
@property (nonatomic, copy) NSString *label;
@property (nonatomic) MTLStorageMode storageMode;
@property (nonatomic) NSUInteger sampleCount;
@end

@interface CharonMetalComputePassSampleBufferAttachmentDescriptor : NSObject
{
    NSUInteger _startOfEncoderSampleIndex, _endOfEncoderSampleIndex;
}
@property (nonatomic) NSUInteger startOfEncoderSampleIndex;
@property (nonatomic) NSUInteger endOfEncoderSampleIndex;
@end

@interface CharonMetalResourceStatePassSampleBufferAttachmentDescriptor : NSObject
{
    NSUInteger _startOfEncoderSampleIndex, _endOfEncoderSampleIndex;
}
@property (nonatomic) NSUInteger startOfEncoderSampleIndex;
@property (nonatomic) NSUInteger endOfEncoderSampleIndex;
@end

@interface CharonMetalRenderPassSampleBufferAttachmentDescriptor : NSObject
{
    NSUInteger _startOfVertexSampleIndex, _endOfVertexSampleIndex;
    NSUInteger _startOfFragmentSampleIndex, _endOfFragmentSampleIndex;
}
@property (nonatomic) NSUInteger startOfVertexSampleIndex;
@property (nonatomic) NSUInteger endOfVertexSampleIndex;
@property (nonatomic) NSUInteger startOfFragmentSampleIndex;
@property (nonatomic) NSUInteger endOfFragmentSampleIndex;
@end

@implementation CharonMetalCounterSampleBufferDescriptor
@synthesize label = _label;
@synthesize storageMode = _storageMode;
// MTLStorageModeShared is 0 in MTLResource.h, the enumeration's own zero.
- (instancetype)init
{
    if ((self = [super init]))
        _storageMode = MTLStorageModeShared;
    return self;
}
@synthesize sampleCount = _sampleCount;
@end

@implementation CharonMetalComputePassSampleBufferAttachmentDescriptor
@synthesize startOfEncoderSampleIndex = _startOfEncoderSampleIndex;
@synthesize endOfEncoderSampleIndex = _endOfEncoderSampleIndex;
@end

@implementation CharonMetalResourceStatePassSampleBufferAttachmentDescriptor
@synthesize startOfEncoderSampleIndex = _startOfEncoderSampleIndex;
@synthesize endOfEncoderSampleIndex = _endOfEncoderSampleIndex;
@end

@implementation CharonMetalRenderPassSampleBufferAttachmentDescriptor
@synthesize startOfVertexSampleIndex = _startOfVertexSampleIndex;
@synthesize endOfVertexSampleIndex = _endOfVertexSampleIndex;
@synthesize startOfFragmentSampleIndex = _startOfFragmentSampleIndex;
@synthesize endOfFragmentSampleIndex = _endOfFragmentSampleIndex;
@end

#pragma mark - the pass descriptors and the binary archive

@interface CharonMetalComputePassDescriptor : NSObject
{
    MTLDispatchType _dispatchType;
}
@property (nonatomic) MTLDispatchType dispatchType;
@end

@interface CharonMetalResourceStatePassDescriptor : NSObject
@end

@interface CharonMetalBinaryArchiveDescriptor : NSObject
{
    NSURL *_url;
}
@property (nonatomic, copy) NSURL *url;
@end

@implementation CharonMetalComputePassDescriptor
// MTLDispatchTypeNonUniform is 0, the enumeration's own zero.
@synthesize dispatchType = _dispatchType;
@end

// The resource-state pass descriptor declares no member of its own but for the attachment array,
// which holds the counter sample buffers of a device this port has no facility to make.
@implementation CharonMetalResourceStatePassDescriptor
@end

@implementation CharonMetalBinaryArchiveDescriptor
@synthesize url = _url;
@end

#pragma mark - the attachment arrays, and the two remaining descriptors

// THE THREE ARRAYS ARE NSArrays OF THE ATTACHMENT DESCRIPTORS, and each declares the two indexed
// members rather than inheriting them. They are real storage, not a stand-in: objectAtIndexedSubscript:
// reads what setObject:atIndex: wrote, and the differential sets and reads the same indices on both
// sides. The sample buffer each attachment carries is a device-made object, so it stays nil.
@interface CharonMetalComputePassSampleBufferAttachmentDescriptorArray : NSObject
{
    NSMutableArray *_attachments;
}
- (MTLComputePassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(nullable MTLComputePassSampleBufferAttachmentDescriptor *)attachment
          atIndex:(NSUInteger)index;
@end

@interface CharonMetalRenderPassSampleBufferAttachmentDescriptorArray : NSObject
{
    NSMutableArray *_attachments;
}
- (MTLRenderPassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(nullable MTLRenderPassSampleBufferAttachmentDescriptor *)attachment
          atIndex:(NSUInteger)index;
@end

@interface CharonMetalResourceStatePassSampleBufferAttachmentDescriptorArray : NSObject
{
    NSMutableArray *_attachments;
}
- (MTLResourceStatePassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(nullable MTLResourceStatePassSampleBufferAttachmentDescriptor *)attachment
          atIndex:(NSUInteger)index;
@end

// The header's own storage for all three: an array that grows to the index written, so an index
// beyond the end reads nil rather than trapping, which is what NSArray's own behaviour is.
@implementation CharonMetalComputePassSampleBufferAttachmentDescriptorArray
- (instancetype)init
{
    if ((self = [super init]))
        _attachments = [[NSMutableArray alloc] init];
    return self;
}
- (MTLComputePassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index
{
    return index < [_attachments count] ? [_attachments objectAtIndex:index] : nil;
}
- (void)setObject:(nullable MTLComputePassSampleBufferAttachmentDescriptor *)attachment
          atIndex:(NSUInteger)index
{
    while ([_attachments count] <= index) { [_attachments addObject:[NSNull null]]; }
    [_attachments replaceObjectAtIndex:index withObject:(attachment ? (id)attachment : (id)[NSNull null])];
    if (!attachment) { [_attachments removeObjectAtIndex:index]; [_attachments addObject:[NSNull null]]; }
}
@end

@implementation CharonMetalRenderPassSampleBufferAttachmentDescriptorArray
- (instancetype)init
{
    if ((self = [super init]))
        _attachments = [[NSMutableArray alloc] init];
    return self;
}
- (MTLRenderPassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index
{
    return index < [_attachments count] ? [_attachments objectAtIndex:index] : nil;
}
- (void)setObject:(nullable MTLRenderPassSampleBufferAttachmentDescriptor *)attachment
          atIndex:(NSUInteger)index
{
    while ([_attachments count] <= index) { [_attachments addObject:[NSNull null]]; }
    [_attachments replaceObjectAtIndex:index withObject:(attachment ? (id)attachment : (id)[NSNull null])];
    if (!attachment) { [_attachments removeObjectAtIndex:index]; [_attachments addObject:[NSNull null]]; }
}
@end

@implementation CharonMetalResourceStatePassSampleBufferAttachmentDescriptorArray
- (instancetype)init
{
    if ((self = [super init]))
        _attachments = [[NSMutableArray alloc] init];
    return self;
}
- (MTLResourceStatePassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index
{
    return index < [_attachments count] ? [_attachments objectAtIndex:index] : nil;
}
- (void)setObject:(nullable MTLResourceStatePassSampleBufferAttachmentDescriptor *)attachment
          atIndex:(NSUInteger)index
{
    while ([_attachments count] <= index) { [_attachments addObject:[NSNull null]]; }
    [_attachments replaceObjectAtIndex:index withObject:(attachment ? (id)attachment : (id)[NSNull null])];
    if (!attachment) { [_attachments removeObjectAtIndex:index]; [_attachments addObject:[NSNull null]]; }
}
@end

// MTLLinkedFunctions carries the functions a library links, and MTLIntersectionFunctionDescriptor
// carries one intersection function. BOTH hold MTLFunction OBJECTS, which are made by a device and
// which this port has no facility to make, so their four and zero members are CARRIED AND NOT
// MEASURED: the arrays read empty, which is a real answer, and the function's own descriptor type
// is carried in the class the header derives it from.
@interface CharonMetalLinkedFunctions : NSObject
{
    NSArray *_functions, *_binaryFunctions, *_privateFunctions;
    NSDictionary *_groups;
}
@property (nonatomic, copy) NSArray *functions;
@property (nonatomic, copy) NSArray *binaryFunctions;
@property (nonatomic, copy) NSDictionary *groups;
@property (nonatomic, copy) NSArray *privateFunctions;
@end

// THE HEADER GIVES THIS CLASS NO MEMBER OF ITS OWN: MTLIntersectionFunctionDescriptor declares
// nothing, and everything it answers is inherited from MTLFunctionDescriptor, which is a different
// row and a different object's business. An earlier revision of this file gave it
// functionBufferOffset, functionBufferOffsetAlignment and functionStride, and NO SUCH MEMBER EXISTS
// in any SDK header - they were invented, and they are gone.
@interface CharonMetalIntersectionFunctionDescriptor : NSObject
@end

@implementation CharonMetalLinkedFunctions
// The four are readwrite in the header and the port carries them, but a caller can only fill them
// with MTLFunction objects, and none can be made without a device - so a fresh one is EMPTY, which
// is what the differential compares against Apple's own fresh object.
@synthesize functions = _functions;
@synthesize binaryFunctions = _binaryFunctions;
@synthesize groups = _groups;
@synthesize privateFunctions = _privateFunctions;
@end

@implementation CharonMetalIntersectionFunctionDescriptor
@end
