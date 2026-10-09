// The MIDI-CI 1.x classes of iOS 12: the device information a MIDI-CI device reports, a profile, the state of a profile's
// channel, and the session a discovered device opens. Measured on macOS (oracle/micicapability.m, micicapability-macos.txt,
// 2026-10-09): a device info is made with a real destination and manufacturer 3, family 2, model 2 and revision 4 bytes, and
// is refused (nil) with a manufacturer of 2 bytes, a revision of 1 byte, or no destination. A session needs a discovered
// device, which this port never has (facts/CoreMIDI/MIDICI.md), so its initialiser answers nil for the nil node it can be given.
#import "CharonMIDICI.h"

@implementation MIDICIDeviceInfo {
    NSData *_manufacturerID;
    NSData *_family;
    NSData *_modelNumber;
    NSData *_revisionLevel;
    MIDIEntityRef _midiDestination;
}

- (instancetype)initWithDestination:(MIDIEntityRef)midiDestination manufacturer:(NSData *)manufacturer family:(NSData *)family
                              model:(NSData *)modelNumber revision:(NSData *)revisionLevel
{
    if (midiDestination == 0 || manufacturer.length != 3 || family.length != 2 || modelNumber.length != 2 || revisionLevel.length != 4)
        return nil;
    self = [super init];
    if (self) {
        _midiDestination = midiDestination;
        _manufacturerID = [manufacturer copy];
        _family = [family copy];
        _modelNumber = [modelNumber copy];
        _revisionLevel = [revisionLevel copy];
    }
    return self;
}

- (NSData *)manufacturerID { return _manufacturerID; }
- (NSData *)family { return _family; }
- (NSData *)modelNumber { return _modelNumber; }
- (NSData *)revisionLevel { return _revisionLevel; }
- (MIDIEntityRef)midiDestination { return _midiDestination; }

@end

@implementation MIDICIProfile {
    NSString *_name;
    NSData *_profileID;
}

- (instancetype)initWithData:(NSData *)data name:(NSString *)inName
{
    if (!data)
        return nil;
    self = [super init];
    if (self) {
        _profileID = [data copy];
        _name = [inName copy];
    }
    return self;
}

- (NSString *)name { return _name; }
- (NSData *)profileID { return _profileID; }

@end

@implementation MIDICIProfileState {
    MIDIChannelNumber _midiChannel;
    NSArray<MIDICIProfile *> *_enabledProfiles;
    NSArray<MIDICIProfile *> *_disabledProfiles;
}

- (instancetype)initWithChannel:(MIDIChannelNumber)midiChannelNum enabledProfiles:(NSArray<MIDICIProfile *> *)enabled
               disabledProfiles:(NSArray<MIDICIProfile *> *)disabled
{
    self = [super init];
    if (self) {
        _midiChannel = midiChannelNum;
        _enabledProfiles = [enabled copy];
        _disabledProfiles = [disabled copy];
    }
    return self;
}

- (MIDIChannelNumber)midiChannel { return _midiChannel; }
- (NSArray<MIDICIProfile *> *)enabledProfiles { return _enabledProfiles; }
- (NSArray<MIDICIProfile *> *)disabledProfiles { return _disabledProfiles; }

@end

@implementation MIDICISession {
    MIDICIDiscoveredNode *_node;
    MIDICISessionDisconnectBlock _disconnectHandler;
    MIDICIProfileChangedBlock _profileChangedCallback;
    MIDICIProfileSpecificDataBlock _profileSpecificDataHandler;
}

@synthesize profileChangedCallback = _profileChangedCallback;
@synthesize profileSpecificDataHandler = _profileSpecificDataHandler;

- (instancetype)initWithDiscoveredNode:(MIDICIDiscoveredNode *)discoveredNode dataReadyHandler:(void (^)(void))handler
                     disconnectHandler:(MIDICISessionDisconnectBlock)disconnectHandler
{
    if (!discoveredNode)
        return nil;
    self = [super init];
    if (self) {
        _node = discoveredNode;
        _disconnectHandler = [disconnectHandler copy];
    }
    return self;
}

- (MIDIEntityRef)midiDestination { return _node.destination; }
- (BOOL)supportsProfileCapability { return _node.supportsProfiles; }
- (BOOL)supportsPropertyCapability { return _node.supportsProperties; }
- (MIDICIDeviceInfo *)deviceInfo { return _node.deviceInfo; }
- (NSNumber *)maxSysExSize { return _node.maximumSysExSize; }
- (NSNumber *)maxPropertyRequests { return @0; }

- (MIDICIProfileState *)profileStateForChannel:(MIDIChannelNumber)channel
{
    return [[MIDICIProfileState alloc] initWithChannel:channel enabledProfiles:@[] disabledProfiles:@[]];
}

// No MIDI-CI transport: the session cannot send a profile change, so the change is refused with no error detail.
- (BOOL)enableProfile:(MIDICIProfile *)profile onChannel:(MIDIChannelNumber)channel error:(NSError **)outError { return NO; }
- (BOOL)disableProfile:(MIDICIProfile *)profile onChannel:(MIDIChannelNumber)channel error:(NSError **)outError { return NO; }

@end
