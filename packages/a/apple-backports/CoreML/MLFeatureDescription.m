/* MLFeatureDescription: what a model says about one of its features, and the constraints that
 * say which values that feature will take.
 *
 * The model reader has already read all of this out of the specification's own fields -- the
 * name, the kind of value, whether the feature may be left out, and for a multi array or an
 * image or a sequence the shape, the size, the element type and the count. This turns that into
 * the classes an application asks, and the one method that matters is `-isAllowedValue:`, which
 * is the check a caller makes before it hands a value to a model and the check the model makes
 * of what it is handed.
 *
 * The constraints are separate classes because that is how Core ML declares them: a feature of
 * the multi array type carries a multi array constraint and none of the others, and a caller
 * reading `multiArrayConstraint` of a string feature gets nil. So a description builds the
 * constraint its own type has and no other.
 */
#import <CoreML/CoreML.h>

#include "CharonMLBridge.h"
#include "CharonMLInternal.h"
#include "CharonMLModel.h"

/* The constraints' own storage and the one initialiser each of them is built with. None of them
 * has a public initialiser in Core ML -- a model builds them and a caller only reads them -- so
 * the initialiser each is built with is declared here, next to the storage it fills, and the
 * declaration comes before the reading code that uses it. */
@interface MLMultiArrayShapeConstraint () {
    MLMultiArrayShapeConstraintType _type;
    NSArray<NSValue *> *_sizeRangeForDimension;
    NSArray<NSArray<NSNumber *> *> *_enumeratedShapes;
}
- (instancetype)charon_initWithType:(MLMultiArrayShapeConstraintType)type
                  sizeRanges:(NSArray<NSValue *> *)sizeRanges
           enumeratedShapes:(NSArray<NSArray<NSNumber *> *> *)enumeratedShapes;
@end

@interface MLMultiArrayConstraint () {
    NSArray<NSNumber *> *_shape;
    MLMultiArrayDataType _dataType;
    MLMultiArrayShapeConstraint *_shapeConstraint;
}
- (instancetype)charon_initWithShape:(NSArray<NSNumber *> *)shape
                     dataType:(MLMultiArrayDataType)dataType
               shapeConstraint:(MLMultiArrayShapeConstraint *)shapeConstraint;
@end

@interface MLImageSize () {
    NSInteger _pixelsWide;
    NSInteger _pixelsHigh;
}
- (instancetype)charon_initWithPixelsWide:(NSInteger)pixelsWide pixelsHigh:(NSInteger)pixelsHigh;
@end

@interface MLImageSizeConstraint () {
    MLImageSizeConstraintType _type;
    NSRange _pixelsWideRange;
    NSRange _pixelsHighRange;
    NSArray<MLImageSize *> *_enumeratedImageSizes;
}
- (instancetype)charon_initWithType:(MLImageSizeConstraintType)type
              pixelsWideRange:(NSRange)pixelsWideRange
             pixelsHighRange:(NSRange)pixelsHighRange
        enumeratedImageSizes:(NSArray<MLImageSize *> *)enumeratedImageSizes;
@end

@interface MLImageConstraint () {
    NSInteger _pixelsHigh;
    NSInteger _pixelsWide;
    OSType _pixelFormatType;
    MLImageSizeConstraint *_sizeConstraint;
}
- (instancetype)charon_initWithPixelsHigh:(NSInteger)pixelsHigh
                        pixelsWide:(NSInteger)pixelsWide
                  pixelFormatType:(OSType)pixelFormatType
                    sizeConstraint:(MLImageSizeConstraint *)sizeConstraint;
@end

@interface MLDictionaryConstraint () {
    MLFeatureType _keyType;
}
- (instancetype)charon_initWithKeyType:(MLFeatureType)keyType;
@end

@interface MLSequenceConstraint () {
    MLFeatureDescription *_valueDescription;
    NSRange _countRange;
}
- (instancetype)charon_initWithValueDescription:(MLFeatureDescription *)valueDescription
                              countRange:(NSRange)countRange;
@end

@interface MLNumericConstraint () {
    NSNumber *_minNumber;
    NSNumber *_maxNumber;
    NSSet<NSNumber *> *_enumeratedNumbers;
}
- (instancetype)charon_initWithMinNumber:(NSNumber *)minNumber
                         maxNumber:(NSNumber *)maxNumber
                enumeratedNumbers:(NSSet<NSNumber *> *)enumeratedNumbers;
@end

