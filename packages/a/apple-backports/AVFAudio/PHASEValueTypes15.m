#import "CharonAVFAudio.h"
#import <PHASE/PHASE.h>

// PHASE's spatial-audio value types: the directivity and distance-model parameter classes, their
// subbands, and PHASENumericPair.
//
// These are value classes and nothing else - the header gives each a small set of doubles and an
// initializer - so what there is to implement is the values and the defaults, and both come from
// the header's own documentation rather than from a table. The gain laws themselves are the unit's,
// not the port's: a directivity model and a distance model are properties of an audio unit, and the
// port has no unit to render through on a release that has no PHASE.framework at all. So what is here
// is the arithmetic a host asks for - a cone's and a cardioid's subband parameters, a distance fade's
// cull distance, geometric spreading's rolloff factor - and every value in it is the header's.
//
// That is also why nothing is taken from Resonance Audio or Steam Audio. The whole of what this
// family computes is a set of doubles with documented defaults and a setInnerAngle:outerAngle: whose
// only stated precondition is outerAngle >= innerAngle. There is no filter bank, no convolution and no
// graph to vendor, and the facts file records the search.

@implementation PHASENumericPair {
    double _charon_first;
    double _charon_second;
}

- (instancetype)initWithFirstValue:(double)first secondValue:(double)second
{
    if ((self = [super init])) {
        _charon_first = first;
        _charon_second = second;
    }
    return self;
}

// The header's own default for both, 0.0, which is what a plain -init leaves behind.
- (instancetype)init
{
    return [self initWithFirstValue:0.0 secondValue:0.0];
}

- (double)first
{
    return _charon_first;
}

- (void)setFirst:(double)first
{
    _charon_first = first;
}

- (double)second
{
    return _charon_second;
}

- (void)setSecond:(double)second
{
    _charon_second = second;
}

@end

@implementation PHASEDistanceModelFadeOutParameters {
    double _charon_cullDistance;
}

- (instancetype)initWithCullDistance:(double)cullDistance
{
    if ((self = [super init])) {
        _charon_cullDistance = cullDistance;
    }
    return self;
}

- (double)cullDistance
{
    return _charon_cullDistance;
}

@end

@implementation PHASEGeometricSpreadingDistanceModelParameters {
    // No initialiser is written: the class derives from PHASEDistanceModelParameters, whose -init and
    // +new the header marks NS_UNAVAILABLE, and clang inherits that unavailability into the
    // subclass, so writing one here is a hard error rather than an override.
    //
    // The header also names no default for the rolloff factor - unlike the cone subband's two
    // angles, which it says are 360.0 each - so none is invented here: the ivar's own zero stands
    // until a caller sets it. facts/AVFAudio/PHASEValueTypes.md records that, and what the gain
    // law does with a zero exponent, so a reader is not left guessing whether it means "no
    // attenuation" or "unset".
    double _charon_rolloffFactor;
}

- (double)rolloffFactor
{
    return _charon_rolloffFactor;
}

- (void)setRolloffFactor:(double)rolloffFactor
{
    _charon_rolloffFactor = rolloffFactor;
}

// The law the rolloff factor is the exponent of. This is the whole of what a geometric spreading
// model computes, and it is written out so a host can be held to it: gain = 1 / distance^rolloff.
- (double)charon_gainAtDistance:(double)distance
{
    if (distance <= 0) {
        return 0;
    }
    // gain = 1 / distance^rolloff. A rolloff of zero - the state a never-set parameter is in - gives
    // a gain of one, which is what that exponent means and not a special case invented here.
    return 1.0 / pow(distance, _charon_rolloffFactor);
}

@end

@implementation PHASEDistanceModelParameters {
    PHASEDistanceModelFadeOutParameters *_charon_fadeOut;
}

- (PHASEDistanceModelFadeOutParameters *)fadeOutParameters
{
    return _charon_fadeOut;
}

- (void)setFadeOutParameters:(PHASEDistanceModelFadeOutParameters *)fadeOutParameters
{
    _charon_fadeOut = fadeOutParameters;
}

