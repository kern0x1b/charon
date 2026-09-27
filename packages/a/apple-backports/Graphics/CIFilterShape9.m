#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// A filter shape is the rectangle a filter is told to work over. It is not the image and not a mask: it
// is the region, and every operation on it is the same operation on that rectangle - two shapes
// intersect where their rectangles do, two shapes take a union where their rectangles do, an inset
// moves each edge in by its own amount, and a transform either bounds the transformed shape or cuts it
// back to its interior, which is the one question the interior flag answers.

@implementation CIFilterShape {
    CGRect _extent;
}

@synthesize extent = _extent;

- (instancetype)initWithRect:(CGRect)rect
{
    if ((self = [super init]))
        _extent = rect;
    return self;
}

+ (instancetype)shapeWithRect:(CGRect)rect
{
    return [[CIFilterShape alloc] initWithRect:rect];
}

- (CIFilterShape *)intersectWith:(CIFilterShape *)otherFilterShape
{
    return [CIFilterShape shapeWithRect:CGRectIntersection(_extent, otherFilterShape.extent)];
}

- (CIFilterShape *)intersectWithRect:(CGRect)rect
{
    return [CIFilterShape shapeWithRect:CGRectIntersection(_extent, rect)];
}

- (CIFilterShape *)unionWith:(CIFilterShape *)otherFilterShape
{
    return [CIFilterShape shapeWithRect:CGRectUnion(_extent, otherFilterShape.extent)];
}

- (CIFilterShape *)unionWithRect:(CGRect)rect
{
    return [CIFilterShape shapeWithRect:CGRectUnion(_extent, rect)];
}

// The header's own spelling and its own types: an inset of whole numbers, and a capital Y. Written
// with a lower-case y and a floating point amount it is a different selector, and a caller naming the
// header's one would not find it.
- (CIFilterShape *)insetByX:(int)dx Y:(int)dy
{
    return [CIFilterShape shapeWithRect:CGRectInset(_extent, dx, dy)];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[CIFilterShape allocWithZone:zone] initWithRect:_extent];
}

// A transform moves the shape. With the interior asked for, what comes back is the part of the
// transformed shape that is still inside the shape it started as, which for a translation is the
// overlap and for a transform that turns the shape inside out is nothing; without it, what comes back
// is the box the four transformed corners reach, which for a rotation is bigger than the shape.
- (CIFilterShape *)transformBy:(CGAffineTransform)transform interior:(BOOL)interior
{
    CGRect bounds = CGRectApplyAffineTransform(_extent, transform);
    if (!interior)
        return [CIFilterShape shapeWithRect:bounds];
    return [CIFilterShape shapeWithRect:CGRectIntersection(_extent, bounds)];
}

@end
