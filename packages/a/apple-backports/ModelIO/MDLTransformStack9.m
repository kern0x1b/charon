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

@implementation MDLTransformRotateXOp {
    CharonMDLOpRecord _record;
    MDLAnimatedScalar *_value;
    int _axis;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _axis = 0;
        _value = [[MDLAnimatedScalar alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_value release];
    [super dealloc];
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
        [_value release];
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
    double angle = [_value doubleAtTime:time];
    return CharonMDLAxisRotation(_axis, _record.inverse ? -angle : angle);
}

- (matrix_float4x4)float4x4AtTime:(NSTimeInterval)time
{
    return CharonMDLFloat4x4([self double4x4AtTime:time]);
}

- (MDLAnimatedScalar *)animatedValue
{
    return _value;
}

@end

// The other two single-axis rotations are the same operation about their own axis.
@implementation MDLTransformRotateYOp {
    CharonMDLOpRecord _record;
    MDLAnimatedScalar *_value;
    int _axis;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _axis = 1;
        _value = [[MDLAnimatedScalar alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_value release];
    [super dealloc];
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
        [_value release];
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
    double angle = [_value doubleAtTime:time];
    return CharonMDLAxisRotation(_axis, _record.inverse ? -angle : angle);
}

- (matrix_float4x4)float4x4AtTime:(NSTimeInterval)time
{
    return CharonMDLFloat4x4([self double4x4AtTime:time]);
}

- (MDLAnimatedScalar *)animatedValue
{
    return _value;
}

@end

@implementation MDLTransformRotateZOp {
    CharonMDLOpRecord _record;
    MDLAnimatedScalar *_value;
    int _axis;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _axis = 2;
        _value = [[MDLAnimatedScalar alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_value release];
    [super dealloc];
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
        [_value release];
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
    double angle = [_value doubleAtTime:time];
    return CharonMDLAxisRotation(_axis, _record.inverse ? -angle : angle);
}

- (matrix_float4x4)float4x4AtTime:(NSTimeInterval)time
{
    return CharonMDLFloat4x4([self double4x4AtTime:time]);
}

- (MDLAnimatedScalar *)animatedValue
{
    return _value;
}

@end

@implementation MDLTransformRotateOp {
    CharonMDLOpRecord _record;
    MDLAnimatedVector3 *_value;
    MDLTransformOpRotationOrder _order;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _order = MDLTransformOpRotationOrderXYZ;
        _value = [[MDLAnimatedVector3 alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_value release];
    [super dealloc];
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
        [_value release];
        _value = (id)value;
    }
}

- (MDLTransformOpRotationOrder)charon_order
{
    return _order;
}

- (void)charon_setOrder:(MDLTransformOpRotationOrder)order
{
    _order = order;
}

- (void)charon_takeOverFrom:(id<MDLTransformOp>)op
{
    [self charon_setAnimatedValue:[(MDLAnimatedValue *)(MDLAnimatedValue *)[(id)op animatedValue] copy]];
    _record.name = [op name];
    _record.inverse = [op IsInverseOp];
    if ([op isKindOfClass:[MDLTransformRotateOp class]])
        _order = [(MDLTransformRotateOp *)op charon_order];
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
    vector_double3 angles = [_value double3AtTime:time];
    if (_record.inverse)
        angles = (vector_double3){-angles.x, -angles.y, -angles.z};
    return CharonMDLAngleRotation(angles, _order);
}

- (matrix_float4x4)float4x4AtTime:(NSTimeInterval)time
{
    return CharonMDLFloat4x4([self double4x4AtTime:time]);
}

- (MDLAnimatedVector3 *)animatedValue
{
    return _value;
}

@end

@implementation MDLTransformTranslateOp {
    CharonMDLOpRecord _record;
    MDLAnimatedVector3 *_value;
}

- (instancetype)init
{
    if ((self = [super init]))
        _value = [[MDLAnimatedVector3 alloc] init];
    return self;
}

- (void)dealloc
{
    [_value release];
    [super dealloc];
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
        [_value release];
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
    vector_double3 translation = [_value double3AtTime:time];
    if (_record.inverse)
        translation = (vector_double3){-translation.x, -translation.y, -translation.z};
    return CharonMDLTranslation(translation);
}

- (matrix_float4x4)float4x4AtTime:(NSTimeInterval)time
{
    return CharonMDLFloat4x4([self double4x4AtTime:time]);
}

- (MDLAnimatedVector3 *)animatedValue
{
    return _value;
}

@end

@implementation MDLTransformScaleOp {
    CharonMDLOpRecord _record;
    MDLAnimatedVector3 *_value;
}

- (instancetype)init
{
    if ((self = [super init]))
        _value = [[MDLAnimatedVector3 alloc] init];
    return self;
}

- (void)dealloc
{
    [_value release];
    [super dealloc];
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
        [_value release];
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
    vector_double3 scale = [_value double3AtTime:time];
    if (_record.inverse)
        scale = (vector_double3){scale.x ? 1 / scale.x : 0, scale.y ? 1 / scale.y : 0, scale.z ? 1 / scale.z : 0};
    return CharonMDLScale(scale);
}

- (matrix_float4x4)float4x4AtTime:(NSTimeInterval)time
{
    return CharonMDLFloat4x4([self double4x4AtTime:time]);
}

- (MDLAnimatedVector3 *)animatedValue
{
    return _value;
}

@end

@implementation MDLTransformMatrixOp {
    CharonMDLOpRecord _record;
    MDLAnimatedMatrix4x4 *_value;
}

- (instancetype)init
{
    if ((self = [super init]))
        _value = [[MDLAnimatedMatrix4x4 alloc] init];
    return self;
}

- (void)dealloc
{
    [_value release];
    [super dealloc];
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
        [_value release];
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
    matrix_double4x4 value = [_value double4x4AtTime:time];
    return _record.inverse ? simd_inverse(value) : value;
}

- (matrix_float4x4)float4x4AtTime:(NSTimeInterval)time
{
    return CharonMDLFloat4x4([self double4x4AtTime:time]);
}

- (MDLAnimatedMatrix4x4 *)animatedValue
{
    return _value;
}

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
    [_value release];
    [super dealloc];
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
        [_value release];
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

// A stack is the product of its operations in the order they were added, and it is also a transform
// component, so an object can carry one in place of an MDLTransform.

@implementation MDLTransformStack {
    NSMutableArray<id<MDLTransformOp>> *_ops;
    NSMutableDictionary<NSString *, MDLAnimatedValue *> *_values;
    BOOL _resetsTransform;
}

@synthesize resetsTransform = _resetsTransform;

- (instancetype)init
{
    if ((self = [super init])) {
        _ops = [[NSMutableArray alloc] init];
        _values = [[NSMutableDictionary alloc] init];
        _resetsTransform = YES;
    }
    return self;
}

- (void)dealloc
{
    [_ops release];
    [_values release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    MDLTransformStack *copy = [[[self class] allocWithZone:zone] init];
    for (id<MDLTransformOp> op in _ops) {
        id<CharonMDLTransformOpRecord> duplicate = [[[op class] allocWithZone:zone] init];
        // The copy keeps the samples of the value, not an empty one of the same shape.
        [duplicate charon_takeOverFrom:op];
        [copy charon_addOp:duplicate named:op.name inverse:[op IsInverseOp]];
    }
    return copy;
}

// Every operation added is named, and the value under that name is the one the operation reads, so
// animatedValueWithName: finds what an operation added under a name.
- (void)charon_addOp:(id<CharonMDLTransformOpRecord>)op named:(NSString *)name inverse:(bool)inverse
{
    CharonMDLOpRecord *record = [op charon_record];
    record->name = [name copy];
    record->inverse = inverse;
    [_ops addObject:op];
    [_values setObject:[op charon_value] forKey:name];
}

- (MDLTransformTranslateOp *)addTranslateOp:(NSString *)animatedValueName inverse:(bool)inverse
{
    MDLTransformTranslateOp *op = [[[MDLTransformTranslateOp alloc] init] autorelease];
    [self charon_addOp:op named:animatedValueName inverse:inverse];
    return op;
}

- (MDLTransformRotateXOp *)addRotateXOp:(NSString *)animatedValueName inverse:(bool)inverse
{
    MDLTransformRotateXOp *op = [[[MDLTransformRotateXOp alloc] init] autorelease];
    [self charon_addOp:op named:animatedValueName inverse:inverse];
    return op;
}

- (MDLTransformRotateYOp *)addRotateYOp:(NSString *)animatedValueName inverse:(bool)inverse
{
    MDLTransformRotateYOp *op = [[[MDLTransformRotateYOp alloc] init] autorelease];
    [self charon_addOp:op named:animatedValueName inverse:inverse];
    return op;
}

- (MDLTransformRotateZOp *)addRotateZOp:(NSString *)animatedValueName inverse:(bool)inverse
{
    MDLTransformRotateZOp *op = [[[MDLTransformRotateZOp alloc] init] autorelease];
    [self charon_addOp:op named:animatedValueName inverse:inverse];
    return op;
}

- (MDLTransformRotateOp *)addRotateOp:(NSString *)animatedValueName order:(MDLTransformOpRotationOrder)order inverse:(bool)inverse
{
    MDLTransformRotateOp *op = [[[MDLTransformRotateOp alloc] init] autorelease];
    [op charon_setOrder:order];
    [self charon_addOp:op named:animatedValueName inverse:inverse];
    return op;
}

- (MDLTransformScaleOp *)addScaleOp:(NSString *)animatedValueName inverse:(bool)inverse
{
    MDLTransformScaleOp *op = [[[MDLTransformScaleOp alloc] init] autorelease];
    [self charon_addOp:op named:animatedValueName inverse:inverse];
    return op;
}

- (MDLTransformMatrixOp *)addMatrixOp:(NSString *)animatedValueName inverse:(bool)inverse
{
    MDLTransformMatrixOp *op = [[[MDLTransformMatrixOp alloc] init] autorelease];
    [self charon_addOp:op named:animatedValueName inverse:inverse];
    return op;
}

- (MDLTransformOrientOp *)addOrientOp:(NSString *)animatedValueName inverse:(bool)inverse
{
    MDLTransformOrientOp *op = [[[MDLTransformOrientOp alloc] init] autorelease];
    [self charon_addOp:op named:animatedValueName inverse:inverse];
    return op;
}

- (MDLAnimatedValue *)animatedValueWithName:(NSString *)name
{
    return _values[name];
}

- (NSUInteger)count
{
    return _ops.count;
}

- (NSArray<id<MDLTransformOp>> *)transformOps
{
    return [[_ops copy] autorelease];
}

- (matrix_double4x4)double4x4AtTime:(NSTimeInterval)time
{
    matrix_double4x4 result = {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}};
    for (id<MDLTransformOp> op in _ops)
        result = simd_mul([op double4x4AtTime:time], result);
    return result;
}

- (matrix_float4x4)float4x4AtTime:(NSTimeInterval)time
{
    return CharonMDLFloat4x4([self double4x4AtTime:time]);
}

- (matrix_float4x4)matrix
{
    return [self float4x4AtTime:0];
}

- (matrix_float4x4)localTransformAtTime:(NSTimeInterval)time
{
    return [self float4x4AtTime:time];
}

- (void)setLocalTransform:(matrix_float4x4)transform forTime:(NSTimeInterval)time
{
    MDLTransformMatrixOp *op = [self addMatrixOp:@"charon_localTransform" inverse:NO];
    [(MDLAnimatedMatrix4x4 *)[(id)op animatedValue] setFloat4x4:transform atTime:time];
}

- (void)setLocalTransform:(matrix_float4x4)transform
{
    [self setLocalTransform:transform forTime:0];
}

- (NSTimeInterval)minimumTime
{
    NSTimeInterval minimum = 0;
    for (id<MDLTransformOp> op in _ops)
        minimum = MIN(minimum, [(MDLAnimatedValue *)[(id)op animatedValue] minimumTime]);
    return minimum;
}

- (NSTimeInterval)maximumTime
{
    NSTimeInterval maximum = 0;
    for (id<MDLTransformOp> op in _ops)
        maximum = MAX(maximum, [(MDLAnimatedValue *)[(id)op animatedValue] maximumTime]);
    return maximum;
}

- (NSArray<NSNumber *> *)keyTimes
{
    NSMutableSet<NSNumber *> *times = [NSMutableSet set];
    for (id<MDLTransformOp> op in _ops)
        for (NSNumber *time in [(MDLAnimatedValue *)[(id)op animatedValue] keyTimes])
            [times addObject:time];
    return [[times allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

@end
