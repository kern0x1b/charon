// HKWorkout and HKWorkoutEvent: an exercise, and what happened during it.

#import <HealthKit/HealthKit.h>

#import "CharonHKStore.h"

@interface HKWorkoutEvent (CharonIOS100Internal)
- (instancetype)charon_initWithType:(HKWorkoutEventType)type date:(NSDate *)date;
@end

@implementation HKWorkoutEvent {
    HKWorkoutEventType _type;
    NSDate *_date;
    NSDictionary *_charonMetadata;
    NSDateInterval *_charonDateInterval;
}
// -dateInterval of 11.0 and -metadata of 10.0 are of the releases after 8.0, which this delivery does
// not carry, so both are @dynamic and no accessor is emitted for either.
@dynamic dateInterval;
@dynamic metadata;


+ (BOOL)supportsSecureCoding
{
    return YES;
}

+ (instancetype)workoutEventWithType:(HKWorkoutEventType)type date:(NSDate *)date
{
    HKWorkoutEvent *event = [[HKWorkoutEvent alloc] charon_initWithType:type date:date];
    return event;
}

- (instancetype)charon_initWithType:(HKWorkoutEventType)type date:(NSDate *)date
{
    HKWorkoutEvent *fresh = [super init];
    if (fresh) {
        fresh->_type = type;
        fresh->_date = [date copy];
    }
    return fresh;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _type = (HKWorkoutEventType)[coder decodeIntegerForKey:@"type"];
        _date = [[coder decodeObjectOfClass:[NSDate class] forKey:@"date"] copy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:(NSInteger)_type forKey:@"type"];
    [coder encodeObject:_date forKey:@"date"];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [HKWorkoutEvent workoutEventWithType:_type date:_date];
}

- (HKWorkoutEventType)type
{
    return _type;
}

- (NSDate *)date
{
    return _date;
}

// 10.0's metadata, kept under the port's own name and answered under the header's from
// HKDocumentQuery10.m, so that this file carries the API of 8.0 alone.
- (nullable NSDictionary *)charon_storedMetadata
{
    return _charonMetadata;
}

- (void)charon_setMetadata:(nullable NSDictionary *)metadata
{
    _charonMetadata = [metadata copy];
}

- (nullable NSDateInterval *)charon_storedDateInterval
{
    return _charonDateInterval;
}

- (void)charon_setDateInterval:(nullable NSDateInterval *)dateInterval
{
    _charonDateInterval = [dateInterval copy];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"HKWorkoutEvent %ld at %@", (long)_type, _date];
}

@end

#pragma mark - HKWorkout

@implementation HKWorkout {
    HKWorkoutActivityType _workoutActivityType;
    HKQuantity *_totalEnergyBurned;
    HKQuantity *_totalDistance;
    NSArray<HKWorkoutEvent *> *_workoutEvents;
    // The workout's own length, kept rather than worked out from the two dates. The header has a
    // factory that takes a duration and two that take the dates, and -duration is the number the
    // factory was given: a workout that is an hour long is an hour long, and the dates are where it
    // starts and ends. A workout made with both dates takes the difference of them, which is what
    // those two dates say; a workout made with a duration takes that duration, and ends at the start
    // plus it.
    NSTimeInterval _duration;
    HKQuantity *_charonStrokeCount;
    // 11.0's flights climbed, beside the one of 10.0
    HKQuantity *_charonFlightsClimbed;
}
// 10.0's -totalSwimmingStrokeCount, kept under the port's own name and answered under the header's
// from HKDocumentQuery10.m, so that this file carries the API of 8.0 alone.

// The members of the releases after 8.0 that this delivery does not carry: -totalSwimmingStrokeCount of
// 10.0, -totalFlightsClimbed of 11.0 and -allStatistics of 16.0. All three are @dynamic, so no
// accessor is emitted and the selector is not in the built library.
@dynamic totalSwimmingStrokeCount;
@dynamic totalFlightsClimbed;
@dynamic allStatistics;
@dynamic workoutActivities;


+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)charon_initWithType:(HKObjectType *)type
                           metadata:(nullable NSDictionary *)metadata
                          startDate:(NSDate *)startDate
                            endDate:(NSDate *)endDate
                           duration:(NSTimeInterval)duration
{
    HKWorkout *workout = [super charon_initWithType:(HKSampleType *)type
                                          metadata:metadata
                                         startDate:startDate
                                           endDate:endDate];
    if (workout)
        workout->_duration = duration;
    return workout;
}

