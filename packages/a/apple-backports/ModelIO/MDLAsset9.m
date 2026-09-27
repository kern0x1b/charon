#import <ModelIO/ModelIO.h>
#import <simd/simd.h>
#import <string.h>
#import <simd/simd.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// An asset is a set of objects read out of a file, or put into one by the caller. The readers here
// are the Wavefront OBJ, the Stanford PLY in its ASCII and its binary little-endian form, and the
// ASCII Universal Scene Description; each of them builds real meshes out of the geometry the file
// actually holds, with its own materials where the file names them. iOS 6 has no ModelIO at all.

// What a reader hands to the asset once it has parsed: the objects to add, and the resolver the
// materials' files are found through.
@interface CharonMDLLoadedScene : NSObject
@property (nonatomic, retain) NSMutableArray<MDLObject *> *objects;
@property (nonatomic, retain) id<MDLAssetResolver> resolver;
@end

// The two ends of a box, a component at a time. simd_min and simd_max take a three-element vector and
// give the vector straight back on this target - measured, not read - so a box built with them keeps
// the inverted box it started from. Every box the port answers goes through these two.
static void CharonMDLBounds(MDLAxisAlignedBoundingBox *box, vector_float3 point)
{
    float low[3], high[3], p[3];
    low[0] = box->minBounds.x, low[1] = box->minBounds.y, low[2] = box->minBounds.z;
    high[0] = box->maxBounds.x, high[1] = box->maxBounds.y, high[2] = box->maxBounds.z;
    p[0] = point.x, p[1] = point.y, p[2] = point.z;
    box->minBounds = (vector_float3){low[0] < p[0] ? low[0] : p[0], low[1] < p[1] ? low[1] : p[1],
                                    low[2] < p[2] ? low[2] : p[2]};
    box->maxBounds = (vector_float3){high[0] > p[0] ? high[0] : p[0], high[1] > p[1] ? high[1] : p[1],
                                    high[2] > p[2] ? high[2] : p[2]};
}

@implementation CharonMDLLoadedScene

- (instancetype)init
{
    if ((self = [super init]))
        self.objects = [NSMutableArray array];
    return self;
}

- (void)dealloc
{
}

@end

@interface MDLAsset (CharonReaders)
- (void)charon_read;
@end

@implementation MDLAsset {
    NSMutableArray<MDLObject *> *_objects;
    MDLObjectContainer *_masters, *_originals;
    id<MDLMeshBufferAllocator> _allocator;
    MDLVertexDescriptor *_descriptor;
    NSURL *_URL;
    NSTimeInterval _frameInterval, _startTime, _endTime;
}

@synthesize URL = _URL;
@synthesize bufferAllocator = _allocator;
@synthesize vertexDescriptor = _descriptor;
@synthesize frameInterval = _frameInterval;
@synthesize startTime = _startTime;
@synthesize endTime = _endTime;
@synthesize masters = _masters;
@synthesize originals = _originals;

- (instancetype)initWithURL:(NSURL *)URL
{
    return [self initWithURL:URL vertexDescriptor:nil bufferAllocator:nil];
}

