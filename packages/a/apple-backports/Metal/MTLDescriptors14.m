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
    id <MTLBuffer> _boundingBoxBuffer;
}
@property (nonatomic, retain) id <MTLBuffer> boundingBoxBuffer;
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
    id <MTLBuffer> _vertexBuffer, _indexBuffer, _transformationMatrixBuffer;
}
@property (nonatomic, retain) id <MTLBuffer> vertexBuffer;
@property (nonatomic, retain) id <MTLBuffer> indexBuffer;
@property (nonatomic, retain) id <MTLBuffer> transformationMatrixBuffer;
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
    NSArray *_geometryDescriptors;
}
@property (nonatomic, retain) NSArray *geometryDescriptors;
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
    id <MTLBuffer> _instanceDescriptorBuffer, _motionTransformBuffer;
    NSArray *_instancedAccelerationStructures;
}
@property (nonatomic, retain) id <MTLBuffer> instanceDescriptorBuffer;
@property (nonatomic, retain) id <MTLBuffer> motionTransformBuffer;
@property (nonatomic, retain) NSArray *instancedAccelerationStructures;
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

// THE FRESH DEFAULTS ARE THE HEADER'S, and four of the five this file once claimed the header did
// not state DO state it. MTLAccelerationStructure.h gives allowDuplicateIntersectionFunction-
// Invocation the default YES (:101-103), motionEndTime 1.0f (:181-182), motionKeyframeCount 1
// (:186-187) and vertexFormat Float3 packed (:213-215, and MTLAttributeFormatFloat3 is 30 in
// MTLStageInputOutputDescriptor.h). An earlier revision of this file called all five unwritten and
// left the port at zero; that was wrong, and a caller reading a fresh descriptor was getting five
// zeroes where the header specifies four values and one it genuinely leaves open.
@implementation CharonMetalAccelerationStructureGeometryDescriptor
@synthesize intersectionFunctionTableOffset = _intersectionFunctionTableOffset;
@synthesize opaque = _opaque;
@synthesize allowDuplicateIntersectionFunctionInvocation = _allowDuplicate;
@synthesize primitiveDataBufferOffset = _primitiveDataBufferOffset;
@synthesize primitiveDataStride = _primitiveDataStride;
@synthesize primitiveDataElementSize = _primitiveDataElementSize;
@synthesize primitiveDataBuffer = _primitiveDataBuffer;
@synthesize label = _label;
// MTLAccelerationStructure.h:101-103 - the header's default for
// allowDuplicateIntersectionFunctionInvocation is YES, so a fresh geometry descriptor answers YES.
- (instancetype)init
{
    if ((self = [super init]))
        _allowDuplicate = YES;
    return self;
}
@end

// THE HEADER WARRANTS 24 for the bounding box stride and no other value: "Stride, in bytes,
// between bounding boxes in the bounding box buffer. Must be at least 24" (MTLAccelerationStructure.h).
// Apple's own fresh object answers 24, which is the header's floor rather than a private default,
// so the port starts there and the case compares it.
@implementation CharonMetalAccelerationStructureBoundingBoxGeometryDescriptor
@synthesize boundingBoxBuffer = _boundingBoxBuffer;
@synthesize boundingBoxBufferOffset = _boundingBoxBufferOffset;
@synthesize boundingBoxStride = _boundingBoxStride;
@synthesize boundingBoxCount = _boundingBoxCount;
- (instancetype)init
{
    if ((self = [super init]))
        _boundingBoxStride = 24;   // the header's own floor: "Must be at least 24"
    return self;
}
@end

@implementation CharonMetalAccelerationStructureTriangleGeometryDescriptor
@synthesize vertexBuffer = _vertexBuffer;
@synthesize indexBuffer = _indexBuffer;
@synthesize transformationMatrixBuffer = _transformationMatrixBuffer;
@synthesize vertexBufferOffset = _vertexBufferOffset;
@synthesize vertexFormat = _vertexFormat;
// MTLAccelerationStructure.h:213-215 - the header's default for vertexFormat is
// MTLAttributeFormatFloat3 packed, and that is 30 (MTLStageInputOutputDescriptor.h).
- (instancetype)init
{
    if ((self = [super init]))
        _vertexFormat = MTLAttributeFormatFloat3;
    return self;
}
@synthesize vertexStride = _vertexStride;
@synthesize indexBufferOffset = _indexBufferOffset;
@synthesize indexType = _indexType;
@synthesize triangleCount = _triangleCount;
@synthesize transformationMatrixBufferOffset = _transformationMatrixBufferOffset;
@end

