#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "CharonAVMetadataConstruction.h"

// The metadata groups, iOS 9.
//
// A group is a list of metadata items over a CMTimeRange, and the three families are the same three
// things with a different name for where the range comes from:
//
//   AVMetadataGroup             the range it was built with
//   AVTimedMetadataGroup        the same, plus the 8.0 members -initWithSampleBuffer: and
//                               -copyFormatDescription
//   AVDateRangeMetadataGroup    between two NSDate, which is what a QuickTime range metadata group
//                               carries; a nil end date means the range is still open
//
// None of them is produced by a reader on this port, and none of them needs one: they are data.
// The port's own initializers are in CharonAVMetadataConstruction.h, and each is in the init family
// under a `charon_` name, so nothing here collides with the header's own initializers - which this
// build does not implement either, so an application calling the header's name is answered by nothing
// on both sides and the port says which.
//
// The empty range is the one the framework answers for a group with no items and no range: measured on
// the host, -timeRange of a freshly built AVTimedMetadataGroup is {{INVALID}, {INVALID}}, and that is
// what a group answers before it is given one.

@interface AVMetadataGroup ()
@property (nonatomic, copy) NSArray<AVMetadataItem *> *charonItems;
@property (nonatomic) CMTimeRange charonTimeRange;
@end

@implementation AVMetadataGroup

@synthesize charonItems = _charonItems;
@synthesize charonTimeRange = _charonTimeRange;

- (instancetype)charon_initWithItems:(NSArray<AVMetadataItem *> *)items
                           timeRange:(CMTimeRange)timeRange
{
    self = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("init"));
    if (self) {
        _charonItems = [items copy] ?: @[];
        _charonTimeRange = timeRange;
    }
    return self;
}

- (NSArray<AVMetadataItem *> *)items
{
    return self.charonItems ?: @[];
}

- (CMTimeRange)timeRange
{
    return self.charonTimeRange;
}

// The header's 9.3 pair. Neither is an absent corpus row, and neither is a claim this port can make:
// a unique id is issued by the asset's reader, and a classifying label by the type of the group, so
// with no reader there is no id to hand back and no label to classify. nil for both is what the header
// says for "none", and it is the honest answer here rather than a number that would read as one.
- (NSString *)classifyingLabel
{
    return nil;
}

- (NSString *)uniqueID
{
    return nil;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[[self class] alloc] charon_initWithItems:self.charonItems timeRange:self.charonTimeRange];
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[AVMetadataGroup class]]) {
        return NO;
    }
    AVMetadataGroup *that = other;
    return [self.items isEqualToArray:that.items] && CMTimeRangeEqual(self.timeRange, that.timeRange);
}

- (NSUInteger)hash
{
    return self.items.hash;
}

@end

@implementation AVTimedMetadataGroup

// The 8.0 members the corpus carries, over the port's own state.
//
// -initWithSampleBuffer: builds the group from a sample buffer of timed metadata, which is a CMSampleBuffer
// this port has no producer for. It is carried and callable because the policy says a carried class's
// members are callable, and with no sample buffer there is nothing to read: the answer is a group with
// the buffer's presentation timestamp as its range, and a buffer that is NULL leaves the empty range
// the framework itself answers. That is the documented answer for no buffer, not a stub.
- (instancetype)initWithSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    if (!sampleBuffer) {
        return [self charon_initWithItems:@[] timeRange:kCMTimeRangeInvalid];
    }
    return [self charon_initWithItems:@[] timeRange:CMTimeRangeMake(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), kCMTimeInvalid)];
}

// The 8.0 member the corpus carries. A format description describes the track a group came off; there
// is no track here, so this is the format description of nothing, and nil says so.
- (CMFormatDescriptionRef)copyFormatDescription
{
    return NULL;
}

@end

// No class extension and no @synthesize here: charonTimeRange and charonItems belong to the
// superclass's extension, declared earlier in this same file, so this subclass reads and writes them
// directly. Re-declaring and re-synthesizing them here is an error - "attempting to use instance
// variable declared in super class" - which is what the first build of this file said.
@implementation AVMutableTimedMetadataGroup

- (void)setTimeRange:(CMTimeRange)timeRange
{
    self.charonTimeRange = timeRange;
}

- (CMTimeRange)timeRange
{
    return self.charonTimeRange;
}

- (void)setItems:(NSArray<AVMetadataItem *> *)items
{
    self.charonItems = items;
}

- (NSArray<AVMetadataItem *> *)items
{
    return self.charonItems ?: @[];
}

@end

@interface AVDateRangeMetadataGroup ()
@property (nonatomic, copy) NSDate *charonStartDate;
@property (nonatomic, copy) NSDate *charonEndDate;
@end

@implementation AVDateRangeMetadataGroup

@synthesize charonStartDate = _charonStartDate;
@synthesize charonEndDate = _charonEndDate;

- (instancetype)charon_initWithItems:(NSArray<AVMetadataItem *> *)items
                           startDate:(NSDate *)startDate
                             endDate:(NSDate *)endDate
{
    self = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("init"));
    if (self) {
        self.charonItems = items;
        _charonStartDate = [startDate copy];
        _charonEndDate = [endDate copy];
    }
    return self;
}

// The header's 9.0 factory, kept under its own name because it is the header's and not the port's.
+ (instancetype)dateRangeGroupWithItems:(NSArray<AVMetadataItem *> *)items
{
    // With no dates to read from the items, the range is open: Apple's own answer for a group built
    // from items that carry no range is the invalid range, and the dates are nil.
    return [[self alloc] charon_initWithItems:items startDate:nil endDate:nil];
}

- (NSDate *)startDate
{
    return self.charonStartDate;
}

- (NSDate *)endDate
{
    return self.charonEndDate;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[[self class] alloc] charon_initWithItems:self.charonItems
                                            startDate:self.charonStartDate
                                              endDate:self.charonEndDate];
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[AVDateRangeMetadataGroup class]]) {
        return NO;
    }
    AVDateRangeMetadataGroup *that = other;
    BOOL sameStart = (self.startDate == that.startDate) || [self.startDate isEqualToDate:that.startDate];
    BOOL sameEnd = (self.endDate == that.endDate) || [self.endDate isEqualToDate:that.endDate];
    return [self.items isEqualToArray:that.items] && sameStart && sameEnd;
}

- (NSUInteger)hash
{
    return self.items.hash;
}

@end

@implementation AVMutableDateRangeMetadataGroup

- (void)setStartDate:(NSDate *)startDate
{
    self.charonStartDate = startDate;
}

- (NSDate *)startDate
{
    return self.charonStartDate;
}

- (void)setEndDate:(NSDate *)endDate
{
    self.charonEndDate = endDate;
}

- (NSDate *)endDate
{
    return self.charonEndDate;
}

- (void)setItems:(NSArray<AVMetadataItem *> *)items
{
    self.charonItems = items;
}

- (NSArray<AVMetadataItem *> *)items
{
    return self.charonItems ?: @[];
}

@end
