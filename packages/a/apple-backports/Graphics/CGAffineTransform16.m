#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// The matrix is [a b; c d] acting on row vectors, with the translation (tx, ty) last. The components are the
// product scale * shear * rotation, with the translation applied after them: the first row of the matrix is
// sx times the unit vector u of the rotation, and the second is sy times (sh * u + v), v being u turned a quarter.
// Measured on the host (tests/backports/host/affine-components): the rotation is the angle of the first row, and sy is
// the second row's component across that angle. A negative sy is the flip: it is made positive, sx is made negative,
// and the rotation is turned a half circle back into [-pi, pi). The host takes the sine and the cosine of an angle
// through one call, and the shear of a singular transform is a quotient of rounding, so the port does the same.
// A matrix with a zero first row has no such angle: the rotation is zero, or a half circle when d is negative.

static CGFloat charon_cosine(CGFloat angle)
{
    return __sincos_stret(angle).__cosval;
}

static CGFloat charon_sine(CGFloat angle)
{
    return __sincos_stret(angle).__sinval;
}

CGAffineTransformComponents CGAffineTransformDecompose(CGAffineTransform transform)
{
    CGFloat a = transform.a, b = transform.b, c = transform.c, d = transform.d;
    CGFloat length = hypot(a, b);
    CGFloat sx, sy, rotation;
    if (length == 0) {
        BOOL flip = d < 0;
        sx = flip ? -0.0 : 0;
        sy = fabs(d);
        rotation = flip ? -M_PI : 0;
    } else {
        CGFloat angle = atan2(b, a);
        CGFloat across = d * charon_cosine(angle) - c * charon_sine(angle);
        BOOL flip = across < 0;
        sx = flip ? -length : length;
        sy = flip ? -across : across;
        rotation = angle - (flip ? M_PI : 0);
        if (rotation < -M_PI)
            rotation += 2 * M_PI;
    }
    CGFloat shear = 0;
    if (sy != 0)
        shear = (c * charon_cosine(rotation) + d * charon_sine(rotation)) / sy;
    CGAffineTransformComponents components;
    components.scale = CGSizeMake(sx, sy);
    components.horizontalShear = shear;
    components.rotation = rotation;
    components.translation = CGVectorMake(transform.tx, transform.ty);
    return components;
}

CGAffineTransform CGAffineTransformMakeWithComponents(CGAffineTransformComponents components)
{
    CGFloat sx = components.scale.width, sy = components.scale.height, shear = components.horizontalShear;
    CGFloat cosine = cos(components.rotation), sine = sin(components.rotation);
    return CGAffineTransformMake(sx * cosine, sx * sine,
                                 sy * (shear * cosine - sine), sy * (shear * sine + cosine),
                                 components.translation.dx, components.translation.dy);
}