@interface MLFeatureDescription () {
    NSString *_name;
    MLFeatureType _type;
    BOOL _optional;
    MLMultiArrayConstraint *_multiArrayConstraint;
    MLImageConstraint *_imageConstraint;
    MLDictionaryConstraint *_dictionaryConstraint;
    MLSequenceConstraint *_sequenceConstraint;
}
- (instancetype)charon_initWithName:(NSString *)name type:(MLFeatureType)type optional:(BOOL)optional;
- (instancetype)charon_initWithFeature:(const charon_ml_feature *)feature;
@end

#pragma mark - reading the specification's own constraint

/* The specification writes a feature's shape or size in one of three ways, and which one it
 * wrote is what decides what a caller is told: one shape, a range per dimension, or a set of the
 * shapes it will take. A set and a range are in the same oneof, so a document that names both
 * names both and the set is the one that decides -- it is the one a caller has to be able to
 * name a shape from, and a range that merely covers the set would tell the caller the shape is
 * allowed without saying which of the allowed ones it is. */
static MLMultiArrayShapeConstraint *charon_ml_shape_constraint_of(const charon_ml_feature *feature)
{
    if (feature->shape_kind == CHARON_ML_SHAPE_ENUMERATED && feature->enumerated_count > 0) {
        NSMutableArray<NSArray<NSNumber *> *> *shapes =
            [NSMutableArray arrayWithCapacity:feature->enumerated_count];
        size_t index;
        for (index = 0; index < feature->enumerated_count; index++) {
            [shapes addObject:charon_ml_shape_to_array(feature->enumerated_shapes[index],
                                                       feature->enumerated_ranks[index])];
        }
        return [[MLMultiArrayShapeConstraint alloc]
            charon_initWithType:MLMultiArrayShapeConstraintTypeEnumerated
             sizeRanges:@[]
          enumeratedShapes:shapes];
    }
    if (feature->shape_kind == CHARON_ML_SHAPE_RANGE) {
        NSMutableArray<NSValue *> *ranges = [NSMutableArray arrayWithCapacity:CHARON_ML_MAX_RANK];
        int axis;
        for (axis = 0; axis < feature->rank; axis++) {
            int64_t least = feature->shape_range[axis][0];
            int64_t most = feature->shape_range[axis][1];
            /* The specification's flexible dimension -- an upper bound of -1 -- is a dimension
             * of no fixed length, so it has no range to answer: NSRange's own flexible length
             * is 0, which is also what a dimension with no range at all gives, and both mean
             * any length. The lower bound is kept either way, because a dimension of at least
             * three and of no fixed length is a real bound. */
            NSUInteger length = most < 0 ? 0 : (NSUInteger)(most - least);
            [ranges addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)least, length)]];
        }
        return [[MLMultiArrayShapeConstraint alloc]
            charon_initWithType:MLMultiArrayShapeConstraintTypeRange
             sizeRanges:ranges
          enumeratedShapes:@[]];
    }
    return nil;
}

/* An image's size, in the two numbers it is measured in. A range of length zero is the
 * specification's "no upper bound", and it is left as zero: a dimension whose upper bound is
 * flexible has no upper bound to report, and the type says which of the two kinds of
 * constraint this is. */
static MLImageSizeConstraint *charon_ml_image_size_constraint_of(const charon_ml_feature *feature)
{
    if (feature->enumerated_count > 0 && feature->enumerated_widths != NULL) {
        NSMutableArray<MLImageSize *> *sizes = [NSMutableArray arrayWithCapacity:feature->enumerated_count];
        size_t index;
        for (index = 0; index < feature->enumerated_count; index++) {
            [sizes addObject:[[MLImageSize alloc] charon_initWithPixelsWide:feature->enumerated_widths[index]
                                                           pixelsHigh:feature->enumerated_heights[index]]];
        }
        return [[MLImageSizeConstraint alloc] charon_initWithType:MLImageSizeConstraintTypeEnumerated
                                             pixelsWideRange:NSMakeRange(0, 0)
                                            pixelsHighRange:NSMakeRange(0, 0)
                                       enumeratedImageSizes:sizes];
    }
    if (feature->image_width_range != 0 || feature->image_height_range != 0 ||
        feature->image_width <= 0 || feature->image_height <= 0) {
        /* A range of either number is a range of both, and an upper bound of -1 is the
         * specification's flexible one: no upper bound, so a length of zero. */
        NSUInteger wide = feature->image_width_range > 0
                              ? (NSUInteger)(feature->image_width - feature->image_width_range)
                              : 0;
        NSUInteger high = feature->image_height_range > 0
                              ? (NSUInteger)(feature->image_height - feature->image_height_range)
                              : 0;
        return [[MLImageSizeConstraint alloc]
            charon_initWithType:MLImageSizeConstraintTypeRange
            pixelsWideRange:NSMakeRange((NSUInteger)feature->image_width_range, wide)
           pixelsHighRange:NSMakeRange((NSUInteger)feature->image_height_range, high)
        enumeratedImageSizes:@[]];
    }
    return [[MLImageSizeConstraint alloc] charon_initWithType:MLImageSizeConstraintTypeUnspecified
                                        pixelsWideRange:NSMakeRange(0, 0)
                                       pixelsHighRange:NSMakeRange(0, 0)
                                  enumeratedImageSizes:@[]];
}

