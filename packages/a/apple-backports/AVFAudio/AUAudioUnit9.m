#import "CharonAUAudioUnit.h"

@implementation AUAudioUnit {
    AudioUnit _charon_audioUnit;
    AudioComponent _charon_component;
    AudioComponentDescription _charon_description;
    AURenderBlock _charon_renderBlock;
    AURenderPullInputBlock _charon_pullInputBlock;
    AUScheduleParameterBlock _charon_scheduleParameterBlock;
    AUAudioUnitBusArray *_charon_inputBusses;
    AUAudioUnitBusArray *_charon_outputBusses;
    AUParameterTree *_charon_parameterTree;
    NSMutableArray<NSValue *> *_charon_renderObservers;
    BOOL _charon_resourcesAllocated;
    AUAudioFrameCount _charon_maximumFramesToRender;
    BOOL _charon_shouldBypassEffect;
    AUAudioUnitPreset *_charon_currentPreset;
}

// The unit is a real one: AudioComponentInstanceNew on the component the description names, which is
// the whole of what a v2 host had to do to make an audio unit on this release. Every property below
// is one AudioUnit call, and the render block is installed the way a v2 host installed one.
- (instancetype)initWithComponentDescription:(AudioComponentDescription)description options:(AudioComponentInstantiationOptions)options error:(NSError **)outError
{
    if ((self = [super init])) {
        _charon_description = description;
        _charon_maximumFramesToRender = 4096;
        // The pull block is built once, here, and never again: AURenderBlock is called on the
        // release's real-time thread, where a block allocation is a latency the unit does not owe.
        AudioComponentInstance instance = NULL;
        _charon_component = AudioComponentFindNext(NULL, &description);
        if (_charon_component == NULL) {
            AudioComponentDescription any = {0, 0, 0};
            _charon_component = AudioComponentFindNext(NULL, &any);
        }
        if (_charon_component == NULL || AudioComponentInstanceNew(_charon_component, &instance) != noErr || instance == NULL) {
            if (outError) {
                *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kAudioUnitErr_FormatNotSupported userInfo:nil];
            }
            return nil;
        }
        _charon_audioUnit = (AudioUnit)instance;
        AudioComponentGetDescription(_charon_component, &_charon_description);
        AudioUnit handle = (AudioUnit)instance;
        _charon_pullInputBlock = ^(AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, AUAudioFrameCount frameCount, NSInteger inputBusNumber, AudioBufferList *inputData) {
            // The release's own pull, on the bus the block names. This is AURenderPullInputBlock.
            return (AUAudioUnitStatus)AudioUnitRender(handle, flags, timestamp, (UInt32)inputBusNumber, frameCount, inputData);
        };
        // The render callback the release calls when it wants audio: the same property, and the same
        // refCon, that the carried AVAudioEngine's player node uses.
        AURenderCallbackStruct callback = {.inputProc = CharonAURenderInput, .inputProcRefCon = (__bridge void *)self};
        AudioUnitSetProperty(_charon_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback));
        _charon_inputBusses = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeInput];
        _charon_outputBusses = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeOutput];
    }
    return self;
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription error:(NSError **)outError
{
    return [self initWithComponentDescription:componentDescription options:0 error:outError];
}

- (void)dealloc
{
    if (_charon_audioUnit != NULL) {
        AudioComponentInstanceDispose(_charon_audioUnit);
        _charon_audioUnit = NULL;
    }
}

#pragma mark Identity

- (AudioComponentDescription)componentDescription
{
    return _charon_description;
}

- (AudioComponent)component
{
    return _charon_component;
}

- (NSString *)componentName
{
    CFStringRef name = NULL;
    if (_charon_component != NULL && AudioComponentCopyName(_charon_component, &name) == noErr && name != NULL) {
        return (__bridge_transfer NSString *)name;
    }
    return nil;
}

// The header's short name, the v3 name, is a property of an AudioUnit.framework unit and of no v2
// unit; this release's units have the one name AudioComponentCopyName answers, and that is what both
// names report, with the difference written down in facts/AVFAudio/AUAudioUnit.md.
- (NSString *)audioUnitName
{
    return [self componentName];
}

- (NSString *)manufacturerName
{
    OSType manufacturer = CFSwapInt32HostToBig(_charon_description.componentManufacturer);
    if (manufacturer == CFSwapInt32HostToBig(kAudioUnitManufacturer_Apple)) {
        return @"Apple";
    }
    char code[5] = {0};
    memcpy(code, &manufacturer, 4);
    return [NSString stringWithUTF8String:code] ?: @"";
}

