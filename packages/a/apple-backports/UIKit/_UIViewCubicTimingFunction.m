#import "CharonTimingParameters.h"

@implementation _UIViewCubicTimingFunction {
@private
    CGPoint _point1;
    CGPoint _point2;
}

- (instancetype)init
{
    [NSException raise:NSInvalidArgumentException format:@"Don't call %@.", NSStringFromSelector(_cmd)];
    return nil;
}

- (instancetype)initWithControlPoint1:(CGPoint)point1 controlPoint2:(CGPoint)point2
{
    if ((self = [super init])) {
        _point1 = point1;
        _point2 = point2;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!coder.allowsKeyedCoding) {
        [NSException raise:NSInvalidUnarchiveOperationException format:@"%@ only supports keyed coding.", [self class]];
        return nil;
    }
    return [self initWithControlPoint1:[coder decodeCGPointForKey:@"point1"]
                         controlPoint2:[coder decodeCGPointForKey:@"point2"]];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeCGPoint:_point1 forKey:@"point1"];
    [coder encodeCGPoint:_point2 forKey:@"point2"];
}

- (CGPoint)controlPoint1
{
    return _point1;
}

- (CGPoint)controlPoint2
{
    return _point2;
}

- (CAMediaTimingFunction *)_mediaTimingFunction
{
    return [CAMediaTimingFunction functionWithControlPoints:_point1.x :_point1.y :_point2.x :_point2.y];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[[self class] allocWithZone:zone] initWithControlPoint1:_point1 controlPoint2:_point2];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ point1 = %@ point2 = %@>", [self class],
                                      NSStringFromCGPoint(_point1), NSStringFromCGPoint(_point2)];
}

@end
