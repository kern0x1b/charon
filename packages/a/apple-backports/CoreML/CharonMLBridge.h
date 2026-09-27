/* Between Core ML's C model and its Objective-C surface.
 *
 * An MLFeatureValue holds a charon_ml_value and an MLFeatureDescription a charon_ml_feature:
 * the two are the same thing written twice, once for the C the interpreter works in and once
 * for the classes an application sees, and the conversions are here so neither the classes nor
 * the interpreter has to know about the other's shape.
 *
 * These are not the package's API. apple-backports compiles every .c file with hidden
 * visibility, so nothing declared here reaches a dylib's exports or a linked program's, and a
 * registry entry is never owed for one of them.
 */
#ifndef CHARON_ML_BRIDGE_H
#define CHARON_ML_BRIDGE_H

#include <Foundation/Foundation.h>

#include "CharonMLModel.h"
#include "CharonMLValue.h"

/* An NSError in the Core ML error domain, or NULL when `error` is NULL. The code is one of the
 * specification's own, and the message says what the port could not do. */
/* The same, for a model that will not load at all. */

/* An MLFeatureType from the C's own enumeration, and the C's from Core ML's. */
/* An MLMultiArrayDataType from the specification's own numbers, which are the C array types
 * with a width bit set on them, and back. */

/* An NSArray of NSNumber from a shape, and a shape from one. A shape is what the array says;
 * a dimension of no fixed length is the specification's own -1 and is carried through as it
 * is, because that is what a caller comparing shapes against a description has to see. */
/* The array behind an MLMultiArray, and its strides, so the Objective-C half can read and
 * write the elements through the C rather than through an index set per element. The array is
 * a window into the object's own buffer and is not owned here. */


/* An NSError in Core ML's own domain, for a code the specification names. The codes are the
 * enumeration's own numbers, so an application that switches on MLModelError sees the case it
 * would see on a release that has Core ML. */
/* The Core ML error domain's own codes, by the numbers the specification's error enumeration
 * gives them, so an application that switches on MLModelError sees the case it would see on a
 * release that has Core ML. */
#define CHARON_ML_ERROR_INVALID_MODEL 1
#define CHARON_ML_ERROR_INVALID_MODEL_FILE 2
#define CHARON_ML_ERROR_INVALID_MODEL_INPUT 4
#define CHARON_ML_ERROR_INVALID_PARAMETER 10
#define CHARON_ML_ERROR_PREDICTION_FAILED 14

/* Everything here is a static inline, and that is the point: a .c file of this package is
 * compiled as C and cannot import Core ML, and a .m file is not compiled with hidden
 * visibility and would put these in the dylib's exports, where the registry would owe an entry
 * for each. A header is the only place a conversion can live that is in every file that needs
 * it and in no export table at all. */

/* An NSError in Core ML's own domain, or NULL when `out` is NULL. */
static inline NSError *charon_ml_error(NSError **out, NSInteger code, NSString *message)
{
    if (out == NULL) {
        return nil;
    }
    *out = [NSError errorWithDomain:@"com.apple.CoreML"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message ?: @"the model could not be used"}];
    return *out;
}

static inline NSError *charon_ml_model_error(NSError **out, NSString *message)
{
    return charon_ml_error(out, CHARON_ML_ERROR_INVALID_MODEL, message);
}

/* The C's own feature kinds, and Core ML's, which are two enumerations of the same list. The
 * state type arrived in iOS 18 and the int8 element type in iOS 26, neither of which this
 * SDK's headers declare and neither of which anything here produces: the C carries both, and
 * the names for them are in facts/CoreML/CoreML.md as not yet carried. */
