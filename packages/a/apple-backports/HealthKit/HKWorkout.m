// HKWorkout and HKWorkoutEvent: an exercise, and what happened during it.

#import <HealthKit/HealthKit.h>

#import "CharonHKStore.h"

@implementation HKWorkoutEvent {
    HKWorkoutEventType _type;
    NSDate *_date;
}

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
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

+ (instancetype)workoutWithActivityType:(HKWorkoutActivityType)activityType
                              startDate:(NSDate *)startDate
                                endDate:(NSDate *)endDate
{
    HKWorkout *workout = [[HKWorkout alloc] charon_initWithType:[HKObjectType workoutType]
                                                       metadata:nil
                                                      startDate:startDate
                                                        endDate:endDate];
    if (workout)
        workout->_workoutActivityType = activityType;
    return workout;
}

+ (instancetype)workoutWithActivityType:(HKWorkoutActivityType)activityType
                              startDate:(NSDate *)startDate
                                endDate:(NSDate *)endDate
                               duration:(NSTimeInterval)duration
                        totalEnergyBurned:(nullable HKQuantity *)totalEnergyBurned
                          totalDistance:(nullable HKQuantity *)totalDistance
{
    return [self workoutWithActivityType:activityType
                               startDate:startDate
                                 endDate:endDate
                            workoutEvents:@[]
                         totalEnergyBurned:totalEnergyBurned
                           totalDistance:totalDistance
                                metadata:nil];
}

// The form with a metadata dictionary. A workout made with a duration ends at the start plus that
// duration, which is what the header says the duration is; the form that takes both dates and that the
// form above takes a duration both keep the dates they are given.
+ (instancetype)workoutWithActivityType:(HKWorkoutActivityType)activityType
                              startDate:(NSDate *)startDate
                                endDate:(NSDate *)endDate
                               duration:(NSTimeInterval)duration
                        totalEnergyBurned:(nullable HKQuantity *)totalEnergyBurned
                          totalDistance:(nullable HKQuantity *)totalDistance
                               metadata:(nullable NSDictionary *)metadata
{
    return [self workoutWithActivityType:activityType
                               startDate:startDate
                                 endDate:[startDate dateByAddingTimeInterval:duration]
                            workoutEvents:@[]
                         totalEnergyBurned:totalEnergyBurned
                           totalDistance:totalDistance
                                metadata:metadata];
}

+ (instancetype)workoutWithActivityType:(HKWorkoutActivityType)activityType
                              startDate:(NSDate *)startDate
                                endDate:(NSDate *)endDate
                         workoutEvents:(NSArray<HKWorkoutEvent *> *)workoutEvents
                    totalEnergyBurned:(nullable HKQuantity *)totalEnergyBurned
                      totalDistance:(nullable HKQuantity *)totalDistance
                             metadata:(nullable NSDictionary *)metadata
{
    HKWorkout *made = [[HKWorkout alloc] charon_initWithType:[HKObjectType workoutType]
                                                    metadata:metadata
                                                   startDate:startDate
                                                     endDate:endDate];
    if (!made)
        return nil;
    made->_workoutActivityType = activityType;
    made->_workoutEvents = [workoutEvents copy] ?: @[];
    made->_totalEnergyBurned = (HKQuantity *)[totalEnergyBurned copy];
    made->_totalDistance = (HKQuantity *)[totalDistance copy];
    return made;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _workoutActivityType = (HKWorkoutActivityType)[coder decodeIntegerForKey:@"workoutActivityType"];
        _totalEnergyBurned = [[coder decodeObjectOfClass:[HKQuantity class] forKey:@"totalEnergyBurned"] copy];
        _totalDistance = [[coder decodeObjectOfClass:[HKQuantity class] forKey:@"totalDistance"] copy];
        _workoutEvents = [[coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [HKWorkoutEvent class], nil]
                                               forKey:@"workoutEvents"] copy] ?: @[];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeInteger:(NSInteger)_workoutActivityType forKey:@"workoutActivityType"];
    [coder encodeObject:_totalEnergyBurned forKey:@"totalEnergyBurned"];
    [coder encodeObject:_totalDistance forKey:@"totalDistance"];
    [coder encodeObject:_workoutEvents forKey:@"workoutEvents"];
}

- (instancetype)charon_copyForStore
{
    HKWorkout *copy = [super charon_copyForStore];
    if (copy) {
        copy->_workoutActivityType = _workoutActivityType;
        copy->_totalEnergyBurned = [_totalEnergyBurned copy];
        copy->_totalDistance = [_totalDistance copy];
        copy->_workoutEvents = [_workoutEvents copy];
    }
    return copy;
}

- (HKWorkoutActivityType)workoutActivityType
{
    return _workoutActivityType;
}

- (NSTimeInterval)duration
{
    return [self.endDate timeIntervalSinceDate:self.startDate];
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
