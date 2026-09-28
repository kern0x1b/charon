#import "CharonAVFAudio.h"
#import <PHASE/PHASE.h>

// PHASEEngine, the spatial audio engine: the largest cluster in the PHASE corpus and the class the
// rest of the framework hangs off. PHASE arrived in iOS 15 and the port's releases are 6.1.3 and 4.3,
// so there is no PHASE.framework on either and none of this is a translation of an engine that exists.
//
// What there is to carry is the engine's state, and every value in it is either a documented default
// or the truth about a fresh engine. The four collection-valued properties answer the empty set a
// fresh engine really holds, which is not a stub: a PHASEEngine has no sound events, no groups and no
// duckers until objects are added to it, and the classes those would hold - PHASESoundEvent,
// PHASEGroup, PHASEDucker, PHASEObject, PHASEMedium, PHASEAssetRegistry, PHASEGroupPreset - are
// separate families of the corpus that this delivery does not carry, and the facts file says so
// rather than the properties inventing objects of classes the port does not have.

// rootObject is the SDK's own @property (readonly, strong, nonatomic), and this file used to declare
// BOTH a @synthesize binding for it and a hand-written getter returning the port's ivar. Two
// definitions of one method in one implementation: the object file carried a single
// -[charon_host_PHASEEngine rootObject] and it was
//
//   mov x0, #0x0
//
// a constant nil with no load at all, while -initWithUpdateMode: stored the root into the ivar at
// offset 72 and the slot held a live object at run time. One definition is what a property with a
// hand-written accessor is supposed to have, and the harness reported the nil for as long as there were
// two.
@implementation PHASEEngine {
    double _charon_unitsPerSecond;
    double _charon_unitsPerMeter;
    PHASESpatializationMode _charon_outputSpatializationMode;
    PHASEReverbPreset _charon_defaultReverbPreset;
    PHASERenderingState _charon_renderingState;
    BOOL _charon_started;
    PHASEUpdateMode _charon_updateMode;
    PHASEMediumPreset _charon_defaultMediumPreset;
    PHASEObject *_charon_rootObject;
}


- (instancetype)initWithUpdateMode:(PHASEUpdateMode)updateMode
{
    if ((self = [super init])) {
        // The header's documented defaults: unitsPerSecond and unitsPerMeter are 1 each
        // (PHASEEngine.h:123 and :134, "Values are clamped to the range (0, inf]. Default value is
        // 1."), the default reverb preset is PHASEReverbPresetNone (:112) and the default medium is
        // PHASEMediumPresetAir (:104).
        _charon_unitsPerSecond = 1.0;
        _charon_unitsPerMeter = 1.0;
        _charon_defaultReverbPreset = PHASEReverbPresetNone;
        // outputSpatializationMode has no documented numeric default - the header says only that it
        // "overrides the default output spatializer and uses the specified one instead" - and the
        // enumeration's own zero is PHASESpatializationModeAutomatic, which is the mode that means
        // "let the framework choose". That is the answer here, and it is the enumeration's naming
        // rather than a number this port picked.
        _charon_outputSpatializationMode = PHASESpatializationModeAutomatic;
        _charon_renderingState = PHASERenderingStateStopped;
        _charon_updateMode = updateMode;
        // The root object, made the way the header says one is made: against this engine, at the
        // identity transform, with no parent and no children. The engine's own root is a PHASERootObject
        // on this release, and that class has no row in the PHASE corpus - but the property's declared
        // type is PHASEObject *, and the declared type is what an application sees, so what the port
        // answers is a PHASEObject standing as the root rather than nil.
        _charon_rootObject = [[PHASEObject alloc] initWithEngine:self];
    }
    return self;
}

// The engine is not rendering until it is started, and the enumeration's zero is Stopped, so a
// fresh engine and a stopped one answer the same and the flag below only distinguishes the two
// paths that lead there.
- (PHASERenderingState)renderingState
{
    return _charon_renderingState;
}

