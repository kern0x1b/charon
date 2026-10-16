#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// The matrix is [a b; c d] acting on row vectors, with the translation (tx, ty) last. The components are the
// product scale * shear * rotation, with the translation applied after them: the first row of the matrix is
// sx times the unit vector u of the rotation, and the second is sy times (sh * u + v), v being u turned a quarter.
// Measured on the host (tests/backports/host/affine-components): the sign of the determinant carries a flip into
// sx, sy is never negative for a transform that is not rank one, and the rotation is the angle of the first row,
// turned a half circle back where the flip is. A matrix with a zero first row has no such angle: the rotation is
// zero, or a half circle when d is negative.

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
        CGFloat determinant = a * d - b * c;
        BOOL flip = determinant < 0;
        sx = flip ? -length : length;
        sy = flip ? -determinant / length : determinant / length;
        rotation = atan2(b, a) - (flip ? M_PI : 0);
    }
    CGFloat shear = 0;
    if (sy != 0)
        shear = (c * cos(rotation) + d * sin(rotation)) / sy;
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
