// MIDIDeviceNewEntity, of iOS 14: adds an entity with a protocol to a device. macOS CoreMIDI answers paramErr and
// no entity for a device of 0, measured (oracle/newentity2.m); a device that exists is the release's own, and the entity
// is the release's (MIDIDeviceAddEntity). The protocol is written to the entity, as the port's choice: where macOS keeps
// it, and whether its endpoints read it, is not measured (facts/CoreMIDI/Devices.md; a crutch in coordination/crutches.md).
#import <CoreMIDI/CoreMIDI.h>

#import "CharonCoreMIDI.h"


// The protocol key, as MIDIProtocol14.m keeps it: the iOS SDK marks kMIDIPropertyProtocolID from iOS 14, so this file
// names the same string rather than use the constant.
static const CFStringRef charon_protocol_key = CFSTR("protocol");

OSStatus MIDIDeviceNewEntity(MIDIDeviceRef device, CFStringRef name, MIDIProtocolID protocol, Boolean embedded,
                             ItemCount numSourceEndpoints, ItemCount numDestinationEndpoints, MIDIEntityRef *newEntity)
{
    *newEntity = 0;
    if (device == 0 || (protocol != kMIDIProtocol_1_0 && protocol != kMIDIProtocol_2_0))
        return charon_paramErr;
    OSStatus status = MIDIDeviceAddEntity(device, name, embedded, numSourceEndpoints, numDestinationEndpoints, newEntity);
    if (status == noErr)
        MIDIObjectSetIntegerProperty(*newEntity, charon_protocol_key, (SInt32)protocol);
    return status;
}
