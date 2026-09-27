/* MLFeatureValue: one value of one feature, over the C value the interpreter passes about.
 *
 * The value the interpreter produces is a charon_ml_value and this holds it: a number, a
 * string, an array, a dictionary or an image. What the accessors do is answer in the form
 * Core ML documents -- a number, a string, an MLMultiArray, a dictionary -- and what a caller
 * asks for a value does not hold is nil, because that is what the documentation says and an
 * application is written to test for it.
 */
#import <CoreML/CoreML.h>

#include "CharonMLBridge.h"
#include "CharonMLTensor.h"
#include "CharonMLValue.h"

/* The value, and the type it is. An undefined value has a type and no contents: that is what
 * `undefinedFeatureValueWithType:` builds, and an optional input the caller left out is
 * answered as one. */
@interface MLFeatureValue () {
@public
    charon_ml_value _value;
    MLFeatureType _type;
    MLMultiArray *_multiArray; /* the MLMultiArray over _value, built once and kept */
    MLSequence *_sequence;     /* the sequence over _value, built once and kept */
    CVPixelBufferRef _pixelBuffer;
}
- (charon_ml_value *)charonValue;
@end

@implementation MLFeatureValue

- (charon_ml_value *)charonValue
{
    return &_value;
}

- (void)dealloc
{
    if (_pixelBuffer != NULL) {
        CVPixelBufferRelease(_pixelBuffer);
        _pixelBuffer = NULL;
    }
    charon_ml_value_free(&_value);
}

#pragma mark - the constructors

/* One constructor for each of the specification's own cases, all of them the same thing: a
 * value of a kind holding one thing. */
+ (instancetype)valueOfKind:(charon_ml_value_kind)kind
{
    MLFeatureValue *value = [[MLFeatureValue alloc] init];
    if (value == nil) {
        return nil;
    }
    value->_type = charon_ml_feature_type_of(kind);
    value->_value.kind = kind;
    return value;
}

+ (instancetype)featureValueWithInt64:(int64_t)number
{
    MLFeatureValue *value = [self valueOfKind:CHARON_ML_VALUE_NUMBER];
    if (value != nil) {
        value->_value = charon_ml_value_number((double)number);
    }
    return value;
}

+ (instancetype)featureValueWithDouble:(double)number
{
    MLFeatureValue *value = [self valueOfKind:CHARON_ML_VALUE_NUMBER];
    if (value != nil) {
        value->_value = charon_ml_value_number(number);
    }
    return value;
}

+ (instancetype)featureValueWithString:(NSString *)string
{
    MLFeatureValue *value = [self valueOfKind:CHARON_ML_VALUE_STRING];
    if (value != nil) {
        /* The bytes are the value's own: a string an application holds after the prediction
         * has gone has to still be there, and a view of a buffer that did not is not. */
        value->_value = charon_ml_value_string_copy(string.UTF8String, strlen(string.UTF8String));
    }
    return value;
}

+ (instancetype)featureValueWithMultiArray:(MLMultiArray *)array
{
    MLFeatureValue *value;
    charon_ml_array *backing;
    if (array == nil) {
        return nil;
    }
    value = [self valueOfKind:CHARON_ML_VALUE_ARRAY];
    if (value == nil) {
        return nil;
    }
    /* The value is a window on the array's own buffer, not a copy of it: an application that
     * writes through the multi array it handed over must see the change in the model. */
    backing = [array charonArray];
    value->_value = charon_ml_value_array(*backing);
    value->_value.array.owns_data = 0;
    value->_multiArray = array;
    return value;
}

+ (instancetype)featureValueWithPixelBuffer:(CVPixelBufferRef)buffer
{
    MLFeatureValue *value;
    void *bytes;
    OSType format;
    int data_type;
    if (buffer == NULL) {
        return nil;
    }
    if (CVPixelBufferLockBaseAddress(buffer, 0) != kCVReturnSuccess) {
        return nil;
    }
    format = CVPixelBufferGetPixelFormatType(buffer);
    switch (format) {
    case kCVPixelFormatType_32BGRA:
    case kCVPixelFormatType_32ARGB:
        data_type = CHARON_ML_ARRAY_FLOAT32;
        break;
    default:
        /* A format this port does not unpack. The image is answered as an undefined value of
         * the image type rather than as a buffer of bytes that are not an image. */
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        return [self undefinedFeatureValueWithType:MLFeatureTypeImage];
    }
    bytes = CVPixelBufferGetBaseAddress(buffer);
    if (bytes == NULL) {
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        return [self undefinedFeatureValueWithType:MLFeatureTypeImage];
    }
    value = [self valueOfKind:CHARON_ML_VALUE_IMAGE];
    if (value == nil) {
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        return nil;
    }
    value->_pixelBuffer = (CVPixelBufferRef)CVPixelBufferRetain(buffer);
    value->_value.kind = CHARON_ML_VALUE_IMAGE;
    value->_value.array = charon_ml_array_make(data_type, NULL, 0, bytes);
    return value;
}