static MLImageConstraint *charon_ml_image_constraint_of(const charon_ml_feature *feature)
{
    return [[MLImageConstraint alloc] charon_initWithPixelsHigh:feature->image_height
                                              pixelsWide:feature->image_width
                                        pixelFormatType:charon_ml_pixel_format_of(feature->image_color_space)
                                          sizeConstraint:charon_ml_image_size_constraint_of(feature)];
}

/* Whether a shape is one the constraint allows. The three cases are the three the constraint
 * type names, and the case that decides is the type rather than what the arrays happen to hold:
 * a constraint of the enumerated kind with nothing in it allows nothing, which is not the same
 * answer as an unconstrained one and is what a caller comparing two constraints has to see. */
static BOOL charon_ml_shape_allowed(MLMultiArrayShapeConstraint *constraint, NSArray<NSNumber *> *shape)
{
    NSUInteger index;
    if (constraint == nil) {
        return YES;
    }
    switch (constraint.type) {
    case MLMultiArrayShapeConstraintTypeEnumerated:
        for (index = 0; index < constraint.enumeratedShapes.count; index++) {
            if ([constraint.enumeratedShapes[index] isEqualToArray:shape]) {
                return YES;
            }
        }
        return NO;
    case MLMultiArrayShapeConstraintTypeRange:
        for (index = 0; index < shape.count && index < constraint.sizeRangeForDimension.count; index++) {
            NSRange allowed = [constraint.sizeRangeForDimension[index] rangeValue];
            NSInteger length = [shape[index] integerValue];
            if (length < (NSInteger)allowed.location ||
                (allowed.length != 0 && (NSUInteger)length > allowed.location + allowed.length)) {
                return NO;
            }
        }
        return YES;
    default:
        return YES;
    }
}

/* Whether an image is one the constraint allows: the size it fixes, a size inside the range it
 * allows, or one of the sizes it enumerates. An image feature this port was handed as a pixel
 * buffer knows its own size, and one that is not a buffer at all -- an undefined value, which
 * the type check has already let through only for an optional feature -- has no size to judge. */
static BOOL charon_ml_image_size_allowed(MLImageSizeConstraint *constraint, NSInteger fixedHigh,
                                         NSInteger fixedWide, CVPixelBufferRef buffer)
{
    NSInteger high, wide;
    NSUInteger index;
    if (buffer == NULL) {
        return NO;
    }
    high = (NSInteger)CVPixelBufferGetHeight(buffer);
    wide = (NSInteger)CVPixelBufferGetWidth(buffer);
    switch (constraint.type) {
    case MLImageSizeConstraintTypeEnumerated:
        for (index = 0; index < constraint.enumeratedImageSizes.count; index++) {
            MLImageSize *size = constraint.enumeratedImageSizes[index];
            if (size.pixelsHigh == high && size.pixelsWide == wide) {
                return YES;
            }
        }
        return NO;
    case MLImageSizeConstraintTypeRange: {
        NSRange wideRange = constraint.pixelsWideRange;
        NSRange highRange = constraint.pixelsHighRange;
        if (wide < (NSInteger)wideRange.location ||
            (wideRange.length != 0 && (NSUInteger)wide > wideRange.location + wideRange.length)) {
            return NO;
        }
        if (high < (NSInteger)highRange.location ||
            (highRange.length != 0 && (NSUInteger)high > highRange.location + highRange.length)) {
            return NO;
        }
        return YES;
    }
    default:
        /* No range and no set: the feature fixes the size, and a feature that fixes none takes
         * any, which is the same answer the fixed numbers give when they are zero. */
        if (fixedHigh > 0 && fixedHigh != high) {
            return NO;
        }
        if (fixedWide > 0 && fixedWide != wide) {
            return NO;
        }
        return YES;
    }
}

