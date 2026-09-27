/* The two Core ML protocols, and the two classes an application hands a model through.
 *
 * A protocol is not only a declaration: a class that conforms to one names a protocol object at
 * run time, and that object has to exist somewhere for `conformsToProtocol:` and
 * `objc_getProtocol` to answer. On a release that has Core ML, Core ML's own dylib carries it.
 * This release has no Core ML at all -- the classes are this port's own -- so the port carries
 * the protocols too, and that is why they are declared here rather than taken from Core ML's
 * header: a protocol the compiler has already seen declared is a *reference* to whatever
 * defines it, and a second declaration beside the first is ignored. Declared first, before
 * Core ML's header is imported, they are definitions, and the ones every other file of this
 * package refers to are these.
 *
 * The two declarations are Core ML's own, from its published headers: MLFeatureProvider is a set
 * of feature names and a lookup by name, MLBatchProvider is a count and a lookup by index.
 * Nothing else may be added to either, because an application that conforms to a protocol this
 * port carries has to be able to implement exactly the methods Core ML declares and no more.
 *
 * Then the classes: a prediction is made from a provider -- something that answers a value for a
 * name -- and the dictionary provider is the ordinary one, an NSDictionary of names to values,
 * which is what almost every caller already has. The batch provider is the same thing for a set
 * of inputs at once, and it is a provider of providers, so a model asked for a batch of
 * predictions is asked for one prediction per element of an array. Both are thin on purpose:
 * they hold what they were given and answer it by name or by index, and the work of deciding
 * whether a value is allowed is the feature description's, which is where the model's own rules
 * are.
 */
#import <Foundation/Foundation.h>

@class MLFeatureValue;

@protocol MLFeatureProvider <NSObject>
@property (readonly, nonatomic) NSSet<NSString *> *featureNames;
- (nullable MLFeatureValue *)featureValueForName:(NSString *)featureName;
@end

@protocol MLBatchProvider <NSObject>
@property (readonly, nonatomic) NSInteger count;
- (id<MLFeatureProvider>)featuresAtIndex:(NSInteger)index;
@end

/* Core ML's own headers declare the same two protocols, and the import below is where they are
 * seen a second time. The compiler ignores the second declaration and says so; the first is the
 * one that reaches the library, and this is the only warning silenced here, for that reason. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wduplicate-protocol"
#import <CoreML/CoreML.h>
#pragma clang diagnostic pop

#include "CharonMLBridge.h"
#include "CharonMLInternal.h"

@implementation MLDictionaryFeatureProvider {
    NSDictionary<NSString *, MLFeatureValue *> *_dictionary;
}

/* One value out of a caller's dictionary, as the value of a feature. What can be converted is
 * what Core ML documents: a value that already is one, a number, a string, a multi array, a
 * dictionary of numbers, and a sequence. Anything else cannot be represented as a feature value
 * -- there is no kind of feature value it would be -- so it is refused rather than turned into
 * a string of its description, which is what an application that printed it would have got and
 * what a model would then fail to read with no explanation. */
static MLFeatureValue *charon_ml_value_of_object(id object, NSError **error)
{
    if ([object isKindOfClass:[MLFeatureValue class]]) {
        return object;
    }
    if ([object isKindOfClass:[NSNumber class]]) {
        return [MLFeatureValue featureValueWithDouble:[object doubleValue]];
    }
    if ([object isKindOfClass:[NSString class]]) {
        return [MLFeatureValue featureValueWithString:object];
    }
    if ([object isKindOfClass:[MLMultiArray class]]) {
        return [MLFeatureValue featureValueWithMultiArray:object];
    }
    if ([object isKindOfClass:[MLSequence class]]) {
        return [MLFeatureValue featureValueWithSequence:object];
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        return [MLFeatureValue featureValueWithDictionary:object error:error];
    }
    charon_ml_error(error, CHARON_ML_ERROR_FEATURE_TYPE,
                    @"a feature value cannot be made out of an object of that class");
    return nil;
}

- (instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary error:(NSError **)error
{
    NSMutableDictionary<NSString *, MLFeatureValue *> *converted;
    NSEnumerator *names;
    id name;
    self = [super init];
    if (self == nil) {
        return nil;
    }
    if (dictionary == nil) {
        charon_ml_error(error, CHARON_ML_ERROR_FEATURE_TYPE,
                        @"a feature provider is made from a dictionary, and there was none");
        return nil;
    }
    converted = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];
    names = [dictionary keyEnumerator];
    while ((name = [names nextObject]) != nil) {
        MLFeatureValue *value = charon_ml_value_of_object([dictionary objectForKey:name], error);
        if (value == nil) {
            /* The name is in the message, because a caller with fifty features and one that will
             * not convert needs to know which one, and "a value could not be made" does not. */
            if (error != NULL && *error != nil) {
                NSString *reason = [*error localizedDescription];
                charon_ml_error(error, [*error code],
                                [NSString stringWithFormat:@"the value of '%@' is not one: %@", name, reason]);
            }
            return nil;
        }
        converted[name] = value;
    }
    _dictionary = converted;
    return self;
}

