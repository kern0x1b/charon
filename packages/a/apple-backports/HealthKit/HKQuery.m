// HKQuery: what every query of this framework is asked, and the predicates one builds to ask it.
//
// The predicates are the release's own: a real NSPredicate over a real key path, which the store
// then hands to the release's own NSPredicate to decide over the objects it read back. Every key
// path here is one of the HKPredicateKeyPath constants, whose values were read out of iOS 8.0's own
// image, and every one of them is a path a sample of this framework answers: UUID, startDate,
// endDate, source, metadata, value, quantity and - through the correlation a sample belongs to -
// correlation.source, correlation.UUID, correlation.metadata and correlation.workout.

#import <HealthKit/HealthKit.h>

#import "CharonHKStore.h"

// The four operators of HKComparisonOperator as NSPredicate spells them. An operator the header does
// not name raises, as the release raises for a comparison it cannot make.
static NSString *CharonHKOperatorSpelling(NSPredicateOperatorType type)
{
    switch (type) {
    case NSEqualToPredicateOperatorType:
        return @"==";
    case NSNotEqualToPredicateOperatorType:
        return @"!=";
    case NSLessThanPredicateOperatorType:
        return @"<";
    case NSLessThanOrEqualToPredicateOperatorType:
        return @"<=";
    case NSGreaterThanPredicateOperatorType:
        return @">";
    case NSGreaterThanOrEqualToPredicateOperatorType:
        return @">=";
    default:
        [NSException raise:NSInvalidArgumentException format:@"%ld is not a comparison operator.", (long)type];
        return @"==";
    }
}

@implementation HKQuery {
    HKObjectType *_objectType;
    NSPredicate *_predicate;
    dispatch_queue_t _charonQueue;
    BOOL _charonExecuted;
}

+ (BOOL)supportsSecureCoding
{
    return NO;
}

- (instancetype)init
{
    return [super init];
}

// The type of the samples a query is for. It is not always one: an activity summary query's type is
// not a sample type, which is what iOS 9.3 deprecated this name for and gave -objectType instead, and
// the release answers nil here for such a query.
- (nullable HKSampleType *)sampleType
{
    return [_objectType isKindOfClass:[HKSampleType class]] ? (HKSampleType *)_objectType : nil;
}

- (NSPredicate *)predicate
{
    return _predicate;
}

- (void)charon_setPredicate:(nullable NSPredicate *)predicate
{
    _predicate = [predicate copy];
}

- (instancetype)initWithSampleType:(nullable HKSampleType *)sampleType
{
    return [self initWithObjectType:sampleType];
}

- (instancetype)initWithObjectType:(nullable HKObjectType *)objectType
{
    HKQuery *fresh = [super init];
    if (fresh)
        fresh->_objectType = (HKObjectType *)[objectType copy];
    return fresh;
}

// Where a query's handlers are called. The release delivers them on the queue the caller chose with
// the private -setClientQueue:, and on the main queue where it chose none; the header says a handler
// is called on an arbitrary background queue, so the main queue is what this port uses, being the one
// queue a caller can rely on being the one it drew its own handlers in.
- (void)charon_perform:(dispatch_block_t)block
{
    dispatch_async(_charonQueue ?: dispatch_get_main_queue(), block);
}

- (void)charon_setQueue:(dispatch_queue_t)queue
{
    _charonQueue = queue;
}

- (void)charon_setHasBeenExecuted:(BOOL)executed
{
    _charonExecuted = executed;
}

- (BOOL)charon_hasBeenExecuted
{
    return _charonExecuted;
}

// Where a query's handlers are called. The release delivers them on a queue the caller chose with the
// private -setClientQueue:, and on the main queue where it chose none; the header says a handler is
// called on an arbitrary background queue, so the main queue is what this port uses, as it is the one
// queue a caller can rely on being the one it drew its own handlers in.
- (nullable NSPredicate *)charon_predicate
{
    return _predicate;
}

- (nullable HKObjectType *)charon_objectType
{
    return _objectType;
}

#pragma mark - The predicates of the header

+ (NSPredicate *)predicateForObjectWithUUID:(NSUUID *)uuid
{
    if (!uuid)
        return nil;
    return [NSPredicate predicateWithFormat:@"%K == %@", HKPredicateKeyPathUUID, uuid];
}

+ (NSPredicate *)predicateForObjectsWithUUIDs:(NSSet<NSUUID *> *)uuids
{
    return [NSPredicate predicateWithFormat:@"%K IN %@", HKPredicateKeyPathUUID, uuids];
}

+ (NSPredicate *)predicateForObjectsFromSource:(HKSource *)source
{
    if (!source)
        return nil;
    return [NSPredicate predicateWithFormat:@"%K == %@", HKPredicateKeyPathSource, source];
}

+ (NSPredicate *)predicateForObjectsFromSources:(NSSet<HKSource *> *)sources
{
    return [NSPredicate predicateWithFormat:@"%K IN %@", HKPredicateKeyPathSource, sources];
}

+ (NSPredicate *)predicateForObjectsWithMetadataKey:(NSString *)key
{
    if (!key)
        return nil;
    return [NSPredicate predicateWithFormat:@"%K.%K != nil", HKPredicateKeyPathMetadata, key];
}

+ (NSPredicate *)predicateForObjectsWithMetadataKey:(NSString *)key allowedValues:(NSSet *)allowedValues
{
    if (!key)
        return nil;
    return [NSPredicate predicateWithFormat:@"%K.%K IN %@", HKPredicateKeyPathMetadata, key, allowedValues];
}

