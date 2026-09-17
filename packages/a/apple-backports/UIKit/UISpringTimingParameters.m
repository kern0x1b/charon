#import "CharonTimingParameters.h"

/* A CGFloat is a float on the architectures this is built for and a double on the
   64-bit ones, and the archive carries whichever it is, as Apple's own does. */
#if CGFLOAT_IS_DOUBLE
#define charon_encode_scalar(coder, value, key) [(coder) encodeDouble:(value) forKey:(key)]
#define charon_decode_scalar(coder, key) ((CGFloat)[(coder) decodeDoubleForKey:(key)])
#else
#define charon_encode_scalar(coder, value, key) [(coder) encodeFloat:(value) forKey:(key)]
#define charon_decode_scalar(coder, key) ((CGFloat)[(coder) decodeFloatForKey:(key)])
#endif

@implementation UISpringTimingParameters {
@private
    BOOL _implicitDuration;
    CGFloat _mass;
    CGFloat _stiffness;
    CGFloat _damping;
    CGFloat _dampingRatio;
    CGVector _initialVelocity;
}

- (instancetype)init
{
    if ((self = [super init])) {
        [self setMass:3];
        [self setStiffness:1000];
        [self setDamping:500];
    }
    return self;
}

- (instancetype)initWithMass:(CGFloat)mass stiffness:(CGFloat)stiffness damping:(CGFloat)damping
             initialVelocity:(CGVector)velocity
{
    if ((self = [super init])) {
        [self setMass:mass];
        [self setStiffness:stiffness];
        [self setDamping:damping];
        _initialVelocity = velocity;
    }
    return self;
}

- (instancetype)initWithDampingRatio:(CGFloat)ratio initialVelocity:(CGVector)velocity
{
    if ((self = [super init])) {
        _dampingRatio = ratio;
        _initialVelocity = velocity;
    }
    return self;
}

- (instancetype)initWithDampingRatio:(CGFloat)ratio
{
    return [self initWithDampingRatio:ratio initialVelocity:CGVectorMake(0, 0)];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!coder.allowsKeyedCoding) {
        [NSException raise:NSInvalidUnarchiveOperationException format:@"%@ only supports keyed coding.", [self class]];
        return nil;
    }
    if ((self = [super init])) {
        if ([coder decodeBoolForKey:@"implicitDuration"]) {
            [self setMass:charon_decode_scalar(coder, @"mass")];
            [self setStiffness:charon_decode_scalar(coder, @"stiffness")];
            [self setDamping:charon_decode_scalar(coder, @"damping")];
        } else {
            _dampingRatio = charon_decode_scalar(coder, @"dampingRatio");
        }
        _initialVelocity = [coder decodeCGVectorForKey:@"velocity"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeBool:_implicitDuration forKey:@"implicitDuration"];
    if (_implicitDuration) {
        charon_encode_scalar(coder, _mass, @"mass");
        charon_encode_scalar(coder, _stiffness, @"stiffness");
        charon_encode_scalar(coder, _damping, @"damping");
    } else {
        charon_encode_scalar(coder, _dampingRatio, @"dampingRatio");
    }
    [coder encodeCGVector:_initialVelocity forKey:@"velocity"];
}

- (UITimingCurveType)timingCurveType
{
    return UITimingCurveTypeSpring;
}

- (UICubicTimingParameters *)cubicTimingParameters
{
    return nil;
}

- (UISpringTimingParameters *)springTimingParameters
{
    return self;
}

- (CGVector)initialVelocity
{
    return _initialVelocity;
}

- (BOOL)implicitDuration
{
    return _implicitDuration;
}

- (CGFloat)mass
{
    return _mass;
}

- (CGFloat)stiffness
{
    return _stiffness;
}

- (CGFloat)damping
{
    return _damping;
}

- (CGFloat)dampingRatio
{
    if (!_implicitDuration)
        return _dampingRatio;
    CGFloat critical = 2 * sqrt(_mass * _stiffness);
    return critical != 0 ? _damping / critical : 0;
}

- (void)setMass:(CGFloat)mass
{
    _mass = mass;
    _implicitDuration = YES;
}

- (void)setStiffness:(CGFloat)stiffness
{
    _stiffness = stiffness;
    _implicitDuration = YES;
}

- (void)setDamping:(CGFloat)damping
{
    _damping = damping;
    _implicitDuration = YES;
}

- (id)copyWithZone:(NSZone *)zone
{
    if (_implicitDuration)
        return [[[self class] allocWithZone:zone] initWithMass:_mass stiffness:_stiffness damping:_damping
                                              initialVelocity:_initialVelocity];
    return [[[self class] allocWithZone:zone] initWithDampingRatio:_dampingRatio initialVelocity:_initialVelocity];
}

- (NSString *)description
{
    if (_implicitDuration)
        return [NSString stringWithFormat:@"<%@ (%p) mass=%.3f, stiffness=%.3f, damping=%.3f, velocity=(%.3f,%.3f)>",
                                          [self class], self, _mass, _stiffness, _damping,
                                          _initialVelocity.dx, _initialVelocity.dy];
    return [NSString stringWithFormat:@"<%@ (%p) dampingRatio=%.3f, velocity=(%.3f,%.3f)>",
                                      [self class], self, _dampingRatio, _initialVelocity.dx, _initialVelocity.dy];
}

@end