static inline MLFeatureType charon_ml_feature_type_of(NSInteger kind)
{
    switch (kind) {
    case CHARON_ML_FEATURE_INT64: return MLFeatureTypeInt64;
    case CHARON_ML_FEATURE_DOUBLE: return MLFeatureTypeDouble;
    case CHARON_ML_FEATURE_STRING: return MLFeatureTypeString;
    case CHARON_ML_FEATURE_IMAGE: return MLFeatureTypeImage;
    case CHARON_ML_FEATURE_MULTI_ARRAY: return MLFeatureTypeMultiArray;
    case CHARON_ML_FEATURE_DICTIONARY: return MLFeatureTypeDictionary;
    case CHARON_ML_FEATURE_SEQUENCE: return MLFeatureTypeSequence;
    default: return MLFeatureTypeInvalid;
    }
}

static inline charon_ml_feature_type charon_ml_feature_kind(MLFeatureType type)
{
    switch (type) {
    case MLFeatureTypeInt64: return CHARON_ML_FEATURE_INT64;
    case MLFeatureTypeDouble: return CHARON_ML_FEATURE_DOUBLE;
    case MLFeatureTypeString: return CHARON_ML_FEATURE_STRING;
    case MLFeatureTypeImage: return CHARON_ML_FEATURE_IMAGE;
    case MLFeatureTypeMultiArray: return CHARON_ML_FEATURE_MULTI_ARRAY;
    case MLFeatureTypeDictionary: return CHARON_ML_FEATURE_DICTIONARY;
    case MLFeatureTypeSequence: return CHARON_ML_FEATURE_SEQUENCE;
    default: return CHARON_ML_FEATURE_NONE;
    }
}

/* The array element types. The specification writes each as a width in the low bits and a
 * class in the high ones, so the C's own type and Core ML's are two spellings of one number;
 * they are mapped rather than added to, because a caller may name either. */
static inline MLMultiArrayDataType charon_ml_array_type(int type)
{
    switch (type) {
    case CHARON_ML_ARRAY_FLOAT32: return MLMultiArrayDataTypeFloat32;
    case CHARON_ML_ARRAY_DOUBLE: return MLMultiArrayDataTypeDouble;
    case CHARON_ML_ARRAY_INT32: return MLMultiArrayDataTypeInt32;
    case CHARON_ML_ARRAY_FLOAT16: return MLMultiArrayDataTypeFloat16;
    default: return MLMultiArrayDataTypeDouble;
    }
}

static inline int charon_ml_type_of_array(MLMultiArrayDataType type)
{
    switch (type) {
    case MLMultiArrayDataTypeFloat32: return CHARON_ML_ARRAY_FLOAT32;
    case MLMultiArrayDataTypeDouble: return CHARON_ML_ARRAY_DOUBLE;
    case MLMultiArrayDataTypeInt32: return CHARON_ML_ARRAY_INT32;
    case MLMultiArrayDataTypeFloat16: return CHARON_ML_ARRAY_FLOAT16;
    default: return CHARON_ML_ARRAY_INVALID;
    }
}

/* A shape as the array of numbers Core ML uses, and back. A dimension of no fixed length is
 * the specification's own -1 and is carried through as it is, because a caller comparing a
 * shape against a description has to see that rather than a zero. */
static inline NSArray<NSNumber *> *charon_ml_shape_to_array(const int64_t *shape, int rank)
{
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:(NSUInteger)rank];
    int index;
    for (index = 0; index < rank; index++) {
        [out addObject:@(shape[index])];
    }
    return out;
}

static inline int charon_ml_shape_from_array(NSArray<NSNumber *> *shape, int64_t *out, int room, int *rank)
{
    NSUInteger index, total = shape.count;
    if (total > (NSUInteger)room) {
        return 0;
    }
    for (index = 0; index < total; index++) {
        out[index] = [shape[index] longLongValue];
    }
    *rank = (int)total;
    return 1;
}

/* The one method of MLMultiArray that is not the specification's: an MLFeatureValue's array
 * becomes an MLMultiArray over the same buffer through it, so the two name one array and a
 * write through either is a write to both. It is a window and owns no buffer. */
@interface MLMultiArray (CharonWindow)
- (instancetype)initWithWindowOf:(charon_ml_array)array;
- (charon_ml_array *)charonArray;
@end

#endif /* CHARON_ML_BRIDGE_H */