+ (instancetype)featureValueWithDictionary:(NSDictionary<id, NSNumber *> *)dictionary
                                     error:(NSError **)error
{
    MLFeatureValue *value;
    __block BOOL ok = YES;
    if (dictionary == nil) {
        charon_ml_error(error, CHARON_ML_ERROR_INVALID_PARAMETER, @"a dictionary feature value needs a dictionary");
        return nil;
    }
    value = [self valueOfKind:CHARON_ML_VALUE_DICTIONARY];
    if (value == nil) {
        return nil;
    }
    value->_value = charon_ml_value_dictionary();
    /* Every key has to be a string and every value a number: a dictionary whose keys are
     * anything else cannot be looked up by name, and one whose values are not numbers has no
     * score behind it. Both are refused rather than half-built. */
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, NSNumber *number, __unused BOOL *stop) {
        if (![key isKindOfClass:[NSString class]] || ![number isKindOfClass:[NSNumber class]]) {
            ok = NO;
            return;
        }
        if (!charon_ml_dictionary_put(&value->_value, [key UTF8String], number.doubleValue)) {
            ok = NO;
        }
    }];
    if (!ok) {
        charon_ml_value_free(&value->_value);
        charon_ml_error(error, CHARON_ML_ERROR_INVALID_PARAMETER,
                        @"a dictionary feature value takes string keys and number values");
        return nil;
    }
    return value;
}

+ (instancetype)featureValueWithSequence:(MLSequence *)sequence
{
    MLFeatureValue *value;
    if (sequence == nil) {
        return nil;
    }
    value = [self valueOfKind:CHARON_ML_VALUE_SEQUENCE];
    if (value == nil) {
        return nil;
    }
    /* The sequence is held, not flattened: it is an ordered list of numbers or of strings with
     * no shape of its own, and the value keeps it as it was given. */
    value->_value.kind = CHARON_ML_VALUE_SEQUENCE;
    value->_type = sequence.type;
    value->_sequence = sequence;
    return value;
}

+ (instancetype)undefinedFeatureValueWithType:(MLFeatureType)type
{
    MLFeatureValue *value = [self valueOfKind:CHARON_ML_VALUE_NONE];
    if (value != nil) {
        value->_type = type;
    }
    return value;
}

#pragma mark - reading the value

- (MLFeatureType)type
{
    return _type;
}

- (BOOL)isUndefined
{
    return _value.kind == CHARON_ML_VALUE_NONE;
}

/* The numeric forms. A value that is not a number answers zero, which is what a number read
 * out of a value of another kind is on a release that has Core ML: the accessor's contract is
 * to answer a number, and `type` is what says which kind it really is. */
- (int64_t)int64Value
{
    if (_value.kind == CHARON_ML_VALUE_NUMBER) {
        return (int64_t)_value.number;
    }
    if (_value.kind == CHARON_ML_VALUE_ARRAY && _value.array.count > 0) {
        return (int64_t)charon_ml_array_get(&_value.array, 0);
    }
    return 0;
}

- (double)doubleValue
{
    if (_value.kind == CHARON_ML_VALUE_NUMBER) {
        return _value.number;
    }
    if (_value.kind == CHARON_ML_VALUE_ARRAY && _value.array.count > 0) {
        return charon_ml_array_get(&_value.array, 0);
    }
    return 0.0;
}

- (NSString *)stringValue
{
    if (_value.kind != CHARON_ML_VALUE_STRING) {
        return @"";
    }
    return [[NSString alloc] initWithBytes:_value.string.bytes
                                    length:_value.string.length
                                  encoding:NSUTF8StringEncoding];
}

