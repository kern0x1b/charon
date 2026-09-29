// The random number generators: MPSMatrixRandomDistributionDescriptor, MPSMatrixRandom and its two
// generators, MPSMatrixRandomPhilox and MPSMatrixRandomMTGP32.
//
// Philox4x32-10 is the release's own stream, bit for bit: the counter based generator of Salmon,
// Moraes, Dror and Shaw, with the caller's seed as the key's first word, the counter (0, 0, 0, block)
// and the four words of a block filling four consecutive elements. That was measured, not assumed -
// tests/backports/host/mpsmatrix/run.sh compares three seeds of it against the MPS of macOS 26.5 and
// the two agree to the bit - and it is the published algorithm, whose reference vectors back it.
//
// The Float32 destination and the MPSVector destination are the two things the release of macOS 26.5
// does not answer: it segfaults on the first and aborts in its own validation on the second, for every
// shape tried. That is the finding, and it is written down in facts/MetalPerformanceShaders/Random.md
// rather than worked around.

#import "CharonMPS.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation MPSMatrixRandomDistributionDescriptor {
    MPSMatrixRandomDistribution _distributionType;
    float _minimum, _maximum, _mean, _standardDeviation;
}

+ (MPSMatrixRandomDistributionDescriptor *)uniformDistributionDescriptorWithMinimum:(float)minimum maximum:(float)maximum
{
    MPSMatrixRandomDistributionDescriptor *descriptor = [[self alloc] init];
    descriptor->_distributionType = MPSMatrixRandomDistributionUniform;
    descriptor->_minimum = minimum;
    descriptor->_maximum = maximum;
    // A uniform distribution over [minimum, maximum] has its mean at the middle and its standard
    // deviation the width over the square root of twelve, which is the variance (width squared over
    // twelve) the distribution's own moments give. The release fills both in as well, measured.
    descriptor->_mean = (minimum + maximum) * 0.5f;
    descriptor->_standardDeviation = (float)((maximum - minimum) / 3.4641016151377544);
    return descriptor;
}

+ (MPSMatrixRandomDistributionDescriptor *)normalDistributionDescriptorWithMean:(float)mean standardDeviation:(float)standardDeviation
{
    return [self normalDistributionDescriptorWithMean:mean standardDeviation:standardDeviation minimum:-INFINITY maximum:INFINITY];
}

+ (MPSMatrixRandomDistributionDescriptor *)normalDistributionDescriptorWithMean:(float)mean standardDeviation:(float)standardDeviation minimum:(float)minimum maximum:(float)maximum
{
    MPSMatrixRandomDistributionDescriptor *descriptor = [[self alloc] init];
    descriptor->_distributionType = MPSMatrixRandomDistributionNormal;
    descriptor->_mean = mean;
    descriptor->_standardDeviation = standardDeviation;
    descriptor->_minimum = minimum;
    descriptor->_maximum = maximum;
    return descriptor;
}

+ (MPSMatrixRandomDistributionDescriptor *)defaultDistributionDescriptor
{
    MPSMatrixRandomDistributionDescriptor *descriptor = [[self alloc] init];
    descriptor->_distributionType = MPSMatrixRandomDistributionDefault;
    return descriptor;
}

- (MPSMatrixRandomDistribution)distributionType
{
    return _distributionType;
}

- (void)setDistributionType:(MPSMatrixRandomDistribution)distributionType
{
    _distributionType = distributionType;
}

- (float)minimum
{
    return _minimum;
}

- (void)setMinimum:(float)minimum
{
    _minimum = minimum;
}

- (float)maximum
{
    return _maximum;
}

- (void)setMaximum:(float)maximum
{
    _maximum = maximum;
}

- (float)mean
{
    return _mean;
}

- (void)setMean:(float)mean
{
    _mean = mean;
}

- (float)standardDeviation
{
    return _standardDeviation;
}

- (void)setStandardDeviation:(float)standardDeviation
{
    _standardDeviation = standardDeviation;
}

