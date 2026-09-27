#import "CharonMetricValue.h"
#import "CharonMetricKit.h"
#import <objc/runtime.h>

// The two roots implement the methods their own headers declare, so a category carrying them says
// "category is implementing a method which will also be implemented by its primary class" for each of
// the five; that is what a backport of a class nobody defined here looks like.
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// The property list, the two representations and the archiver. This is the whole of the machinery the
// 37 classes of this framework share; each of them is then its own list of properties and nothing else.

// The conversion below is recursive over arrays and dictionaries, so it is declared before the first
// use of it as well as defined before the first one.
// What a property's value becomes in the dictionary. Four cases, and each is the only one that keeps the
// value true:
//
//   - a MetricKit value (a metric, a payload, a histogram, a distribution) is its own dictionary, so the
//     JSON is a tree of the same shape the object graph is and nothing is flattened into a string;
//   - an NSMeasurement carries a double in a unit, and the double is the value: the unit is named by the
//     property's own declared type, which the header keeps, so a reader knows which unit a number is in
//     without the number having to repeat it;
//   - an NSDate is a point in time, and the number a JSON can carry is its time interval since the
//     reference date, which is exact and reversible;
//   - and an NSURL is its absolute string, because that is what identifies it to anything that reads it.
//
// Anything else is already a JSON type: a string, a number, an array, a dictionary. A nil property is left
// out of the dictionary entirely rather than written as null, so a reader can tell "not measured" from
// "measured as nothing".
static id CharonConvertedValue(id value)
{
    if (!value || value == [NSNull null])
        return nil;
    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]])
        return value;
    if ([value isKindOfClass:[NSDate class]])
        return @([(NSDate *)value timeIntervalSinceReferenceDate]);
    if ([value isKindOfClass:[NSURL class]])
        return [(NSURL *)value absoluteString];
    if ([value isKindOfClass:[NSMeasurement class]])
        return @([(NSMeasurement *)value doubleValue]);
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *converted = [NSMutableArray array];
        for (id element in (NSArray *)value) {
            id one = CharonConvertedValue(element);
            [converted addObject:one ?: [NSNull null]];
        }
        return converted;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *converted = [NSMutableDictionary dictionary];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id element, BOOL *stop) {
            id one = CharonConvertedValue(element);
            if (one)
                converted[[key description]] = one;
        }];
        return converted;
    }
    // Anything else that is a MetricKit value represents itself the way its own class does, which is
    // the contract MXMetric's and MXDiagnostic's own methods make.
    if ([[value class] isSubclassOfClass:[MXMetric class]] || [[value class] isSubclassOfClass:[MXDiagnostic class]])
        return [CharonMetricValue dictionaryOf:value];
    return [value description];
}

@implementation CharonMetricValue

// The property names, innermost class first. The walk stops at NSObject, whose own properties (none in
// this framework, and none an application reads off a metric) are not the metric's.
+ (NSArray<NSString *> *)propertyNamesOf:(Class)cls
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (Class current = cls; current && current != [NSObject class]; current = class_getSuperclass(current)) {
        unsigned int count = 0;
        objc_property_t *properties = class_copyPropertyList(current, &count);
        for (unsigned int index = 0; index < count; index++)
            [names addObject:[NSString stringWithUTF8String:property_getName(properties[index])]];
        free(properties);
    }
    return names;
}

+ (NSDictionary *)dictionaryOf:(id)value
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (NSString *name in [self propertyNamesOf:[value class]]) {
        id converted = CharonConvertedValue([value valueForKey:name]);
        if (converted)
            dictionary[name] = converted;
    }
    return dictionary;
}

+ (NSData *)jsonOf:(id)value
{
    // The JSON is the dictionary, serialised: there is no second, private shape to match, so anything
    // that can read this JSON can read -dictionaryRepresentation and find the same content.
    NSDictionary *dictionary = [self dictionaryOf:value];
    if (![NSJSONSerialization isValidJSONObject:dictionary])
        return [NSJSONSerialization dataWithJSONObject:@{} options:0 error:NULL];
    return [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:NULL];
}