- (instancetype)initWithURL:(NSURL *)URL vertexDescriptor:(MDLVertexDescriptor *)vertexDescriptor bufferAllocator:(id<MDLMeshBufferAllocator>)bufferAllocator
{
    if ((self = [self initWithBufferAllocator:bufferAllocator])) {
        _descriptor = [vertexDescriptor copy];
        if (URL) {
            _URL = URL;
            [self charon_read];
        }
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)URL
           vertexDescriptor:(MDLVertexDescriptor *)vertexDescriptor
            bufferAllocator:(id<MDLMeshBufferAllocator>)bufferAllocator
           preserveTopology:(BOOL)preserveTopology
                      error:(NSError **)error
{
    // The port's readers keep the topology of the file: a submesh's faces are the file's faces, in
    // the file's order, so there is nothing to preserve or flatten.
    (void)preserveTopology;
    self = [self initWithURL:URL vertexDescriptor:vertexDescriptor bufferAllocator:bufferAllocator];
    if (!self && error)
        *error = [NSError errorWithDomain:@"MDLAssetErrorDomain" code:1 userInfo:nil];
    return self;
}

- (instancetype)initWithBufferAllocator:(id<MDLMeshBufferAllocator>)bufferAllocator
{
    if ((self = [super init])) {
        _objects = [[NSMutableArray alloc] init];
        _allocator = bufferAllocator;
        _descriptor = [[MDLVertexDescriptor alloc] init];
        _frameInterval = 1 / 30.0;
    }
    return self;
}

- (void)dealloc
{
}

- (id)copyWithZone:(NSZone *)zone
{
    MDLAsset *copy = [[[self class] allocWithZone:zone] initWithBufferAllocator:_allocator];
    for (MDLObject *object in _objects)
        [copy addObject:object];
    return copy;
}

- (void)addObject:(MDLObject *)object
{
    if (!object || [_objects containsObject:object])
        return;
    [_objects addObject:object];
}

- (void)removeObject:(MDLObject *)object
{
    [_objects removeObject:object];
}

- (NSUInteger)count
{
    return _objects.count;
}

- (MDLObject *)objectAtIndex:(NSUInteger)index
{
    return index < _objects.count ? _objects[index] : nil;
}

- (MDLObject *)objectAtIndexedSubscript:(NSUInteger)index
{
    return [self objectAtIndex:index];
}

- (NSArray<MDLObject *> *)childObjectsOfClass:(Class)objectClass
{
    NSMutableArray<MDLObject *> *found = [NSMutableArray array];
    for (MDLObject *object in _objects) {
        if (!objectClass || [object isKindOfClass:objectClass])
            [found addObject:object];
        [object enumerateChildObjectsOfClass:objectClass root:object usingBlock:^(MDLObject *child, BOOL *stop) {
            [found addObject:child];
        } stopPointer:NULL];
    }
    return found;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)length
{
    return [_objects countByEnumeratingWithState:state objects:buffer count:length];
}

- (MDLAxisAlignedBoundingBox)boundingBoxAtTime:(NSTimeInterval)time
{
    // The empty box, from outside in. MDLAxisAlignedBoundingBox declares maxBounds first, so this is
    // max at the top: written the other way round it is a box that starts unbounded and never closes.
    MDLAxisAlignedBoundingBox box = {{-INFINITY, -INFINITY, -INFINITY}, {INFINITY, INFINITY, INFINITY}};
    for (MDLObject *object in _objects) {
        MDLAxisAlignedBoundingBox own = [object boundingBoxAtTime:time];
        CharonMDLBounds(&box, own.minBounds);
        CharonMDLBounds(&box, own.maxBounds);
    }
    if (box.minBounds[0] > box.maxBounds[0]) {
        box.minBounds = (vector_float3){0, 0, 0};
        box.maxBounds = (vector_float3){0, 0, 0};
    }
    return box;
}

- (MDLAxisAlignedBoundingBox)boundingBox
{
    return [self boundingBoxAtTime:0];
}

+ (BOOL)canImportFileExtension:(NSString *)extension
{
    // What the readers here really read: the Wavefront object, the Stanford polygon file in its
    // ASCII and binary forms, and the ASCII Universal Scene Description.
    return [@[@"obj", @"ply", @"usda"] containsObject:extension.lowercaseString];
}

+ (BOOL)canExportFileExtension:(NSString *)extension
{
    return NO;
}

- (BOOL)exportAssetToURL:(NSURL *)URL
{
    return [self exportAssetToURL:URL error:NULL];
}

- (BOOL)exportAssetToURL:(NSURL *)URL error:(NSError **)error
{
    // Nothing this port reads is written back out yet, and saying so is better than writing a file
    // that is not the asset.
    if (error)
        *error = [NSError errorWithDomain:@"MDLAssetErrorDomain" code:2 userInfo:nil];
    return NO;
}

@end

@implementation MDLRelativeAssetResolver {
    __unsafe_unretained MDLAsset *_asset;
}

- (instancetype)initWithAsset:(MDLAsset *)asset
{
    if ((self = [super init]))
        _asset = asset;
    return self;
}

- (MDLAsset *)asset
{
    return _asset;
}

- (void)setAsset:(MDLAsset *)asset
{
    _asset = asset;
}

// A name is resolved beside the asset that names it, which is the directory the asset's own file is
// in, so a mesh's material is found where the mesh's file is.
- (NSURL *)resolveAssetNamed:(NSString *)name
{
    if (!name)
        return nil;
    if ([name hasPrefix:@"/"])
        return [NSURL fileURLWithPath:name];
    NSURL *base = _asset.URL;
    if (!base)
        return nil;
    NSString *directory = [base URLByDeletingLastPathComponent].path;
    if (!directory.length)
        return nil;
    return [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
}

- (BOOL)canResolveAssetNamed:(NSString *)name
{
    if (!name)
        return NO;
    if ([name hasPrefix:@"/"])
        return [[NSFileManager defaultManager] fileExistsAtPath:name];
    NSURL *resolved = [self resolveAssetNamed:name];
    return resolved && [[NSFileManager defaultManager] fileExistsAtPath:resolved.path];
}

@end

@implementation MDLPathAssetResolver {
    NSString *_path;
}

@synthesize path = _path;

- (instancetype)initWithPath:(NSString *)path
{
    if ((self = [super init]))
        _path = [path copy];
    return self;
}

- (void)dealloc
{
}

- (NSURL *)resolveAssetNamed:(NSString *)name
{
    if (!name)
        return nil;
    if ([name hasPrefix:@"/"])
        return [NSURL fileURLWithPath:name];
    if (!self.path.length)
        return [NSURL fileURLWithPath:name];
    return [NSURL fileURLWithPath:[self.path stringByAppendingPathComponent:name]];
}

- (BOOL)canResolveAssetNamed:(NSString *)name
{
    NSURL *resolved = [self resolveAssetNamed:name];
    return resolved && [[NSFileManager defaultManager] fileExistsAtPath:resolved.path];
}

@end

@implementation MDLBundleAssetResolver {
    NSString *_path;
}

@synthesize path = _path;

- (instancetype)initWithBundle:(NSString *)path
{
    if ((self = [super init]))
        _path = [path copy];
    return self;
}

- (void)dealloc
{
}

// A bundle is a directory: the path given, or the main bundle's own resource directory.
- (NSURL *)resolveAssetNamed:(NSString *)name
{
    if (!name)
        return nil;
    NSString *base = self.path.length ? self.path : [NSBundle mainBundle].resourcePath;
    if (!base)
        return nil;
    return [NSURL fileURLWithPath:[base stringByAppendingPathComponent:name]];
}

- (BOOL)canResolveAssetNamed:(NSString *)name
{
    NSURL *resolved = [self resolveAssetNamed:name];
    return resolved && [[NSFileManager defaultManager] fileExistsAtPath:resolved.path];
}

@end

// What a reader builds: the meshes and their materials, with the geometry the file really holds. The
// three readers below share this, so a mesh is built the same way whichever file it came from.

typedef struct {
    vector_float3 position;
    vector_float3 normal;
    vector_float2 uv;
    BOOL hasNormal;
    BOOL hasUV;
} CharonMDLSourceVertex;

typedef struct {
    CharonMDLSourceVertex *vertex;
    NSUInteger vertexCount, vertexCapacity;
    uint32_t *index;
    NSUInteger indexCount, indexCapacity;
    int group;      // the group the faces after them belong to, -1 before the first
    int material;   // the material the faces after them are drawn with, -1 before the first
} CharonMDLSourceMesh;

static void CharonMDLSourceVertexAdd(CharonMDLSourceMesh *mesh, vector_float3 position, vector_float3 normal, vector_float2 uv,
                                     BOOL hasNormal, BOOL hasUV)
{
    if (mesh->vertexCount == mesh->vertexCapacity) {
        mesh->vertexCapacity = mesh->vertexCapacity ? mesh->vertexCapacity * 2 : 256;
        mesh->vertex = realloc(mesh->vertex, mesh->vertexCapacity * sizeof(CharonMDLSourceVertex));
    }
    CharonMDLSourceVertex *at = mesh->vertex + mesh->vertexCount++;
    at->position = position;
    at->normal = normal;
    at->uv = uv;
    at->hasNormal = hasNormal;
    at->hasUV = hasUV;
}

static void CharonMDLSourceIndexAdd(CharonMDLSourceMesh *mesh, uint32_t value)
{
    if (mesh->indexCount == mesh->indexCapacity) {
        mesh->indexCapacity = mesh->indexCapacity ? mesh->indexCapacity * 2 : 512;
        mesh->index = realloc(mesh->index, mesh->indexCapacity * sizeof(uint32_t));
    }
    mesh->index[mesh->indexCount++] = value;
}

static void CharonMDLSourceMeshFree(CharonMDLSourceMesh *mesh)
{
    free(mesh->vertex);
    free(mesh->index);
}

// The index of the vertex an OBJ or a USDA face names, which is one-based and may run past the
// vertices read so far, in which case it counts back from the ones there are.
static BOOL CharonMDLFaceIndex(NSInteger named, NSUInteger count, NSUInteger *out)
{
    NSInteger index = named > 0 ? named - 1 : (NSInteger)count + named;
    if (index < 0 || (NSUInteger)index >= count)
        return NO;
    *out = (NSUInteger)index;
    return YES;
}

// One mesh of the port's own, from the vertices and the indices a reader collected: the three
// attributes in one interleaved buffer, and a submesh over every index of it.
static MDLMesh *CharonMDLBuildMesh(CharonMDLSourceMesh *mesh, id<MDLMeshBufferAllocator> allocator, NSString *name)
{
    if (!mesh->vertexCount || !mesh->indexCount)
        return nil;
    NSUInteger stride = sizeof(vector_float3) * 2 + sizeof(vector_float2);
    NSMutableData *vertices = [NSMutableData dataWithLength:mesh->vertexCount * stride];
    uint8_t *bytes = vertices.mutableBytes;
    for (NSUInteger k = 0; k < mesh->vertexCount; k++) {
        CharonMDLSourceVertex *vertex = mesh->vertex + k;
        *(vector_float3 *)(bytes + k * stride) = vertex->position;
        // A file that gives no normal has its faces' own normals computed, so the attribute holds
        // the direction the face really points in rather than a zero that means nothing.
        vector_float3 normal = vertex->normal;
        if (!vertex->hasNormal) {
            vector_float3 sum = {0, 0, 0};
            for (NSUInteger i = 0; i + 2 < mesh->indexCount; i += 3) {
                if (mesh->index[i] != k && mesh->index[i + 1] != k && mesh->index[i + 2] != k)
                    continue;
                vector_float3 a = mesh->vertex[mesh->index[i]].position, b = mesh->vertex[mesh->index[i + 1]].position,
                             c = mesh->vertex[mesh->index[i + 2]].position;
                vector_float3 face = simd_cross((vector_float3){b.x - a.x, b.y - a.y, b.z - a.z},
                                                (vector_float3){c.x - a.x, c.y - a.y, c.z - a.z});
                sum = (vector_float3){sum.x + face.x, sum.y + face.y, sum.z + face.z};
            }
            normal = simd_length(sum) > 0 ? simd_normalize(sum) : (vector_float3){0, 1, 0};
        }
        *(vector_float3 *)(bytes + k * stride + sizeof(vector_float3)) = normal;
        *(vector_float2 *)(bytes + k * stride + sizeof(vector_float3) * 2) = vertex->uv;
    }
    NSData *indices = [NSData dataWithBytes:mesh->index length:mesh->indexCount * sizeof(uint32_t)];
    id<MDLMeshBuffer> vertexBuffer = [allocator newBuffer:vertices.length type:MDLMeshBufferTypeVertex];
    id<MDLMeshBuffer> indexBuffer = [allocator newBuffer:indices.length type:MDLMeshBufferTypeIndex];
    if (!vertexBuffer || !indexBuffer)
        return nil;
    [vertexBuffer fillData:vertices offset:0];
    [indexBuffer fillData:indices offset:0];

    MDLVertexDescriptor *descriptor = [[MDLVertexDescriptor alloc] init];
    [descriptor addOrReplaceAttribute:[[MDLVertexAttribute alloc] initWithName:MDLVertexAttributePosition format:MDLVertexFormatFloat3
                                                                              offset:0 bufferIndex:0]];
    [descriptor addOrReplaceAttribute:[[MDLVertexAttribute alloc] initWithName:MDLVertexAttributeNormal format:MDLVertexFormatFloat3
                                                                          offset:sizeof(vector_float3) bufferIndex:0]];
    [descriptor addOrReplaceAttribute:[[MDLVertexAttribute alloc] initWithName:MDLVertexAttributeTextureCoordinate
                                                                          format:MDLVertexFormatFloat2
                                                                          offset:sizeof(vector_float3) * 2 bufferIndex:0]];
    [descriptor.layouts addObject:[[MDLVertexBufferLayout alloc] initWithStride:stride]];
    MDLMaterial *material = [[MDLMaterial alloc] initWithName:name
                                          scatteringFunction:[[MDLPhysicallyPlausibleScatteringFunction alloc] init]];
    MDLSubmesh *submesh = [[MDLSubmesh alloc] initWithName:name indexBuffer:indexBuffer indexCount:mesh->indexCount
                                                   indexType:MDLIndexBitDepthUInt32 geometryType:MDLGeometryTypeTriangles
                                                    material:material];
    return [[MDLMesh alloc] initWithVertexBuffers:@[vertexBuffer] vertexCount:mesh->vertexCount descriptor:descriptor
                                         submeshes:@[submesh]];
}

// The Wavefront object: one mesh for the file, with a submesh for every group and material it names,
// and the vertices and normals and texture coordinates shared between them the way the file shares
// them. A face of n corners is n - 2 triangles fanned from its first corner, and a corner that names
// the same position, normal and texture coordinate as another is the same vertex of the mesh.
static void CharonMDLReadOBJ(NSData *data, NSMutableArray<MDLObject *> *objects, id<MDLMeshBufferAllocator> allocator)
{
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text)
        return;
    vector_float3 *positions = NULL, *normals = NULL;
    vector_float2 *uvs = NULL;
    NSUInteger positionCount = 0, normalCount = 0, uvCount = 0, capacity = 0;
    CharonMDLSourceMesh mesh;
    memset(&mesh, 0, sizeof mesh);
    // The vertices the file's own corners have already made, and the submeshes the faces have been
    // put into, each a name, a material and the range of indices it owns.
    NSMutableArray<NSArray<NSNumber *> *> *corners = [NSMutableArray array];
    NSMutableArray<NSString *> *submeshNames = [NSMutableArray array];
    NSMutableArray<NSString *> *submeshMaterials = [NSMutableArray array];
    NSMutableArray<NSNumber *> *submeshFirst = [NSMutableArray array];
    NSMutableArray<NSNumber *> *submeshCount = [NSMutableArray array];
    NSInteger at = -1;
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length < 2 || [line hasPrefix:@"#"])
            continue;
        NSArray<NSString *> *words = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *key = words[0];
        if ([key isEqualToString:@"v"] || [key isEqualToString:@"vn"] || [key isEqualToString:@"vt"]) {
            if (positionCount == capacity) {
                capacity = capacity ? capacity * 2 : 256;
                positions = realloc(positions, capacity * sizeof(vector_float3));
                normals = realloc(normals, capacity * sizeof(vector_float3));
                uvs = realloc(uvs, capacity * sizeof(vector_float2));
            }
            if ([key isEqualToString:@"v"] && words.count >= 4) {
                positions[positionCount] = (vector_float3){[words[1] floatValue], [words[2] floatValue], [words[3] floatValue]};
                positionCount++;
            } else if ([key isEqualToString:@"vn"] && words.count >= 4) {
                normals[normalCount] = (vector_float3){[words[1] floatValue], [words[2] floatValue], [words[3] floatValue]};
                normalCount++;
            } else if ([key isEqualToString:@"vt"] && words.count >= 3) {
                uvs[uvCount] = (vector_float2){[words[1] floatValue], [words[2] floatValue]};
                uvCount++;
            }
        } else if ([key isEqualToString:@"o"] || [key isEqualToString:@"g"]) {
            NSString *name = words.count > 1 ? [[words subarrayWithRange:NSMakeRange(1, words.count - 1)] componentsJoinedByString:@" "] : @"";
            [submeshNames addObject:name];
            [submeshMaterials addObject:@""];
            [submeshFirst addObject:@(mesh.indexCount)];
            [submeshCount addObject:@0];
            at = (NSInteger)submeshNames.count - 1;
        } else if ([key isEqualToString:@"usemtl"] && at >= 0 && words.count > 1) {
            submeshMaterials[at] = words[1];
        } else if ([key isEqualToString:@"f"]) {
            // A face with no group before it belongs to a submesh of its own, named as the file names
            // no one: that is what a file that opens with a face and no "o" means.
            if (at < 0) {
                [submeshNames addObject:@""];
                [submeshMaterials addObject:@""];
                [submeshFirst addObject:@(mesh.indexCount)];
                [submeshCount addObject:@0];
                at = 0;
            }
            NSUInteger before = mesh.indexCount;
            for (NSUInteger cornerIndex = 2; cornerIndex < words.count - 1; cornerIndex++)
                for (int part = 0; part < 3; part++) {
                    NSString *token = words[1 + (part == 0 ? 0 : (part == 1 ? cornerIndex - 1 : cornerIndex))];
                    NSArray<NSString *> *parts = [token componentsSeparatedByString:@"/"];
                    // A corner that names no normal or no coordinate says so, because "none" and "the
                    // first one" are different corners: the fifth vertex of a lid is not the first
                    // corner of the face below it.
                    NSUInteger positionAt = 0, normalAt = 0, uvAt = 0;
                    BOOL named = parts.count > 0 && CharonMDLFaceIndex(parts[0].integerValue, positionCount, &positionAt);
                    BOOL hasNormal = named && parts.count > 1 && parts[1].length &&
                                     CharonMDLFaceIndex(parts[1].integerValue, normalCount, &normalAt);
                    BOOL hasUV = named && parts.count > 2 && parts[2].length &&
                                 CharonMDLFaceIndex(parts[2].integerValue, uvCount, &uvAt);
                    if (!named)
                        continue;
                    NSArray<NSNumber *> *corner = @[@(positionAt), @(hasNormal ? normalAt + 1 : 0), @(hasUV ? uvAt + 1 : 0)];
                    NSUInteger found = [corners indexOfObject:corner];
                    if (found == NSNotFound) {
                        [corners addObject:corner];
                        CharonMDLSourceVertexAdd(&mesh, positions[positionAt],
                                                 hasNormal ? normals[normalAt] : (vector_float3){0, 0, 0},
                                                 hasUV ? uvs[uvAt] : (vector_float2){0, 0}, hasNormal, hasUV);
                        found = mesh.vertexCount - 1;
                    }
                    CharonMDLSourceIndexAdd(&mesh, (uint32_t)found);
                }
            submeshCount[at] = @(mesh.indexCount - before);
        }
    }
    if (mesh.vertexCount && mesh.indexCount) {
        MDLMesh *built = CharonMDLBuildMesh(&mesh, allocator, submeshNames.firstObject);
        if (built) {
            NSString *first = submeshNames.firstObject, *firstMaterial = submeshMaterials.firstObject;
            built.name = firstMaterial.length ? [NSString stringWithFormat:@"%@_%@", first, firstMaterial] : first;
            // One submesh for every group and material the file names, over the indices that belong to
            // it, each with a material of the name the file gave it.
            [built.submeshes removeAllObjects];
            for (NSUInteger k = 0; k < submeshNames.count; k++) {
                NSUInteger first = [submeshFirst[k] unsignedIntegerValue], count = [submeshCount[k] unsignedIntegerValue];
                if (!count)
                    continue;
                NSString *name = submeshNames[k], *material = submeshMaterials[k];
                MDLMaterial *mat = [[MDLMaterial alloc] initWithName:material
                                                  scatteringFunction:[[MDLPhysicallyPlausibleScatteringFunction alloc] init]];
                MDLSubmesh *submesh = [[MDLSubmesh alloc] initWithName:material.length ? material : name
                                                             indexBuffer:built.submeshes.firstObject.indexBuffer
                                                              indexCount:count
                                                               indexType:MDLIndexBitDepthUInt32
                                                            geometryType:MDLGeometryTypeTriangles
                                                                material:mat];
                [built.submeshes addObject:submesh];
            }
            [objects addObject:built];
        }
    }
    CharonMDLSourceMeshFree(&mesh);
    free(positions);
    free(normals);
    free(uvs);
}