static const char *charon_ml_feature_type_name_of(MLFeatureType type)
{
    switch (type) {
    case MLFeatureTypeInt64: return "int64";
    case MLFeatureTypeDouble: return "double";
    case MLFeatureTypeString: return "string";
    case MLFeatureTypeImage: return "image";
    case MLFeatureTypeMultiArray: return "multiArray";
    case MLFeatureTypeDictionary: return "dictionary";
    case MLFeatureTypeSequence: return "sequence";
    default: return "invalid";
    }
}

#pragma mark - the constraints

@implementation MLMultiArrayShapeConstraint

- (instancetype)charon_initWithType:(MLMultiArrayShapeConstraintType)type
                  sizeRanges:(NSArray<NSValue *> *)sizeRanges
           enumeratedShapes:(NSArray<NSArray<NSNumber *> *> *)enumeratedShapes
{
    MLMultiArrayShapeConstraint *built = [super init];
    if (built != nil) {
        _type = type;
        _sizeRangeForDimension = sizeRanges != nil ? [sizeRanges copy] : @[];
        _enumeratedShapes = enumeratedShapes != nil ? [enumeratedShapes copy] : @[];
    }
    return built;
}

- (MLMultiArrayShapeConstraintType)type
{
    return _type;
}

- (NSArray<NSValue *> *)sizeRangeForDimension
{
    return _sizeRangeForDimension;
}

- (NSArray<NSArray<NSNumber *> *> *)enumeratedShapes
{
    return _enumeratedShapes;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self != nil) {
        _type = (MLMultiArrayShapeConstraintType)[coder decodeIntegerForKey:@"type"];
        _sizeRangeForDimension = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [NSValue class], nil]
                                                      forKey:@"sizeRangeForDimension"];
        _enumeratedShapes = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [NSArray class], [NSNumber class], nil]
                                                forKey:@"enumeratedShapes"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:(NSInteger)_type forKey:@"type"];
    [coder encodeObject:_sizeRangeForDimension forKey:@"sizeRangeForDimension"];
    [coder encodeObject:_enumeratedShapes forKey:@"enumeratedShapes"];
}

@end

/* The element type and the shape a multi array feature takes. A model that fixes its shape
 * gives one shape here and no shape constraint at all; a model that will take a range of shapes
 * gives the range in the shape constraint, and its shape array then holds a -1 for the dimension
 * whose length is not fixed, which is the specification's own way of writing "flexible". */
@implementation MLMultiArrayConstraint

- (instancetype)charon_initWithShape:(NSArray<NSNumber *> *)shape
                     dataType:(MLMultiArrayDataType)dataType
               shapeConstraint:(MLMultiArrayShapeConstraint *)shapeConstraint
{
    MLMultiArrayConstraint *built = [super init];
    if (built != nil) {
        _shape = shape != nil ? [shape copy] : @[];
        _dataType = dataType;
        _shapeConstraint = shapeConstraint;
    }
    return built;
}

- (NSArray<NSNumber *> *)shape
{
    return _shape;
}

- (MLMultiArrayDataType)dataType
{
    return _dataType;
}

- (MLMultiArrayShapeConstraint *)shapeConstraint
{
    return _shapeConstraint;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self != nil) {
        _shape = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [NSNumber class], nil] forKey:@"shape"];
        _dataType = (MLMultiArrayDataType)[coder decodeIntForKey:@"dataType"];
        _shapeConstraint = [coder decodeObjectOfClass:[MLMultiArrayShapeConstraint class]
                                            forKey:@"shapeConstraint"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_shape forKey:@"shape"];
    [coder encodeInt:(int)_dataType forKey:@"dataType"];
    [coder encodeObject:_shapeConstraint forKey:@"shapeConstraint"];
}

@end

/* One image size, in the two numbers an image is measured in. */
@implementation MLImageSize

- (instancetype)charon_initWithPixelsWide:(NSInteger)pixelsWide pixelsHigh:(NSInteger)pixelsHigh
{
    MLImageSize *built = [super init];
    if (built != nil) {
        _pixelsWide = pixelsWide;
        _pixelsHigh = pixelsHigh;
    }
    return built;
}

- (NSInteger)pixelsWide
{
    return _pixelsWide;
}

- (NSInteger)pixelsHigh
{
    return _pixelsHigh;
}

/* Two sizes are the same size when they are the same two numbers: there is nothing else an
 * image size carries, and a caller putting sizes in a set is asking exactly that. */