- (id)copyWithZone:(NSZone *)zone
{
    MPSMatrixRandomDistributionDescriptor *copy = [[[self class] allocWithZone:zone] init];
    copy->_distributionType = _distributionType;
    copy->_minimum = _minimum;
    copy->_maximum = _maximum;
    copy->_mean = _mean;
    copy->_standardDeviation = _standardDeviation;
    return copy;
}

@end

@implementation MPSMatrixRandom {
    MPSDataType _destinationDataType;
    MPSMatrixRandomDistribution _distributionType;
    NSUInteger _batchStart, _batchSize;
    double _minimum, _maximum, _mean, _standardDeviation;
    uint32_t _seed;
    BOOL _philox;
    uint32_t _mersenne[624];
    NSUInteger _mersenneIndex;
    BOOL _mersenneSeeded;
    NSUInteger _mersenneDrawn;
    uint32_t _mersenneHeld;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    NSLog(@"MPSMatrixRandom: -initWithDevice: is not a generator; use MPSMatrixRandomPhilox or MPSMatrixRandomMTGP32");
    return nil;
}

// The two generators share one construction. -initWithDevice: is unavailable on MPSMatrixRandom itself
// because a random kernel is always one of the two subclasses, and this is how each of them reaches
// MPSKernel's own initialiser: it is in the init family, so it may build the object.
- (id)initWithDevice:(id<MTLDevice>)device charonRandom:(BOOL)philox
{
    if ((self = [super initWithDevice:device]))
        _philox = philox;
    return self;
}

// What the two generators share after that: the data type, the distribution and the seed. A caller that
// changes the data type or the distribution after the kernel is made gets a kernel that draws from the
// new ones with the same seed, which is what the release's own properties do.
- (id)charon_mps_configureWithDataType:(MPSDataType)dataType
                                  seed:(uint32_t)seed
                            distribution:(MPSMatrixRandomDistributionDescriptor *)distribution
{
    if (dataType != MPSDataTypeUInt32 && dataType != MPSDataTypeFloat32) {
        CharonMPSRefuse(@"MPSMatrixRandom: a destination of data type %u is neither MPSDataTypeUInt32 nor MPSDataTypeFloat32, which are the two this kernel writes", (unsigned)dataType);
        return nil;
    }
    _destinationDataType = dataType;
    _seed = seed;
    _mersenneSeeded = NO;
    if (distribution) {
        _distributionType = distribution.distributionType;
        _minimum = distribution.minimum;
        _maximum = distribution.maximum;
        _mean = distribution.mean;
        _standardDeviation = distribution.standardDeviation;
    } else {
        _distributionType = MPSMatrixRandomDistributionDefault;
    }
    return self;
}

// Philox4x32-10, the counter based generator of Salmon, Moraes, Dror and Shaw: two 32 bit multipliers,
// a Weyl sequence on the key and ten rounds. The counter is (0, 0, 0, block) for the caller's seed as
// the key's first word, and the four words of a block are four consecutive elements of the stream.
// Measured against the release's own MPSMatrixRandomPhilox, which produces exactly this, for the seeds
// and the lengths in tests/backports/host/mpsmatrix/run.sh.
static inline void CharonMPSPhiloxBlock(uint32_t block, uint32_t seed, uint32_t out[4])
{
    uint32_t c0 = 0, c1 = 0, c2 = 0, c3 = block;
    uint32_t k0 = seed, k1 = 0;
    for (int round = 0; round < 10; round++) {
        uint64_t low0 = (uint64_t)c0 * 0xD2511F53u;
        uint64_t low1 = (uint64_t)c2 * 0xCD9E8D57u;
        uint32_t hi0 = (uint32_t)(low0 >> 32), lo0 = (uint32_t)low0;
        uint32_t hi1 = (uint32_t)(low1 >> 32), lo1 = (uint32_t)low1;
        uint32_t n0 = hi1 ^ c1 ^ k0, n1 = lo1, n2 = hi0 ^ c3 ^ k1, n3 = lo0;
        c0 = n0; c1 = n1; c2 = n2; c3 = n3;
        k0 += 0x9E3779B9u;
        k1 += 0xBB67AE85u;
    }
    out[0] = c0;
    out[1] = c1;
    out[2] = c2;
    out[3] = c3;
}

