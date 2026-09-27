#import <ModelIO/ModelIO.h>
#import <simd/simd.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// A transform is a translation, a rotation, a shear and a scale applied in that order, which is the
// order MDLTransform's own accessors read a matrix back in. The rotation is a product of the three
// axis rotations in X, Y, Z order. The samples themselves are held as an MDLAnimatedMatrix4x4, so
// the times between them are interpolated the way every other animated value's are.

static matrix_float4x4 CharonMDLRotationMatrix(vector_float3 radians)
{
    float cx = cosf(radians.x), sx = sinf(radians.x);
    float cy = cosf(radians.y), sy = sinf(radians.y);
    float cz = cosf(radians.z), sz = sinf(radians.z);
    matrix_float4x4 x = {{1, 0, 0, 0}, {0, cx, sx, 0}, {0, -sx, cx, 0}, {0, 0, 0, 1}};
    matrix_float4x4 y = {{cy, 0, -sy, 0}, {0, 1, 0, 0}, {sy, 0, cy, 0}, {0, 0, 0, 1}};
    matrix_float4x4 z = {{cz, sz, 0, 0}, {-sz, cz, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}};
    return simd_mul(x, simd_mul(y, z));
}

// The three axis angles of a rotation matrix, the standard reading of one whose trace is largest
// about the axis it turns around most.
static vector_float3 CharonMDLRotationAngles(matrix_float4x4 rotation)
{
    float trace = rotation.columns[0][0] + rotation.columns[1][1] + rotation.columns[2][2];
    vector_float3 angles;
    if (trace > 0) {
        float s = sqrtf(trace + 1) * 2;
        angles.z = asinf(MIN(1, MAX(-1, (rotation.columns[1][0] - rotation.columns[0][1]) / s)));
        angles.x = atan2((rotation.columns[2][1] + rotation.columns[1][2]) / s, (rotation.columns[2][2] + rotation.columns[0][0]) / s);
        angles.y = atan2((rotation.columns[0][2] + rotation.columns[2][0]) / s, (rotation.columns[0][0] + rotation.columns[2][2]) / s);
    } else if (rotation.columns[0][0] > rotation.columns[1][1] && rotation.columns[0][0] > rotation.columns[2][2]) {
        float s = sqrtf(1 + rotation.columns[0][0] - rotation.columns[1][1] - rotation.columns[2][2]) * 2;
        angles.x = asinf(MIN(1, MAX(-1, (rotation.columns[2][1] - rotation.columns[1][2]) / s)));
        angles.y = atan2((rotation.columns[1][0] + rotation.columns[0][1]) / s, (rotation.columns[2][2] + rotation.columns[0][0]) / s);
        angles.z = atan2((rotation.columns[0][2] + rotation.columns[2][0]) / s, (rotation.columns[1][1] + rotation.columns[0][0]) / s);
    } else if (rotation.columns[1][1] > rotation.columns[2][2]) {
        float s = sqrtf(1 + rotation.columns[1][1] - rotation.columns[0][0] - rotation.columns[2][2]) * 2;
        angles.x = atan2((rotation.columns[2][1] + rotation.columns[1][2]) / s, (rotation.columns[1][1] + rotation.columns[2][2]) / s);
        angles.y = asinf(MIN(1, MAX(-1, (rotation.columns[0][2] - rotation.columns[2][0]) / s)));
        angles.z = atan2((rotation.columns[0][1] + rotation.columns[1][0]) / s, (rotation.columns[1][1] + rotation.columns[0][0]) / s);
    } else {
        float s = sqrtf(1 + rotation.columns[2][2] - rotation.columns[0][0] - rotation.columns[1][1]) * 2;
        angles.x = atan2((rotation.columns[1][2] + rotation.columns[2][1]) / s, (rotation.columns[2][2] + rotation.columns[0][0]) / s);
        angles.y = atan2((rotation.columns[0][2] + rotation.columns[2][0]) / s, (rotation.columns[2][2] + rotation.columns[1][1]) / s);
        angles.z = asinf(MIN(1, MAX(-1, (rotation.columns[1][0] - rotation.columns[0][1]) / s)));
    }
    return angles;
}

