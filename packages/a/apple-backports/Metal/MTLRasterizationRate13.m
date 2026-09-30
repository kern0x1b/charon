#import "CharonMetal.h"
#import "CharonMetalProtocols.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"
#pragma clang diagnostic ignored "-Wincomplete-implementation"
// The header marks -init API_UNAVAILABLE and -initWithSampleCount: the DESIGNATED initializer, so the
// port has to override -init to give a fresh layer its two sample arrays and cannot say so in an
// interface the SDK already owns. That is two initializer warnings by construction, so they are
// silenced HERE and named, the way MTLHeap10.m silences its own.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

// THE RASTERIZATION-RATE FAMILY, the part of it that is a plain data holder.
//
// A rasterization-rate MAP says how densely a render target is sampled: how many layers it has, and
// per layer a grid of sample rates. So the whole of it is numbers and two small containers, and none
// of it asks a device anything. THAT IS THE CASE FOR CARRYING IT, and it is why this unit needs no
// device: a caller building a map writes a layer count, a screen size and some sample rates, and
// reads the same numbers back.
//
// THE THREE CLASSES ARE MUTUALLY DEPENDENT and land together: the descriptor OWNS the layer array,
// and a layer descriptor OWNS the two sample arrays, so a map without them and a layer without its
// samples are not the family. MTLRasterizationRateMap - the object a device makes out of a map - is
// NOT here; it is a reader over device-made state and belongs with the device work.
//
// NO DEVICE IS CREATED anywhere in this file or its case, and MTLCreateSystemDefaultDevice() hangs
// on a machine with no GPU, so nothing calls it.

@interface MTLRasterizationRateSampleArray ()
{
    NSMutableArray *_samples;
}
@end

@interface MTLRasterizationRateLayerDescriptor ()
{
    MTLRasterizationRateSampleArray *_horizontal;
    MTLRasterizationRateSampleArray *_vertical;
    MTLSize _sampleCount;
    MTLSize _maxSampleCount;
    float *_horizontalSampleStorage;
    float *_verticalSampleStorage;
}
@end

@interface MTLRasterizationRateLayerArray ()
{
    NSMutableArray *_layers;
}
// The port's own: the header gives this class two indexed members and no count, and the map's
// readonly layerCount is DERIVED from the array, so the array needs a way to say how many it holds.
- (NSUInteger)count;
@end

@interface MTLRasterizationRateMapDescriptor ()
{
    MTLRasterizationRateLayerArray *_layers;
    MTLSize _screenSize;
}
@end

// THE SAMPLE ARRAY holds NSNumber, exactly as the header says, and grows to the index written so a
// read past the end is nil rather than a trap - which is NSArray's own behaviour and what the case
// compares against Apple's.
@implementation MTLRasterizationRateSampleArray

- (NSNumber *)objectAtIndexedSubscript:(NSUInteger)index
{
    return index < [_samples count] ? [_samples objectAtIndex:index] : nil;
}

- (void)setObject:(NSNumber *)value atIndexedSubscript:(NSUInteger)index
{
    while ([_samples count] <= index) { [_samples addObject:[NSNull null]]; }
    if (value == nil) {
        [_samples replaceObjectAtIndex:index withObject:[NSNull null]];
    } else {
        [_samples replaceObjectAtIndex:index withObject:(id)value];
    }
}

@end

@implementation MTLRasterizationRateLayerDescriptor

// The header makes -init API_UNAVAILABLE and -initWithSampleCount:horizontal:vertical: the
// designated initializer, so the port does the same: a layer is made with its sample count, and the
// two sample arrays exist from the start. A fresh one reads the enumeration's own zero for both
// counts, which is what the case compares against Apple's own fresh object.
- (instancetype)init
{
    if ((self = [super init])) {
        _horizontal = [[MTLRasterizationRateSampleArray alloc] init];
        _vertical = [[MTLRasterizationRateSampleArray alloc] init];
        _sampleCount = MTLSizeMake(0, 0, 0);
        _maxSampleCount = MTLSizeMake(0, 0, 0);
    }
    return self;
}

- (instancetype)initWithSampleCount:(MTLSize)sampleCount
{
    if ((self = [self init])) {
        _sampleCount = sampleCount;
    }
    return self;
}

@synthesize sampleCount = _sampleCount;
@synthesize maxSampleCount = _maxSampleCount;
@synthesize horizontal = _horizontal;
@synthesize vertical = _vertical;
@synthesize horizontalSampleStorage = _horizontalSampleStorage;
@synthesize verticalSampleStorage = _verticalSampleStorage;

@end

@implementation MTLRasterizationRateLayerArray

- (NSUInteger)count
{
    return [_layers count];
}

- (MTLRasterizationRateLayerDescriptor *)objectAtIndexedSubscript:(NSUInteger)index
{
    if (index >= [_layers count]) { return nil; }
    id v = [_layers objectAtIndex:index];
    return v == [NSNull null] ? nil : v;
}

- (void)setObject:(MTLRasterizationRateLayerDescriptor *)layer atIndexedSubscript:(NSUInteger)index
{
    while ([_layers count] <= index) { [_layers addObject:[NSNull null]]; }
    [_layers replaceObjectAtIndex:index withObject:(layer ? (id)layer : (id)[NSNull null])];
}

@end

@implementation MTLRasterizationRateMapDescriptor

// The header makes -init API_UNAVAILABLE and the class carries a layer array from the start, so a
// fresh map already HAS one - and that is the thing the case checks, because Apple's own fresh
// descriptor answers a non-nil -layers too.
- (instancetype)init
{
    if ((self = [super init])) {
        _layers = [[MTLRasterizationRateLayerArray alloc] init];
        _screenSize = MTLSizeMake(0, 0, 0);
    }
    return self;
}

@synthesize layers = _layers;
@synthesize screenSize = _screenSize;

// THE LAYER COUNT IS DERIVED, not stored twice: the header declares it readonly and a count that can
// disagree with the array holding the layers is a bug waiting to happen. The array is the truth.
- (NSUInteger)layerCount
{
    return [_layers count];
}

- (MTLRasterizationRateLayerDescriptor *)layerAtIndex:(NSUInteger)layerIndex
{
    return [_layers objectAtIndexedSubscript:layerIndex];
}

- (void)setLayer:(MTLRasterizationRateLayerDescriptor *)layer atIndex:(NSUInteger)layerIndex
{
    [_layers setObject:layer atIndexedSubscript:layerIndex];
}

@end
