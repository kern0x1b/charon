// The MIDI-UMP and MIDI-CI classes of iOS 18 that describe a device and its endpoints: MIDI2DeviceInfo, MIDIUMPFunctionBlock
// and its mutable form, MIDIUMPEndpoint and its mutable form (a client-created endpoint), MIDIUMPEndpointManager, MIDICIDevice,
// MIDIUMPCIProfile and MIDICIDeviceManager.
//
// What is measured on macOS (oracle/umpclasses.m and umpclasses2.m, recorded in umpclasses-macos.txt and
// umpclasses2-macos.txt, 2026-10-09): a client-created endpoint is made, is disabled until setEnabled:YES, returns YES to
// setName: and to registerFunctionBlocks:, and is listed by the endpoint manager while disabled; the manager lists no MIDI-CI
// devices and no endpoints it did not see made; a function block made with any of the group, direction and stream values
// tried is made; a function block not registered to an endpoint answers NO to its setters. Everything else here follows the
// header: a MIDI-CI device needs a MIDI-CI transport, which this port does not have, so no MIDI-CI device is ever listed and
// the classes that describe one are storage that nothing returns (their discovery is in facts/CoreMIDI/MIDICI.md).
#import <Foundation/Foundation.h>
#import "CharonCoreMIDI.h"
#import "CharonMIDIUMP18.h"

#include <pthread.h>

// One MIDI client for the endpoints this file makes, made on first use.
static MIDIClientRef charon_client(void)
{
    static MIDIClientRef client = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        MIDIClientCreate(CFSTR("charon-ump"), NULL, NULL, &client);
    });
    return client;
}

// The endpoints a client made, in the order they were made; the manager lists them, enabled or not.
static NSMutableArray *charon_endpoints(void)
{
    static NSMutableArray *endpoints;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        endpoints = [NSMutableArray array];
    });
    return endpoints;
}

@implementation MIDI2DeviceInfo {
    MIDI2DeviceManufacturer _manufacturerID;
    MIDIUInteger14 _family;
    MIDIUInteger14 _modelNumber;
    MIDI2DeviceRevisionLevel _revisionLevel;
}

- (instancetype)initWithManufacturerID:(MIDI2DeviceManufacturer)manufacturerID family:(MIDIUInteger14)family
                           modelNumber:(MIDIUInteger14)modelNumber revisionLevel:(MIDI2DeviceRevisionLevel)revisionLevel
{
    self = [super init];
    if (self) {
        _manufacturerID = manufacturerID;
        _family = family;
        _modelNumber = modelNumber;
        _revisionLevel = revisionLevel;
    }
    return self;
}

- (MIDI2DeviceManufacturer)manufacturerID { return _manufacturerID; }
- (MIDIUInteger14)family { return _family; }
- (MIDIUInteger14)modelNumber { return _modelNumber; }
- (MIDI2DeviceRevisionLevel)revisionLevel { return _revisionLevel; }

@end

// Set by the endpoint when it registers the block; not part of the public interface.
@interface MIDIUMPMutableFunctionBlock ()
- (void)charon_registeredWith:(MIDIUMPEndpoint *)endpoint;
@end

@implementation MIDIUMPFunctionBlock {
@protected
    NSString *_name;
    MIDIUMPFunctionBlockID _functionBlockID;
    MIDIUMPFunctionBlockDirection _direction;
    MIDIUMPGroupNumber _firstGroup;
    MIDIUInteger7 _totalGroupsSpanned;
    UInt8 _maxSysEx8Streams;
    MIDIUMPFunctionBlockMIDI1Info _MIDI1Info;
    MIDIUMPFunctionBlockUIHint _UIHint;
    BOOL _isEnabled;
}

- (NSString *)name { return _name; }
- (MIDIUMPFunctionBlockID)functionBlockID { return _functionBlockID; }
- (MIDIUMPFunctionBlockDirection)direction { return _direction; }
- (MIDIUMPGroupNumber)firstGroup { return _firstGroup; }
- (MIDIUInteger7)totalGroupsSpanned { return _totalGroupsSpanned; }
- (UInt8)maxSysEx8Streams { return _maxSysEx8Streams; }
- (MIDIUMPFunctionBlockMIDI1Info)MIDI1Info { return _MIDI1Info; }
- (MIDIUMPFunctionBlockUIHint)UIHint { return _UIHint; }
- (BOOL)isEnabled { return _isEnabled; }
- (MIDIUMPEndpoint *)UMPEndpoint { return nil; }
- (MIDICIDevice *)midiCIDevice { return nil; }

@end

@implementation MIDIUMPMutableFunctionBlock {
    __weak MIDIUMPEndpoint *_endpoint;
}