- (BOOL)isEqual:(id)object
{
    MLImageSize *other = [object isKindOfClass:[MLImageSize class]] ? object : nil;
    if (other == nil) {
        return NO;
    }
    return other->_pixelsWide == _pixelsWide && other->_pixelsHigh == _pixelsHigh;
}

- (NSUInteger)hash
{
    return (NSUInteger)(_pixelsWide * 31 + _pixelsHigh);
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MLImageSize %ld x %ld>", (long)_pixelsWide, (long)_pixelsHigh];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self != nil) {
        _pixelsWide = [coder decodeIntegerForKey:@"pixelsWide"];
        _pixelsHigh = [coder decodeIntegerForKey:@"pixelsHigh"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:_pixelsWide forKey:@"pixelsWide"];
    [coder encodeInteger:_pixelsHigh forKey:@"pixelsHigh"];
}

@end

/* The sizes an image feature takes: any, a set of them, or a range for each of the two numbers.
 * A range of length zero is the specification's "no upper bound", which is a range that does not
 * stop -- and a range of *location* zero with no length is a range that does not start either,
 * which is the same thing as no range at all. */
@implementation MLImageSizeConstraint

- (instancetype)charon_initWithType:(MLImageSizeConstraintType)type
              pixelsWideRange:(NSRange)pixelsWideRange
             pixelsHighRange:(NSRange)pixelsHighRange
        enumeratedImageSizes:(NSArray<MLImageSize *> *)enumeratedImageSizes
{
    MLImageSizeConstraint *built = [super init];
    if (built != nil) {
        _type = type;
        _pixelsWideRange = pixelsWideRange;
        _pixelsHighRange = pixelsHighRange;
        _enumeratedImageSizes = enumeratedImageSizes != nil ? [enumeratedImageSizes copy] : @[];
    }
    return built;
}

- (MLImageSizeConstraintType)type
{
    return _type;
}

- (NSRange)pixelsWideRange
{
    return _pixelsWideRange;
}

- (NSRange)pixelsHighRange
{
    return _pixelsHighRange;
}

- (NSArray<MLImageSize *> *)enumeratedImageSizes
{
    return _enumeratedImageSizes;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self != nil) {
        _type = (MLImageSizeConstraintType)[coder decodeIntegerForKey:@"type"];
        _pixelsWideRange = [[coder decodeObjectOfClass:[NSValue class] forKey:@"pixelsWideRange"] rangeValue];
        _pixelsHighRange = [[coder decodeObjectOfClass:[NSValue class] forKey:@"pixelsHighRange"] rangeValue];
        _enumeratedImageSizes = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [MLImageSize class], nil]
                                                forKey:@"enumeratedImageSizes"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:(NSInteger)_type forKey:@"type"];
    [coder encodeObject:[NSValue valueWithRange:_pixelsWideRange] forKey:@"pixelsWideRange"];
    [coder encodeObject:[NSValue valueWithRange:_pixelsHighRange] forKey:@"pixelsHighRange"];
    [coder encodeObject:_enumeratedImageSizes forKey:@"enumeratedImageSizes"];
}

@end

/* An image feature's own numbers: the size it wants, the pixel format it wants, and the range or
 * the set of sizes it will take. The specification writes an image feature as a width, a height
 * and a colour space, and a model that will take more than one size writes the set or the range
 * beside them. */
@implementation MLImageConstraint

- (instancetype)charon_initWithPixelsHigh:(NSInteger)pixelsHigh
                        pixelsWide:(NSInteger)pixelsWide
                  pixelFormatType:(OSType)pixelFormatType
                    sizeConstraint:(MLImageSizeConstraint *)sizeConstraint
{
    MLImageConstraint *built = [super init];
    if (built != nil) {
        _pixelsHigh = pixelsHigh;
        _pixelsWide = pixelsWide;
        _pixelFormatType = pixelFormatType;
        _sizeConstraint = sizeConstraint;
    }
    return built;
}

- (NSInteger)pixelsHigh
{
    return _pixelsHigh;
}

- (NSInteger)pixelsWide
{
    return _pixelsWide;
}

- (OSType)pixelFormatType
{
    return _pixelFormatType;
}

