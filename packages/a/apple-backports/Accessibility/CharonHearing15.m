//
//  CharonHearing15.m
//  Accessibility
//
//  The three hearing-device functions of 15.0, one object because one object carries the API of one
//  release. The declarations are the SDK's own - AXHearingUtilities.h is in the SDK this package compiles
//  against - so there is no Charon header for this group and nothing is transcribed here.
//
//  The device has no hearing-device hardware and no pairing to one, which is the answer all three give.
//  That is measured the same way the settings are: the Accessibility surface a release the port carries
//  holds is 310 AX-prefixed exports and every one is an AXS or kAXS preference name, with no hearing
//  device, no pairing and no Bluetooth audio-device symbol in it at all. So:
//

#import <Foundation/Foundation.h>
#import <Accessibility/Accessibility.h>
#import <objc/runtime.h>

// The pairing list. Empty is the true answer with nothing paired and not a nil standing in for it: a
// caller that iterates this gets zero devices, which is what it would get from a device with no hearing
// hardware, and a nil would make a caller treat the answer as a failure to ask.
NSArray<NSUUID *> *AXMFiHearingDevicePairedUUIDs(void)
{
    return @[];
}

// Which ear a hearing device streams to. With no device the answer is the enumeration's own no-device
// case, whose value is 0 - the header's first case, and the one a caller checks for before drawing a
// left/right indicator.
AXHearingDeviceEar AXMFiHearingDeviceStreamingEar(void)
{
    return AXHearingDeviceEarNone;
}

// Whether the device can stream in both directions at once. No, and the reason is the same one every
// other answer in this file has: there is no hearing device, so there is nothing that could stream in
// either direction.
BOOL AXSupportsBidirectionalAXMFiHearingDeviceStreaming(void)
{
    return NO;
}