- (instancetype)initWithName:(NSString *)name direction:(MIDIUMPFunctionBlockDirection)direction firstGroup:(MIDIUMPGroupNumber)firstGroup
          totalGroupsSpanned:(MIDIUInteger7)totalGroupsSpanned maxSysEx8Streams:(MIDIUInteger7)maxSysEx8Streams
                    MIDI1Info:(MIDIUMPFunctionBlockMIDI1Info)MIDI1Info UIHint:(MIDIUMPFunctionBlockUIHint)UIHint
                   isEnabled:(BOOL)isEnabled
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _functionBlockID = 0;
        _direction = direction;
        _firstGroup = firstGroup;
        _totalGroupsSpanned = totalGroupsSpanned;
        _maxSysEx8Streams = maxSysEx8Streams;
        _MIDI1Info = MIDI1Info;
        _UIHint = UIHint;
        _isEnabled = isEnabled;
    }
    return self;
}

- (MIDIUMPEndpoint *)UMPEndpoint { return _endpoint; }

// A function block answers its setters once an endpoint has registered it; before that they answer NO, as macOS does.
- (BOOL)setEnabled:(BOOL)isEnabled error:(NSError **)error
{
    if (!_endpoint)
        return NO;
    _isEnabled = isEnabled;
    return YES;
}

- (BOOL)setName:(NSString *)name error:(NSError **)error
{
    if (!_endpoint)
        return NO;
    _name = [name copy];
    return YES;
}

- (BOOL)reconfigureWithFirstGroup:(MIDIUMPGroupNumber)firstGroup direction:(MIDIUMPFunctionBlockDirection)direction
                        MIDI1Info:(MIDIUMPFunctionBlockMIDI1Info)MIDI1Info UIHint:(MIDIUMPFunctionBlockUIHint)UIHint error:(NSError **)error
{
    if (!_endpoint)
        return NO;
    _firstGroup = firstGroup;
    _direction = direction;
    _MIDI1Info = MIDI1Info;
    _UIHint = UIHint;
    return YES;
}

// Set by the endpoint when it registers the block.
- (void)charon_registeredWith:(MIDIUMPEndpoint *)endpoint
{
    _endpoint = endpoint;
}

@end

@implementation MIDIUMPEndpoint {
@protected
    NSString *_name;
    MIDIProtocolID _MIDIProtocol;
    MIDIEndpointRef _MIDIDestination;
    MIDIEndpointRef _MIDISource;
    MIDI2DeviceInfo *_deviceInfo;
    NSString *_productInstanceID;
    NSArray *_functionBlocks;
}

- (NSString *)name { return _name; }
- (MIDIProtocolID)MIDIProtocol { return _MIDIProtocol; }
- (MIDIUMPProtocolOptions)supportedMIDIProtocols
{
    return _MIDIProtocol == kMIDIProtocol_2_0 ? (kMIDIUMPProtocolOptionsMIDI1 | kMIDIUMPProtocolOptionsMIDI2) : kMIDIUMPProtocolOptionsMIDI1;
}
- (MIDIEndpointRef)MIDIDestination { return _MIDIDestination; }
- (MIDIEndpointRef)MIDISource { return _MIDISource; }
- (MIDI2DeviceInfo *)deviceInfo { return _deviceInfo; }
- (NSString *)productInstanceID { return _productInstanceID; }
- (BOOL)hasStaticFunctionBlocks { return NO; }
- (BOOL)hasJRTSReceiveCapability { return NO; }
- (BOOL)hasJRTSTransmitCapability { return NO; }
- (MIDIUMPCIObjectBackingType)endpointType { return kMIDIUMPCIObjectBackingTypeVirtual; }
- (NSArray<MIDIUMPFunctionBlock *> *)functionBlocks { return _functionBlocks; }
- (void)setFunctionBlocks:(NSArray<MIDIUMPFunctionBlock *> *)functionBlocks { _functionBlocks = [functionBlocks copy]; }

@end

@implementation MIDIUMPMutableEndpoint {
    BOOL _enabled;
    NSArray *_mutableBlocks;
    MIDIReceiveBlock _callback;
}

- (instancetype)initWithName:(NSString *)name deviceInfo:(MIDI2DeviceInfo *)deviceInfo productInstanceID:(NSString *)productInstanceID
                MIDIProtocol:(MIDIProtocolID)MIDIProtocol destinationCallback:(MIDIReceiveBlock)destinationCallback
{
    if (MIDIProtocol != kMIDIProtocol_1_0 && MIDIProtocol != kMIDIProtocol_2_0)
        return nil;
    self = [super init];
    if (!self)
        return nil;
    _name = [name copy];
    _deviceInfo = deviceInfo;
    _productInstanceID = [productInstanceID copy];
    _MIDIProtocol = MIDIProtocol;
    _callback = [destinationCallback copy];
    _enabled = NO;
    _mutableBlocks = @[];
    _functionBlocks = @[];
    // The endpoint's two ends are the library's own protocol endpoints; with the release refusing a virtual endpoint
    // (facts/CoreMIDI/CoreMIDI.md) they cannot be made, and the initialiser answers nil.
    MIDIEndpointRef destination = 0, source = 0;
    OSStatus status = CharonMIDIDestination(charon_client(), (__bridge CFStringRef)name, MIDIProtocol, &destination, _callback);
    if (status != noErr)
        return nil;
    status = CharonMIDISource(charon_client(), (__bridge CFStringRef)name, MIDIProtocol, &source);
    if (status != noErr) {
        MIDIEndpointDispose(destination);
        return nil;
    }
    _MIDIDestination = destination;
    _MIDISource = source;
    @synchronized (charon_endpoints()) {
        [charon_endpoints() addObject:self];
    }
    return self;
}