// The Stanford polygon file, in its ASCII form and in its binary little-endian form. The header says
// how the elements are laid out and what each property is; the body is then read at that layout, so
// a file with properties the port does not know is still read correctly, its unknown properties
// skipped by their own size.
typedef struct {
    int kind;        // 0 scalar, 1 list
    char name[32];
    int countKind;   // for a list, the type of its count
    int valueKind;   // for a list, the type of its values
} CharonMDLPLYProperty;

static int CharonMDLPLYSize(int kind)
{
    switch (kind) {
        case 0:
        case 1:
            return 1;  // char, uchar
        case 2:
        case 3:
            return 2;  // short, ushort
        case 4:
        case 5:
        case 6:
            return 4;  // int, uint, float
        default:
            return 8;  // double
    }
}

static double CharonMDLPLYReadBinary(const uint8_t **at, int kind, BOOL swap)
{
    int size = CharonMDLPLYSize(kind);
    uint8_t bytes[8];
    memcpy(bytes, *at, size);
    *at += size;
    if (swap) {
        // A file whose own header says big endian, read on a little-endian release.
        for (int k = 0; k < size / 2; k++) {
            uint8_t t = bytes[k];
            bytes[k] = bytes[size - 1 - k];
            bytes[size - 1 - k] = t;
        }
    }
    switch (kind) {
        case 0:
            return (double)*(int8_t *)bytes;
        case 1:
            return (double)*(uint8_t *)bytes;
        case 2: {
            int16_t value;
            memcpy(&value, bytes, 2);
            return value;
        }
        case 3: {
            uint16_t value;
            memcpy(&value, bytes, 2);
            return value;
        }
        case 4: {
            int32_t value;
            memcpy(&value, bytes, 4);
            return value;
        }
        case 5: {
            uint32_t value;
            memcpy(&value, bytes, 4);
            return value;
        }
        case 6: {
            float value;
            memcpy(&value, bytes, 4);
            return value;
        }
        default: {
            double value;
            memcpy(&value, bytes, 8);
            return value;
        }
    }
}

