#import "CharonMetricValue.h"
#import "CharonMetricKit.h"
#import <objc/runtime.h>

// The two roots implement the methods their own headers declare, so a category carrying them says
// "category is implementing a method which will also be implemented by its primary class" for each of
// the five; that is what a backport of a class nobody defined here looks like.
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// Everything this file used to carry - the property walk, the conversion table, the dictionary and
// the JSON, the decodable-class set, the archiver walk and the store - is the shared machinery in
// CharonValueStore.h now, so that a second framework whose classes are value objects includes the
// same implementation instead of a copy. What is left here is MetricKit's own shape: the sixteen
// roots, the two roots a leaf metric inherits from, and the private snapshot.

// MetricKit's own root for a nested value, and the two classes its representation methods walk from.
@implementation CharonMetricValue

+ (NSArray<NSString *> *)propertyNamesOf:(Class)cls
{
    return CharonValuePropertyNames(cls);
}

+ (NSDictionary *)dictionaryOf:(id)value
{
    return CharonValueConvertProperties(value, [MXMetric class], [MXDiagnostic class]);
}

+ (NSData *)jsonOf:(id)value
{
    return CharonValueJSON(value, [MXMetric class], [MXDiagnostic class]);
}

+ (NSSet<Class> *)decodableClasses
{
    return CharonValueDecodableClasses(@"MX");
}

@end

static NSSet<Class> *charon_decodable(void)
{
    return CharonValueDecodableClasses(@"MX");
}

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
// Its own header gives it the two representations.
- (NSData *)JSONRepresentation { return [CharonMetricValue jsonOf:self]; }
- (NSDictionary *)dictionaryRepresentation { return [CharonMetricValue dictionaryOf:self]; }
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
// Its own header gives it the two representations.
- (NSData *)JSONRepresentation { return [CharonMetricValue jsonOf:self]; }
- (NSDictionary *)dictionaryRepresentation { return [CharonMetricValue dictionaryOf:self]; }
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