- (MLImageSizeConstraint *)sizeConstraint
{
    return _sizeConstraint;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self != nil) {
        _pixelsHigh = [coder decodeIntegerForKey:@"pixelsHigh"];
        _pixelsWide = [coder decodeIntegerForKey:@"pixelsWide"];
        _pixelFormatType = (OSType)[[coder decodeObjectOfClass:[NSNumber class]
                                                   forKey:@"pixelFormatType"] unsignedIntValue];
        _sizeConstraint = [coder decodeObjectOfClass:[MLImageSizeConstraint class] forKey:@"sizeConstraint"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:_pixelsHigh forKey:@"pixelsHigh"];
    [coder encodeInteger:_pixelsWide forKey:@"pixelsWide"];
    [coder encodeObject:@((uint32_t)_pixelFormatType) forKey:@"pixelFormatType"];
    [coder encodeObject:_sizeConstraint forKey:@"sizeConstraint"];
}

@end

/* What a dictionary feature's keys have to be. There is one thing to say about a dictionary --
 * the kind of its keys -- so this is the smallest of the constraints. */
@implementation MLDictionaryConstraint

- (instancetype)charon_initWithKeyType:(MLFeatureType)keyType
{
    MLDictionaryConstraint *built = [super init];
    if (built != nil) {
        _keyType = keyType;
    }
    return built;
}

- (MLFeatureType)keyType
{
    return _keyType;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self != nil) {
        _keyType = (MLFeatureType)[coder decodeIntegerForKey:@"keyType"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:(NSInteger)_keyType forKey:@"keyType"];
}

@end

/* A sequence feature: what one element of it is, which is a description of its own, and how many
 * elements it may have. The count range's length of zero is the specification's "no upper
 * bound", so a sequence with a lower bound of two and no upper one answers a range starting at
 * two with no length -- and a sequence with neither answers a range of zero, which is any count. */
@implementation MLSequenceConstraint

- (instancetype)charon_initWithValueDescription:(MLFeatureDescription *)valueDescription
                              countRange:(NSRange)countRange
{
    MLSequenceConstraint *built = [super init];
    if (built != nil) {
        _valueDescription = valueDescription;
        _countRange = countRange;
    }
    return built;
}

- (MLFeatureDescription *)valueDescription
{
    return _valueDescription;
}

- (NSRange)countRange
{
    return _countRange;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self != nil) {
        _valueDescription = [coder decodeObjectOfClass:[MLFeatureDescription class]
                                            forKey:@"valueDescription"];
        _countRange = [[coder decodeObjectOfClass:[NSValue class] forKey:@"countRange"] rangeValue];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_valueDescription forKey:@"valueDescription"];
    [coder encodeObject:[NSValue valueWithRange:_countRange] forKey:@"countRange"];
}

@end

/* The bound a model's own parameter values sit in, which is how an updatable model says that a
 * learning rate is one of these numbers rather than any. This port reads no updatable model --
 * facts/CoreML/CoreML.md says why -- so no description of the port's own carries such a
 * constraint, and a parameter description answers nil for it rather than a bound of nothing. */
@implementation MLNumericConstraint

- (instancetype)charon_initWithMinNumber:(NSNumber *)minNumber
                         maxNumber:(NSNumber *)maxNumber
                enumeratedNumbers:(NSSet<NSNumber *> *)enumeratedNumbers
{
    MLNumericConstraint *built = [super init];
    if (built != nil) {
        _minNumber = minNumber;
        _maxNumber = maxNumber;
        _enumeratedNumbers = enumeratedNumbers != nil ? [enumeratedNumbers copy] : nil;
    }
    return built;
}

- (NSNumber *)minNumber
{
    return _minNumber;
}

- (NSNumber *)maxNumber
{
    return _maxNumber;
}

- (NSSet<NSNumber *> *)enumeratedNumbers
{
    return _enumeratedNumbers;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self != nil) {
        _minNumber = [coder decodeObjectOfClass:[NSNumber class] forKey:@"minNumber"];
        _maxNumber = [coder decodeObjectOfClass:[NSNumber class] forKey:@"maxNumber"];
        _enumeratedNumbers = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSSet class], [NSNumber class], nil]
                                                forKey:@"enumeratedNumbers"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_minNumber forKey:@"minNumber"];
    [coder encodeObject:_maxNumber forKey:@"maxNumber"];
    [coder encodeObject:_enumeratedNumbers forKey:@"enumeratedNumbers"];
}

@end

#pragma mark - the description

@implementation MLFeatureDescription

/* The description of a feature that names no constraints of its own, which is what a sequence's
 * element is: the specification types a sequence's element in the feature's own oneof rather
 * than in a description, so an element is a number or a string and nothing else, and the
 * description a caller reads it through has to say that much and no more. */
- (instancetype)charon_initWithName:(NSString *)name
                        type:(MLFeatureType)type
                    optional:(BOOL)optional
{
    MLFeatureDescription *built = [super init];
    if (built != nil) {
        _name = [name copy];
        _type = type;
        _optional = optional;
    }
    return built;
}