@implementation CharonMetalPrimitiveAccelerationStructureDescriptor
@synthesize geometryDescriptors = _geometryDescriptors;
@synthesize motionStartBorderMode = _motionStartBorderMode;
@synthesize motionEndBorderMode = _motionEndBorderMode;
@synthesize motionStartTime = _motionStartTime;
@synthesize motionEndTime = _motionEndTime;
@synthesize motionKeyframeCount = _motionKeyframeCount;
// MTLAccelerationStructure.h:181-182 and :186-187 - motionEndTime defaults to 1.0f and
// motionKeyframeCount to 1, and the header says the second means no motion.
- (instancetype)init
{
    if ((self = [super init])) {
        _motionEndTime = 1.0f;
        _motionKeyframeCount = 1;
    }
    return self;
}
@end

@implementation CharonMetalInstanceAccelerationStructureDescriptor
// The header does not write a number here - "Defaults to the size of the instance descriptor type"
// (MTLAccelerationStructure.h) - and that size is 64 for MTLAccelerationStructureInstanceDescriptor-
// TypeDefault, MEASURED on the host rather than assumed, so the port starts there and the case
// compares it rather than leaving a bare zero that means nothing.
- (instancetype)init
{
    if ((self = [super init]))
        _instanceDescriptorStride = 64;
    return self;
}
@synthesize instanceDescriptorBuffer = _instanceDescriptorBuffer;
@synthesize motionTransformBuffer = _motionTransformBuffer;
@synthesize instancedAccelerationStructures = _instancedAccelerationStructures;
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
    id _counterSet;
}
@property (nonatomic, retain) id counterSet;
@property (nonatomic, copy) NSString *label;
@property (nonatomic) MTLStorageMode storageMode;
@property (nonatomic) NSUInteger sampleCount;
@end

@interface CharonMetalComputePassSampleBufferAttachmentDescriptor : NSObject
{
    NSUInteger _startOfEncoderSampleIndex, _endOfEncoderSampleIndex;
    id _sampleBuffer;
}
@property (nonatomic, retain) id sampleBuffer;
@property (nonatomic) NSUInteger startOfEncoderSampleIndex;
@property (nonatomic) NSUInteger endOfEncoderSampleIndex;
@end

@interface CharonMetalResourceStatePassSampleBufferAttachmentDescriptor : NSObject
{
    NSUInteger _startOfEncoderSampleIndex, _endOfEncoderSampleIndex;
    id _sampleBuffer;
}
@property (nonatomic, retain) id sampleBuffer;
@property (nonatomic) NSUInteger startOfEncoderSampleIndex;
@property (nonatomic) NSUInteger endOfEncoderSampleIndex;
@end

@interface CharonMetalRenderPassSampleBufferAttachmentDescriptor : NSObject
{
    NSUInteger _startOfVertexSampleIndex, _endOfVertexSampleIndex;
    NSUInteger _startOfFragmentSampleIndex, _endOfFragmentSampleIndex;
    id _sampleBuffer;
}
@property (nonatomic, retain) id sampleBuffer;
@property (nonatomic) NSUInteger startOfVertexSampleIndex;
@property (nonatomic) NSUInteger endOfVertexSampleIndex;
@property (nonatomic) NSUInteger startOfFragmentSampleIndex;
@property (nonatomic) NSUInteger endOfFragmentSampleIndex;
@end

@implementation CharonMetalCounterSampleBufferDescriptor
@synthesize counterSet = _counterSet;
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
- (instancetype)init
{
    if ((self = [super init])) {
        _startOfEncoderSampleIndex = MTLCounterDontSample;
        _endOfEncoderSampleIndex = MTLCounterDontSample;
    }
    return self;
}
@synthesize sampleBuffer = _sampleBuffer;
@synthesize startOfEncoderSampleIndex = _startOfEncoderSampleIndex;
@synthesize endOfEncoderSampleIndex = _endOfEncoderSampleIndex;
@end

