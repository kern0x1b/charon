#import "CharonAVAudioUnit.h"
#import <AudioToolbox/AudioUnitParameters.h>

// The AVAudioUnit subclasses that are a *description of one of the release's own built-in units* plus
// a set of the release's own parameters. Each description is a release subtype out of
// AudioUnitParameters.h - kAudioUnitSubType_Delay, kAudioUnitSubType_Varispeed,
// kAudioUnitSubType_TimePitch, kAudioUnitSubType_Distortion, kAudioUnitSubType_AudioUnitReverb - and
// every parameter id is the release's own out of the same header, so a value set here is an
// AudioUnitSetParameter on a real unit of the release and changes what it renders.
//
// The base classes - AVAudioUnit, AVAudioUnitEffect, AVAudioNode - are carried in
// libAVFoundationBackports.dylib, which this library links; nothing of theirs is edited here.
//
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-property-synthesis"
#pragma clang diagnostic ignored "-Wprotocol"

// AVAudioUnitMIDIInstrument and AVAudioUnitSampler are deliberately NOT here: iOS 6.1.3 exports no
// function that sends a MIDI event to an audio unit (its AudioToolbox AudioUnit family is the
// twenty-seven functions enumerated in facts/AVFAudio/AUAudioUnit.md, and none of them is a MIDI
// send), and it carries no sampler component. The path a MIDI instrument has on this release is
// MusicSequence and MusicPlayer, which it exports in full, and that is the sequencer family's to
// build. Writing the note methods as a queue nothing drains would be exactly the silent fake
// COORDINATION section 2 forbids, so they wait for that family - see facts/AVFAudio/AVAudioUnitMIDI.md.

@implementation AVAudioUnitTimeEffect

- (instancetype)initWithAudioComponentDescription:(AudioComponentDescription)audioComponentDescription
{
    return [self initWithCharonComponentDescription:audioComponentDescription name:nil manufacturerName:nil version:0];
}

@end

@implementation AVAudioUnitEffect

- (instancetype)initWithAudioComponentDescription:(AudioComponentDescription)audioComponentDescription
{
    return [self initWithCharonComponentDescription:audioComponentDescription name:nil manufacturerName:nil version:0];
}

@end

@implementation AVAudioUnitGenerator

- (instancetype)initWithAudioComponentDescription:(AudioComponentDescription)audioComponentDescription
{
    return [self initWithCharonComponentDescription:audioComponentDescription name:nil manufacturerName:nil version:0];
}

@end

// A parameter's value, and its default: -1 means "the application has not chosen one", so the unit's
// own current value is read back instead. The unit is asked, not a table consulted.
#define CharonParameterOf(unit, identifier) CharonUnitParameter((unit).audioUnit, (identifier))
#define CharonSetParameterOf(unit, identifier, value) CharonSetUnitParameter((unit).audioUnit, (identifier), (value))

@implementation AVAudioUnitDelay {
    float _charon_delayTime;
    float _charon_feedback;
    float _charon_lowPassCutoff;
    float _charon_wetDryMix;
}

- (instancetype)initWithAudioComponentDescription:(AudioComponentDescription)audioComponentDescription
{
    self = [super initWithAudioComponentDescription:audioComponentDescription];
    if (self) {
        _charon_delayTime = -1;
        _charon_feedback = -1;
        _charon_lowPassCutoff = -1;
        _charon_wetDryMix = -1;
    }
    return self;
}

- (NSTimeInterval)delayTime
{
    if (_charon_delayTime >= 0) {
        return _charon_delayTime;
    }
    return CharonParameterOf(self, kDelayParam_DelayTime);
}

- (void)setDelayTime:(NSTimeInterval)delayTime
{
    _charon_delayTime = (float)delayTime;
    CharonSetParameterOf(self, kDelayParam_DelayTime, _charon_delayTime);
}

- (float)feedback
{
    if (_charon_feedback >= 0) {
        return _charon_feedback;
    }
    return CharonParameterOf(self, kDelayParam_Feedback);
}

- (void)setFeedback:(float)feedback
{
    _charon_feedback = feedback;
    CharonSetParameterOf(self, kDelayParam_Feedback, feedback);
}