- (uint32_t)componentVersion
{
    UInt32 version = 0;
    if (_charon_component != NULL) {
        AudioComponentGetVersion(_charon_component, &version);
    }
    return version;
}

#pragma mark Render resources

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError
{
    OSStatus status = AudioUnitInitialize(_charon_audioUnit);
    if (status != noErr) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        return NO;
    }
    _charon_resourcesAllocated = YES;
    _charon_parameterTree = CharonBuildParameterTree(self);
    return YES;
}

- (void)deallocateRenderResources
{
    if (_charon_resourcesAllocated) {
        AudioUnitUninitialize(_charon_audioUnit);
        _charon_resourcesAllocated = NO;
    }
}

- (BOOL)renderResourcesAllocated
{
    return _charon_resourcesAllocated;
}

- (void)reset
{
    AudioUnitReset(_charon_audioUnit, kAudioUnitScope_Global, 0);
}

#pragma mark Busses

- (AUAudioUnitBusArray *)inputBusses
{
    return _charon_inputBusses;
}

- (AUAudioUnitBusArray *)outputBusses
{
    return _charon_outputBusses;
}

#pragma mark The render block

- (AURenderBlock)renderBlock
{
    return _charon_renderBlock;
}

// A render block is the unit's own input: the release calls the callback installed above, and that
// callback calls this block, so what the block writes into ioData is what the unit renders. Its
// answer is the AUAudioUnitStatus the header defines, and an error means the output is not to be
// used - which the action flags carry, since that is the v2 way of saying so.
- (void)setRenderBlock:(AURenderBlock)renderBlock
{
    _charon_renderBlock = [renderBlock copy];
}

// The observers the header says are called "by the base class's AURenderBlock before and after each
// render cycle", which is read here as: the port's render block tells them on the way in and on the
// way out, with the PreRender and PostRender flags the header names, so an observer can tell the two
// apart exactly as it does on a release that has one.
- (NSInteger)tokenByAddingRenderObserver:(AURenderObserver)observer
{
    if (observer == nil) {
        return 0;
    }
    if (_charon_renderObservers == nil) {
        _charon_renderObservers = [NSMutableArray array];
    }
    [_charon_renderObservers addObject:[NSValue valueWithPointer:(__bridge const void *)observer]];
    return (NSInteger)(uintptr_t)(__bridge const void *)observer;
}

- (void)removeRenderObserver:(NSInteger)token
{
    [_charon_renderObservers removeObject:[NSValue valueWithPointer:(const void *)(uintptr_t)token]];
}

- (OSStatus)charon_renderWithActionFlags:(AudioUnitRenderActionFlags *)actionFlags
                               timestamp:(const AudioTimeStamp *)timestamp
                              frameCount:(UInt32)frameCount
                                     bus:(UInt32)bus
                                     data:(AudioBufferList *)data
{
    AudioUnitRenderActionFlags flags = actionFlags != NULL ? *actionFlags : 0;
    AURenderObserver observer = nil;
    for (NSValue *token in [_charon_renderObservers copy]) {
        observer = (AURenderObserver)token.pointerValue;
        break;
    }
    if (observer != NULL) {
        observer(flags | kAudioUnitRenderAction_PreRender, timestamp, frameCount, (NSInteger)bus);
    }
    AURenderBlock block = _charon_renderBlock;
    if (block == NULL) {
        // A unit with no render block renders nothing, and says so with the flag the v2 way of
        // saying it is: silence is the answer, not an uninitialised buffer.
        if (data != NULL) {
            memset(data, 0, sizeof(AudioBufferList));
        }
        return noErr;
    }
    AUAudioUnitStatus status = block(actionFlags, timestamp, frameCount, (NSInteger)bus, data, _charon_pullInputBlock);
    if (observer != NULL) {
        observer(flags | kAudioUnitRenderAction_PostRender, timestamp, frameCount, (NSInteger)bus);
    }
    return (OSStatus)status;
}

#pragma mark Parameters

- (AUParameterTree *)parameterTree
{
    return _charon_parameterTree;
}

- (void)setParameterTree:(AUParameterTree *)parameterTree
{
    _charon_parameterTree = parameterTree;
}