- (MLMultiArray *)multiArrayValue
{
    if (_value.kind != CHARON_ML_VALUE_ARRAY) {
        return nil;
    }
    if (_multiArray == nil) {
        /* An array that arrived as a value becomes an MLMultiArray over the same buffer, so
         * an application that reads it and an application that wrote it see one array. */
        _multiArray = [[MLMultiArray alloc] initWithWindowOf:_value.array];
    }
    return _multiArray;
}

- (NSDictionary<id, NSNumber *> *)dictionaryValue
{
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:_value.dictionary.count];
    size_t index;
    if (_value.kind != CHARON_ML_VALUE_DICTIONARY) {
        return out;
    }
    for (index = 0; index < _value.dictionary.count; index++) {
        out[@(_value.dictionary.keys[index])] = @(_value.dictionary.values[index]);
    }
    return out;
}

- (CVPixelBufferRef)imageBufferValue
{
    return _pixelBuffer;
}

- (MLSequence *)sequenceValue
{
    return _value.kind == CHARON_ML_VALUE_SEQUENCE ? _sequence : nil;
}

- (BOOL)isEqualToFeatureValue:(MLFeatureValue *)value
{
    if (value == nil || value->_type != _type || value->_value.kind != _value.kind) {
        return NO;
    }
    switch (_value.kind) {
    case CHARON_ML_VALUE_NUMBER:
        return value->_value.number == _value.number;
    case CHARON_ML_VALUE_STRING:
        return value->_value.string.length == _value.string.length &&
               memcmp(value->_value.string.bytes, _value.string.bytes, _value.string.length) == 0;
    case CHARON_ML_VALUE_ARRAY:
        return value->_value.array.count == _value.array.count &&
               value->_value.array.data_type == _value.array.data_type &&
               charon_ml_shape_equal(_value.array.shape, _value.array.rank,
                                      value->_value.array.shape, value->_value.array.rank) &&
               memcmp(value->_value.array.data, _value.array.data,
                      _value.array.count * charon_ml_type_size(_value.array.data_type)) == 0;
    case CHARON_ML_VALUE_DICTIONARY:
        if (value->_value.dictionary.count != _value.dictionary.count) {
            return NO;
        }
        {
            size_t index;
            for (index = 0; index < _value.dictionary.count; index++) {
                int found = 0;
                double number = 0.0;
                charon_ml_dictionary_get(&value->_value, _value.dictionary.keys[index], &number, &found);
                if (!found || number != _value.dictionary.values[index]) {
                    return NO;
                }
            }
        }
        return YES;
    default:
        return YES; /* two undefined values, or two images of the same type, are equal */
    }
}

#pragma mark - NSCopying and NSSecureCoding

- (id)copyWithZone:(NSZone *)zone
{
    MLFeatureValue *copy = [[MLFeatureValue allocWithZone:zone] init];
    if (copy == nil) {
        return nil;
    }
    copy->_type = _type;
    switch (_value.kind) {
    case CHARON_ML_VALUE_STRING:
        copy->_value = charon_ml_value_string_copy(_value.string.bytes, _value.string.length);
        break;
    case CHARON_ML_VALUE_ARRAY:
        /* A copy is its own buffer and its own values: a copy that shared the buffer would
         * change under the caller that made it. */
        copy->_value = charon_ml_value_array(
            charon_ml_array_alloc(_value.array.data_type, _value.array.shape, _value.array.rank));
        {
            size_t index;
            for (index = 0; index < _value.array.count && index < copy->_value.array.count; index++) {
                charon_ml_array_set(&copy->_value.array, (int64_t)index,
                                     charon_ml_array_get(&_value.array, (int64_t)index));
            }
        }
        break;
    case CHARON_ML_VALUE_DICTIONARY:
        copy->_value = charon_ml_value_dictionary();
        {
            size_t index;
            for (index = 0; index < _value.dictionary.count; index++) {
                charon_ml_dictionary_put(&copy->_value, _value.dictionary.keys[index],
                                          _value.dictionary.values[index]);
            }
        }
        break;
    default:
        copy->_value = _value;
        break;
    }
    return copy;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSNumber *type = [coder decodeObjectOfClass:[NSNumber class] forKey:@"type"];
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _type = (MLFeatureType)type.integerValue;
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:@(_type) forKey:@"type"];
    [coder encodeObject:self.stringValue forKey:@"string"];
    [coder encodeObject:self.multiArrayValue forKey:@"array"];
}

@end
