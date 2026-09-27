#import "CharonAUAudioUnit.h"

@implementation AUParameter {
    CharonAUParameterImpl *_charon;
}

// The value of a parameter is the unit's, not this object's: it is read with AudioUnitGetParameter
// and written with AudioUnitSetParameter, both exported by AudioToolbox on iOS 6.1.3. That is what
// makes an AUParameter change what the unit renders rather than only what a caller reads back.
- (AUValue)value
{
    if (_charon.owner == nil || _charon.owner.audioUnit == NULL) {
        return _charon.minValue;
    }
    AudioUnitParameterValue value = 0;
    if (AudioUnitGetParameter(_charon.owner.audioUnit, _charon.identifier, _charon.scope, _charon.element, &value) != noErr) {
        return _charon.minValue;
    }
    return (AUValue)value;
}

- (void)setValue:(AUValue)value
{
    [self setValue:value originator:NULL];
}

- (void)setValue:(AUValue)value originator:(AUParameterObserverToken)originator
{
    [self charon_apply:value originator:originator atHostTime:0 eventType:AUParameterAutomationEventTypeValue automate:NO];
}

// A value set with a host time is a scheduled change: AudioUnitScheduleParameters (exported by
// AudioToolbox on iOS 6.1.3) is the release's own scheduling path, so a host time that has not come
// yet really has not taken effect yet, and one that has really has.
- (void)setValue:(AUValue)value originator:(AUParameterObserverToken)originator atHostTime:(uint64_t)hostTime
{
    [self charon_apply:value originator:originator atHostTime:hostTime eventType:AUParameterAutomationEventTypeValue automate:hostTime != 0];
}

- (void)charon_apply:(AUValue)value
           originator:(AUParameterObserverToken)originator
           atHostTime:(uint64_t)hostTime
            eventType:(AUParameterAutomationEventType)eventType
            automate:(BOOL)automate
{
    AUAudioUnit *owner = _charon.owner;
    if (automate && owner != nil && owner.audioUnit != NULL) {
        AudioUnitParameterEvent event;
        memset(&event, 0, sizeof(event));
        event.scope = _charon.scope;
        event.element = _charon.element;
        event.parameter = _charon.identifier;
        event.eventType = kParameterEvent_Immediate;
        event.eventValues.immediate.value = (AudioUnitParameterValue)value;
        AudioUnitScheduleParameters(owner.audioUnit, &event, 1);
        // The unit takes the value at the host time it was given, and the observers hear of the
        // change now, which is what a host that moved a control expects.
        AURecordedParameterEvent recorded = {
            .hostTime = hostTime,
            .address = self.address,
            .value = value,
        };
        AUParameterAutomationEvent automated = {
            .hostTime = hostTime,
            .address = self.address,
            .value = value,
            .eventType = eventType,
            .reserved = 0,
        };
        [self charon_notifyValue:value atAddress:self.address];
        [self charon_notifyRecording:1 events:&recorded];
        [self charon_notifyAutomation:1 events:&automated];
        return;
    }
    if (owner != nil && owner.audioUnit != NULL) {
        AudioUnitParameterValue written = (AudioUnitParameterValue)value;
        AudioUnitSetParameter(owner.audioUnit, _charon.identifier, _charon.scope, _charon.element, written, 0);
    }
    // The observer whose own token is the originator is the one that made this change; the header
    // says the token can be passed to -setValue:originator: for exactly that, and a host that moves a
    // control does not want its own observer called back for the move it just made.
    if (originator != NULL) {
        for (NSValue *token in [self charon_observerTokens]) {
            if (token.pointerValue == (const void *)originator) {
                return;
            }
        }
    }
    [self charon_notifyValue:value atAddress:self.address];
}

- (AUValue)minValue
{
    return _charon.minValue;
}

- (AUValue)maxValue
{
    return _charon.maxValue;
}

- (AudioUnitParameterUnit)unit
{
    return _charon.unit;
}

- (NSString *)unitName
{
    return _charon.unitName;
}

- (AudioUnitParameterOptions)flags
{
    return _charon.flags;
}

- (AUParameterAddress)address
{
    return CharonAddress(_charon.identifier, _charon.scope, _charon.element);
}

- (NSArray<NSString *> *)valueStrings
{
    return _charon.valueStrings;
}

- (NSArray<NSNumber *> *)dependentParameters
{
    return _charon.dependentParameters;
}

// A discrete parameter is one the unit names the values of; its strings are the unit's own, so
// stringFromValue: is the string at that index and valueFromString: the index of that string. A
// continuous parameter has no such list, and the header's own shape for a parameter without one is a
// number written out of the value itself.
- (NSString *)stringFromValue:(const AUValue *)value
{
    AUValue wanted = value != NULL ? *value : self.value;
    if (_charon.valueStrings.count > 0) {
        NSInteger index = (NSInteger)llround(wanted);
        if (index >= 0 && index < (NSInteger)_charon.valueStrings.count) {
            return _charon.valueStrings[index];
        }
        return nil;
    }
    return [NSString stringWithFormat:@"%g", (double)wanted];
}