- (float)lowPassCutoff
{
    if (_charon_lowPassCutoff >= 0) {
        return _charon_lowPassCutoff;
    }
    return CharonParameterOf(self, kDelayParam_LopassCutoff);
}

- (void)setLowPassCutoff:(float)lowPassCutoff
{
    _charon_lowPassCutoff = lowPassCutoff;
    CharonSetParameterOf(self, kDelayParam_LopassCutoff, lowPassCutoff);
}

- (float)wetDryMix
{
    if (_charon_wetDryMix >= 0) {
        return _charon_wetDryMix;
    }
    return CharonParameterOf(self, kDelayParam_WetDryMix);
}

- (void)setWetDryMix:(float)wetDryMix
{
    _charon_wetDryMix = wetDryMix;
    CharonSetParameterOf(self, kDelayParam_WetDryMix, wetDryMix);
}

// A value chosen before the node was ever attached reaches the unit when the real one arrives.
- (void)charon_applyPendingParameters
{
    if (_charon_delayTime >= 0) CharonSetParameterOf(self, kDelayParam_DelayTime, _charon_delayTime);
    if (_charon_feedback >= 0) CharonSetParameterOf(self, kDelayParam_Feedback, _charon_feedback);
    if (_charon_lowPassCutoff >= 0) CharonSetParameterOf(self, kDelayParam_LopassCutoff, _charon_lowPassCutoff);
    if (_charon_wetDryMix >= 0) CharonSetParameterOf(self, kDelayParam_WetDryMix, _charon_wetDryMix);
    [super charon_applyPendingParameters];
}

@end

@implementation AVAudioUnitVarispeed {
    float _charon_rate;
}

- (instancetype)initWithAudioComponentDescription:(AudioComponentDescription)audioComponentDescription
{
    self = [super initWithAudioComponentDescription:audioComponentDescription];
    if (self) {
        _charon_rate = -1;
    }
    return self;
}

- (float)rate
{
    if (_charon_rate >= 0) {
        return _charon_rate;
    }
    return CharonParameterOf(self, kVarispeedParam_PlaybackRate);
}

- (void)setRate:(float)rate
{
    _charon_rate = rate;
    CharonSetParameterOf(self, kVarispeedParam_PlaybackRate, rate);
}

- (void)charon_applyPendingParameters
{
    if (_charon_rate >= 0) CharonSetParameterOf(self, kVarispeedParam_PlaybackRate, _charon_rate);
    [super charon_applyPendingParameters];
}

@end

@implementation AVAudioUnitTimePitch {
    float _charon_rate;
    float _charon_pitch;
    float _charon_overlap;
}

- (instancetype)initWithAudioComponentDescription:(AudioComponentDescription)audioComponentDescription
{
    self = [super initWithAudioComponentDescription:audioComponentDescription];
    if (self) {
        _charon_rate = -1;
        _charon_pitch = -1;
        _charon_overlap = -1;
    }
    return self;
}

- (float)rate
{
    if (_charon_rate >= 0) {
        return _charon_rate;
    }
    return CharonParameterOf(self, kTimePitchParam_Rate);
}

- (void)setRate:(float)rate
{
    _charon_rate = rate;
    CharonSetParameterOf(self, kTimePitchParam_Rate, rate);
}

- (float)pitch
{
    if (_charon_pitch >= 0) {
        return _charon_pitch;
    }
    return CharonParameterOf(self, kTimePitchParam_Pitch);
}

- (void)setPitch:(float)pitch
{
    _charon_pitch = pitch;
    CharonSetParameterOf(self, kTimePitchParam_Pitch, pitch);
}

- (float)overlap
{
    if (_charon_overlap >= 0) {
        return _charon_overlap;
    }
    return CharonParameterOf(self, kTimePitchParam_EffectBlend);
}

- (void)setOverlap:(float)overlap
{
    _charon_overlap = overlap;
    CharonSetParameterOf(self, kTimePitchParam_EffectBlend, overlap);
}