// The classes a decoded value may be. Every class this library carries is found through the runtime by
// the framework's own prefix, so the set cannot fall behind the classes that are built, and the
// Foundation value types those hold are named here because they are the port's own and not MetricKit's.
+ (NSSet<Class> *)decodableClasses
{
    static NSSet<Class> *classes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet *found = [NSMutableSet set];
        int count = objc_getClassList(NULL, 0);
        if (count > 0) {
            Class *list = (Class *)malloc(sizeof(Class) * (size_t)count);
            count = objc_getClassList(list, count);
            for (int index = 0; index < count; index++) {
                NSString *name = NSStringFromClass(list[index]);
                if ([name hasPrefix:@"MX"])
                    [found addObject:list[index]];
            }
            free(list);
        }
        for (NSString *name in @[@"NSString", @"NSDate", @"NSNumber", @"NSData", @"NSURL", @"NSArray",
                                 @"NSDictionary", @"NSMeasurement", @"NSDimension", @"NSNull"])
            if (NSClassFromString(name))
                [found addObject:NSClassFromString(name)];
        classes = found;
    });
    return classes;
}

@end

// The store itself, one pair of functions for every root: the dictionary is created on first use, so an
// object the port only reads costs nothing, and it is keyed by the property's own name - the same names
// the walk returns - so a value is found by name from either side.