/* Builds the description of one feature out of what the model reader read for it. The name is
 * copied because the reader's copy belongs to the model and the description outlives it, and
 * each constraint is built here because whether a feature has one follows from its own type: a
 * multi array has a multi array constraint and nothing else does. */
- (instancetype)charon_initWithFeature:(const charon_ml_feature *)feature
{
    /* The description of one feature is the description of its name, type and optionality with
     * the constraints of that type built onto it, so it is built by handing those three to the
     * initialiser that takes them and then filling in what the type implies. */
    MLFeatureDescription *built = [self charon_initWithName:feature->name != NULL ? @(feature->name) : nil
                                                      type:charon_ml_feature_type_of(feature->type)
                                                  optional:feature->optional != 0];
    if (built == nil) {
        return nil;
    }
    switch (_type) {
    case MLFeatureTypeMultiArray:
        _multiArrayConstraint = [[MLMultiArrayConstraint alloc]
            charon_initWithShape:charon_ml_shape_to_array(feature->shape, feature->rank)
                 dataType:charon_ml_array_type(feature->data_type)
           shapeConstraint:charon_ml_shape_constraint_of(feature)];
        break;
    case MLFeatureTypeImage:
        _imageConstraint = charon_ml_image_constraint_of(feature);
        break;
    case MLFeatureTypeDictionary:
        _dictionaryConstraint = [[MLDictionaryConstraint alloc] charon_initWithKeyType:MLFeatureTypeString];
        break;
    case MLFeatureTypeSequence: {
        MLFeatureDescription *element =
            [[MLFeatureDescription alloc] charon_initWithName:nil
                                                  type:charon_ml_feature_type_of(feature->element_type)
                                              optional:NO];
        NSUInteger length = feature->has_count_range && feature->count_upper >= 0
                                ? (NSUInteger)(feature->count_upper - feature->count_lower)
                                : 0;
        _sequenceConstraint = [[MLSequenceConstraint alloc]
            charon_initWithValueDescription:element
                          countRange:NSMakeRange((NSUInteger)feature->count_lower, length)];
        break;
    }
    default:
        break;
    }
    return built;
}

- (NSString *)name
{
    return _name;
}

- (MLFeatureType)type
{
    return _type;
}

- (BOOL)isOptional
{
    return _optional;
}

- (MLMultiArrayConstraint *)multiArrayConstraint
{
    return _multiArrayConstraint;
}

- (MLImageConstraint *)imageConstraint
{
    return _imageConstraint;
}

- (MLDictionaryConstraint *)dictionaryConstraint
{
    return _dictionaryConstraint;
}

- (MLSequenceConstraint *)sequenceConstraint
{
    return _sequenceConstraint;
}

/* Whether a value may be given to a feature with this description. This is the check the
 * specification's own fields are read for, and it is the check a model makes of what it is
 * handed, so the rules are the model's rules rather than this class's own:
 *
 *   - an undefined value is allowed exactly when the feature is optional, because a feature
 *     that is not optional is one the model cannot do without;
 *   - a defined value has to be of the type the feature names. Int64 and Double are separate
 *     types and a value of one is not a value of the other: a model that multiplies what it is
 *     given and a model that counts what it is given are told apart by this;
 *   - a multi array has to have the element type the feature names and a shape it will take:
 *     the one shape the feature fixes, or a shape inside the range it allows, or one of the
 *     shapes it enumerates. A feature that fixes no shape at all takes any, which is what a
 *     shape constraint of the unspecified kind means;
 *   - an image has to be of the size the feature fixes, inside the range it allows, or one of
 *     the sizes it enumerates;
 *   - a dictionary's keys have to be of the key type its constraint names;
 *   - a sequence has to have as many elements as its count range allows.
 */