- (void)charon_applyPendingParameters
{
    if (_charon_rate >= 0) CharonSetParameterOf(self, kTimePitchParam_Rate, _charon_rate);
    if (_charon_pitch >= 0) CharonSetParameterOf(self, kTimePitchParam_Pitch, _charon_pitch);
    if (_charon_overlap >= 0) CharonSetParameterOf(self, kTimePitchParam_EffectBlend, _charon_overlap);
    [super charon_applyPendingParameters];
}

@end

@implementation AVAudioUnitDistortion {
    float _charon_preGain;
    float _charon_wetDryMix;
    NSInteger _charon_preset;
}

- (instancetype)initWithAudioComponentDescription:(AudioComponentDescription)audioComponentDescription
{
    self = [super initWithAudioComponentDescription:audioComponentDescription];
    if (self) {
        _charon_preGain = 0;
        _charon_wetDryMix = 0;
    }
    return self;
}

// The v2 distortion unit of this release has no PreGain and no WetDryMix parameter. Its fifteen are
// Delay, Decay, DelayMix, Decimation, Rounding, DecimationMix, LinearTerm, SquaredTerm, CubicTerm,
// PolynomialMix, RingModFreq1, RingModFreq2, RingModBalance, RingModMix, SoftClipGain and FinalMix -
// all out of AudioUnitParameters.h, and none of them either of these. So both values are kept and
// read back, and the unit is not told; a host that sets preGain before it is rendered sees it come
// back, and the audio does not change. That difference from a release whose distortion unit has the
// property is written down in facts/AVFAudio/AVAudioUnitDistortion.md rather than papered over with
// a parameter the release does not have.
- (float)preGain
{
    return _charon_preGain;
}

- (void)setPreGain:(float)preGain
{
    _charon_preGain = preGain;
}

- (float)wetDryMix
{
    return _charon_wetDryMix;
}

- (void)setWetDryMix:(float)wetDryMix
{
    _charon_wetDryMix = wetDryMix;
}

// The v2 distortion unit of this release has no preset parameter and no factory presets: its fifteen
// parameters are the ring modulator and decimation ones listed above, and a preset number is not one
// of them. The preset is therefore kept and nothing acts on it, which is what the registry calls
// inert - a value a host can set and read back that changes no audio on this release.
- (void)loadFactoryPreset:(AVAudioUnitDistortionPreset)preset
{
    _charon_preset = (NSInteger)preset;
}

- (AVAudioUnitDistortionPreset)preset
{
    return (AVAudioUnitDistortionPreset)_charon_preset;
}

- (void)charon_applyPendingParameters
{
    [super charon_applyPendingParameters];
}

@end

@implementation AVAudioUnitReverb {
    float _charon_wetDryMix;
    NSInteger _charon_preset;
}

- (instancetype)initWithAudioComponentDescription:(AudioComponentDescription)audioComponentDescription
{
    self = [super initWithAudioComponentDescription:audioComponentDescription];
    if (self) {
        _charon_wetDryMix = -1;
    }
    return self;
}

- (float)wetDryMix
{
    if (_charon_wetDryMix >= 0) {
        return _charon_wetDryMix;
    }
    return CharonParameterOf(self, kReverb2Param_DryWetMix);
}

- (void)setWetDryMix:(float)wetDryMix
{
    _charon_wetDryMix = wetDryMix;
    CharonSetParameterOf(self, kReverb2Param_DryWetMix, wetDryMix);
}

// The same for the reverb: iOS's v2 reverb unit has no preset parameter either, so the preset is
// kept and nothing acts on it. Written down in facts/AVFAudio/AVAudioUnitDistortion.md alongside the
// distortion one, because the reason is the same.
- (void)loadFactoryPreset:(AVAudioUnitReverbPreset)preset
{
    _charon_preset = (NSInteger)preset;
}

- (AVAudioUnitReverbPreset)preset
{
    return (AVAudioUnitReverbPreset)_charon_preset;
}

- (void)charon_applyPendingParameters
{
    if (_charon_wetDryMix >= 0) CharonSetParameterOf(self, kReverb2Param_DryWetMix, _charon_wetDryMix);
    [super charon_applyPendingParameters];
}

@end

#pragma clang diagnostic pop