- (NSDictionary<NSString *, MLFeatureValue *> *)dictionary
{
    return _dictionary;
}

- (NSSet<NSString *> *)featureNames
{
    return [NSSet setWithArray:[_dictionary allKeys]];
}

- (MLFeatureValue *)featureValueForName:(NSString *)featureName
{
    return featureName != nil ? _dictionary[featureName] : nil;
}

- (MLFeatureValue *)objectForKeyedSubscript:(NSString *)featureName
{
    return [self featureValueForName:featureName];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MLDictionaryFeatureProvider %@>", [_dictionary.allKeys
                                                                          componentsJoinedByString:@", "]];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self != nil) {
        _dictionary = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSDictionary class],
                                                                          [NSString class],
                                                                          [MLFeatureValue class], nil]
                                           forKey:@"dictionary"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_dictionary forKey:@"dictionary"];
}

/* Fast enumeration walks the names, in the dictionary's own order, which is the order the values
 * were given in. A caller iterating a provider wants the names -- it asks for each value by the
 * name it is given -- and an unordered set would make the walk of a provider whose order is
 * meaningful come out in an order that is not the model's. */
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])buffer
                                    count:(NSUInteger)length
{
    return [_dictionary.allKeys countByEnumeratingWithState:state objects:buffer count:length];
}

@end

@implementation MLArrayBatchProvider {
    NSArray<id<MLFeatureProvider>> *_array;
}

- (instancetype)initWithFeatureProviderArray:(NSArray<id<MLFeatureProvider>> *)array
{
    self = [super init];
    if (self != nil) {
        _array = array != nil ? [array copy] : @[];
    }
    return self;
}

/* A dictionary of names to arrays is the other shape a batch arrives in: one array per feature,
 * each of the same length, which is the form a caller has when its inputs came out of a table
 * or a file of columns. The providers are then built by index across the arrays, so element
 * zero of every array is the first input and the names stay the names. The arrays have to be of
 * one length, because a batch of inputs that is not a rectangle is not a batch, and a caller
 * that is refused here is told which name is short rather than being answered a prediction for
 * an input that was never complete. */
- (instancetype)initWithDictionary:(NSDictionary<NSString *, NSArray *> *)dictionary error:(NSError **)error
{
    NSMutableArray<id<MLFeatureProvider>> *providers;
    NSUInteger count = 0, index;
    NSEnumerator *names;
    id name;
    self = [super init];
    if (self == nil) {
        return nil;
    }
    if (dictionary == nil) {
        charon_ml_error(error, CHARON_ML_ERROR_FEATURE_TYPE,
                        @"a batch provider is made from a dictionary, and there was none");
        return nil;
    }
    for (name in dictionary) {
        if (![dictionary[name] isKindOfClass:[NSArray class]]) {
            charon_ml_error(error, CHARON_ML_ERROR_FEATURE_TYPE,
                            [NSString stringWithFormat:@"the values of '%@' are not an array", name]);
            return nil;
        }
        if (count == 0) {
            count = [dictionary[name] count];
        } else if ([dictionary[name] count] != count) {
            charon_ml_error(error, CHARON_ML_ERROR_FEATURE_TYPE,
                            [NSString stringWithFormat:@"the values of '%@' are %lu of %lu, and every "
                                                       @"feature of a batch has to be of one length",
                                                       name, (unsigned long)[dictionary[name] count],
                                                       (unsigned long)count]);
            return nil;
        }
    }
    providers = [NSMutableArray arrayWithCapacity:count];
    for (index = 0; index < count; index++) {
        NSMutableDictionary *one = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];
        names = [dictionary keyEnumerator];
        while ((name = [names nextObject]) != nil) {
            one[name] = [dictionary[name] objectAtIndex:index];
        }
        {
            MLDictionaryFeatureProvider *provider =
                [[MLDictionaryFeatureProvider alloc] initWithDictionary:one error:error];
            if (provider == nil) {
                return nil;
            }
            [providers addObject:provider];
        }
    }
    _array = providers;
    return self;
}

- (NSArray<id<MLFeatureProvider>> *)array
{
    return _array;
}

- (NSInteger)count
{
    return (NSInteger)_array.count;
}

- (id<MLFeatureProvider>)featuresAtIndex:(NSInteger)index
{
    /* Out of range is nil rather than a crash or an exception: the protocol says a provider at
     * an index, and a caller walking a count it just read is not making a mistake the framework
     * should stop the program over. */
    if (index < 0 || (NSUInteger)index >= _array.count) {
        return nil;
    }
    return _array[(NSUInteger)index];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MLArrayBatchProvider %lu providers>", (unsigned long)_array.count];
}

@end
