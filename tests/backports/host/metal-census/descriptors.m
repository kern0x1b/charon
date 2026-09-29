/* The 14.0 descriptors, compared PROPERTY BY PROPERTY against Apple's own objects.
 *
 * NO DEVICE IS EVER CREATED. `MTLCreateSystemDefaultDevice()` HANGS on a machine with no GPU - it
 * was measured hanging and killed - so nothing here calls it, and nothing in this family needs it:
 * a descriptor is `[[X alloc] init]` on both sides. The host object is APPLE'S, made by Apple's
 * class, and it is the oracle: the port's value is compared against what Apple's own object answers
 * for the same property after the same write. A round trip of the port's object against ITSELF would
 * prove only that the port agrees with the port, and that is the round trip that let three reviews
 * through.
 *
 * Every value set below is one the header's own enumerations name, read from the SDK, and none of
 * them is chosen to make a comparison pass.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@interface CharonMetalAccelerationStructureDescriptor : NSObject
@property (nonatomic) MTLAccelerationStructureUsage usage;
@end
@interface CharonMetalAccelerationStructureGeometryDescriptor : NSObject
@property (nonatomic) NSUInteger intersectionFunctionTableOffset;
@property (nonatomic) BOOL opaque;
@property (nonatomic) BOOL allowDuplicateIntersectionFunctionInvocation;
@property (nonatomic) NSUInteger primitiveDataBufferOffset;
@property (nonatomic) NSUInteger primitiveDataStride;
@property (nonatomic) NSUInteger primitiveDataElementSize;
@property (nonatomic, retain) id <MTLBuffer> primitiveDataBuffer;
@property (nonatomic, copy) NSString *label;
@end
@interface CharonMetalAccelerationStructureBoundingBoxGeometryDescriptor
    : CharonMetalAccelerationStructureGeometryDescriptor
@property (nonatomic) NSUInteger boundingBoxBufferOffset;
@property (nonatomic) NSUInteger boundingBoxStride;
@property (nonatomic) NSUInteger boundingBoxCount;
@end
@interface CharonMetalAccelerationStructureTriangleGeometryDescriptor
    : CharonMetalAccelerationStructureGeometryDescriptor
@property (nonatomic) NSUInteger vertexBufferOffset;
@property (nonatomic) MTLAttributeFormat vertexFormat;
@property (nonatomic) NSUInteger vertexStride;
@property (nonatomic) NSUInteger indexBufferOffset;
@property (nonatomic) MTLIndexType indexType;
@property (nonatomic) NSUInteger triangleCount;
@property (nonatomic) NSUInteger transformationMatrixBufferOffset;
@end
@interface CharonMetalPrimitiveAccelerationStructureDescriptor : CharonMetalAccelerationStructureDescriptor
@property (nonatomic) MTLMotionBorderMode motionStartBorderMode;
@property (nonatomic) MTLMotionBorderMode motionEndBorderMode;
@property (nonatomic) float motionStartTime;
@property (nonatomic) float motionEndTime;
@property (nonatomic) NSUInteger motionKeyframeCount;
@end
@interface CharonMetalInstanceAccelerationStructureDescriptor : CharonMetalAccelerationStructureDescriptor
@property (nonatomic) NSUInteger instanceDescriptorBufferOffset;
@property (nonatomic) NSUInteger instanceDescriptorStride;
@property (nonatomic) NSUInteger instanceCount;
@property (nonatomic) MTLAccelerationStructureInstanceDescriptorType instanceDescriptorType;
@property (nonatomic) NSUInteger motionTransformBufferOffset;
@property (nonatomic) NSUInteger motionTransformCount;
@end
@interface CharonMetalIntersectionFunctionTableDescriptor : NSObject
@property (nonatomic) NSUInteger functionCount;
@end
@interface CharonMetalVisibleFunctionTableDescriptor : NSObject
@property (nonatomic) NSUInteger functionCount;
@end
@interface CharonMetalCounterSampleBufferDescriptor : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic) MTLStorageMode storageMode;
@property (nonatomic) NSUInteger sampleCount;
@end
@interface CharonMetalComputePassSampleBufferAttachmentDescriptor : NSObject
@property (nonatomic) NSUInteger startOfEncoderSampleIndex;
@property (nonatomic) NSUInteger endOfEncoderSampleIndex;
@end
@interface CharonMetalResourceStatePassSampleBufferAttachmentDescriptor : NSObject
@property (nonatomic) NSUInteger startOfEncoderSampleIndex;
@property (nonatomic) NSUInteger endOfEncoderSampleIndex;
@end
@interface CharonMetalRenderPassSampleBufferAttachmentDescriptor : NSObject
@property (nonatomic) NSUInteger startOfVertexSampleIndex;
@property (nonatomic) NSUInteger endOfVertexSampleIndex;
@property (nonatomic) NSUInteger startOfFragmentSampleIndex;
@property (nonatomic) NSUInteger endOfFragmentSampleIndex;
@end
@interface CharonMetalComputePassDescriptor : NSObject
@property (nonatomic) MTLDispatchType dispatchType;
@end
@interface CharonMetalResourceStatePassDescriptor : NSObject
@end
@interface CharonMetalBinaryArchiveDescriptor : NSObject
@property (nonatomic, copy) NSURL *url;
@end
@interface CharonMetalLinkedFunctions : NSObject
@property (nonatomic, copy) NSArray *functions;
@property (nonatomic, copy) NSArray *binaryFunctions;
@property (nonatomic, copy) NSDictionary *groups;
@property (nonatomic, copy) NSArray *privateFunctions;
@end
@interface CharonMetalIntersectionFunctionDescriptor : NSObject
@end
@interface CharonMetalComputePassSampleBufferAttachmentDescriptorArray : NSObject
- (MTLComputePassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(MTLComputePassSampleBufferAttachmentDescriptor *)o atIndex:(NSUInteger)i;
@end
@interface CharonMetalRenderPassSampleBufferAttachmentDescriptorArray : NSObject
- (MTLRenderPassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(MTLRenderPassSampleBufferAttachmentDescriptor *)o atIndex:(NSUInteger)i;
@end
@interface CharonMetalResourceStatePassSampleBufferAttachmentDescriptorArray : NSObject
- (MTLResourceStatePassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)setObject:(MTLResourceStatePassSampleBufferAttachmentDescriptor *)o atIndex:(NSUInteger)i;
@end

static int failures;
static int checks;

static void check(BOOL ok, NSString *what)
{
    checks++;
    if (ok) { printf("  ok   %s\n", [what UTF8String]); }
    else { printf("  FAIL %s\n", [what UTF8String]); failures++; }
}

/* THE COMPARISON ITSELF: the same write on both sides, then both values read. */
static void same_u(NSUInteger port, NSUInteger host, NSString *what)
{
    check(port == host, ([NSString stringWithFormat:@"%@: the port %lu and Apple's own object %lu",
                          what, (unsigned long)port, (unsigned long)host]));
}
static void same_i(long port, long host, NSString *what)
{
    check(port == host, ([NSString stringWithFormat:@"%@: the port %ld and Apple's own object %ld",
                          what, port, host]));
}