@end

@implementation PHASECardioidDirectivityModelSubbandParameters {
    double _charon_frequency;
    double _charon_pattern;
    double _charon_sharpness;
}

- (instancetype)init
{
    if ((self = [super init])) {
        // The header's own defaults: 0.0 for each of the three.
        _charon_frequency = 0.0;
        _charon_pattern = 0.0;
        _charon_sharpness = 0.0;
    }
    return self;
}

- (double)frequency
{
    return _charon_frequency;
}

- (void)setFrequency:(double)frequency
{
    _charon_frequency = frequency;
}

- (double)pattern
{
    return _charon_pattern;
}

- (void)setPattern:(double)pattern
{
    _charon_pattern = pattern;
}

- (double)sharpness
{
    return _charon_sharpness;
}

- (void)setSharpness:(double)sharpness
{
    _charon_sharpness = sharpness;
}

@end

@implementation PHASEConeDirectivityModelSubbandParameters {
    double _charon_frequency;
    double _charon_innerAngle;
    double _charon_outerAngle;
    double _charon_outerGain;
}

- (instancetype)init
{
    if ((self = [super init])) {
        // "The default value for each angle is 360.0", which the header states for both.
        _charon_frequency = 0.0;
        _charon_innerAngle = 360.0;
        _charon_outerAngle = 360.0;
        _charon_outerGain = 0.0;
    }
    return self;
}

// The header's one precondition: "outerAngle must be >= innerAngle". A call that breaks it is
// refused with the pair unchanged, which is what "must" means and what keeps the model coherent -
// an inner angle outside the outer one describes no cone.
- (void)setInnerAngle:(double)innerAngle outerAngle:(double)outerAngle
{
    if (outerAngle < innerAngle) {
        return;
    }
    _charon_innerAngle = innerAngle;
    _charon_outerAngle = outerAngle;
}

- (double)frequency
{
    return _charon_frequency;
}

- (void)setFrequency:(double)frequency
{
    _charon_frequency = frequency;
}

- (double)innerAngle
{
    return _charon_innerAngle;
}

- (double)outerAngle
{
    return _charon_outerAngle;
}

- (double)outerGain
{
    return _charon_outerGain;
}

- (void)setOuterGain:(double)outerGain
{
    _charon_outerGain = outerGain;
}

@end

@implementation PHASECardioidDirectivityModelParameters {
    NSArray<PHASECardioidDirectivityModelSubbandParameters *> *_charon_subbands;
}

// The superclass marks -init NS_UNAVAILABLE (PHASEDirectivityModel.h:121) and this subclass declares
// -initWithSubbandParameters:, so [super init] is a hard error here and [super alloc] is the only
// path the header permits. It is not a shortcut: the subclass has no inherited state to initialise
// and its own state is set immediately below, which is the whole of what -init would have done.
- (instancetype)initWithSubbandParameters:(NSArray<PHASECardioidDirectivityModelSubbandParameters *> *)subbandParameters
{
    if ((self = [PHASECardioidDirectivityModelParameters alloc])) {
        _charon_subbands = [subbandParameters copy] ?: @[];
    }
    return self;
}

- (NSArray<PHASECardioidDirectivityModelSubbandParameters *> *)subbandParameters
{
    return _charon_subbands;
}

@end

@implementation PHASEConeDirectivityModelParameters {
    NSArray<PHASEConeDirectivityModelSubbandParameters *> *_charon_subbands;
}

// As above: [super alloc], not [super init], because the superclass forbids it.
- (instancetype)initWithSubbandParameters:(NSArray<PHASEConeDirectivityModelSubbandParameters *> *)subbandParameters
{
    if ((self = [PHASEConeDirectivityModelParameters alloc])) {
        _charon_subbands = [subbandParameters copy] ?: @[];
    }
    return self;
}

- (NSArray<PHASEConeDirectivityModelSubbandParameters *> *)subbandParameters
{
    return _charon_subbands;
}

@end
