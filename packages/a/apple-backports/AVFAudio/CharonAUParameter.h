#import "CharonAVFAudio.h"
#import <AudioUnit/AudioUnit.h>

NS_ASSUME_NONNULL_BEGIN

// AudioUnitParameterInfo is the v2 wire format a real unit answers kAudioUnitProperty_ParameterInfo
// in. SDK 26.2 no longer declares it - its AudioUnitProperties.h names the property and its value
// type and nothing else - while SDK 15.6 still declares it in full, so the declaration below is
// transcribed from $SDKS/iPhoneOS15.6.sdk/System/Library/Frameworks/AudioToolbox.framework/Headers/
// AudioUnitProperties.h:1622 and its field order is the ABI the release answers, not a choice.
// Nothing is read past what the unit wrote, and the size the unit answers is the size asked for.
struct CharonAudioUnitParameterInfo {
    char name[52];
    CFStringRef __nullable unitName;
    UInt32 clumpID;
    CFStringRef __nullable cfNameString;
    AudioUnitParameterUnit unit;
    AudioUnitParameterValue minValue;
    AudioUnitParameterValue maxValue;
    AudioUnitParameterValue defaultValue;
    AudioUnitParameterOptions flags;
};
typedef struct CharonAudioUnitParameterInfo CharonAudioUnitParameterInfo;

// Shared private plumbing for the AudioUnit.framework classes this folder carries: AUParameterNode
// and its group, tree and leaf, AUAudioUnitBus and AUAudioUnitBusArray, AUAudioUnitPreset and
// AUAudioUnit itself.
//
// The release has no AudioUnit.framework: on iOS 6.1.3 the whole AudioUnit C API - AudioComponent
// discovery, AudioUnitSetProperty/GetProperty/GetPropertyInfo, AudioUnitRender, AudioUnitInitialize,
// AudioUnitReset, AudioUnitScheduleParameters - and the whole AUGraph API live in AudioToolbox, which
// is where they are measured to be. So the classes below are built directly on those: a real
// AudioComponentInstanceNew for the unit, a real AudioUnitSetProperty for every property, a real
// AudioUnitRender for the input the render block pulls, and a real
// AudioUnitGetPropertyInfo(kAudioUnitProperty_ParameterInfo) walk for the parameter tree. Nothing
// here is a translation of Apple's, because there is nothing on this release to translate.

// The address of a parameter is its three v2 coordinates packed into one word, from the top down:
// identifier, then scope, then element. The header's AUParameterAddress, and the packing both ways
// is this file's because both sides of it are here.
static inline AUParameterAddress CharonAddress(AudioUnitParameterID identifier, AudioUnitScope scope, AudioUnitElement element)
{
    return ((AUParameterAddress)identifier << 32) | ((AUParameterAddress)scope << 16) | (AUParameterAddress)element;
}

// What one parameter of a real unit is, as that unit describes it. The AUParameter is the header's
// value object; this is what it holds, and the AudioUnit behind it is the unit the value is read
// from and written to.
@interface CharonAUParameterImpl : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) AudioUnitParameterID identifier;
@property (nonatomic) AudioUnitScope scope;
@property (nonatomic) AudioUnitElement element;
@property (nonatomic) AUValue minValue;
@property (nonatomic) AUValue maxValue;
@property (nonatomic) AudioUnitParameterUnit unit;
@property (nonatomic) AudioUnitParameterOptions flags;
@property (nonatomic, copy, nullable) NSString *unitName;
@property (nonatomic, copy, nullable) NSArray<NSString *> *valueStrings;
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *dependentParameters;
@property (nonatomic, weak, nullable) AUAudioUnit *owner;
@end

@implementation CharonAUParameterImpl
// Explicit synthesis for every one of them: this class is one the package defines rather than a
// release's, and the build compiles with -Werror=objc-missing-property-synthesis.
@synthesize name = _name;
@synthesize identifier = _identifier;
@synthesize scope = _scope;
@synthesize element = _element;
@synthesize minValue = _minValue;
@synthesize maxValue = _maxValue;
@synthesize unit = _unit;
@synthesize flags = _flags;
@synthesize unitName = _unitName;
@synthesize valueStrings = _valueStrings;
@synthesize dependentParameters = _dependentParameters;
@synthesize owner = _owner;
@end

// The tree a real unit publishes, built by asking that unit. The walk is AudioUnitGetPropertyInfo
// with kAudioUnitProperty_ParameterInfo, and every range, unit, flag and name below is that call's
// answer - not a table the port chose.
@interface AUParameterTree (CharonImpl)
- (instancetype _Nonnull)initWithCharonChildren:(NSArray<AUParameterNode *> *_Nonnull)children;
@end

@interface AUParameterGroup (CharonImpl)
- (instancetype _Nonnull)initWithCharonChildren:(NSArray<AUParameterNode *> *_Nonnull)children;
@end

@interface AUParameter (CharonImpl)
- (instancetype _Nonnull)charon_parameterWithImpl:(CharonAUParameterImpl *_Nonnull)impl;
- (AudioUnitParameterID)charon_identifier;
- (AudioUnitScope)charon_scope;
- (AudioUnitElement)charon_element;
- (void)charon_apply:(AUValue)value
           originator:(AUParameterObserverToken _Nullable)originator
           atHostTime:(uint64_t)hostTime
            eventType:(AUParameterAutomationEventType)eventType
            automate:(BOOL)automate;
@end

// The real AudioUnit of an AUAudioUnit. The C type AudioToolbox calls AUAudioUnit arrived with the
// AudioUnit.framework of iOS 9 and is not exported by iOS 6.1.3, so the unit this port holds and
// hands out is the v2 AudioUnit every release carries, and the parameter tree reads and writes that.
@interface AUAudioUnit (CharonImpl)
@property (nonatomic, readonly) AudioUnit audioUnit;
@end

// The parent link and the key path of a node: the key path is the identifiers of a node's parents
// joined with periods, which is what the header says a key path is.
@interface AUParameterNode (CharonImpl)
- (void)charon_setParent:(AUParameterNode *)parent keyPath:(NSString *)keyPath;
- (void)charon_setDisplayName:(NSString *)displayName;
- (void)charon_setIdentifier:(NSString *)identifier;
- (NSArray<NSValue *> *_Nonnull)charon_observerTokens;
- (void)charon_addAutomationObserver:(id _Nonnull)observer;
- (void)charon_notifyValue:(AUValue)value atAddress:(AUParameterAddress)address;
- (void)charon_notifyRecording:(NSInteger)count events:(const AURecordedParameterEvent *_Nonnull)events;
- (void)charon_notifyAutomation:(NSInteger)count events:(const AUParameterAutomationEvent *_Nonnull)events;
@end

@class AUAudioUnit;
@class AUParameterTree;

AUParameterTree *_Nullable CharonBuildParameterTree(AUAudioUnit *_Nonnull owner);

NS_ASSUME_NONNULL_END