+ (instancetype)workoutWithActivityType:(HKWorkoutActivityType)activityType
                              startDate:(NSDate *)startDate
                                endDate:(NSDate *)endDate
{
    HKWorkout *workout = [[HKWorkout alloc] charon_initWithType:[HKObjectType workoutType]
                                                       metadata:nil
                                                      startDate:startDate
                                                        endDate:endDate
                                                       duration:[endDate timeIntervalSinceDate:startDate]];
    if (workout)
        workout->_workoutActivityType = activityType;
    return workout;
}

// The release's own form: a duration, and the dates it gives. The end date is the start plus the
// duration, so that a caller that passes both a start and a length gets a workout of that length, and
// -duration answers the length and not the difference of two dates the port guessed.
+ (instancetype)workoutWithActivityType:(HKWorkoutActivityType)activityType
                              startDate:(NSDate *)startDate
                                endDate:(NSDate *)endDate
                               duration:(NSTimeInterval)duration
                        totalEnergyBurned:(nullable HKQuantity *)totalEnergyBurned
                          totalDistance:(nullable HKQuantity *)totalDistance
                               metadata:(nullable NSDictionary *)metadata
{
    HKWorkout *workout = [[HKWorkout alloc] charon_initWithType:[HKObjectType workoutType]
                                                       metadata:metadata
                                                      startDate:startDate
                                                        endDate:[startDate dateByAddingTimeInterval:duration]
                                                       duration:duration];
    if (workout) {
        workout->_workoutActivityType = activityType;
        workout->_totalEnergyBurned = (HKQuantity *)[totalEnergyBurned copy];
        workout->_totalDistance = (HKQuantity *)[totalDistance copy];
    }
    return workout;
}

+ (instancetype)workoutWithActivityType:(HKWorkoutActivityType)activityType
                              startDate:(NSDate *)startDate
                                endDate:(NSDate *)endDate
                         workoutEvents:(NSArray<HKWorkoutEvent *> *)workoutEvents
                    totalEnergyBurned:(nullable HKQuantity *)totalEnergyBurned
                      totalDistance:(nullable HKQuantity *)totalDistance
                             metadata:(nullable NSDictionary *)metadata
{
    HKWorkout *workout = [[HKWorkout alloc] charon_initWithType:[HKObjectType workoutType]
                                                       metadata:metadata
                                                      startDate:startDate
                                                        endDate:endDate
                                                       duration:[endDate timeIntervalSinceDate:startDate]];
    if (workout) {
        workout->_workoutActivityType = activityType;
        workout->_workoutEvents = [workoutEvents copy] ?: @[];
        workout->_totalEnergyBurned = (HKQuantity *)[totalEnergyBurned copy];
        workout->_totalDistance = (HKQuantity *)[totalDistance copy];
    }
    return workout;
}

- (HKWorkoutActivityType)workoutActivityType
{
    return _workoutActivityType;
}

// What the port's own files set, for the release's factory that takes a device: the activity type
// and the two totals are the release's own properties and the constructor above does not take them,
// so a factory outside this file sets them here rather than reaching for an ivar it cannot name.
- (void)charon_setWorkoutActivityType:(HKWorkoutActivityType)activityType
{
    _workoutActivityType = activityType;
}

- (void)charon_setWorkoutEvents:(NSArray<HKWorkoutEvent *> *)workoutEvents
{
    _workoutEvents = [workoutEvents copy] ?: @[];
}

- (nullable HKQuantity *)charon_totalSwimmingStrokeCount
{
    return _charonStrokeCount;
}

- (void)charon_setTotalSwimmingStrokeCount:(nullable HKQuantity *)count
{
    _charonStrokeCount = (HKQuantity *)[count copy];
}

- (nullable HKQuantity *)charon_storedTotalFlightsClimbed
{
    return _charonFlightsClimbed;
}

- (void)charon_setTotalFlightsClimbed:(nullable HKQuantity *)flights
{
    _charonFlightsClimbed = (HKQuantity *)[flights copy];
}

- (void)charon_setTotalEnergyBurned:(nullable HKQuantity *)energy totalDistance:(nullable HKQuantity *)distance
{
    _totalEnergyBurned = (HKQuantity *)[energy copy];
    _totalDistance = (HKQuantity *)[distance copy];
}

- (NSTimeInterval)duration
{
    return _duration;
}

- (nullable HKQuantity *)totalEnergyBurned
{
    return _totalEnergyBurned;
}

- (nullable HKQuantity *)totalDistance
{
    return _totalDistance;
}

- (NSArray<HKWorkoutEvent *> *)workoutEvents
{
    return _workoutEvents;
}

- (NSInteger)charon_storeKind
{
    return 3;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"HKWorkout %ld from %@ to %@", (long)_workoutActivityType, self.startDate, self.endDate];
}

@end