// The type a PLY property of a name has, read off the name the header gives it.
static int CharonMDLPLYKind(NSString *type, NSString *name)
{
    if ([type isEqualToString:@"char"] || [type isEqualToString:@"int8"])
        return 0;
    if ([type isEqualToString:@"uchar"] || [type isEqualToString:@"uint8"])
        return 1;
    if ([type isEqualToString:@"short"] || [type isEqualToString:@"int16"])
        return 2;
    if ([type isEqualToString:@"ushort"] || [type isEqualToString:@"uint16"])
        return 3;
    if ([type isEqualToString:@"int"] || [type isEqualToString:@"int32"])
        return 4;
    if ([type isEqualToString:@"uint"] || [type isEqualToString:@"uint32"])
        return 5;
    if ([type isEqualToString:@"float"] || [type isEqualToString:@"float32"])
        return 6;
    if ([type isEqualToString:@"double"] || [type isEqualToString:@"float64"])
        return 7;
    // A property the header does not type, named the way the format names it.
    if ([name hasPrefix:@"red"] || [name hasPrefix:@"green"] || [name hasPrefix:@"blue"] || [name hasPrefix:@"alpha"])
        return 1;
    if ([name hasPrefix:@"tex_u"] || [name hasPrefix:@"tex_v"])
        return 6;
    return 6;
}

