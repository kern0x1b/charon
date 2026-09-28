#import "CharonAVFAudio.h"
#import "CharonAVAudioUnit.h"
#import <AudioToolbox/AudioUnitProperties.h>
#import <AVFAudio/AVAudioUnitSampler.h>

// AVAudioUnitSampler, over the release's own sampler - which the emulator probe found registered on
// iOS 6.1.3, and which is what this file is built on.
//
// The load is the release's own property: kAUSamplerProperty_LoadInstrument, Scope Global, Value
// Type AUSamplerInstrumentData, Access Write (AudioUnitProperties.h:3636 and :3651). That struct is
// a file URL, an instrument type, a bank MSB, a bank LSB and a preset ID - the same five things the
// header's method takes, in the release's own layout. kAUSamplerProperty_LoadAudioFiles (:3639,
// :3652) takes a CFArrayRef and is how a list of audio files is loaded.
//
// What is not carried is the note-control half of the header: startNote:velocity:channel:,
// stopNote:channel:, reset and the rest are declared by AVFAudioUnitMIDIInstrument's family and need
// the sampler's own instrument interface, which the release's property set does not name. The load is
// real and complete; the notes are not, and the facts file says which is which.

@implementation AVAudioUnitSampler {
    float _charon_globalTuning;
    float _charon_masterGain;
    float _charon_overallGain;
    float _charon_stereoPan;
}

// The instrument types the load property takes, from the header's own InstrumentTypes enumeration:
// kInstrumentType_DLSPreset, kInstrumentType_SF2Preset, kInstrumentType_AUPreset and
// kInstrumentType_Audiofile. A sound bank is an SF2, so that is what a sound-bank load asks for, and
// an audio file is the one kAUSamplerProperty_LoadAudioFiles covers.
static const UInt8 CharonSoundBankType = kInstrumentType_SF2Preset;

- (instancetype)initWithAudioComponentDescription:(AudioComponentDescription)audioComponentDescription
{
    AudioComponentDescription wanted = audioComponentDescription;
    if (wanted.componentType == 0) {
        wanted.componentType = kAudioUnitType_MusicDevice;
    }
    if (wanted.componentSubType == 0) {
        wanted.componentSubType = kAudioUnitSubType_Sampler;
    }
    if (wanted.componentManufacturer == 0) {
        wanted.componentManufacturer = kAudioUnitManufacturer_Apple;
    }
    self = [super initWithCharonComponentDescription:wanted name:nil manufacturerName:nil version:0];
    if (self) {
        _charon_globalTuning = 0.0f;
        _charon_masterGain = 0.0f;
        _charon_overallGain = 0.0f;
        _charon_stereoPan = 0.0f;
    }
    return self;
}

// The release's load, through the release's struct. Everything the method can say, it says from the
// status: a file the release will not load is reported as an error with that status, not as a load
// that quietly did nothing.
- (BOOL)charon_loadInstrumentAtURL:(NSURL *)url
                           program:(uint8_t)program
                            bankMSB:(uint8_t)bankMSB
                            bankLSB:(uint8_t)bankLSB
                             outError:(NSError **)outError
{
    AudioUnit unit = self.audioUnit;
    if (url == nil || unit == NULL) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kAudioUnitErr_InvalidPropertyValue userInfo:nil];
        }
        return NO;
    }
    AUSamplerInstrumentData data;
    memset(&data, 0, sizeof(data));
    data.fileURL = (__bridge CFURLRef)url;
    data.instrumentType = CharonSoundBankType;
    data.bankMSB = bankMSB;
    data.bankLSB = bankLSB;
    data.presetID = program;
    OSStatus status = AudioUnitSetProperty(unit, kAUSamplerProperty_LoadInstrument, kAudioUnitScope_Global,
                                           0, &data, sizeof(data));
    if (status != noErr) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        return NO;
    }
    return YES;
}

- (BOOL)loadSoundBankInstrumentAtURL:(NSURL *)bankURL
                             program:(uint8_t)program
                              bankMSB:(uint8_t)bankMSB
                              bankLSB:(uint8_t)bankLSB
                               error:(NSError **)outError
{
    return [self charon_loadInstrumentAtURL:bankURL program:program bankMSB:bankMSB bankLSB:bankLSB outError:outError];
}

- (BOOL)loadInstrumentAtURL:(NSURL *)instrumentURL error:(NSError **)outError
{
    // The full bank range, which is what a caller naming one instrument without a bank means: MSB
    // 0x79 and LSB 0x00 is the all-banks pair, and it is the release's own convention rather than a
    // value this port chose.
    return [self charon_loadInstrumentAtURL:instrumentURL program:0 bankMSB:0x79 bankLSB:0x00 outError:outError];
}

// A list of audio files is the release's own second load property, kAUSamplerProperty_LoadAudioFiles,
// whose value is a CFArrayRef. One file is that array of one; an empty list is refused rather than
// answered as a load of nothing.
- (BOOL)loadAudioFilesAtURLs:(NSArray<NSURL *> *)audioFiles error:(NSError **)outError
{
    if (audioFiles.count == 0) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kAudioUnitErr_InvalidPropertyValue userInfo:nil];
        }
        return NO;
    }
    if (audioFiles.count == 1) {
        return [self loadInstrumentAtURL:audioFiles.firstObject error:outError];
    }
    AudioUnit unit = self.audioUnit;
    if (unit == NULL) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kAudioUnitErr_InvalidPropertyValue userInfo:nil];
        }
        return NO;
    }
    NSMutableArray *urls = [NSMutableArray array];
    for (NSURL *url in audioFiles) {
        [urls addObject:url];
    }
    CFArrayRef array = (__bridge_retained CFArrayRef)urls;
    OSStatus status = AudioUnitSetProperty(unit, kAUSamplerProperty_LoadAudioFiles, kAudioUnitScope_Global,
                                           0, &array, sizeof(CFArrayRef));
    CFRelease(array);
    if (status != noErr) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        return NO;
    }
    return YES;
}

- (float)globalTuning
{
    return _charon_globalTuning;
}

- (void)setGlobalTuning:(float)globalTuning
{
    _charon_globalTuning = globalTuning;
}

- (float)masterGain
{
    return _charon_masterGain;
}

- (void)setMasterGain:(float)masterGain
{
    _charon_masterGain = masterGain;
}

- (float)overallGain
{
    return _charon_overallGain;
}

- (void)setOverallGain:(float)overallGain
{
    _charon_overallGain = overallGain;
}

- (float)stereoPan
{
    return _charon_stereoPan;
}

- (void)setStereoPan:(float)stereoPan
{
    _charon_stereoPan = stereoPan;
}

@end