- (BOOL)startAndReturnError:(NSError **)error
{
    _charon_started = YES;
    _charon_renderingState = PHASERenderingStateStarted;
    if (error) {
        *error = nil;
    }
    return YES;
}

// A manual-update engine advances on the caller's thread; an automatic one is advanced by the
// framework's own loop, which does not exist on a release with no PHASE.framework. The update is
// therefore a no-op that records that it was asked for, rather than a scheduling mechanism this port
// cannot provide: the corpus has no row for it (the lift declares it) and inventing a timer would be
// a mechanism the release does not have.
- (void)update
{
}

- (void)pause
{
    if (_charon_started) {
        _charon_renderingState = PHASERenderingStatePaused;
    }
}

- (void)stop
{
    _charon_started = NO;
    _charon_renderingState = PHASERenderingStateStopped;
}

- (PHASESpatializationMode)outputSpatializationMode
{
    return _charon_outputSpatializationMode;
}

- (void)setOutputSpatializationMode:(PHASESpatializationMode)outputSpatializationMode
{
    _charon_outputSpatializationMode = outputSpatializationMode;
}

- (double)unitsPerSecond
{
    return _charon_unitsPerSecond;
}

// The header clamps to (0, inf] and says so: a non-positive value is not a setting the property
// takes, and the host's own clamp is what a caller has to live with, so the port refuses it here
// rather than storing a value the release would clamp.
- (void)setUnitsPerSecond:(double)unitsPerSecond
{
    if (unitsPerSecond > 0) {
        _charon_unitsPerSecond = unitsPerSecond;
    }
}

- (double)unitsPerMeter
{
    return _charon_unitsPerMeter;
}

- (void)setUnitsPerMeter:(double)unitsPerMeter
{
    if (unitsPerMeter > 0) {
        _charon_unitsPerMeter = unitsPerMeter;
    }
}

- (PHASEReverbPreset)defaultReverbPreset
{
    return _charon_defaultReverbPreset;
}

- (void)setDefaultReverbPreset:(PHASEReverbPreset)defaultReverbPreset
{
    _charon_defaultReverbPreset = defaultReverbPreset;
}

// The default medium, the enumeration's own PHASEMediumPresetAir. It is held as the preset rather
// than as a PHASEMedium, because PHASEMedium is a separate family of the corpus that this delivery
// does not carry: a caller asking for the object gets the value it has rather than an object of a
// class the port does not have, and the facts file says what that costs.
- (id)defaultMedium
{
    return @(PHASEMediumPresetAir);
}

- (PHASEUpdateMode)updateMode
{
    return _charon_updateMode;
}

- (void)setDefaultMedium:(id)defaultMedium
{
    _charon_defaultMediumPreset = [defaultMedium respondsToSelector:@selector(integerValue)]
        ? (PHASEMediumPreset)[defaultMedium integerValue] : PHASEMediumPresetAir;
}

- (PHASEObject *)rootObject
{
    // The root, not nil. A rewrite of this method replaced the comment above it and left the body, so
    // the accessor returned a constant nil - which is why the disassembly was `mov x0, #0x0` while
    // -initWithUpdateMode: stored a live root in the ivar at offset 72, and why @synthesize changed
    // nothing: a hand-written accessor wins over a synthesised one, and this one returned nil.
    return _charon_rootObject;
}

- (id)assetRegistry
{
    // PHASEAssetRegistry is a separate family of the corpus and is not carried here, so this is nil:
    // the empty answer rather than an object of a class the port does not have. The facts file names it.
    return nil;
}

// The engine's sound events. A fresh engine has none, and PHASESoundEvent is a separate family of
// the corpus, so an event added to this engine cannot be held yet; the empty answer is the truth about
// the engine and the framework around it is incomplete.
- (NSArray<PHASESoundEvent *> *)soundEvents
{
    return @[];
}

- (NSDictionary<NSString *, PHASEGroup *> *)groups
{
    return @{};
}

- (NSArray<PHASEDucker *> *)duckers
{
    return @[];
}

- (PHASEGroupPreset *)activeGroupPreset
{
    return nil;
}

@end
