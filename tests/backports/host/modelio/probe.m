// One probe, two processes. Built once against the system's ModelIO and once against the port's own
// sources, it is run on the same generated inputs in both, and each writes what it computed as
// canonical text: the vertices, indices and bounds of every mesh it loaded, the transforms and
// animated values, the texels of a texture, the voxels of an array, the properties of a material.
// run.sh then compares the two files line by line.
//
// Nothing here is tuned to agree. A line that differs is a line where the port and the system answer
// differently, and it is reported as it is: that is the measurement.
#import <Foundation/Foundation.h>
#import <ModelIO/ModelIO.h>
#import <simd/simd.h>
#import <string.h>

#if !MDL_TEXTURE_TAKES_IS_CUBE
#import "port-support.h"
#endif

static void put(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void put(NSString *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    printf("%s\n", line.UTF8String);
}

// A section the system refuses is an answer, not the end of the run: what it said is printed and the
// rest of the probe still runs.
static void guard(NSString *key, void (^body)(void));

static void guard(NSString *key, void (^body)(void))
{
    @try {
        body();
    } @catch (NSException *exception) {
        put(@"%@ this side does not answer: %@: %@", key, exception.name, exception.reason);
    }
}

static void put3(NSString *key, vector_float3 v)
{
    put(@"%@ %.5f %.5f %.5f", key, v.x, v.y, v.z);
}

static void put_box(NSString *key, MDLAxisAlignedBoundingBox box)
{
    put(@"%@ min %.5f %.5f %.5f max %.5f %.5f %.5f", key, box.minBounds.x, box.minBounds.y, box.minBounds.z, box.maxBounds.x, box.maxBounds.y, box.maxBounds.z);
}

// The bytes of a block, as a length and a checksum, so a difference anywhere in it is named without
// printing a megabyte of hex.
static void put_bytes(NSString *key, NSData *data)
{
    const uint8_t *bytes = data.bytes;
    uint32_t sum = 2166136261u;
    for (NSUInteger k = 0; k < data.length; k++) {
        sum ^= bytes[k];
        sum *= 16777619u;
    }
    put(@"%@ %lu %08x", key, (unsigned long)data.length, sum);
}

#pragma mark - the inputs both processes are given

// A Wavefront object: two groups, a quad, a triangle, normals, texture coordinates and a material
// name, so a reader is measured on its sharing of its vertices and on the order of its faces.
static void writeOBJ(NSString *path)
{
    NSArray<NSString *> *lines = @[
        @"# a cube of two faces, one of them a quad",
        @"mtllib cube.mtl",
        @"o solid",
        @"v -1 -1 0", @"v 1 -1 0", @"v 1 1 0", @"v -1 1 0", @"v 0 0 1",
        @"vt 0 0", @"vt 1 0", @"vt 1 1", @"vt 0 1",
        @"vn 0 0 1", @"vn 0 0 -1",
        @"usemtl red",
        @"f 1/1/1 2/2/1 4/4/1 3/3/1",
        @"g lid",
        @"f 1/1/1 3/3/1 5",
    ];
    [[lines componentsJoinedByString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

// The same shape as a polygon file in its ASCII form, with a colour per vertex and a face list of
// three, so the reader is measured over its header's properties and its fan of a face.
static void writePLYAscii(NSString *path)
{
    NSArray<NSString *> *lines = @[
        @"ply", @"format ascii 1.0", @"comment a triangle with a colour", @"element vertex 4",
        @"property float x", @"property float y", @"property float z", @"property float nx",
        @"property float ny", @"property float nz", @"property uchar red", @"property uchar green",
        @"property uchar blue", @"element face 2", @"property list uchar int vertex_indices", @"end_header",
        @"0 0 0 0 0 1 255 0 0", @"1 0 0 0 0 1 0 255 0", @"1 1 0 0 0 1 0 0 255", @"0 1 0 0 0 1 255 255 0",
        @"3 0 1 2", @"3 0 2 3",
    ];
    [[lines componentsJoinedByString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

// The same file in its binary little-endian form, so the reader is measured on reading a body at the
// layout the header states rather than at the header's own words.
static void writePLYBinary(NSString *path)
{
    NSMutableData *data = [NSMutableData data];
    const char *header = "ply\nformat binary_little_endian 1.0\nelement vertex 4\nproperty float x\nproperty float y\n"
                         "property float z\nproperty float nx\nproperty float ny\nproperty float nz\n"
                         "property uchar red\nproperty uchar green\nproperty uchar blue\n"
                         "element face 2\nproperty list uchar int vertex_indices\nend_header\n";
    [data appendBytes:header length:strlen(header)];
    const float positions[4][3] = {{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}};
    const uint8_t colours[4][3] = {{255, 0, 0}, {0, 255, 0}, {0, 0, 255}, {255, 255, 0}};
    for (int k = 0; k < 4; k++) {
        [data appendBytes:positions[k] length:12];
        float normal[3] = {0, 0, 1};
        [data appendBytes:normal length:12];
        [data appendBytes:colours[k] length:3];
    }
    for (int face = 0; face < 2; face++) {
        uint8_t count = 3;
        [data appendBytes:&count length:1];
        int32_t indices[3] = {face, face + 1, face + 2};
        [data appendBytes:indices length:12];
    }
    [data writeToFile:path atomically:YES];
}

// A mesh prim of the ASCII scene description: four points, two triangular faces, and a bound.
static void writeUSDA(NSString *path)
{
    NSArray<NSString *> *lines = @[
        @"#usda 1.0", @"(", @"    defaultPrim = \"root\"", @"    upAxis = \"Y\"", @")", @"def Mesh \"plate\"",
        @"    int[] faceVertexCounts = [3, 3]",
        @"    int[] faceVertexIndices = [0, 1, 2, 0, 2, 3]",
        @"    point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]",
        @"    uniform token subdivisionScheme = \"none\"",
    ];
    [[lines componentsJoinedByString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

#pragma mark - the measurements

static void reportMesh(MDLMesh *mesh, NSString *key)
{
    put(@"%@ name %@", key, mesh.name);
    put(@"%@ vertices %lu", key, (unsigned long)mesh.vertexCount);
    put(@"%@ submeshes %lu", key, (unsigned long)mesh.submeshes.count);
    for (MDLSubmesh *submesh in mesh.submeshes) {
        put(@"%@ submesh %@ indices %lu depth %lu geometry %ld", key, submesh.name, (unsigned long)submesh.indexCount,
            (unsigned long)submesh.indexType, (long)submesh.geometryType);
        MDLVertexAttributeData *positions = [mesh vertexAttributeDataForAttributeNamed:MDLVertexAttributePosition
                                                                             asFormat:MDLVertexFormatFloat3];
        MDLVertexAttributeData *normals = [mesh vertexAttributeDataForAttributeNamed:MDLVertexAttributeNormal
                                                                           asFormat:MDLVertexFormatFloat3];
        MDLVertexAttributeData *uvs = [mesh vertexAttributeDataForAttributeNamed:MDLVertexAttributeTextureCoordinate
                                                                      asFormat:MDLVertexFormatFloat2];
        if (positions)
            for (NSUInteger v = 0; v < mesh.vertexCount && v < 8; v++)
                put3([NSString stringWithFormat:@"%@ v%lu p", key, (unsigned long)v],
                     *(vector_float3 *)((uint8_t *)positions.dataStart + v * positions.stride));
        if (normals)
            for (NSUInteger v = 0; v < mesh.vertexCount && v < 4; v++)
                put3([NSString stringWithFormat:@"%@ v%lu n", key, (unsigned long)v],
                     *(vector_float3 *)((uint8_t *)normals.dataStart + v * normals.stride));
        if (uvs)
            for (NSUInteger v = 0; v < mesh.vertexCount && v < 4; v++) {
                vector_float2 uv = *(vector_float2 *)((uint8_t *)uvs.dataStart + v * uvs.stride);
                put(@"%@ v%lu uv %.5f %.5f", key, (unsigned long)v, uv.x, uv.y);
            }
        put(@"%@ submesh material %@ properties %lu", key, submesh.material.name ?: @"-", (unsigned long)submesh.material.count);
        for (MDLMaterialProperty *property in submesh.material) {
            put(@"%@ property %@ semantic %lu type %lu", key, property.name, (unsigned long)property.semantic,
                (unsigned long)property.type);
            if (property.type == MDLMaterialPropertyTypeFloat3)
                put3([NSString stringWithFormat:@"%@ property %@ value", key, property.name], property.float3Value);
            else if (property.type == MDLMaterialPropertyTypeFloat)
                put(@"%@ property %@ value %.5f", key, property.name, property.floatValue);
        }
    }
    put_box([key stringByAppendingString:@" box"], mesh.boundingBox);
}

static NSString *inputDirectory;

static void reportAsset(NSString *key, NSString *extension)
{
    MDLAsset *asset = [[MDLAsset alloc] initWithURL:[NSURL fileURLWithPath:[inputDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", key, extension]]]];
    put(@"%@ canImport %d", key, [MDLAsset canImportFileExtension:extension]);
    put(@"%@ objects %lu", key, (unsigned long)asset.count);
    put_box([key stringByAppendingString:@" box"], asset.boundingBox);
    for (MDLObject *object in asset) {
        if ([object isKindOfClass:[MDLMesh class]])
            reportMesh((MDLMesh *)object, [key stringByAppendingString:@" mesh"]);
        else
            put(@"%@ object %@", key, NSStringFromClass([object class]));
    }
}

static void reportTransform(void)
{
    matrix_float4x4 matrix = {{2, 0, 0, 0}, {0, 3, 0, 0}, {0, 0, 4, 1}, {5, 6, 7, 1}};
    MDLTransform *transform = [[MDLTransform alloc] init];
    [transform setMatrix:matrix];
    put3(@"transform translation", [transform translationAtTime:0]);
    put3(@"transform scale", [transform scaleAtTime:0]);
    put3(@"transform rotation", [transform rotationAtTime:0]);
    put3(@"transform shear", [transform shearAtTime:0]);
    put(@"transform keyTimes %lu", (unsigned long)transform.keyTimes.count);
    [transform setTranslation:(vector_float3){1, 2, 3} forTime:0];
    put3(@"transform after setTranslation", [transform translationAtTime:0]);

    MDLAnimatedScalar *scalar = [[MDLAnimatedScalar alloc] init];
    [scalar setFloat:0 atTime:0];
    [scalar setFloat:10 atTime:1];
    for (NSTimeInterval t = -0.5; t <= 1.5; t += 0.25)
        put(@"animated scalar %g %.5f", t, [scalar floatAtTime:t]);
    put(@"animated scalar keyTimes %@", [scalar.keyTimes componentsJoinedByString:@","]);

    MDLAnimatedVector3 *vector = [[MDLAnimatedVector3 alloc] init];
    [vector setFloat3:(vector_float3){0, 0, 0} atTime:0];
    [vector setFloat3:(vector_float3){1, 2, 3} atTime:2];
    put3(@"animated vector at 1", [vector float3AtTime:1]);
    put(@"animated vector animated %d samples %lu", [vector isAnimated], (unsigned long)vector.timeSampleCount);

    MDLTransformStack *stack = [[MDLTransformStack alloc] init];
    MDLTransformTranslateOp *translate = [stack addTranslateOp:@"t" inverse:NO];
    MDLTransformRotateXOp *rotate = [stack addRotateXOp:@"r" inverse:NO];
    [(MDLAnimatedVector3 *)[translate animatedValue] setFloat3:(vector_float3){1, 2, 3} atTime:0];
    [(MDLAnimatedScalar *)[rotate animatedValue] setFloat:(float)M_PI_2 atTime:0];
    put(@"stack count %lu", (unsigned long)stack.count);
    put(@"stack names %@ %@", [translate name], [rotate name]);
    matrix_float4x4 product = [stack float4x4AtTime:0];
    for (int c = 0; c < 4; c++)
        put(@"stack matrix %d %.5f %.5f %.5f %.5f", c, product.columns[c][0], product.columns[c][1], product.columns[c][2],
            product.columns[c][3]);
    put(@"stack value by name %@", [[[stack animatedValueWithName:@"t"] class] description]);
}

static void reportGenerators(void)
{
    // The two SDKs disagree on the plane: the iOS 16.4 header takes inwardNormals: and the macOS one
    // does not, so the plane is the one generator the two processes cannot be asked the same
    // question about. It is named here rather than skipped quietly.
#if MDL_PLANE_TAKES_INWARD_NORMALS
    MDLMesh *plane = [MDLMesh newPlaneWithDimensions:(vector_float2){2, 2} segments:(vector_uint2){2, 3}
                                            geometryType:MDLGeometryTypeTriangles inwardNormals:NO allocator:nil];
    put(@"plane vertices %lu indices %lu", (unsigned long)plane.vertexCount,
        (unsigned long)plane.submeshes.firstObject.indexCount);
    put_box(@"plane", plane.boundingBox);
#else
    MDLMesh *plane = [MDLMesh newPlaneWithDimensions:(vector_float2){2, 2} segments:(vector_uint2){2, 3}
                                            geometryType:MDLGeometryTypeTriangles allocator:nil];
    put(@"plane vertices %lu indices %lu", (unsigned long)plane.vertexCount,
        (unsigned long)plane.submeshes.firstObject.indexCount);
    put_box(@"plane", plane.boundingBox);
#endif
    MDLMesh *box = [MDLMesh newBoxWithDimensions:(vector_float3){2, 2, 2} segments:(vector_uint3){1, 1, 1}
                                      geometryType:MDLGeometryTypeTriangles inwardNormals:NO allocator:nil];
    put(@"box vertices %lu indices %lu", (unsigned long)box.vertexCount, (unsigned long)box.submeshes.firstObject.indexCount);
    put_box(@"box", box.boundingBox);
    MDLMesh *ball = [MDLMesh newEllipsoidWithRadii:(vector_float3){1, 2, 3} radialSegments:8 verticalSegments:6
                                      geometryType:MDLGeometryTypeTriangles inwardNormals:NO hemisphere:NO allocator:nil];
    put(@"ellipsoid vertices %lu indices %lu", (unsigned long)ball.vertexCount,
        (unsigned long)ball.submeshes.firstObject.indexCount);
    put_box(@"ellipsoid", ball.boundingBox);
    MDLMesh *cylinder = [MDLMesh newCylinderWithHeight:4 radii:(vector_float2){1, 1} radialSegments:8 verticalSegments:2
                                         geometryType:MDLGeometryTypeTriangles inwardNormals:NO allocator:nil];
    put(@"cylinder vertices %lu indices %lu", (unsigned long)cylinder.vertexCount,
        (unsigned long)cylinder.submeshes.firstObject.indexCount);
    put_box(@"cylinder", cylinder.boundingBox);
}

static void reportSubmesh(void)
{
    MDLMeshBufferData *indices = [[MDLMeshBufferData alloc] initWithType:MDLMeshBufferTypeIndex data:
                                                    [NSData dataWithBytes:(uint32_t[]){0, 1, 2, 2, 1, 3} length:24]];
    NSMutableData *empty = [NSMutableData dataWithLength:4 * 32];
    MDLMeshBufferData *vertices = [[MDLMeshBufferData alloc] initWithType:MDLMeshBufferTypeVertex data:empty];
    MDLVertexDescriptor *descriptor = [[MDLVertexDescriptor alloc] init];
    [descriptor addOrReplaceAttribute:[[MDLVertexAttribute alloc] initWithName:MDLVertexAttributePosition
                                                                       format:MDLVertexFormatFloat3 offset:0 bufferIndex:0]];
    [descriptor.layouts addObject:[[MDLVertexBufferLayout alloc] initWithStride:32]];
    MDLSubmesh *submesh = [[MDLSubmesh alloc] initWithName:@"s" indexBuffer:indices indexCount:6
                                                   indexType:MDLIndexBitDepthUInt32 geometryType:MDLGeometryTypeTriangles
                                                   material:nil];
    MDLMesh *mesh = [[MDLMesh alloc] initWithVertexBuffers:@[vertices] vertexCount:4 descriptor:descriptor
                                                submeshes:@[submesh]];
    put(@"mesh vertices %lu submeshes %lu", (unsigned long)mesh.vertexCount, (unsigned long)mesh.submeshes.count);
    put_box(@"mesh", mesh.boundingBox);
    id<MDLMeshBuffer> narrow = [submesh indexBufferAsIndexType:MDLIndexBitDepthUInt16];
    put(@"submesh 16 bit buffer %@", narrow ? @"made" : @"none");
    if (narrow) {
        uint8_t *bytes = [narrow map].bytes;
        NSMutableData *out = [NSMutableData data];
        for (NSUInteger k = 0; k < 6; k++) {
            uint16_t value = 0;
            memcpy(&value, bytes + k * 2, 2);
            [out appendBytes:&value length:2];
        }
        put_bytes(@"submesh 16 bit", out);
    }
    put(@"mesh attributes %lu", (unsigned long)mesh.vertexDescriptor.attributes.count);
}

static void reportTexture(void)
{
    NSMutableData *texels = [NSMutableData dataWithLength:8 * 8 * 4];
    uint8_t *bytes = texels.mutableBytes;
    for (NSUInteger k = 0; k < 8 * 8 * 4; k++)
        bytes[k] = (uint8_t)(k * 7 + (k / 32));
    // The iOS header's initialiser has no isCube: and the macOS one has it as its designated one, so
    // each side is asked through the initialiser it declares and what is compared is the texels.
#if MDL_TEXTURE_TAKES_IS_CUBE
    MDLTexture *texture = [[MDLTexture alloc] initWithData:texels topLeftOrigin:NO name:@"t" dimensions:(vector_int2){8, 8}
                                                rowStride:32 channelCount:4 channelEncoding:MDLTextureChannelEncodingUInt8
                                                    isCube:NO];
#else
    MDLTexture *texture = [[MDLTexture alloc] initWithData:texels topLeftOrigin:NO name:@"t" dimensions:(vector_int2){8, 8}
                                                rowStride:32 channelCount:4 channelEncoding:MDLTextureChannelEncodingUInt8];
#endif
    put(@"texture dimensions %ld %ld stride %ld channels %lu mips %lu", (long)texture.dimensions.x, (long)texture.dimensions.y,
        (long)texture.rowStride, (unsigned long)texture.channelCount, (unsigned long)texture.mipLevelCount);
    put_bytes(@"texture bottom left", [texture texelDataWithBottomLeftOrigin]);
    put_bytes(@"texture top left", [texture texelDataWithTopLeftOrigin]);
    put(@"texture alpha %d cube %d", texture.hasAlphaValues, texture.isCube);
}

static void reportObjectAndVoxels(void)
{
    MDLObject *root = [[MDLObject alloc] init], *child = [[MDLObject alloc] init];
    root.name = @"root";
    child.name = @"child";
    [root addChild:child];
    put(@"object children %lu path %@", (unsigned long)root.children.count, child.path);
    put(@"object at path %d", [root objectAtPath:@"/root/child"] == child);
    put_box(@"object", [root boundingBoxAtTime:0]);

    // maxBounds first, as the struct declares it: a box of the unit cube is a maximum of one and a
    // minimum of zero, and written the other way round the framework rightly refuses it.
    MDLAxisAlignedBoundingBox box = {{1, 1, 1}, {0, 0, 0}};
    // The signed shell field of a 4x4x4 division, all of it empty: one byte per voxel, as the header
    // says the data is.
    NSMutableData *empty = [NSMutableData dataWithLength:2 * 2 * 2];
    MDLVoxelArray *host = nil;
    @try {
        host = [[MDLVoxelArray alloc] initWithData:empty boundingBox:box voxelExtent:0.5f];
    } @catch (NSException *exception) {
        put(@"voxels the array this side does not accept: %@: %@", exception.name, exception.reason);
        return;
    }
    [host setVoxelAtIndex:(MDLVoxelIndex){0, 0, 0}];
    [host setVoxelAtIndex:(MDLVoxelIndex){1, 1, 0}];
    put(@"voxels %lu", (unsigned long)host.count);
    MDLVoxelIndexExtent extent = host.voxelIndexExtent;
    put(@"voxel extent %ld %ld %ld to %ld %ld %ld", (long)extent.minimumExtent.x, (long)extent.minimumExtent.y,
        (long)extent.minimumExtent.z, (long)extent.maximumExtent.x, (long)extent.maximumExtent.y,
        (long)extent.maximumExtent.z);
    MDLVoxelIndex at = [host indexOfSpatialLocation:(vector_float3){0.9f, 0.6f, 0.4f}];
    put(@"voxel index %ld %ld %ld", (long)at.x, (long)at.y, (long)at.z);
    put3(@"voxel centre", [host spatialLocationOfIndex:(MDLVoxelIndex){1, 1, 1}]);
    MDLVoxelArray *other = [[MDLVoxelArray alloc] initWithData:[NSMutableData dataWithLength:2 * 2 * 2]
                                                     boundingBox:box voxelExtent:0.5f];
    [other setVoxelAtIndex:(MDLVoxelIndex){1, 1, 1}];
    [host unionWithVoxels:other];
    put(@"voxels after union %lu", (unsigned long)host.count);
    [host differenceWithVoxels:other];
    put(@"voxels after difference %lu", (unsigned long)host.count);
    put_bytes(@"voxel indices", [host voxelIndices]);
}

// The sharing rule of a generator, read off the counts: the vertex count and the index count of the
// same surface with its segments varied say where a vertex is shared and where one is not, and the
// box says the surface itself did not change.
static void reportSharing(void)
{
    static const NSUInteger radial[] = {3, 4, 6, 8, 12};
    static const NSUInteger vertical[] = {1, 2, 3, 6};
    for (size_t r = 0; r < sizeof radial / sizeof *radial; r++)
        for (size_t v = 0; v < sizeof vertical / sizeof *vertical; v++) {
            MDLMesh *ball = [MDLMesh newEllipsoidWithRadii:(vector_float3){1, 1, 1} radialSegments:radial[r]
                                               verticalSegments:vertical[v] geometryType:MDLGeometryTypeTriangles
                                               inwardNormals:NO hemisphere:NO allocator:nil];
            put(@"share ellipsoid r%lu v%lu vertices %lu indices %lu", (unsigned long)radial[r], (unsigned long)vertical[v],
                (unsigned long)ball.vertexCount, (unsigned long)ball.submeshes.firstObject.indexCount);
        }
    for (size_t r = 0; r < sizeof radial / sizeof *radial; r++)
        for (size_t v = 0; v < 2; v++) {
            MDLMesh *tube = [MDLMesh newCylinderWithHeight:2 radii:(vector_float2){1, 1} radialSegments:radial[r]
                                            verticalSegments:vertical[v] + 1 geometryType:MDLGeometryTypeTriangles
                                            inwardNormals:NO allocator:nil];
            put(@"share cylinder r%lu v%lu vertices %lu indices %lu", (unsigned long)radial[r], (unsigned long)(vertical[v] + 1),
                (unsigned long)tube.vertexCount, (unsigned long)tube.submeshes.firstObject.indexCount);
            MDLMesh *box = [MDLMesh newBoxWithDimensions:(vector_float3){2, 2, 2} segments:(vector_uint3){radial[r], vertical[v], 1}
                                             geometryType:MDLGeometryTypeTriangles inwardNormals:NO allocator:nil];
            put(@"share box r%lu v%lu vertices %lu indices %lu", (unsigned long)radial[r], (unsigned long)vertical[v],
                (unsigned long)box.vertexCount, (unsigned long)box.submeshes.firstObject.indexCount);
        }
}

// The extent of a voxel's division, read off arrays of a known size: the count of the voxels, the
// extent the array reports, and what the box and the voxel size were.
static void reportVoxelRules(void)
{
    for (int along = 1; along <= 4; along++)
        for (int voxel = 1; voxel <= 2; voxel++) {
            MDLAxisAlignedBoundingBox box = {{along * voxel, along * voxel, along * voxel}, {0, 0, 0}};
            NSMutableData *field = [NSMutableData dataWithLength:(NSUInteger)(along * along * along)];
            @try {
                MDLVoxelArray *array = [[MDLVoxelArray alloc] initWithData:field boundingBox:box voxelExtent:(float)voxel];
                MDLVoxelIndexExtent extent = array.voxelIndexExtent;
                put(@"voxrule %ld voxels of %d data %lu extent %ld %ld %ld to %ld %ld %ld", (long)along, voxel,
                    (unsigned long)field.length, (long)extent.minimumExtent.x, (long)extent.minimumExtent.y,
                    (long)extent.minimumExtent.z, (long)extent.maximumExtent.x, (long)extent.maximumExtent.y,
                    (long)extent.maximumExtent.z);
            } @catch (NSException *exception) {
                put(@"voxrule %ld voxels of %d refused %@", (long)along, voxel, exception.reason);
            }
        }
}

int main(int argc, const char **argv)
{
    @autoreleasepool {
        NSString *directory = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : NSTemporaryDirectory();
        inputDirectory = directory;
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        writeOBJ([directory stringByAppendingPathComponent:@"cube.obj"]);
        writePLYAscii([directory stringByAppendingPathComponent:@"tri.ply"]);
        writePLYBinary([directory stringByAppendingPathComponent:@"tribin.ply"]);
        writeUSDA([directory stringByAppendingPathComponent:@"plate.usda"]);

        put(@"probe %@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"] ?: @"host");
        put(@"canImport obj %d ply %d usda %d usd %d", [MDLAsset canImportFileExtension:@"obj"],
            [MDLAsset canImportFileExtension:@"ply"], [MDLAsset canImportFileExtension:@"usda"],
            [MDLAsset canImportFileExtension:@"usd"]);
        guard(@"assets", ^{
            reportAsset(@"cube", @"obj");
            reportAsset(@"tri", @"ply");
            reportAsset(@"tribin", @"ply");
            reportAsset(@"plate", @"usda");
        });
        guard(@"transform", ^{ reportTransform(); });
        guard(@"generators", ^{ reportGenerators(); });
        guard(@"submesh", ^{ reportSubmesh(); });
        guard(@"texture", ^{ reportTexture(); });
        guard(@"object", ^{ reportObjectAndVoxels(); });
        guard(@"sharing", ^{ reportSharing(); });
        guard(@"voxrule", ^{ reportVoxelRules(); });
    }
    return 0;
}