@implementation MDLTransform {
    MDLAnimatedMatrix4x4 *_samples;
    vector_float3 _translation, _rotation, _shear, _scale;
}

@synthesize matrix = _matrix;
@synthesize resetsTransform = _resetsTransform;
@synthesize translation = _translation;
@synthesize rotation = _rotation;
@synthesize shear = _shear;
@synthesize scale = _scale;

- (instancetype)initWithMatrix:(matrix_float4x4)matrix resetsTransform:(BOOL)resetsTransform
{
    if ((self = [super init])) {
        _samples = [[MDLAnimatedMatrix4x4 alloc] init];
        _resetsTransform = resetsTransform;
        [self setMatrix:matrix forTime:0];
    }
    return self;
}

- (void)dealloc
{
}

- (instancetype)init
{
    return [self initWithMatrix:(matrix_float4x4){{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}} resetsTransform:YES];
}

- (instancetype)initWithIdentity
{
    return [self init];
}

- (instancetype)initWithMatrix:(matrix_float4x4)matrix
{
    return [self initWithMatrix:matrix resetsTransform:YES];
}

- (instancetype)initWithTransformComponent:(id<MDLTransformComponent>)component
{
    return [self initWithTransformComponent:component resetsTransform:NO];
}

- (instancetype)initWithTransformComponent:(id<MDLTransformComponent>)component resetsTransform:(BOOL)resetsTransform
{
    matrix_float4x4 matrix =
        [component respondsToSelector:@selector(matrix)] ? component.matrix : [component localTransformAtTime:0];
    return [self initWithMatrix:matrix resetsTransform:resetsTransform];
}

- (id)copyWithZone:(NSZone *)zone
{
    MDLTransform *copy = [[[self class] allocWithZone:zone] initWithMatrix:self.matrix resetsTransform:self.resetsTransform];
    NSArray<NSNumber *> *times = _samples.keyTimes;
    for (NSUInteger k = 1; k < times.count; k++)
        [copy setMatrix:[_samples float4x4AtTime:times[k].doubleValue] forTime:times[k].doubleValue];
    return copy;
}

- (void)setIdentity
{
    [self setMatrix:(matrix_float4x4){{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}} forTime:0];
}

// A sample at a time already held replaces that sample rather than standing beside it, and a time
// before the first or after the last sample falls on the first or the last, as every animated value
// of the port and of the host reads there.
- (void)setMatrix:(matrix_float4x4)matrix forTime:(NSTimeInterval)time
{
    [_samples setFloat4x4:matrix atTime:time];
    if (time <= 0)
        [self decompose];
}

- (matrix_float4x4)localTransformAtTime:(NSTimeInterval)time
{
    return [_samples float4x4AtTime:time];
}

- (void)setLocalTransform:(matrix_float4x4)transform forTime:(NSTimeInterval)time
{
    [self setMatrix:transform forTime:time];
}

- (void)setLocalTransform:(matrix_float4x4)transform
{
    [self setMatrix:transform forTime:0];
}

- (NSTimeInterval)minimumTime
{
    return _samples.minimumTime;
}

- (NSTimeInterval)maximumTime
{
    return _samples.maximumTime;
}

- (NSArray<NSNumber *> *)keyTimes
{
    return _samples.keyTimes;
}

- (vector_float3)translationAtTime:(NSTimeInterval)time
{
    vector_float4 translation = [_samples float4x4AtTime:time].columns[3];
    return (vector_float3){translation.x, translation.y, translation.z};
}

- (matrix_float4x4)rotationMatrixAtTime:(NSTimeInterval)time
{
    matrix_float4x4 matrix = [_samples float4x4AtTime:time];
    vector_float3 scale = {simd_length(matrix.columns[0]), simd_length(matrix.columns[1]), simd_length(matrix.columns[2])};
    matrix_float4x4 rotation;
    for (int c = 0; c < 3; c++) {
        float length = scale[c];
        rotation.columns[c] = length ? matrix.columns[c] / length : (vector_float4){0, 0, 0, 0};
    }
    rotation.columns[3] = (vector_float4){0, 0, 0, 1};
    return rotation;
}

- (vector_float3)rotationAtTime:(NSTimeInterval)time
{
    return CharonMDLRotationAngles([self rotationMatrixAtTime:time]);
}