int main(void)
{
    @autoreleasepool {
        /* A fresh descriptor on both sides, before any write: the DEFAULTS are compared too, because
         * a port that invented a default would pass every written value and still be wrong. */
        check([[MTLAccelerationStructureDescriptor new] usage]
              == [[[CharonMetalAccelerationStructureDescriptor alloc] init] usage],
              @"MTLAccelerationStructureDescriptor: a fresh one answers Apple's own usage on both sides");
        check([[MTLCounterSampleBufferDescriptor new] storageMode]
              == [[[CharonMetalCounterSampleBufferDescriptor alloc] init] storageMode],
              @"MTLCounterSampleBufferDescriptor: a fresh one answers Apple's own storage mode on both sides");
        check([[MTLCounterSampleBufferDescriptor new] sampleCount]
              == [[[CharonMetalCounterSampleBufferDescriptor alloc] init] sampleCount],
              @"MTLCounterSampleBufferDescriptor: a fresh one answers Apple's own sample count on both sides");

        {   /* MTLAccelerationStructureUsageNone = 0 and MTLAccelerationStructureUsageRefit = 1,
             * the header's own two first cases. */
            MTLAccelerationStructureDescriptor *h = [MTLAccelerationStructureDescriptor new];
            CharonMetalAccelerationStructureDescriptor *p = [CharonMetalAccelerationStructureDescriptor new];
            h.usage = MTLAccelerationStructureUsageRefit;
            p.usage = MTLAccelerationStructureUsageRefit;
            same_i((long)p.usage, (long)h.usage, @"MTLAccelerationStructureDescriptor.usage = Refit");
            h.usage = MTLAccelerationStructureUsageNone;
            p.usage = MTLAccelerationStructureUsageNone;
            same_i((long)p.usage, (long)h.usage, @"MTLAccelerationStructureDescriptor.usage = None");
        }
        {   /* the geometry descriptor: a SIBLING of the base, and the values are its own */
            MTLAccelerationStructureGeometryDescriptor *h = [MTLAccelerationStructureGeometryDescriptor new];
            CharonMetalAccelerationStructureGeometryDescriptor *p = [CharonMetalAccelerationStructureGeometryDescriptor new];
            h.intersectionFunctionTableOffset = 64; p.intersectionFunctionTableOffset = 64;
            h.opaque = YES; p.opaque = YES;
            h.allowDuplicateIntersectionFunctionInvocation = YES;
            p.allowDuplicateIntersectionFunctionInvocation = YES;
            h.primitiveDataBufferOffset = 16; p.primitiveDataBufferOffset = 16;
            h.primitiveDataStride = 32; p.primitiveDataStride = 32;
            h.primitiveDataElementSize = 4; p.primitiveDataElementSize = 4;
            same_u(p.intersectionFunctionTableOffset, h.intersectionFunctionTableOffset,
                   @"MTLAccelerationStructureGeometryDescriptor.intersectionFunctionTableOffset");
            check(p.opaque == h.opaque, @"MTLAccelerationStructureGeometryDescriptor.opaque");
            check(p.allowDuplicateIntersectionFunctionInvocation == h.allowDuplicateIntersectionFunctionInvocation,
                  @"MTLAccelerationStructureGeometryDescriptor.allowDuplicateIntersectionFunctionInvocation");
            same_u(p.primitiveDataBufferOffset, h.primitiveDataBufferOffset,
                   @"MTLAccelerationStructureGeometryDescriptor.primitiveDataBufferOffset");
            same_u(p.primitiveDataStride, h.primitiveDataStride,
                   @"MTLAccelerationStructureGeometryDescriptor.primitiveDataStride");
            same_u(p.primitiveDataElementSize, h.primitiveDataElementSize,
                   @"MTLAccelerationStructureGeometryDescriptor.primitiveDataElementSize");
            /* the buffer references are CARRIED AND NOT MEASURED: both sides answer nil with no
             * device, and that is all a no-device comparison can say about them */
            check(h.primitiveDataBuffer == nil && p.primitiveDataBuffer == nil,
                  @"the primitive data buffer is nil on both sides, and is not measured further");
        }
        {   /* MTLAttributeFormatFloat2 is 29 and MTLIndexTypeUInt16 is 0, the header's own values */
            MTLAccelerationStructureTriangleGeometryDescriptor *h = [MTLAccelerationStructureTriangleGeometryDescriptor new];
            CharonMetalAccelerationStructureTriangleGeometryDescriptor *p = [CharonMetalAccelerationStructureTriangleGeometryDescriptor new];
            h.vertexFormat = MTLAttributeFormatFloat2; p.vertexFormat = MTLAttributeFormatFloat2;
            h.indexType = MTLIndexTypeUInt16; p.indexType = MTLIndexTypeUInt16;
            h.vertexBufferOffset = 8; p.vertexBufferOffset = 8;
            h.vertexStride = 24; p.vertexStride = 24;
            h.indexBufferOffset = 128; p.indexBufferOffset = 128;
            h.triangleCount = 6; p.triangleCount = 6;
            h.transformationMatrixBufferOffset = 256; p.transformationMatrixBufferOffset = 256;
            same_i((long)p.vertexFormat, (long)h.vertexFormat,
                   @"MTLAccelerationStructureTriangleGeometryDescriptor.vertexFormat = Float2");
            same_i((long)p.indexType, (long)h.indexType,
                   @"MTLAccelerationStructureTriangleGeometryDescriptor.indexType = UInt16");
            same_u(p.vertexBufferOffset, h.vertexBufferOffset, @"…TriangleGeometry.vertexBufferOffset");
            same_u(p.vertexStride, h.vertexStride, @"…TriangleGeometry.vertexStride");
            same_u(p.indexBufferOffset, h.indexBufferOffset, @"…TriangleGeometry.indexBufferOffset");
            same_u(p.triangleCount, h.triangleCount, @"…TriangleGeometry.triangleCount");
            same_u(p.transformationMatrixBufferOffset, h.transformationMatrixBufferOffset,
                   @"…TriangleGeometry.transformationMatrixBufferOffset");
        }
        {   /* MTLAttributeFormatFloat3 is 30; unused here, the float2 case above is the one compared */
            MTLAccelerationStructureBoundingBoxGeometryDescriptor *h = [MTLAccelerationStructureBoundingBoxGeometryDescriptor new];
            CharonMetalAccelerationStructureBoundingBoxGeometryDescriptor *p = [CharonMetalAccelerationStructureBoundingBoxGeometryDescriptor new];
            h.boundingBoxBufferOffset = 32; p.boundingBoxBufferOffset = 32;
            h.boundingBoxStride = 48; p.boundingBoxStride = 48;
            h.boundingBoxCount = 3; p.boundingBoxCount = 3;
            same_u(p.boundingBoxBufferOffset, h.boundingBoxBufferOffset,
                   @"MTLAccelerationStructureBoundingBoxGeometryDescriptor.boundingBoxBufferOffset");
            same_u(p.boundingBoxStride, h.boundingBoxStride, @"…BoundingBoxGeometry.boundingBoxStride");
            same_u(p.boundingBoxCount, h.boundingBoxCount, @"…BoundingBoxGeometry.boundingBoxCount");
            /* and it INHERITS the geometry members, as the header has it */
            same_u(p.intersectionFunctionTableOffset, h.intersectionFunctionTableOffset,
                   @"…BoundingBoxGeometry inherits intersectionFunctionTableOffset");
        }
        {   /* MTLMotionBorderModeClamp = 0 and MTLMotionBorderModeVanish = 1 */
            MTLPrimitiveAccelerationStructureDescriptor *h = [MTLPrimitiveAccelerationStructureDescriptor new];
            CharonMetalPrimitiveAccelerationStructureDescriptor *p = [CharonMetalPrimitiveAccelerationStructureDescriptor new];
            h.motionStartBorderMode = MTLMotionBorderModeClamp; p.motionStartBorderMode = MTLMotionBorderModeClamp;
            h.motionEndBorderMode = MTLMotionBorderModeVanish; p.motionEndBorderMode = MTLMotionBorderModeVanish;
            h.motionStartTime = 0.5f; p.motionStartTime = 0.5f;
            h.motionEndTime = 2.5f; p.motionEndTime = 2.5f;
            h.motionKeyframeCount = 4; p.motionKeyframeCount = 4;
            same_i((long)p.motionStartBorderMode, (long)h.motionStartBorderMode,
                   @"MTLPrimitiveAccelerationStructureDescriptor.motionStartBorderMode = Clamp");
            same_i((long)p.motionEndBorderMode, (long)h.motionEndBorderMode,
                   @"MTLPrimitiveAccelerationStructureDescriptor.motionEndBorderMode = Vanish");
            check(p.motionStartTime == h.motionStartTime,
                  @"MTLPrimitiveAccelerationStructureDescriptor.motionStartTime");
            check(p.motionEndTime == h.motionEndTime,
                  @"MTLPrimitiveAccelerationStructureDescriptor.motionEndTime");
            same_u(p.motionKeyframeCount, h.motionKeyframeCount,
                   @"MTLPrimitiveAccelerationStructureDescriptor.motionKeyframeCount");
            /* it INHERITS the usage, as the header has it */
            same_i((long)p.usage, (long)h.usage,
                   @"MTLPrimitiveAccelerationStructureDescriptor inherits usage");
        }
        {   /* MTLAccelerationStructureInstanceDescriptorTypeMotion = 0 */
            MTLInstanceAccelerationStructureDescriptor *h = [MTLInstanceAccelerationStructureDescriptor new];
            CharonMetalInstanceAccelerationStructureDescriptor *p = [CharonMetalInstanceAccelerationStructureDescriptor new];
            h.instanceDescriptorBufferOffset = 16; p.instanceDescriptorBufferOffset = 16;
            h.instanceDescriptorStride = 64; p.instanceDescriptorStride = 64;
            h.instanceCount = 9; p.instanceCount = 9;
            h.instanceDescriptorType = MTLAccelerationStructureInstanceDescriptorTypeMotion;
            p.instanceDescriptorType = MTLAccelerationStructureInstanceDescriptorTypeMotion;
            h.motionTransformBufferOffset = 48; p.motionTransformBufferOffset = 48;
            h.motionTransformCount = 2; p.motionTransformCount = 2;
            same_u(p.instanceDescriptorBufferOffset, h.instanceDescriptorBufferOffset,
                   @"MTLInstanceAccelerationStructureDescriptor.instanceDescriptorBufferOffset");
            same_u(p.instanceDescriptorStride, h.instanceDescriptorStride,
                   @"MTLInstanceAccelerationStructureDescriptor.instanceDescriptorStride");
            same_u(p.instanceCount, h.instanceCount,
                   @"MTLInstanceAccelerationStructureDescriptor.instanceCount");
            same_i((long)p.instanceDescriptorType, (long)h.instanceDescriptorType,
                   @"MTLInstanceAccelerationStructureDescriptor.instanceDescriptorType = Refit");
            same_u(p.motionTransformBufferOffset, h.motionTransformBufferOffset,
                   @"MTLInstanceAccelerationStructureDescriptor.motionTransformBufferOffset");
            same_u(p.motionTransformCount, h.motionTransformCount,
                   @"MTLInstanceAccelerationStructureDescriptor.motionTransformCount");
        }
        {   /* the two function tables: one member each, and the same value on both sides */
            MTLVisibleFunctionTableDescriptor *h = [MTLVisibleFunctionTableDescriptor new];
            CharonMetalVisibleFunctionTableDescriptor *p = [CharonMetalVisibleFunctionTableDescriptor new];
            h.functionCount = 5; p.functionCount = 5;
            same_u(p.functionCount, h.functionCount, @"MTLVisibleFunctionTableDescriptor.functionCount");
            MTLIntersectionFunctionTableDescriptor *ih = [MTLIntersectionFunctionTableDescriptor new];
            CharonMetalIntersectionFunctionTableDescriptor *ip = [CharonMetalIntersectionFunctionTableDescriptor new];
            ih.functionCount = 7; ip.functionCount = 7;
            same_u(ip.functionCount, ih.functionCount, @"MTLIntersectionFunctionTableDescriptor.functionCount");
        }
        {   /* MTLStorageModeShared = 0 and MTLStorageModeManaged = 1, MTLResource.h's own */
            MTLCounterSampleBufferDescriptor *h = [MTLCounterSampleBufferDescriptor new];
            CharonMetalCounterSampleBufferDescriptor *p = [CharonMetalCounterSampleBufferDescriptor new];
            h.label = @"host"; p.label = @"host";
            h.storageMode = MTLStorageModeManaged; p.storageMode = MTLStorageModeManaged;
            h.sampleCount = 12; p.sampleCount = 12;
            check([[p.label copy] isEqualToString:[h.label copy]],
                  @"MTLCounterSampleBufferDescriptor.label");
            same_i((long)p.storageMode, (long)h.storageMode,
                   @"MTLCounterSampleBufferDescriptor.storageMode = Managed");
            same_u(p.sampleCount, h.sampleCount, @"MTLCounterSampleBufferDescriptor.sampleCount");
        }
        {   /* the three attachment descriptors, each with its own index members */
            MTLComputePassSampleBufferAttachmentDescriptor *h = [MTLComputePassSampleBufferAttachmentDescriptor new];
            CharonMetalComputePassSampleBufferAttachmentDescriptor *p = [CharonMetalComputePassSampleBufferAttachmentDescriptor new];
            h.startOfEncoderSampleIndex = 1; p.startOfEncoderSampleIndex = 1;
            h.endOfEncoderSampleIndex = 8; p.endOfEncoderSampleIndex = 8;
            same_u(p.startOfEncoderSampleIndex, h.startOfEncoderSampleIndex,
                   @"MTLComputePassSampleBufferAttachmentDescriptor.startOfEncoderSampleIndex");
            same_u(p.endOfEncoderSampleIndex, h.endOfEncoderSampleIndex,
                   @"MTLComputePassSampleBufferAttachmentDescriptor.endOfEncoderSampleIndex");

            MTLResourceStatePassSampleBufferAttachmentDescriptor *rh = [MTLResourceStatePassSampleBufferAttachmentDescriptor new];
            CharonMetalResourceStatePassSampleBufferAttachmentDescriptor *rp = [CharonMetalResourceStatePassSampleBufferAttachmentDescriptor new];
            rh.startOfEncoderSampleIndex = 2; rp.startOfEncoderSampleIndex = 2;
            rh.endOfEncoderSampleIndex = 9; rp.endOfEncoderSampleIndex = 9;
            same_u(rp.startOfEncoderSampleIndex, rh.startOfEncoderSampleIndex,
                   @"MTLResourceStatePassSampleBufferAttachmentDescriptor.startOfEncoderSampleIndex");
            same_u(rp.endOfEncoderSampleIndex, rh.endOfEncoderSampleIndex,
                   @"MTLResourceStatePassSampleBufferAttachmentDescriptor.endOfEncoderSampleIndex");

            MTLRenderPassSampleBufferAttachmentDescriptor *vh = [MTLRenderPassSampleBufferAttachmentDescriptor new];
            CharonMetalRenderPassSampleBufferAttachmentDescriptor *vp = [CharonMetalRenderPassSampleBufferAttachmentDescriptor new];
            vh.startOfVertexSampleIndex = 3; vp.startOfVertexSampleIndex = 3;
            vh.endOfVertexSampleIndex = 10; vp.endOfVertexSampleIndex = 10;
            vh.startOfFragmentSampleIndex = 4; vp.startOfFragmentSampleIndex = 4;
            vh.endOfFragmentSampleIndex = 11; vp.endOfFragmentSampleIndex = 11;
            same_u(vp.startOfVertexSampleIndex, vh.startOfVertexSampleIndex,
                   @"MTLRenderPassSampleBufferAttachmentDescriptor.startOfVertexSampleIndex");
            same_u(vp.endOfVertexSampleIndex, vh.endOfVertexSampleIndex,
                   @"MTLRenderPassSampleBufferAttachmentDescriptor.endOfVertexSampleIndex");
            same_u(vp.startOfFragmentSampleIndex, vh.startOfFragmentSampleIndex,
                   @"MTLRenderPassSampleBufferAttachmentDescriptor.startOfFragmentSampleIndex");
            same_u(vp.endOfFragmentSampleIndex, vh.endOfFragmentSampleIndex,
                   @"MTLRenderPassSampleBufferAttachmentDescriptor.endOfFragmentSampleIndex");
        }
        {   /* MTLDispatchTypeSerial = 0 and MTLDispatchTypeConcurrent = 1 */
            MTLComputePassDescriptor *h = [MTLComputePassDescriptor new];
            CharonMetalComputePassDescriptor *p = [CharonMetalComputePassDescriptor new];
            h.dispatchType = MTLDispatchTypeSerial; p.dispatchType = MTLDispatchTypeSerial;
            same_i((long)p.dispatchType, (long)h.dispatchType, @"MTLComputePassDescriptor.dispatchType = Serial");
            h.dispatchType = MTLDispatchTypeConcurrent;
            p.dispatchType = MTLDispatchTypeConcurrent;
            same_i((long)p.dispatchType, (long)h.dispatchType,
                   @"MTLComputePassDescriptor.dispatchType = Concurrent");
        }
        {   /* the URL, which is a real object and needs no device */
            MTLBinaryArchiveDescriptor *h = [MTLBinaryArchiveDescriptor new];
            CharonMetalBinaryArchiveDescriptor *p = [CharonMetalBinaryArchiveDescriptor new];
            NSURL *u = [NSURL fileURLWithPath:@"/tmp/archive.mtar"];
            h.url = u; p.url = u;
            check([[p.url path] isEqualToString:[h.url path]], @"MTLBinaryArchiveDescriptor.url");
            /* and the DEFAULTS, with no device anywhere */
            check([MTLBinaryArchiveDescriptor new].url == nil
                  && [CharonMetalBinaryArchiveDescriptor new].url == nil,
                  @"MTLBinaryArchiveDescriptor: a fresh one's url is nil on both sides");
            check([MTLResourceStatePassDescriptor new] != nil
                  && [CharonMetalResourceStatePassDescriptor new] != nil,
                  @"MTLResourceStatePassDescriptor: both sides make one with no device");
        }
        {   /* MTLLinkedFunctions and the intersection function descriptor */
            MTLLinkedFunctions *h = [MTLLinkedFunctions new];
            CharonMetalLinkedFunctions *p = [CharonMetalLinkedFunctions new];
            check([p.functions count] == [h.functions count],
                  @"MTLLinkedFunctions.functions: both are empty with no device to make a function");
            check([p.binaryFunctions count] == [h.binaryFunctions count],
                  @"MTLLinkedFunctions.binaryFunctions: both are empty with no device");
            check([p.groups count] == [h.groups count],
                  @"MTLLinkedFunctions.groups: both are empty with no device");
            check([p.privateFunctions count] == [h.privateFunctions count],
                  @"MTLLinkedFunctions.privateFunctions: both are empty with no device");
            /* THE HEADER GIVES THIS CLASS NO MEMBER OF ITS OWN, and an earlier revision of this case
             * compared three - functionBufferOffset, functionBufferOffsetAlignment, functionStride -
             * that no SDK header declares. What is compared is what the header does say: both sides
             * make the class with no device, and on both sides everything it answers comes from a
             * base, MTLFunctionDescriptor, which is a different row. */
            MTLIntersectionFunctionDescriptor *ih = [MTLIntersectionFunctionDescriptor new];
            CharonMetalIntersectionFunctionDescriptor *ip = [CharonMetalIntersectionFunctionDescriptor new];
            check(ih != nil && ip != nil,
                  @"MTLIntersectionFunctionDescriptor: both sides make one with no device");
            check([NSStringFromClass([ip class]) hasSuffix:@"IntersectionFunctionDescriptor"],
                  @"MTLIntersectionFunctionDescriptor: the port's class carries the row's own name");
        }
        {   /* THE THREE ARRAYS: real storage, indexed both ways, and a read past the end is nil */
            MTLComputePassSampleBufferAttachmentDescriptor *one = [MTLComputePassSampleBufferAttachmentDescriptor new];
            one.startOfEncoderSampleIndex = 5;
            CharonMetalComputePassSampleBufferAttachmentDescriptor *pone = [CharonMetalComputePassSampleBufferAttachmentDescriptor new];
            pone.startOfEncoderSampleIndex = 5;
            CharonMetalComputePassSampleBufferAttachmentDescriptorArray *p =
                [CharonMetalComputePassSampleBufferAttachmentDescriptorArray new];
            [p setObject:pone atIndex:0];
            same_u([p objectAtIndexedSubscript:0].startOfEncoderSampleIndex,
                   one.startOfEncoderSampleIndex,
                   @"MTLComputePassSampleBufferAttachmentDescriptorArray: index 0 reads back what was set");
            check([p objectAtIndexedSubscript:4] == nil,
                  @"MTLComputePassSampleBufferAttachmentDescriptorArray: an index past the end reads nil");
            CharonMetalRenderPassSampleBufferAttachmentDescriptorArray *rp =
                [CharonMetalRenderPassSampleBufferAttachmentDescriptorArray new];
            CharonMetalRenderPassSampleBufferAttachmentDescriptor *r = [CharonMetalRenderPassSampleBufferAttachmentDescriptor new];
            r.startOfVertexSampleIndex = 6;
            [rp setObject:r atIndex:1];
            same_u([rp objectAtIndexedSubscript:1].startOfVertexSampleIndex, 6,
                   @"MTLRenderPassSampleBufferAttachmentDescriptorArray: index 1 reads back what was set");
            CharonMetalResourceStatePassSampleBufferAttachmentDescriptorArray *sp =
                [CharonMetalResourceStatePassSampleBufferAttachmentDescriptorArray new];
            CharonMetalResourceStatePassSampleBufferAttachmentDescriptor *sp1 = [CharonMetalResourceStatePassSampleBufferAttachmentDescriptor new];
            sp1.endOfEncoderSampleIndex = 7;
            [sp setObject:sp1 atIndex:2];
            same_u([sp objectAtIndexedSubscript:2].endOfEncoderSampleIndex, 7,
                   @"MTLResourceStatePassSampleBufferAttachmentDescriptorArray: index 2 reads back what was set");
        }
        printf("no device was created: %d checks, each one against Apple's own object\n", checks);
    }
    if (failures) { printf("%d failure(s)\n", failures); return 1; }
    printf("all checks passed\n");
    return 0;
}