// The Mersenne Twister of Matsumoto and Nishimura, the recurrence MTGP32 belongs to: the same 624 word
// state and the same tempering, seeded from the caller's word. See facts/MetalPerformanceShaders/Solve.md
// for what this does and does not reproduce of the release's own MTGP32 stream.
static inline uint32_t CharonMPSMersenne(uint32_t state[624], NSUInteger *index)
{
    if (*index >= 624) {
        for (NSUInteger i = 0; i < 624; i++) {
            uint32_t y = (state[i] & 0x80000000u) | (state[(i + 1) % 624] & 0x7fffffffu);
            state[i] = state[(i + 397) % 624] ^ (y >> 1) ^ ((y & 1) ? 0x9908B0DFu : 0u);
        }
        *index = 0;
    }
    uint32_t y = state[*index];
    *index = *index + 1;
    y ^= y >> 11;
    y ^= (y << 7) & 0x9D2C5680u;
    y ^= (y << 15) & 0xEFC60000u;
    y ^= y >> 18;
    return y;
}

static void CharonMPSMersenneSeed(uint32_t state[624], uint32_t seed)
{
    state[0] = seed;
    for (NSUInteger i = 1; i < 624; i++)
        state[i] = (uint32_t)(1812433253u * (state[i - 1] ^ (state[i - 1] >> 30)) + i);
}

// The value a random word takes for a distribution, in the release's own arithmetic: the default
// distribution hands the word over untouched, a uniform one takes the top 23 bits as a fraction and
// scales it into the range, and a normal one takes the inverse normal of that fraction. The uniform's
// scale and add are done once, at the precision of the expression, which is what the release's own
// lerp does and what the differential's bits confirm.
static inline double CharonMPSRandomValue(MPSMatrixRandomDistribution type, uint32_t word, double minimum, double maximum, double mean, double standardDeviation)
{
    if (type == MPSMatrixRandomDistributionDefault)
        return (double)word;
    double t = (double)(word >> 9) * (1.0 / 8388608.0);
    if (type == MPSMatrixRandomDistributionUniform)
        return minimum + (maximum - minimum) * t;
    return mean + standardDeviation * CharonMPSInverseNormal(t);
}

- (MPSDataType)destinationDataType
{
    return _destinationDataType;
}

- (MPSMatrixRandomDistribution)distributionType
{
    return _distributionType;
}

- (NSUInteger)batchStart
{
    return _batchStart;
}

- (void)setBatchStart:(NSUInteger)batchStart
{
    _batchStart = batchStart;
}

- (NSUInteger)batchSize
{
    return _batchSize;
}

- (void)setBatchSize:(NSUInteger)batchSize
{
    _batchSize = batchSize;
}

// One word of the stream, by position. Philox is counter based and so can be asked for any position
// directly, which is what lets a batch range start in the middle of a destination; the Mersenne
// Twister can only be walked, so the state is advanced to the batch's first word and then runs on.
- (uint32_t)charon_mps_wordAtIndex:(NSUInteger)index
{
    if (_philox) {
        uint32_t block[4];
        CharonMPSPhiloxBlock(index / 4, _seed, block);
        return block[index % 4];
    }
    if (!_mersenneSeeded) {
        CharonMPSMersenneSeed(_mersenne, _seed);
        _mersenneIndex = 624;
        _mersenneSeeded = YES;
        _mersenneDrawn = 0;
    }
    while (_mersenneDrawn <= index)
        _mersenneHeld = CharonMPSMersenne(_mersenne, &_mersenneIndex), _mersenneDrawn++;
    return _mersenneHeld;
}