- (NSArray<MIDIUMPMutableFunctionBlock *> *)mutableFunctionBlocks { return _mutableBlocks; }
- (void)setMutableFunctionBlocks:(NSArray<MIDIUMPMutableFunctionBlock *> *)mutableFunctionBlocks { _mutableBlocks = [mutableFunctionBlocks copy]; }
- (BOOL)isEnabled { return _enabled; }

// The name is the release's own name of the endpoint's two ends (kMIDIPropertyName): the server shows it, and the release
// answers it. An error of the release is returned, not swallowed.
- (BOOL)setName:(NSString *)name error:(NSError **)error
{
    OSStatus status = MIDIObjectSetStringProperty(_MIDIDestination, kMIDIPropertyName, (__bridge CFStringRef)name);
    if (status == noErr)
        status = MIDIObjectSetStringProperty(_MIDISource, kMIDIPropertyName, (__bridge CFStringRef)name);
    if (status != noErr) {
        if (error)
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        return NO;
    }
    _name = [name copy];
    return YES;
}

- (BOOL)registerFunctionBlocks:(NSArray<MIDIUMPMutableFunctionBlock *> *)functionBlocks markAsStatic:(BOOL)markAsStatic error:(NSError **)error
{
    for (MIDIUMPMutableFunctionBlock *block in functionBlocks)
        [block charon_registeredWith:self];
    _mutableBlocks = [functionBlocks copy];
    _functionBlocks = [functionBlocks copy];
    return YES;
}

- (BOOL)setEnabled:(BOOL)isEnabled error:(NSError **)error
{
    _enabled = isEnabled;
    return YES;
}

@end

@implementation MIDIUMPEndpointManager

+ (MIDIUMPEndpointManager *)sharedInstance
{
    static MIDIUMPEndpointManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = [[MIDIUMPEndpointManager alloc] init];
    });
    return manager;
}

- (NSArray<MIDIUMPEndpoint *> *)UMPEndpoints
{
    @synchronized (charon_endpoints()) {
        return [charon_endpoints() copy];
    }
}

@end

@implementation MIDICIDevice

- (MIDI2DeviceInfo *)deviceInfo { return nil; }
- (MIDICIMUID)MUID { return 0; }
- (BOOL)supportsProtocolNegotiation { return NO; }
- (BOOL)supportsProfileConfiguration { return NO; }
- (BOOL)supportsPropertyExchange { return NO; }
- (BOOL)supportsProcessInquiry { return NO; }
- (NSUInteger)maxSysExSize { return 0; }
- (NSUInteger)maxPropertyExchangeRequests { return 0; }
- (MIDICIDeviceType)deviceType { return kMIDICIDeviceTypeUnknown; }
- (NSArray<MIDIUMPCIProfile *> *)profiles { return @[]; }

@end

@implementation MIDIUMPCIProfile

- (NSString *)name { return nil; }
- (MIDICIProfileID)profileID { return (MIDICIProfileID){{0, 0, 0, 0, 0}}; }
- (MIDICIProfileType)profileType { return kMIDICIProfileTypeSingleChannel; }
- (MIDIUMPGroupNumber)groupOffset { return 0; }
- (MIDIChannelNumber)firstChannel { return 0; }
- (MIDIUInteger14)enabledChannelCount { return 0; }
- (MIDIUInteger14)totalChannelCount { return 0; }
- (BOOL)isEnabled { return NO; }

- (BOOL)setProfileState:(BOOL)isEnabled enabledChannelCount:(MIDIUInteger14)enabledChannelCount error:(NSError **)error
{
    return NO;
}

@end

@implementation MIDICIDeviceManager

+ (MIDICIDeviceManager *)sharedInstance
{
    static MIDICIDeviceManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = [[MIDICIDeviceManager alloc] init];
    });
    return manager;
}

// No MIDI-CI transport: no device is ever discovered on this port (macOS: none on the measured host).
- (NSArray<MIDICIDevice *> *)discoveredCIDevices { return @[]; }

@end