- (BOOL)isAllowedValue:(MLFeatureValue *)value
{
    if (value == nil) {
        return NO;
    }
    if (value.isUndefined) {
        return _optional;
    }
    if (value.type != _type) {
        return NO;
    }
    switch (_type) {
    case MLFeatureTypeMultiArray: {
        MLMultiArray *array = value.multiArrayValue;
        if (array == nil || _multiArrayConstraint == nil) {
            return NO;
        }
        if (_multiArrayConstraint.dataType != (MLMultiArrayDataType)0 &&
            array.dataType != _multiArrayConstraint.dataType) {
            return NO;
        }
        return charon_ml_shape_allowed(_multiArrayConstraint.shapeConstraint, array.shape);
    }
    case MLFeatureTypeImage:
        return _imageConstraint != nil &&
               charon_ml_image_size_allowed(_imageConstraint.sizeConstraint, _imageConstraint.pixelsHigh,
                                            _imageConstraint.pixelsWide, value.imageBufferValue);
    case MLFeatureTypeDictionary:
        return _dictionaryConstraint != nil && _dictionaryConstraint.keyType == MLFeatureTypeString;
    case MLFeatureTypeSequence: {
        MLSequence *sequence = value.sequenceValue;
        NSRange allowed = _sequenceConstraint.countRange;
        NSUInteger count;
        if (sequence == nil) {
            return NO;
        }
        count = (NSUInteger)sequence.count;
        if (count < allowed.location ||
            (allowed.length != 0 && count > allowed.location + allowed.length)) {
            return NO;
        }
        return YES;
    }
    default:
        return YES;
    }
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self != nil) {
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        _type = (MLFeatureType)[coder decodeIntegerForKey:@"type"];
        _optional = [coder decodeBoolForKey:@"optional"];
        _multiArrayConstraint = [coder decodeObjectOfClass:[MLMultiArrayConstraint class]
                                                forKey:@"multiArrayConstraint"];
        _imageConstraint = [coder decodeObjectOfClass:[MLImageConstraint class] forKey:@"imageConstraint"];
        _dictionaryConstraint = [coder decodeObjectOfClass:[MLDictionaryConstraint class]
                                               forKey:@"dictionaryConstraint"];
        _sequenceConstraint = [coder decodeObjectOfClass:[MLSequenceConstraint class]
                                               forKey:@"sequenceConstraint"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_name forKey:@"name"];
    [coder encodeInteger:(NSInteger)_type forKey:@"type"];
    [coder encodeBool:_optional forKey:@"optional"];
    [coder encodeObject:_multiArrayConstraint forKey:@"multiArrayConstraint"];
    [coder encodeObject:_imageConstraint forKey:@"imageConstraint"];
    [coder encodeObject:_dictionaryConstraint forKey:@"dictionaryConstraint"];
    [coder encodeObject:_sequenceConstraint forKey:@"sequenceConstraint"];
}

/* A copy is a description of the same feature, and the constraints are copied with it rather
 * than shared: they are the same numbers, and one description's constraint changing under
 * another would be a change nobody asked for. */
- (id)copyWithZone:(NSZone *)zone
{
    MLFeatureDescription *copy = [[MLFeatureDescription allocWithZone:zone] init];
    if (copy == nil) {
        return nil;
    }
    copy->_name = [_name copy];
    copy->_type = _type;
    copy->_optional = _optional;
    if (_multiArrayConstraint != nil) {
        copy->_multiArrayConstraint = [[MLMultiArrayConstraint alloc]
            charon_initWithShape:_multiArrayConstraint.shape
                 dataType:_multiArrayConstraint.dataType
           shapeConstraint:[_multiArrayConstraint.shapeConstraint copy]];
    }
    if (_imageConstraint != nil) {
        copy->_imageConstraint = [[MLImageConstraint alloc]
            charon_initWithPixelsHigh:_imageConstraint.pixelsHigh
                    pixelsWide:_imageConstraint.pixelsWide
              pixelFormatType:_imageConstraint.pixelFormatType
                sizeConstraint:[_imageConstraint.sizeConstraint copy]];
    }
    if (_dictionaryConstraint != nil) {
        copy->_dictionaryConstraint =
            [[MLDictionaryConstraint alloc] charon_initWithKeyType:_dictionaryConstraint.keyType];
    }
    if (_sequenceConstraint != nil) {
        copy->_sequenceConstraint = [[MLSequenceConstraint alloc]
            charon_initWithValueDescription:[_sequenceConstraint.valueDescription copy]
                          countRange:_sequenceConstraint.countRange];
    }
    return copy;
}

- (BOOL)isEqual:(id)object
{
    MLFeatureDescription *other = [object isKindOfClass:[MLFeatureDescription class]] ? object : nil;
    return other != nil && other->_type == _type && other->_optional == _optional &&
           (other->_name == _name || [other->_name isEqualToString:_name]);
}

- (NSUInteger)hash
{
    return [_name hash] ^ (NSUInteger)_type;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MLFeatureDescription %@ %s%@>", _name,
                                      charon_ml_feature_type_name_of(_type),
                                      _optional ? @" optional" : @""];
}

@end