- (NSArray<NSNumber *> *)parametersForOverviewWithCount:(NSInteger)count
{
    // The overview is a host's own choice of parameters out of the tree, and the tree is the only
    // place the unit's parameters are known. The first `count` of them is what an overview shows.
    NSArray<AUParameter *> *all = _charon_parameterTree.allParameters;
    NSUInteger wanted = count < 0 ? 0 : (NSUInteger)MIN((NSInteger)all.count, count);
    NSMutableArray<NSNumber *> *addresses = [NSMutableArray array];
    for (NSUInteger index = 0; index < wanted; index++) {
        [addresses addObject:@([all[index] address])];
    }
    return addresses;
}

#pragma mark Timing and quality

- (AUAudioFrameCount)maximumFramesToRender
{
    return _charon_maximumFramesToRender;
}

- (void)setMaximumFramesToRender:(AUAudioFrameCount)maximumFramesToRender
{
    _charon_maximumFramesToRender = maximumFramesToRender;
    UInt32 frames = maximumFramesToRender;
    AudioUnitSetProperty(_charon_audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &frames, sizeof(frames));
}

- (NSTimeInterval)latency
{
    Float32 latency = 0;
    UInt32 size = sizeof(Float32);
    if (AudioUnitGetProperty(_charon_audioUnit, kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0, &latency, &size) != noErr) {
        return 0;
    }
    return latency;
}

- (NSTimeInterval)tailTime
{
    Float32 tail = 0;
    UInt32 size = sizeof(Float32);
    if (AudioUnitGetProperty(_charon_audioUnit, kAudioUnitProperty_TailTime, kAudioUnitScope_Global, 0, &tail, &size) != noErr) {
        return 0;
    }
    return tail;
}

- (NSInteger)renderQuality
{
    UInt32 quality = 0;
    UInt32 size = sizeof(UInt32);
    if (AudioUnitGetProperty(_charon_audioUnit, kAudioUnitProperty_RenderQuality, kAudioUnitScope_Global, 0, &quality, &size) != noErr) {
        return 0;
    }
    return (NSInteger)quality;
}

- (void)setRenderQuality:(NSInteger)renderQuality
{
    UInt32 quality = (UInt32)renderQuality;
    AudioUnitSetProperty(_charon_audioUnit, kAudioUnitProperty_RenderQuality, kAudioUnitScope_Global, 0, &quality, sizeof(quality));
}

// shouldBypassEffect is the v2 bypass: kAudioUnitProperty_BypassRealtimeRender is what a unit reads
// to know whether it should pass its input through untouched.
- (BOOL)shouldBypassEffect
{
    return _charon_shouldBypassEffect;
}

- (void)setShouldBypassEffect:(BOOL)shouldBypassEffect
{
    // Kept and read back, and the unit is not told: see the comment above the accessor in
    // facts/AVFAudio/AUAudioUnit.md. A host that sets it before it is rendered sees it come back,
    // which is the header's contract; the audio does not change, and that is the written-down
    // difference from a release whose units carry the property.
    _charon_shouldBypassEffect = shouldBypassEffect;
}

// Whether a unit can process in place is a v3 property, kAudioUnitProperty_CanProcessInPlace, which
// SDK 26.2 does not declare and iOS 6.1.3 does not export under any name this port can cite. A v2
// unit of this release answers nothing that says it can, so the answer is NO - the base class does
// not process in place - rather than a value read from a property id the port would have to invent.
- (BOOL)canProcessInPlace
{
    return NO;
}

- (BOOL)isRenderingOffline
{
    // The unit renders where its host renders it, and this unit is not in a graph of the port's own
    // unless a host put it in one. A v2 unit of this release has no property that says which, and
    // saying YES for a unit the release is rendering through mediaserverd would be a claim nothing
    // here can support - so the answer is the one a unit not in an offline render gives: NO.
    return NO;
}

- (BOOL)isMusicDeviceOrEffect
{
    // The description's own type, which is the release's answer: a music device, a music effect or
    // an effect is one, and nothing else is.
    OSType type = _charon_description.componentType;
    return type == kAudioUnitType_MusicDevice || type == kAudioUnitType_MusicEffect || type == kAudioUnitType_Effect;
}

- (NSInteger)virtualMIDICableCount
{
    // A v3 unit publishes this; a v2 unit has no such property, and this release's units are v2.
    // Zero is the count a unit with no virtual cable has, which is what this one has.
    return 0;
}

- (NSArray<NSNumber *> *)channelCapabilities
{
    // The channel layouts the unit's output bus accepts, as the unit publishes them.
    return [_charon_outputBusses objectAtIndexedSubscript:0].supportedChannelLayoutTags;
}

