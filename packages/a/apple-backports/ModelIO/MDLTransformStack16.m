#import <ModelIO/ModelIO.h>
#import <simd/simd.h>
#import <simd/simd.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// Every operation of a transform stack reads an animated value of one shape and turns it into a
// matrix. They differ only in that shape and in what the inverse of the operation is, so what they
// share - the name the stack was given for the operation, whether it was added as an inverse, the
// two spellings of its matrix - is a small set of methods each of them writes itself. All of this is
// the port's own: iOS 6 has no ModelIO at all.

// The name, the inverse flag and the matrix of one operation, in one struct every operation carries,
// so the stack can read and write them without knowing which operation it is holding.
typedef struct {
    __unsafe_unretained NSString *name;
    BOOL inverse;
} CharonMDLOpRecord;

static matrix_float4x4 CharonMDLFloat4x4(matrix_double4x4 value)
{
    matrix_float4x4 result;
    for (size_t c = 0; c < 4; c++)
        for (size_t r = 0; r < 4; r++)
            result.columns[c][r] = (float)value.columns[c][r];
    return result;
}

static matrix_double4x4 CharonMDLDouble4x4(matrix_float4x4 value)
{
    matrix_double4x4 result;
    for (size_t c = 0; c < 4; c++)
        for (size_t r = 0; r < 4; r++)
            result.columns[c][r] = value.columns[c][r];
    return result;
}

static matrix_double4x4 CharonMDLTranslation(vector_double3 translation)
{
    matrix_double4x4 result = {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}};
    result.columns[3] = (vector_double4){translation.x, translation.y, translation.z, 1};
    return result;
}

static matrix_double4x4 CharonMDLScale(vector_double3 scale)
{
    matrix_double4x4 result = {{scale.x, 0, 0, 0}, {0, scale.y, 0, 0}, {0, 0, scale.z, 0}, {0, 0, 0, 1}};
    return result;
}

// One axis rotation by an angle in radians, its inverse turning the other way by as much.
static matrix_double4x4 CharonMDLAxisRotation(int axis, double angle)
{
    double c = cos(angle), s = sin(angle);
    matrix_double4x4 result = {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}};
    result.columns[axis] = (vector_double4){c, s, 0, 0};
    result.columns[(axis + 1) % 3] = (vector_double4){-s, c, 0, 0};
    return result;
}

// Three axis angles composed in the order the operation was added with, the axes named as
// MDLTransformOpRotationOrder names them, so XYZ is the product of X, Y and Z in that order.
static matrix_double4x4 CharonMDLAngleRotation(vector_double3 angles, MDLTransformOpRotationOrder order)
{
    static const int axes[6] = {0, 1, 2, 0, 1, 2};
    static const int orderOf[6] = {0, 1, 2, 1, 0, 2};
    MDLTransformOpRotationOrder chosen = order >= MDLTransformOpRotationOrderXYZ && order <= MDLTransformOpRotationOrderZYX ? order
                                                                                                                          : MDLTransformOpRotationOrderXYZ;
    matrix_double4x4 result = {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}};
    for (int k = 0; k < 6; k++) {
        int axis = axes[orderOf[chosen - 1 + k]];
        result = simd_mul(CharonMDLAxisRotation(axis, angles[axis]), result);
    }
    return result;
}

// The rotation matrix of a quaternion, by its own four components: the imaginary part first and the
// real part last, which is the order a quaternion is written in.
static matrix_double4x4 CharonMDLQuaternionMatrix(simd_quatd rotation)
{
    double x = rotation.vector.x, y = rotation.vector.y, z = rotation.vector.z, w = rotation.vector.w;
    matrix_double4x4 result = {{1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0},
                               {2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0},
                               {2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0}, {0, 0, 0, 1}};
    return result;
}

// What the operations share, as the methods the stack and the protocol below use. Each operation
// writes them itself, over the one record it carries, and a new operation of the same class takes
// the whole state of the one it is a copy of.
@protocol CharonMDLTransformOpRecord <NSObject>
- (CharonMDLOpRecord *)charon_record;
- (MDLAnimatedValue *)charon_value;
- (void)charon_setAnimatedValue:(MDLAnimatedValue *)value;
- (void)charon_takeOverFrom:(id<MDLTransformOp>)op;
@end

@interface MDLTransformRotateXOp () <CharonMDLTransformOpRecord>
@end
@interface MDLTransformRotateYOp () <CharonMDLTransformOpRecord>
@end
@interface MDLTransformRotateZOp () <CharonMDLTransformOpRecord>
@end
@interface MDLTransformRotateOp () <CharonMDLTransformOpRecord>
- (MDLTransformOpRotationOrder)charon_order;
- (void)charon_setOrder:(MDLTransformOpRotationOrder)order;
@end
@interface MDLTransformTranslateOp () <CharonMDLTransformOpRecord>
@end
@interface MDLTransformScaleOp () <CharonMDLTransformOpRecord>
@end
@interface MDLTransformMatrixOp () <CharonMDLTransformOpRecord>
@end
@interface MDLTransformOrientOp () <CharonMDLTransformOpRecord>
@end

@implementation MDLTransformOrientOp {
    CharonMDLOpRecord _record;
    MDLAnimatedQuaternion *_value;
}

- (instancetype)init
{
    if ((self = [super init]))
        _value = [[MDLAnimatedQuaternion alloc] init];
    return self;
}

- (void)dealloc
{
}

- (CharonMDLOpRecord *)charon_record
{
    return &_record;
}

- (MDLAnimatedValue *)charon_value
{
    return _value;
}

- (void)charon_setAnimatedValue:(MDLAnimatedValue *)value
{
    if (_value != value) {
        _value = (id)value;
    }
}

- (void)charon_takeOverFrom:(id<MDLTransformOp>)op
{
    [self charon_setAnimatedValue:[(MDLAnimatedValue *)(MDLAnimatedValue *)[(id)op animatedValue] copy]];
    _record.name = [(id<MDLTransformOp>)op name];
    _record.inverse = [op IsInverseOp];
}

- (NSString *)name
{
    return _record.name;
}

- (bool)IsInverseOp
{
    return _record.inverse;
}

- (matrix_double4x4)double4x4AtTime:(NSTimeInterval)time
{
    simd_quatd rotation = [_value doubleQuaternionAtTime:time];
    return CharonMDLQuaternionMatrix(rotation);
}

- (matrix_float4x4)float4x4AtTime:(NSTimeInterval)time
{
    return CharonMDLFloat4x4([self double4x4AtTime:time]);
}

- (MDLAnimatedQuaternion *)animatedValue
{
    return _value;
}

@end