// The batch a random kernel walks is its destination's batch dimension - the matrices of an MPSMatrix,
// the vectors of an MPSVector - and within the batch the elements are the destination's own order. A
// batchSize of zero, or a range past the end, is the whole of it, as the headers say.
- (void)charon_mps_batchOver:(NSUInteger)available first:(NSUInteger *)first count:(NSUInteger *)count
{
    NSUInteger begin = _batchStart < available ? _batchStart : available;
    NSUInteger end = available;
    if (_batchSize && begin + _batchSize < end)
        end = begin + _batchSize;
    *first = begin;
    *count = end - begin;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer destinationVector:(MPSVector *)destinationVector
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSVectorView out = CharonMPSVectorViewOf(destinationVector);
    NSUInteger first, count;
    [self charon_mps_batchOver:out.vectors first:&first count:&count];
    for (NSUInteger vector = first; vector < first + count; vector++) {
        for (NSUInteger component = 0; component < out.length; component++) {
            uint32_t word = [self charon_mps_wordAtIndex:vector * out.length + component];
            void *element = CharonMPSVectorElement(&out, vector, component);
            if (out.dataType == MPSDataTypeUInt32)
                CharonMPSStore(element, out.dataType, 0, (double)word);
            else
                CharonMPSStore(element, out.dataType, 0, CharonMPSRandomValue(_distributionType, word, _minimum, _maximum, _mean, _standardDeviation));
        }
    }
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer destinationMatrix:(MPSMatrix *)destinationMatrix
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView out = CharonMPSMatrixViewOf(destinationMatrix);
    NSUInteger first, count;
    [self charon_mps_batchOver:out.matrices first:&first count:&count];
    for (NSUInteger matrix = first; matrix < first + count; matrix++) {
        for (NSUInteger row = 0; row < out.rows; row++) {
            for (NSUInteger column = 0; column < out.columns; column++) {
                NSUInteger index = (matrix * out.rows + row) * out.columns + column;
                uint32_t word = [self charon_mps_wordAtIndex:index];
                void *element = CharonMPSMatrixElement(&out, matrix, row, column);
                if (out.dataType == MPSDataTypeUInt32)
                    CharonMPSStore(element, out.dataType, 0, (double)word);
                else
                    CharonMPSStore(element, out.dataType, 0, CharonMPSRandomValue(_distributionType, word, _minimum, _maximum, _mean, _standardDeviation));
            }
        }
    }
}

@end

@implementation MPSMatrixRandomPhilox

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if (!(self = [super initWithDevice:device charonRandom:YES]))
        return nil;
    return [self charon_mps_configureWithDataType:MPSDataTypeUInt32 seed:0 distribution:nil];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device destinationDataType:(MPSDataType)destinationDataType seed:(NSUInteger)seed
{
    if (!(self = [super initWithDevice:device charonRandom:YES]))
        return nil;
    return [self charon_mps_configureWithDataType:destinationDataType seed:(uint32_t)seed distribution:nil];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device destinationDataType:(MPSDataType)destinationDataType seed:(NSUInteger)seed distributionDescriptor:(MPSMatrixRandomDistributionDescriptor *)distributionDescriptor
{
    if (!(self = [super initWithDevice:device charonRandom:YES]))
        return nil;
    return [self charon_mps_configureWithDataType:destinationDataType seed:(uint32_t)seed distribution:distributionDescriptor];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (void)synchronizeStateOnCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    // The generator's state is the caller's seed and this object's own fields, all of them on the CPU,
    // so there is nothing on a device to read back.
    (void)commandBuffer;
}

@end

@implementation MPSMatrixRandomMTGP32

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if (!(self = [super initWithDevice:device charonRandom:NO]))
        return nil;
    return [self charon_mps_configureWithDataType:MPSDataTypeUInt32 seed:0 distribution:nil];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device destinationDataType:(MPSDataType)destinationDataType seed:(NSUInteger)seed
{
    if (!(self = [super initWithDevice:device charonRandom:NO]))
        return nil;
    return [self charon_mps_configureWithDataType:destinationDataType seed:(uint32_t)seed distribution:nil];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device destinationDataType:(MPSDataType)destinationDataType seed:(NSUInteger)seed distributionDescriptor:(MPSMatrixRandomDistributionDescriptor *)distributionDescriptor
{
    if (!(self = [super initWithDevice:device charonRandom:NO]))
        return nil;
    return [self charon_mps_configureWithDataType:destinationDataType seed:(uint32_t)seed distribution:distributionDescriptor];
}

- (void)synchronizeStateOnCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    (void)commandBuffer;
}

@end