+ (NSPredicate *)predicateForObjectsWithMetadataKey:(NSString *)key operatorType:(NSPredicateOperatorType)type value:(id)value
{
    if (!key)
        return nil;
    return [NSPredicate predicateWithFormat:@"%K.%K %@ %@", HKPredicateKeyPathMetadata, key,
                                         CharonHKOperatorSpelling(type), value];
}

+ (NSPredicate *)predicateForObjectsWithNoCorrelation
{
    return [NSPredicate predicateWithFormat:@"%K == nil", HKPredicateKeyPathCorrelation];
}

+ (NSPredicate *)predicateForObjectsFromWorkout:(HKWorkout *)workout
{
    if (!workout)
        return nil;
    return [NSPredicate predicateWithFormat:@"%K == %@", HKPredicateKeyPathWorkout, workout];
}

+ (NSPredicate *)predicateForQuantitySamplesWithOperatorType:(NSPredicateOperatorType)type quantity:(HKQuantity *)quantity
{
    if (!quantity)
        return nil;
    return [NSPredicate predicateWithFormat:@"%K %@ %@", HKPredicateKeyPathQuantity,
                                         CharonHKOperatorSpelling(type), quantity];
}

+ (NSPredicate *)predicateForCategorySamplesWithOperatorType:(NSPredicateOperatorType)type value:(NSInteger)value
{
    return [NSPredicate predicateWithFormat:@"%K %@ %d", HKPredicateKeyPathCategoryValue,
                                         CharonHKOperatorSpelling(type), (int)value];
}

+ (NSPredicate *)predicateForCategorySamplesEqualToValues:(NSSet<NSNumber *> *)values
{
    return [NSPredicate predicateWithFormat:@"%K IN %@", HKPredicateKeyPathCategoryValue, values];
}

+ (NSPredicate *)predicateForStatesOfMindWithValence:(double)valence operatorType:(NSPredicateOperatorType)type
{
    return [NSPredicate predicateWithFormat:@"valence %@ %f", CharonHKOperatorSpelling(type), valence];
}

+ (NSPredicate *)predicateForStatesOfMindWithKind:(NSInteger)kind
{
    return [NSPredicate predicateWithFormat:@"kind == %ld", (long)kind];
}

+ (NSPredicate *)predicateForStatesOfMindWithLabel:(NSString *)label
{
    return [NSPredicate predicateWithFormat:@"label == %@", label];
}

+ (NSPredicate *)predicateForSamplesWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate options:(HKQueryOptions)options
{
    if (!startDate && !endDate)
        return nil;
    NSMutableArray *parts = [NSMutableArray array];
    if (startDate)
        [parts addObject:[NSPredicate predicateWithFormat:@"%K >= %@", HKPredicateKeyPathStartDate, startDate]];
    if (endDate)
        [parts addObject:[NSPredicate predicateWithFormat:@"%K <= %@", HKPredicateKeyPathEndDate, endDate]];
    if (options & HKQueryOptionStrictStartDate)
        [parts addObject:[NSPredicate predicateWithFormat:@"%K < %@", HKPredicateKeyPathEndDate, endDate]];
    if (options & HKQueryOptionStrictEndDate)
        [parts addObject:[NSPredicate predicateWithFormat:@"%K > %@", HKPredicateKeyPathStartDate, startDate]];
    if (!parts.count)
        return nil;
    return parts.count == 1 ? parts[0] : [NSCompoundPredicate andPredicateWithSubpredicates:parts];
}

+ (NSPredicate *)predicateForWorkoutsWithWorkoutActivityType:(HKWorkoutActivityType)type
{
    return [NSPredicate predicateWithFormat:@"%K == %d", HKPredicateKeyPathWorkoutType, (int)type];
}

+ (NSPredicate *)predicateForWorkoutsWithOperatorType:(NSPredicateOperatorType)type duration:(NSTimeInterval)duration
{
    return [NSPredicate predicateWithFormat:@"%K %@ %f", HKPredicateKeyPathWorkoutDuration,
                                         CharonHKOperatorSpelling(type), duration];
}

+ (NSPredicate *)predicateForWorkoutsWithOperatorType:(NSPredicateOperatorType)type totalDistance:(HKQuantity *)distance
{
    if (!distance)
        return nil;
    return [NSPredicate predicateWithFormat:@"%K %@ %@", HKPredicateKeyPathWorkoutTotalDistance,
                                         CharonHKOperatorSpelling(type), distance];
}

+ (NSPredicate *)predicateForWorkoutsWithOperatorType:(NSPredicateOperatorType)type totalEnergyBurned:(HKQuantity *)energy
{
    if (!energy)
        return nil;
    return [NSPredicate predicateWithFormat:@"%K %@ %@", HKPredicateKeyPathWorkoutTotalEnergyBurned,
                                         CharonHKOperatorSpelling(type), energy];
}

// The base class has no store of its own to run against: a query is a request, and only a subclass
// knows what to ask the store for. HKHealthStore refuses a query of the base class as the release
// refuses to execute one it has no results for.
- (void)charon_run
{
    [NSException raise:NSInvalidArgumentException
                format:@"An %@ is a request and not a query: execute one of its subclasses.", NSStringFromClass(self.class)];
}

- (void)charon_stop
{
}

@end