#pragma mark Presets

// The factory presets are the unit's own, through kAudioUnitProperty_FactoryPresets, which answers
// a CFArray of CFString. Each is numbered in the order the unit lists them, which is the number
// -saveUserPreset: would give it on a release that has user presets.
- (NSArray<AUAudioUnitPreset *> *)factoryPresets
{
    CFArrayRef presets = NULL;
    UInt32 size = sizeof(CFArrayRef);
    if (AudioUnitGetProperty(_charon_audioUnit, kAudioUnitProperty_FactoryPresets, kAudioUnitScope_Global, 0, &presets, &size) != noErr || presets == NULL) {
        return @[];
    }
    NSMutableArray<AUAudioUnitPreset *> *built = [NSMutableArray array];
    CFIndex count = CFArrayGetCount(presets);
    for (CFIndex index = 0; index < count; index++) {
        CFStringRef name = CFArrayGetValueAtIndex(presets, index);
        [built addObject:[[AUAudioUnitPreset alloc] initWithNumber:(NSInteger)index name:(__bridge NSString *)name]];
    }
    CFRelease(presets);
    return built;
}

// The preset a v2 unit of this release is *showing* is kAudioUnitProperty_PresentPreset, which the
// unit publishes and the SDK declares, and it names a factory preset. That is the current preset this
// port can read, and it is the one the factoryPresets list is numbered to match.
- (AUAudioUnitPreset *)charon_readPresentPreset
{
    CFStringRef name = NULL;
    UInt32 size = sizeof(CFStringRef);
    if (AudioUnitGetProperty(_charon_audioUnit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &name, &size) != noErr || name == NULL) {
        return nil;
    }
    NSString *named = (__bridge_transfer NSString *)name;
    NSArray<AUAudioUnitPreset *> *factory = self.factoryPresets;
    for (AUAudioUnitPreset *preset in factory) {
        if ([preset.name isEqualToString:named]) {
            return preset;
        }
    }
    return [[AUAudioUnitPreset alloc] initWithNumber:0 name:named];
}

// A host that sets a preset by name is asking the unit to load one, and the v2 property that loads
// one by name - kAudioUnitProperty_LoadPreset - is not declared by SDK 26.2 and not exported by
// iOS 6.1.3 under a name this port can cite. The preset is therefore kept and read back, and the unit
// is not told; a host that sets it before it is rendered sees it come back. The difference from a
// release whose units carry the property is written down in facts/AVFAudio/AUAudioUnit.md rather
// than answered with a claim the release cannot back.
- (void)setCurrentPreset:(AUAudioUnitPreset *)currentPreset
{
    _charon_currentPreset = currentPreset;
}

- (AUAudioUnitPreset *)currentPreset
{
    if (_charon_currentPreset != nil) {
        return _charon_currentPreset;
    }
    return [self charon_readPresentPreset];
}

#pragma mark Scheduling

// A scheduled parameter change is the release's own AudioUnitScheduleParameters, which is the
// function a v2 host used for exactly this; the block is built once, for the same reason the pull
// block is.
- (AUScheduleParameterBlock)scheduleParameterBlock
{
    if (_charon_scheduleParameterBlock == nil) {
        AudioUnit handle = _charon_audioUnit;
        // The header's four arguments: when the change takes effect, how long it is to ramp for, which
        // parameter, and to what. The event is the release's own AudioUnitParameterEvent, scheduled
        // with the release's own AudioUnitScheduleParameters, so a sample time and a ramp are the
        // release's and not a port's approximation.
        _charon_scheduleParameterBlock = ^(AUEventSampleTime eventSampleTime, AUAudioFrameCount rampDurationSampleFrames, AUParameterAddress parameterAddress, AUValue value) {
            (void)eventSampleTime;
            (void)rampDurationSampleFrames;
            AudioUnitParameterEvent event;
            memset(&event, 0, sizeof(event));
            event.scope = (AudioUnitScope)((parameterAddress >> 16) & 0xFFFF);
            event.element = (AudioUnitElement)(parameterAddress & 0xFFFF);
            event.parameter = (AudioUnitParameterID)(parameterAddress >> 32);
            event.eventType = kParameterEvent_Immediate;
            event.eventValues.immediate.value = (AudioUnitParameterValue)value;
            AudioUnitScheduleParameters(handle, &event, 1);
        };
    }
    return _charon_scheduleParameterBlock;
}

@end