@implementation CharonMetalResourceStatePassSampleBufferAttachmentDescriptor
- (instancetype)init
{
    if ((self = [super init])) {
        _startOfEncoderSampleIndex = MTLCounterDontSample;
        _endOfEncoderSampleIndex = MTLCounterDontSample;
    }
    return self;
}
@synthesize sampleBuffer = _sampleBuffer;
@synthesize startOfEncoderSampleIndex = _startOfEncoderSampleIndex;
@synthesize endOfEncoderSampleIndex = _endOfEncoderSampleIndex;
@end

@implementation CharonMetalRenderPassSampleBufferAttachmentDescriptor
- (instancetype)init
{
    if ((self = [super init])) {
        _startOfVertexSampleIndex = MTLCounterDontSample;
        _endOfVertexSampleIndex = MTLCounterDontSample;
        _startOfFragmentSampleIndex = MTLCounterDontSample;
        _endOfFragmentSampleIndex = MTLCounterDontSample;
    }
    return self;
}
@synthesize sampleBuffer = _sampleBuffer;
@synthesize startOfVertexSampleIndex = _startOfVertexSampleIndex;
@synthesize endOfVertexSampleIndex = _endOfVertexSampleIndex;
@synthesize startOfFragmentSampleIndex = _startOfFragmentSampleIndex;
@synthesize endOfFragmentSampleIndex = _endOfFragmentSampleIndex;
@end


// Declared here because the two pass descriptors CREATE one in -init, and the header declares the
// property readonly: a caller asking for it gets a real array, not nil, on both sides.
@class CharonMetalComputePassSampleBufferAttachmentDescriptorArray;
@class CharonMetalResourceStatePassSampleBufferAttachmentDescriptorArray;

#pragma mark - the pass descriptors and the binary archive

@interface CharonMetalComputePassDescriptor : NSObject
{
    MTLDispatchType _dispatchType;
    CharonMetalComputePassSampleBufferAttachmentDescriptorArray *_sampleBufferAttachments;
}
@property (nonatomic) MTLDispatchType dispatchType;
@property (nonatomic, retain) CharonMetalComputePassSampleBufferAttachmentDescriptorArray *sampleBufferAttachments;
@end

@interface CharonMetalResourceStatePassDescriptor : NSObject
{
    CharonMetalResourceStatePassSampleBufferAttachmentDescriptorArray *_sampleBufferAttachments;
}
@property (nonatomic, retain) CharonMetalResourceStatePassSampleBufferAttachmentDescriptorArray *sampleBufferAttachments;
@end

@interface CharonMetalBinaryArchiveDescriptor : NSObject
{
    NSURL *_url;
}
@property (nonatomic, copy) NSURL *url;
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

// THE TWO PASS DESCRIPTORS COME LAST, because each -init creates its attachment array and needs
// that class's interface to be complete - a @class forward declaration is not enough to send
// it alloc. Their interfaces are above with the rest.
@implementation CharonMetalComputePassDescriptor
// MTLDispatchTypeNonUniform is 0, the enumeration's own zero.
@synthesize dispatchType = _dispatchType;
@synthesize sampleBufferAttachments = _sampleBufferAttachments;
// THE HEADER DECLARES THIS PROPERTY READONLY and Apple's own object hands one back on a fresh
// descriptor, so the port makes one too: the array is the port's own class and needs no device.
- (instancetype)init
{
    if ((self = [super init]))
        _sampleBufferAttachments = [[CharonMetalComputePassSampleBufferAttachmentDescriptorArray alloc] init];
    return self;
}
@end

// The resource-state pass descriptor declares no member of its own but for the attachment array,
// which holds the counter sample buffers of a device this port has no facility to make - but the
// ARRAY itself the port can and does make, because the header declares it readonly.
@implementation CharonMetalResourceStatePassDescriptor
@synthesize sampleBufferAttachments = _sampleBufferAttachments;
- (instancetype)init
{
    if ((self = [super init]))
        _sampleBufferAttachments = [[CharonMetalResourceStatePassSampleBufferAttachmentDescriptorArray alloc] init];
    return self;
}
@end
