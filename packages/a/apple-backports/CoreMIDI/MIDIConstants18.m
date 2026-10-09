// The MIDI-CI and MIDI-UMP keys and notifications of iOS 18, and kMIDIPropertyAssociatedEndpoint. The notification
// and key strings are the names themselves, as macOS CoreMIDI gives them (oracle/constants.m); the property constants
// are NULL there, as the framework has them (measured, the same probe), so they are NULL here: an application that
// reads one gets the answer macOS gives it, not a value of this port's choosing.
#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

const CFStringRef kMIDIPropertyAssociatedEndpoint = NULL;

NSString *const MIDICIDeviceObjectKey = @"MIDICIDeviceObjectKey";
NSString *const MIDICIProfileObjectKey = @"MIDICIProfileObjectKey";
NSString *const MIDIUMPEndpointObjectKey = @"MIDIUMPEndpointObjectKey";
NSString *const MIDIUMPFunctionBlockObjectKey = @"MIDIUMPFunctionBlockObjectKey";

NSString *const MIDICIDeviceWasAddedNotification = @"MIDICIDeviceWasAddedNotification";
NSString *const MIDICIDeviceWasRemovedNotification = @"MIDICIDeviceWasRemovedNotification";
NSString *const MIDICIProfileWasRemovedNotification = @"MIDICIProfileWasRemovedNotification";
NSString *const MIDICIProfileWasUpdatedNotification = @"MIDICIProfileWasUpdatedNotification";
NSString *const MIDIUMPEndpointWasAddedNotification = @"MIDIUMPEndpointWasAddedNotification";
NSString *const MIDIUMPEndpointWasRemovedNotification = @"MIDIUMPEndpointWasRemovedNotification";
NSString *const MIDIUMPEndpointWasUpdatedNotification = @"MIDIUMPEndpointWasUpdatedNotification";
NSString *const MIDIUMPFunctionBlockWasUpdatedNotification = @"MIDIUMPFunctionBlockWasUpdatedNotification";