- (vector_float3)scaleAtTime:(NSTimeInterval)time
{
    matrix_float4x4 matrix = [_samples float4x4AtTime:time];
    return (vector_float3){simd_length(matrix.columns[0]), simd_length(matrix.columns[1]), simd_length(matrix.columns[2])};
}

- (vector_float3)shearAtTime:(NSTimeInterval)time
{
    matrix_float4x4 matrix = [_samples float4x4AtTime:time];
    vector_float3 scale = [self scaleAtTime:time];
    vector_float3 shear = {0, 0, 0};
    if (scale.x)
        shear.x = matrix.columns[1].x / scale.x;
    if (scale.y && matrix.columns[1].x)
        shear.y = matrix.columns[2].x / (scale.x * matrix.columns[1].x / scale.y);
    if (scale.z)
        shear.z = matrix.columns[2].y / scale.z;
    return shear;
}

// The four accessors read the matrix; the four setters and the matrix setter write it back.
- (void)decompose
{
    _matrix = [_samples float4x4AtTime:0];
    _translation = [self translationAtTime:0];
    _scale = [self scaleAtTime:0];
    _shear = [self shearAtTime:0];
    _rotation = [self rotationAtTime:0];
}

- (void)setMatrix:(matrix_float4x4)matrix
{
    [self setMatrix:matrix forTime:0];
}

- (matrix_float4x4)matrixForTranslation:(vector_float3)translation
                               rotation:(vector_float3)rotation
                                  shear:(vector_float3)shear
                                  scale:(vector_float3)scale
{
    matrix_float4x4 result = {{scale.x, scale.x * shear.x, 0, 0}, {0, scale.y, scale.y * shear.y, 0}, {0, 0, scale.z, 0}, {0, 0, 0, 1}};
    result = simd_mul(CharonMDLRotationMatrix(rotation), result);
    result.columns[3] = (vector_float4){translation.x, translation.y, translation.z, 1};
    return result;
}

- (void)setTranslation:(vector_float3)translation forTime:(NSTimeInterval)time
{
    [self setMatrix:[self matrixForTranslation:translation rotation:[self rotationAtTime:time] shear:[self shearAtTime:time]
                                         scale:[self scaleAtTime:time]]
             forTime:time];
}

- (void)setRotation:(vector_float3)rotation forTime:(NSTimeInterval)time
{
    [self setMatrix:[self matrixForTranslation:[self translationAtTime:time] rotation:rotation shear:[self shearAtTime:time]
                                         scale:[self scaleAtTime:time]]
             forTime:time];
}

- (void)setShear:(vector_float3)shear forTime:(NSTimeInterval)time
{
    [self setMatrix:[self matrixForTranslation:[self translationAtTime:time] rotation:[self rotationAtTime:time] shear:shear
                                         scale:[self scaleAtTime:time]]
             forTime:time];
}

- (void)setScale:(vector_float3)scale forTime:(NSTimeInterval)time
{
    [self setMatrix:[self matrixForTranslation:[self translationAtTime:time] rotation:[self rotationAtTime:time]
                                         shear:[self shearAtTime:time] scale:scale]
             forTime:time];
}

- (void)setTranslation:(vector_float3)translation
{
    [self setTranslation:translation forTime:0];
}

- (void)setRotation:(vector_float3)rotation
{
    [self setRotation:rotation forTime:0];
}

- (void)setShear:(vector_float3)shear
{
    [self setShear:shear forTime:0];
}

- (void)setScale:(vector_float3)scale
{
    [self setScale:scale forTime:0];
}

+ (matrix_float4x4)globalTransformWithObject:(MDLObject *)object atTime:(NSTimeInterval)time
{
    matrix_float4x4 global = (matrix_float4x4){{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}};
    for (MDLObject *at = object; at; at = at.parent) {
        id<MDLTransformComponent> transform = at.transform;
        if (!transform)
            continue;
        // A transform that carries its own samples is asked for the time given; one that is a plain
        // matrix has the same matrix at every time.
        matrix_float4x4 local = [transform respondsToSelector:@selector(localTransformAtTime:)] ? [transform localTransformAtTime:time]
                                                                                              : transform.matrix;
        global = simd_mul(global, local);
    }
    return global;
}

@end