static NSMutableDictionary *CharonValuesOf(id owner)
{
    static const char key;
    NSMutableDictionary *values = objc_getAssociatedObject(owner, &key);
    if (!values) {
        values = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(owner, &key, values, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return values;
}

static void CharonSetValueOf(id owner, id value, NSString *key)
{
    if (!key)
        return;
    if (value)
        CharonValuesOf(owner)[key] = value;
    else
        [CharonValuesOf(owner) removeObjectForKey:key];
}

#define CHARON_VALUE_STORE_IMPLEMENTATION                                          \
    -(NSMutableDictionary *)charon_values { return CharonValuesOf(self); }          \
    -(id)charon_valueForKey:(NSString *)key { return [self charon_values][key]; }    \
    -(void)charon_setValue:(id)value forKey:(NSString *)key { CharonSetValueOf(self, value, key); }


@implementation MXMetric (CharonMetricValueCoding)

- (void)charon_encodePropertiesWithCoder:(NSCoder *)coder
{
    for (NSString *name in [CharonMetricValue propertyNamesOf:[self class]]) {
        id value = [self charon_valueForKey:name];
        if (value)
            [coder encodeObject:value forKey:name];
    }
}

- (BOOL)charon_decodePropertiesWithCoder:(NSCoder *)coder
{
    NSSet *allowed = [CharonMetricValue decodableClasses];
    BOOL whole = YES;
    for (NSString *name in [CharonMetricValue propertyNamesOf:[self class]]) {
        if (![coder containsValueForKey:name])
            continue;
        // The set of classes is what stops an archive from naming a class this process does not have;
        // a class it does not have decodes as nil rather than as an instance of something else.
        id value = [coder decodeObjectOfClasses:allowed forKey:name];
        if (value)
            [self charon_setValue:value forKey:name];
        else
            whole = NO;
    }
    return whole;
}

@end


// MXAverage, MXHistogram and MXHistogramBucket are NSObject subclasses in Apple's own hierarchy, not
// MXMetric's or MXDiagnostic's, and they carry values the same way, so each holds the same store, answers
// the same property list, and archives through the same three methods. One block each, from one template,
// because they differ only in whether the header gives them a representation of their own.


// MXAverage, MXHistogram and MXHistogramBucket are NSObject subclasses in Apple's own hierarchy, not
// MXMetric's or MXDiagnostic's, and they carry values the same way, so each holds the same store, answers
// the same property list, and archives through the same three methods. One block each, from one template,
// because they differ only in whether the header gives them a representation of their own.


// MXAverage, MXHistogram and MXHistogramBucket are NSObject subclasses in Apple's own hierarchy, not
// MXMetric's or MXDiagnostic's, and they carry values the same way, so each holds the same store, answers
// the same property list, and archives through the same three methods. One block each, from one template,
// because they differ only in whether the header gives them a representation of their own.







@implementation MXSignpostRecord (CharonMetricValueNSSecureCoding)
- (void)charon_encodePropertiesWithCoder:(NSCoder *)coder
{
    for (NSString *name in [CharonMetricValue propertyNamesOf:[self class]]) {
        id value = [self charon_valueForKey:name];
        if (value)
            [coder encodeObject:value forKey:name];
    }
}
- (BOOL)charon_decodePropertiesWithCoder:(NSCoder *)coder
{
    NSSet *allowed = [CharonMetricValue decodableClasses];
    BOOL whole = YES;
    for (NSString *name in [CharonMetricValue propertyNamesOf:[self class]]) {
        if (![coder containsValueForKey:name])
            continue;
        id value = [coder decodeObjectOfClasses:allowed forKey:name];
        if (value)
            [self charon_setValue:value forKey:name];
        else
            whole = NO;
    }
    return whole;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end










@implementation MXCrashDiagnosticObjectiveCExceptionReason (CharonMetricValueNSSecureCoding)
- (void)charon_encodePropertiesWithCoder:(NSCoder *)coder
{
    for (NSString *name in [CharonMetricValue propertyNamesOf:[self class]]) {
        id value = [self charon_valueForKey:name];
        if (value)
            [coder encodeObject:value forKey:name];
    }
}
- (BOOL)charon_decodePropertiesWithCoder:(NSCoder *)coder
{
    NSSet *allowed = [CharonMetricValue decodableClasses];
    BOOL whole = YES;
    for (NSString *name in [CharonMetricValue propertyNamesOf:[self class]]) {
        if (![coder containsValueForKey:name])
            continue;
        id value = [coder decodeObjectOfClasses:allowed forKey:name];
        if (value)
            [self charon_setValue:value forKey:name];
        else
            whole = NO;
    }
    return whole;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

// The four standalone value classes - MXBackgroundExitData, MXForegroundExitData, MXCallStackTree and
// MXSignpostIntervalData - are NSObject subclasses in Apple's own hierarchy and carry values the same
// way, so each gets the same store, the same property list, the same archiving and the two
// representations its own header gives it: one block, from the same template, four times.

// The sixteen NSObject roots of this framework, one category each, from one table. What a class gets is
// what its own header declares: the store everywhere, the archiving where it conforms to NSSecureCoding,
// and the two representations where the header gives it those two methods as well. MXMetric and
// MXDiagnostic are in the list because their leaf classes inherit the store from them.
@implementation MXMetric (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
- (NSData *)JSONRepresentation { return [CharonMetricValue jsonOf:self]; }
- (NSDictionary *)DictionaryRepresentation { return [CharonMetricValue dictionaryOf:self]; }
- (NSDictionary *)dictionaryRepresentation { return [CharonMetricValue dictionaryOf:self]; }
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXDiagnostic (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
- (NSData *)JSONRepresentation { return [CharonMetricValue jsonOf:self]; }
- (NSDictionary *)dictionaryRepresentation { return [CharonMetricValue dictionaryOf:self]; }
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXAverage (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
- (NSData *)JSONRepresentation { return [CharonMetricValue jsonOf:self]; }
- (NSDictionary *)dictionaryRepresentation { return [CharonMetricValue dictionaryOf:self]; }
CHARON_VALUE_CODING_METHODS
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXHistogram (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
CHARON_VALUE_CODING_METHODS
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXHistogramBucket (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
CHARON_VALUE_CODING_METHODS
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXMetaData (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
CHARON_VALUE_CODING_METHODS
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXMetricPayload (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
CHARON_VALUE_CODING_METHODS
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXDiagnosticPayload (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
CHARON_VALUE_CODING_METHODS
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXCrashDiagnosticObjectiveCExceptionReason (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
CHARON_VALUE_CODING_METHODS
@end

@implementation MXSignpostRecord (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
CHARON_VALUE_CODING_METHODS
@end

@implementation MXSignpostIntervalData (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
- (NSData *)JSONRepresentation { return [CharonMetricValue jsonOf:self]; }
- (NSDictionary *)dictionaryRepresentation { return [CharonMetricValue dictionaryOf:self]; }
CHARON_VALUE_CODING_METHODS
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXBackgroundExitData (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
- (NSData *)JSONRepresentation { return [CharonMetricValue jsonOf:self]; }
- (NSDictionary *)dictionaryRepresentation { return [CharonMetricValue dictionaryOf:self]; }
CHARON_VALUE_CODING_METHODS
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXForegroundExitData (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
- (NSData *)JSONRepresentation { return [CharonMetricValue jsonOf:self]; }
- (NSDictionary *)dictionaryRepresentation { return [CharonMetricValue dictionaryOf:self]; }
CHARON_VALUE_CODING_METHODS
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXCallStackTree (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
- (NSData *)JSONRepresentation { return [CharonMetricValue jsonOf:self]; }
- (NSDictionary *)dictionaryRepresentation { return [CharonMetricValue dictionaryOf:self]; }
CHARON_VALUE_CODING_METHODS
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [self charon_encodePropertiesWithCoder:coder]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        [self charon_decodePropertiesWithCoder:coder];
    return self;
}
@end

@implementation MXUnitAveragePixelLuminance (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
@end

@implementation MXUnitSignalBars (CharonMetricValue)
CHARON_VALUE_STORE_IMPLEMENTATION
@end

