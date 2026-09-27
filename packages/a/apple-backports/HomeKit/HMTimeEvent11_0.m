// The time-based events of iOS 11.0, the events an event trigger fires on without an accessory being
// involved: HMTimeEvent and its subclasses, their mutable forms, and HMNumberRange, which is the
// threshold a characteristic event fires on. One release's API per object file: everything here
// arrived in iOS 11.0, whatever release a later member of one of them arrived in.
#import "CharonHomeKitInternal.h"

#pragma mark - HMNumberRange

@implementation HMNumberRange
@synthesize charon_minValue = _charon_minValue, charon_maxValue = _charon_maxValue;
// -init is NS_UNAVAILABLE in the release's own header, so the port makes the range the way the
// release makes it, through +numberRangeWithMinValue:maxValue:.
+ (instancetype)numberRangeWithMinValue:(NSNumber *)minValue maxValue:(NSNumber *)maxValue
{
    HMNumberRange *range = [super new];
    range.charon_minValue = minValue;
    range.charon_maxValue = maxValue;
    return range;
}

- (NSNumber *)minValue
{
    return [self.charon_minValue copy];
}

- (NSNumber *)maxValue
{
    return [self.charon_maxValue copy];
}

// The port's own: a range is a value object with no identifier, built from the two numbers.
HMNumberRange *CharonHomeKitNumberRange(NSNumber *minimum, NSNumber *maximum)
{
    return [HMNumberRange numberRangeWithMinValue:minimum maxValue:maximum];
}

@end

#pragma mark - HMTimeEvent

@implementation HMTimeEvent

- (instancetype)init
{
    self = [super init];
    return self;
}

@end

#pragma mark - HMDurationEvent


@implementation HMDurationEvent
@synthesize charon_duration = _charon_duration;
- (instancetype)init
{
    self = [super init];
    return self;
}

- (instancetype)initWithDuration:(NSTimeInterval)duration
{
    self = [super init];
    if (self)
        _charon_duration = @(duration);
    return self;
}

- (NSTimeInterval)duration
{
    return [_charon_duration doubleValue];
}

@end

@implementation HMMutableDurationEvent

- (instancetype)init
{
    self = [super init];
    return self;
}

- (void)setDuration:(NSTimeInterval)duration
{
    self.charon_duration = @(duration);
}

@end

#pragma mark - HMCalendarEvent


@implementation HMCalendarEvent
@synthesize charon_fireDateComponents = _charon_fireDateComponents;
- (instancetype)init
{
    self = [super init];
    return self;
}

- (instancetype)initWithFireDateComponents:(NSDateComponents *)fireDateComponents
{
    self = [super init];
    if (self)
        _charon_fireDateComponents = [fireDateComponents copy];
    return self;
}

- (NSDateComponents *)fireDateComponents
{
    return [_charon_fireDateComponents copy];
}

@end

@implementation HMMutableCalendarEvent

- (instancetype)init
{
    self = [super init];
    return self;
}

- (void)setFireDateComponents:(NSDateComponents *)fireDateComponents
{
    self.charon_fireDateComponents = fireDateComponents;
}

@end

#pragma mark - HMSignificantTimeEvent


@implementation HMSignificantTimeEvent
@synthesize charon_significantEvent = _charon_significantEvent, charon_offset = _charon_offset;
- (instancetype)init
{
    self = [super init];
    return self;
}

- (instancetype)initWithSignificantEvent:(HMSignificantEvent)significantEvent offset:(NSTimeInterval)offset
{
    self = [super init];
    if (self) {
        _charon_significantEvent = [significantEvent copy];
        _charon_offset = @(offset);
    }
    return self;
}

- (HMSignificantEvent)significantEvent
{
    return [self.charon_significantEvent copy];
}

- (NSTimeInterval)offset
{
    return [_charon_offset doubleValue];
}

@end

@implementation HMMutableSignificantTimeEvent

- (instancetype)init
{
    self = [super init];
    return self;
}

- (void)setSignificantEvent:(HMSignificantEvent)significantEvent
{
    self.charon_significantEvent = significantEvent;
}

- (void)setOffset:(NSTimeInterval)offset
{
    self.charon_offset = @(offset);
}

@end

#pragma mark - HMPresenceEvent


@implementation HMPresenceEvent
@synthesize charon_presenceEventType = _charon_presenceEventType, charon_presenceUserType = _charon_presenceUserType;
- (instancetype)initWithPresenceEventType:(HMPresenceEventType)presenceEventType
                          presenceUserType:(HMPresenceEventUserType)presenceUserType
{
    self = [super init];
    if (self) {
        _charon_presenceEventType = @(presenceEventType);
        _charon_presenceUserType = @(presenceUserType);
    }
    return self;
}

- (HMPresenceEventType)presenceEventType
{
    return (HMPresenceEventType)[self.charon_presenceEventType unsignedIntegerValue];
}

- (HMPresenceEventUserType)presenceUserType
{
    return (HMPresenceEventUserType)[self.charon_presenceUserType unsignedIntegerValue];
}

@end

@implementation HMMutablePresenceEvent

- (void)setPresenceEventType:(HMPresenceEventType)presenceEventType
{
    self.charon_presenceEventType = @(presenceEventType);
}

- (void)setPresenceUserType:(HMPresenceEventUserType)presenceUserType
{
    self.charon_presenceUserType = @(presenceUserType);
}

@end

#pragma mark - HMCharacteristicEvent's mutable form and the threshold event

@implementation HMMutableCharacteristicEvent

- (void)setCharacteristic:(HMCharacteristic *)characteristic
{
    self.charon_characteristic = characteristic;
}

- (void)setTriggerValue:(id)triggerValue
{
    self.charon_triggerValue = triggerValue;
}

@end


@implementation HMCharacteristicThresholdRangeEvent
@synthesize charon_thresholdRange = _charon_thresholdRange, charon_characteristic = _charon_characteristic;
- (instancetype)init
{
    self = [super init];
    return self;
}

- (instancetype)initWithCharacteristic:(HMCharacteristic *)characteristic thresholdRange:(HMNumberRange *)thresholdRange
{
    self = [super init];
    if (self) {
        self.charon_characteristic = characteristic;
        _charon_thresholdRange = thresholdRange;
    }
    return self;
}

- (HMCharacteristic *)characteristic
{
    return self.charon_characteristic;
}

- (HMNumberRange *)thresholdRange
{
    return self.charon_thresholdRange;
}

@end

@implementation HMMutableCharacteristicThresholdRangeEvent

- (instancetype)init
{
    self = [super init];
    return self;
}

- (void)setCharacteristic:(HMCharacteristic *)characteristic
{
    self.charon_characteristic = characteristic;
}

- (void)setThresholdRange:(HMNumberRange *)thresholdRange
{
    self.charon_thresholdRange = thresholdRange;
}

@end