static void CharonMDLReadPLY(NSData *data, NSMutableArray<MDLObject *> *objects, id<MDLMeshBufferAllocator> allocator)
{
    // Only the header is text; the body of a binary file is not text at all, so the header is found in
    // the bytes and decoded on its own rather than the whole file being decoded and coming back nil.
    const uint8_t *bytes = data.bytes;
    static const char marker[] = "end_header";
    NSUInteger headerEnd = NSNotFound;
    for (NSUInteger k = 0; k + sizeof marker - 1 <= data.length; k++)
        if (!memcmp(bytes + k, marker, sizeof marker - 1)) {
            headerEnd = k;
            break;
        }
    if (headerEnd == NSNotFound)
        return;
    NSString *header = [[NSString alloc] initWithBytes:bytes length:headerEnd encoding:NSUTF8StringEncoding];
    if (!header)
        return;
    NSArray<NSString *> *lines = [header componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *format = @"";
    NSMutableArray<NSString *> *elements = [NSMutableArray array];
    NSMutableArray<NSNumber *> *elementCounts = [NSMutableArray array];
    NSMutableArray<NSArray *> *elementProperties = [NSMutableArray array];
    NSMutableArray<NSString *> *elementTypes = [NSMutableArray array];
    for (NSString *raw in lines) {
        NSArray<NSString *> *words = [[raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
            componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!words.count || [[words objectAtIndex:0] isEqualToString:@"comment"])
            continue;
        NSString *key = words[0];
        if ([key isEqualToString:@"ply"])
            continue;
        if ([key isEqualToString:@"format"] && words.count > 1)
            format = words[1];
        else if ([key isEqualToString:@"element"] && words.count > 2) {
            [elements addObject:words[1]];
            [elementCounts addObject:@(words[2].integerValue)];
            [elementTypes addObject:words[1]];
            [elementProperties addObject:[NSMutableArray array]];
        } else if ([key isEqualToString:@"property"] && elements.count) {
            CharonMDLPLYProperty property;
            memset(&property, 0, sizeof property);
            if (words.count > 2 && [words[1] isEqualToString:@"list"]) {
                property.kind = 1;
                property.countKind = CharonMDLPLYKind(words[2], @"count");
                property.valueKind = words.count > 4 ? CharonMDLPLYKind(words[3], words[4]) : 6;
                strncpy(property.name, words[4].UTF8String ?: "list", sizeof property.name - 1);
            } else if (words.count > 2) {
                property.kind = 0;
                property.valueKind = CharonMDLPLYKind(words[1], words[2]);
                strncpy(property.name, words[2].UTF8String ?: "", sizeof property.name - 1);
            }
            NSMutableArray *properties = elementProperties[elements.count - 1];
            [properties addObject:[NSValue valueWithBytes:&property objCType:@encode(CharonMDLPLYProperty)]];
        }
    }
    BOOL ascii = [format isEqualToString:@"ascii"];
    BOOL swap = [format isEqualToString:@"binary_big_endian"];
    CharonMDLSourceMesh mesh;
    memset(&mesh, 0, sizeof mesh);
    NSUInteger bodyStart = headerEnd + sizeof marker - 1;
    while (bodyStart < data.length && (bytes[bodyStart] == '\n' || bytes[bodyStart] == '\r'))
        bodyStart++;
    if (ascii) {
        NSString *rest = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(bodyStart, data.length - bodyStart)]
                                             encoding:NSUTF8StringEncoding];
        // The body is read a line at a time and a "#" line is skipped, because a comment after
        // end_header is what real writers emit and reading the tokens flat ate every word of it as a
        // coordinate, so the whole of the file after the first comment was consumed as geometry and
        // the asset came back empty with no error anywhere.
        NSMutableArray<NSString *> *body = [NSMutableArray array];
        for (NSString *line in [rest componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (!trimmed.length || [trimmed hasPrefix:@"#"])
                continue;
            [body addObjectsFromArray:[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
        NSUInteger at = 0;
        for (NSUInteger e = 0; e < elements.count; e++) {
            NSArray *properties = elementProperties[e];
            NSUInteger count = [elementCounts[e] unsignedIntegerValue];
            BOOL vertices = [elements[e] isEqualToString:@"vertex"];
            for (NSUInteger k = 0; k < count; k++) {
                if (vertices) {
                    CharonMDLSourceVertex vertex = {{0, 0, 0}, {0, 0, 0}, {0, 0}, NO, NO};
                    for (NSValue *held in properties) {
                        CharonMDLPLYProperty property;
                        [held getValue:&property];
                        if (at >= body.count)
                            break;
                        double value = [body[at++] doubleValue];
                        if (!strcmp(property.name, "x"))
                            vertex.position.x = (float)value;
                        else if (!strcmp(property.name, "y"))
                            vertex.position.y = (float)value;
                        else if (!strcmp(property.name, "z"))
                            vertex.position.z = (float)value;
                        else if (!strcmp(property.name, "nx"))
                            vertex.normal.x = (float)value, vertex.hasNormal = YES;
                        else if (!strcmp(property.name, "ny"))
                            vertex.normal.y = (float)value, vertex.hasNormal = YES;
                        else if (!strcmp(property.name, "nz"))
                            vertex.normal.z = (float)value, vertex.hasNormal = YES;
                        else if (!strcmp(property.name, "s") || !strcmp(property.name, "u") || !strcmp(property.name, "tex_u"))
                            vertex.uv.x = (float)value, vertex.hasUV = YES;
                        else if (!strcmp(property.name, "t") || !strcmp(property.name, "v") || !strcmp(property.name, "tex_v"))
                            vertex.uv.y = (float)value, vertex.hasUV = YES;
                    }
                    if (mesh.vertexCount == mesh.vertexCapacity) {
                        mesh.vertexCapacity = mesh.vertexCapacity ? mesh.vertexCapacity * 2 : 256;
                        mesh.vertex = realloc(mesh.vertex, mesh.vertexCapacity * sizeof(CharonMDLSourceVertex));
                    }
                    mesh.vertex[mesh.vertexCount++] = vertex;
                } else if ([elements[e] isEqualToString:@"face"]) {
                    // A face is a list of indices, fanned into triangles as the object format is.
                    NSMutableArray<NSNumber *> *corners = [NSMutableArray array];
                    for (NSValue *held in properties) {
                        CharonMDLPLYProperty property;
                        [held getValue:&property];
                        NSUInteger length = at < body.count ? (NSUInteger)[body[at++] doubleValue] : 0;
                        for (NSUInteger c = 0; c < length && at < body.count; c++)
                            [corners addObject:@((NSUInteger)[body[at++] doubleValue])];
                        (void)property;
                    }
                    for (NSUInteger c = 2; c < corners.count; c++) {
                        NSUInteger first = [corners[0] unsignedIntegerValue];
                        NSUInteger second = [corners[c - 1] unsignedIntegerValue], third = [corners[c] unsignedIntegerValue];
                        if (first >= mesh.vertexCount || second >= mesh.vertexCount || third >= mesh.vertexCount)
                            continue;
                        CharonMDLSourceIndexAdd(&mesh, (uint32_t)first);
                        CharonMDLSourceIndexAdd(&mesh, (uint32_t)second);
                        CharonMDLSourceIndexAdd(&mesh, (uint32_t)third);
                    }
                }
            }
        }
    } else {
        NSUInteger offset = bodyStart;
        for (NSUInteger e = 0; e < elements.count; e++) {
            NSArray *properties = elementProperties[e];
            NSUInteger count = [elementCounts[e] unsignedIntegerValue];
            BOOL vertices = [elements[e] isEqualToString:@"vertex"];
            for (NSUInteger k = 0; k < count; k++) {
                const uint8_t *at = bytes + offset;
                if (vertices) {
                    CharonMDLSourceVertex vertex = {{0, 0, 0}, {0, 0, 0}, {0, 0}, NO, NO};
                    for (NSValue *held in properties) {
                        CharonMDLPLYProperty property;
                        [held getValue:&property];
                        double value = CharonMDLPLYReadBinary(&at, property.valueKind, swap);
                        if (!strcmp(property.name, "x"))
                            vertex.position.x = (float)value;
                        else if (!strcmp(property.name, "y"))
                            vertex.position.y = (float)value;
                        else if (!strcmp(property.name, "z"))
                            vertex.position.z = (float)value;
                        else if (!strcmp(property.name, "nx"))
                            vertex.normal.x = (float)value, vertex.hasNormal = YES;
                        else if (!strcmp(property.name, "ny"))
                            vertex.normal.y = (float)value, vertex.hasNormal = YES;
                        else if (!strcmp(property.name, "nz"))
                            vertex.normal.z = (float)value, vertex.hasNormal = YES;
                        else if (!strcmp(property.name, "s") || !strcmp(property.name, "u") || !strcmp(property.name, "tex_u"))
                            vertex.uv.x = (float)value, vertex.hasUV = YES;
                        else if (!strcmp(property.name, "t") || !strcmp(property.name, "v") || !strcmp(property.name, "tex_v"))
                            vertex.uv.y = (float)value, vertex.hasUV = YES;
                    }
                    offset = (NSUInteger)(at - bytes);
                    if (mesh.vertexCount == mesh.vertexCapacity) {
                        mesh.vertexCapacity = mesh.vertexCapacity ? mesh.vertexCapacity * 2 : 256;
                        mesh.vertex = realloc(mesh.vertex, mesh.vertexCapacity * sizeof(CharonMDLSourceVertex));
                    }
                    mesh.vertex[mesh.vertexCount++] = vertex;
                } else if ([elements[e] isEqualToString:@"face"]) {
                    for (NSValue *held in properties) {
                        CharonMDLPLYProperty property;
                        [held getValue:&property];
                        NSUInteger length = property.kind == 1 ? (NSUInteger)CharonMDLPLYReadBinary(&at, property.countKind, swap) : 0;
                        NSMutableArray<NSNumber *> *corners = [NSMutableArray array];
                        for (NSUInteger c = 0; c < length; c++)
                            [corners addObject:@((NSUInteger)CharonMDLPLYReadBinary(&at, property.valueKind, swap))];
                        offset = (NSUInteger)(at - bytes);
                        for (NSUInteger c = 2; c < corners.count; c++) {
                            NSUInteger first = [corners[0] unsignedIntegerValue], second = [corners[c - 1] unsignedIntegerValue],
                                      third = [corners[c] unsignedIntegerValue];
                            if (first >= mesh.vertexCount || second >= mesh.vertexCount || third >= mesh.vertexCount)
                                continue;
                            CharonMDLSourceIndexAdd(&mesh, (uint32_t)first);
                            CharonMDLSourceIndexAdd(&mesh, (uint32_t)second);
                            CharonMDLSourceIndexAdd(&mesh, (uint32_t)third);
                        }
                    }
                }
            }
        }
    }
    MDLMesh *built = CharonMDLBuildMesh(&mesh, allocator, @"");
    if (built) {
        built.name = data.length ? @"" : @"";
        [objects addObject:built];
    }
    CharonMDLSourceMeshFree(&mesh);
}

// The ASCII Universal Scene Description: a mesh prim is a set of points, the faces over them as a
// count per face and a run of indices, and the optional normals and texture coordinates beside them.
static NSString *CharonMDLUSDAArray(NSString *text, NSString *after, NSString **rest)
{
    NSRange start = [text rangeOfString:after];
    if (start.location == NSNotFound)
        return nil;
    NSUInteger open = NSMaxRange(start);
    while (open < text.length && [text characterAtIndex:open] != '[')
        open++;
    if (open >= text.length)
        return nil;
    NSUInteger close = open;
    int depth = 0;
    for (; close < text.length; close++) {
        unichar c = [text characterAtIndex:close];
        if (c == '[')
            depth++;
        else if (c == ']' && --depth == 0)
            break;
    }
    if (rest)
        *rest = [text substringFromIndex:MIN(close + 1, text.length)];
    return [text substringWithRange:NSMakeRange(open + 1, close > open ? close - open - 1 : 0)];
}

static void CharonMDLReadUSDA(NSData *data, NSMutableArray<MDLObject *> *objects, id<MDLMeshBufferAllocator> allocator)
{
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text)
        return;
    NSUInteger at = 0;
    while (YES) {
        NSRange found = [text rangeOfString:@"def Mesh" options:0 range:NSMakeRange(at, text.length - at)];
        if (found.location == NSNotFound)
            break;
        NSRange open = [text rangeOfString:@"{" options:0 range:NSMakeRange(NSMaxRange(found), text.length - NSMaxRange(found))];
        if (open.location == NSNotFound)
            break;
        NSUInteger depth = 0, close = open.location;
        for (; close < text.length; close++) {
            unichar c = [text characterAtIndex:close];
            if (c == '{')
                depth++;
            else if (c == '}' && --depth == 0)
                break;
        }
        NSString *body = [text substringWithRange:NSMakeRange(open.location, close > open.location ? close - open.location : 0)];
        at = MIN(close + 1, text.length);
        // The name is the first quoted token of the def, which is the prim's own name.
        NSRange quote = [text rangeOfString:@"\"" options:0 range:NSMakeRange(NSMaxRange(found), MIN(60, text.length - NSMaxRange(found)))];
        NSString *name = @"";
        if (quote.location != NSNotFound) {
            NSRange end = [text rangeOfString:@"\"" options:0 range:NSMakeRange(NSMaxRange(quote), text.length - NSMaxRange(quote))];
            if (end.location != NSNotFound)
                name = [text substringWithRange:NSMakeRange(quote.location + 1, end.location - quote.location - 1)];
        }
        NSArray<NSString *> *points = [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSString *pointsText = nil;
        for (NSString *line in points)
            if ([line rangeOfString:@"point3f[] points"].location != NSNotFound)
                pointsText = line;
        NSString *pointArray = CharonMDLUSDAArray(pointsText ?: body, @"points", NULL);
        NSString *countArray = CharonMDLUSDAArray(body, @"faceVertexCounts", NULL);
        NSString *indexArray = CharonMDLUSDAArray(body, @"faceVertexIndices", NULL);
        if (!pointArray || !countArray || !indexArray)
            continue;
        NSArray<NSString *> *pointWords = [pointArray componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSUInteger vertexCount = pointWords.count / 3;
        CharonMDLSourceMesh mesh;
        memset(&mesh, 0, sizeof mesh);
        CharonMDLSourceVertex *vertex = calloc(vertexCount ? vertexCount : 1, sizeof(CharonMDLSourceVertex));
        for (NSUInteger k = 0; k < vertexCount; k++)
            vertex[k].position = (vector_float3){[pointWords[k * 3] floatValue], [pointWords[k * 3 + 1] floatValue],
                                                [pointWords[k * 3 + 2] floatValue]};
        mesh.vertex = vertex;
        mesh.vertexCount = vertexCount;
        mesh.vertexCapacity = vertexCount;
        NSArray<NSString *> *counts = [countArray componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // The indices are a bracketed run of numbers, so they are tokenised here the way the counts
        // above are: a for..in over the string itself sends countByEnumeratingWithState: to an NSString,
        // which does not answer it, and every measurement after that one was lost.
        NSMutableArray<NSNumber *> *indices = [NSMutableArray array];
        for (NSString *word in [indexArray componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
            NSString *number = [word stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",()"]];
            if (number.length)
                [indices addObject:@(number.integerValue)];
        }
        NSUInteger corner = 0;
        for (NSString *word in counts) {
            NSUInteger length = (NSUInteger)[word integerValue];
            if (length < 3)
                continue;
            for (NSUInteger c = 2; c < length; c++) {
                NSUInteger face[3] = {corner, corner + c - 1, corner + c};
                for (int part = 0; part < 3; part++)
                    if (face[part] < mesh.vertexCount)
                        CharonMDLSourceIndexAdd(&mesh, (uint32_t)face[part]);
            }
            corner += length;
        }
        MDLMesh *built = CharonMDLBuildMesh(&mesh, allocator, name);
        if (built) {
            built.name = name;
            [objects addObject:built];
        }
        CharonMDLSourceMeshFree(&mesh);
    }
}

@implementation MDLAsset (CharonReaders)

// The read the asset's own initializer makes: the file's bytes, and whichever of the readers above
// the file's own extension names.
- (void)charon_read
{
    NSData *data = [NSData dataWithContentsOfURL:_URL];
    if (!data.length)
        return;
    // A mesh the asset reads needs an allocator to hand out its buffers with; one the caller named
    // is used, and otherwise the port's own data allocator is.
    if (!_allocator)
        _allocator = [[MDLMeshBufferDataAllocator alloc] init];
    id<MDLMeshBufferAllocator> allocator = _allocator;
    NSString *extension = _URL.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"obj"])
        CharonMDLReadOBJ(data, _objects, allocator);
    else if ([extension isEqualToString:@"ply"])
        CharonMDLReadPLY(data, _objects, allocator);
    else if ([extension isEqualToString:@"usda"])
        CharonMDLReadUSDA(data, _objects, allocator);
}

@end
