#import <UIKit/UIKit.h>

// A pointer accessory, from iOS 15: a shape drawn beside the pointer at a position. The shape is copied on creation, as the host copies it
// (tests/backports/host/pointer-accessory). The orientation is NO for a custom accessory and keeps the value set; a copy does not carry it,
// which the host's copy does not either.
@implementation UIPointerAccessory {
@private
    UIPointerShape *_shape;
    UIPointerAccessoryPosition _position;
    BOOL _orientationMatchesAngle;
}

+ (instancetype)accessoryWithShape:(UIPointerShape *)shape position:(UIPointerAccessoryPosition)position
{
    UIPointerAccessory *accessory = [[self alloc] init];
    accessory->_shape = [shape copy];
    accessory->_position = position;
    return accessory;
}

- (UIPointerShape *)shape
{
    return _shape;
}

- (UIPointerAccessoryPosition)position
{
    return _position;
}

- (BOOL)orientationMatchesAngle
{
    return _orientationMatchesAngle;
}

- (void)setOrientationMatchesAngle:(BOOL)orientationMatchesAngle
{
    _orientationMatchesAngle = orientationMatchesAngle;
}

- (id)copyWithZone:(NSZone *)zone
{
    UIPointerAccessory *copy = [[[self class] allocWithZone:zone] init];
    copy->_shape = [_shape copy];
    copy->_position = _position;
    return copy;
}

@end