- (AudioUnitParameterID)charon_identifier
{
    return _charon.identifier;
}

- (AudioUnitScope)charon_scope
{
    return _charon.scope;
}

- (AudioUnitElement)charon_element
{
    return _charon.element;
}

- (AUValue)valueFromString:(NSString *)string
{
    if (_charon.valueStrings.count > 0) {
        NSUInteger index = [_charon.valueStrings indexOfObject:string];
        return index == NSNotFound ? _charon.minValue : (AUValue)index;
    }
    return (AUValue)string.doubleValue;
}

#pragma mark NSSecureCoding

// The header declares NSSecureCoding on the class, so a parameter survives an archive: the v2
// coordinates, the range and the unit go in, and reading them back asks the same unit for the same
// parameter, which is the only source of the rest.
+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:(NSInteger)_charon.identifier forKey:@"identifier"];
    [coder encodeInteger:(NSInteger)_charon.scope forKey:@"scope"];
    [coder encodeInteger:(NSInteger)_charon.element forKey:@"element"];
    [coder encodeFloat:_charon.minValue forKey:@"minValue"];
    [coder encodeFloat:_charon.maxValue forKey:@"maxValue"];
    [coder encodeObject:_charon.unitName forKey:@"unitName"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        _charon = [CharonAUParameterImpl new];
        _charon.identifier = (AudioUnitParameterID)[coder decodeIntegerForKey:@"identifier"];
        _charon.scope = (AudioUnitScope)[coder decodeIntegerForKey:@"scope"];
        _charon.element = (AudioUnitElement)[coder decodeIntegerForKey:@"element"];
        _charon.minValue = [coder decodeFloatForKey:@"minValue"];
        _charon.maxValue = [coder decodeFloatForKey:@"maxValue"];
        _charon.unitName = [coder decodeObjectForKey:@"unitName"];
    }
    return self;
}

@end

// The tree a real unit publishes, built by asking it. AudioUnitGetPropertyInfo with
// kAudioUnitProperty_ParameterInfo answers how many parameters there are and describes each one; the
// address, range, unit, flags, value strings and dependent parameters all come from that answer, so
// nothing here is a value the port chose.
AUParameterTree *CharonBuildParameterTree(AUAudioUnit *owner)
{
    AudioUnit unit = owner.audioUnit;
    if (unit == NULL) {
        return nil;
    }
    NSMutableArray<AUParameterNode *> *parameters = [NSMutableArray array];
    // The v2 walk: kAudioUnitProperty_ParameterInfo is a property whose element is the parameter's
    // index, and a unit answers an error for the index past its last parameter. iOS 6.1.3 exports no
    // AudioUnitGetParameterInfo - the whole AudioUnit family it carries is the twenty-seven functions
    // enumerated in facts/AVFAudio/AUAudioUnitParameter.md - so AudioUnitGetProperty is the only way
    // in, and it is the way a v2 host of that release did it.
    for (AudioUnitElement index = 0; index < 4096; index++) {
        CharonAudioUnitParameterInfo info;
        memset(&info, 0, sizeof(info));
        UInt32 size = (UInt32)sizeof(info);
        if (AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterInfo, kAudioUnitScope_Global, index, &info, &size) != noErr || size < sizeof(info)) {
            break;
        }
        CharonAUParameterImpl *impl = [CharonAUParameterImpl new];
        // Two names, kept apart: the fixed 52-byte C string in the struct is the parameter's
        // identifier, which is what a key path and a KVC key are made of, and its index in the walk
        // is the v2 parameter id, which is what an address is made of.
        impl.name = [NSString stringWithUTF8String:info.name] ?: [NSString stringWithFormat:@"%u", (unsigned)index];
        impl.identifier = index;
        impl.scope = kAudioUnitScope_Global;
        impl.element = 0;
        impl.minValue = info.minValue;
        impl.maxValue = info.maxValue;
        impl.unit = info.unit;
        impl.flags = info.flags;
        impl.owner = owner;
        if (info.unitName != NULL) {
            impl.unitName = (__bridge_transfer NSString *)info.unitName;
        }
        NSString *display = [NSString stringWithUTF8String:info.name];
        if (info.cfNameString != NULL) {
            display = (__bridge_transfer NSString *)info.cfNameString;
            if (info.flags & kAudioUnitParameterFlag_CFNameRelease) {
                CFRelease(info.cfNameString);
            }
        }
        AUParameter *parameter = [[AUParameter alloc] charon_parameterWithImpl:impl];
        // The unit's published name is the parameter's display name and its identifier at once - the
        // C string is the only name the v2 format carries - and the localized name, when the unit
        // publishes one, is the display name.
        [parameter charon_setIdentifier:impl.name];
        [parameter charon_setDisplayName:display];
        [parameters addObject:parameter];
    }
    if (parameters.count == 0) {
        return nil;
    }
    AUParameterTree *tree = [[AUParameterTree alloc] initWithCharonChildren:parameters];
    [tree charon_setIdentifier:@""];   // the root's own identifier, empty as the header's own
    for (AUParameterNode *child in parameters) {
        [child charon_setParent:tree keyPath:child.identifier];
    }
    return tree;
}
