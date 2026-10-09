// The iOS 18 classes, held to macOS (oracle/umpclasses.m and umpclasses2.m, recorded in umpclasses-macos.txt and
// umpclasses2-macos.txt). The names are the renamed ones run.sh gives the port's objects. This file is its own translation
// unit: the 26.2 typedefs of the MIDI-UMP headers would clash with the visitor's on the host (differential.m).
#import <Foundation/Foundation.h>
#include <stdio.h>
#include "CharonMIDIUMP18.h"
#include "CharonCoreMIDI.h"
#include "CharonMIDICI.h"

static int gUMPChecks;
static int gUMPFailures;

static void check(int passed, const char *name, const char *detail)
{
    gUMPChecks++;
    if (passed) {
        printf("ok %s\n", name);
    } else {
        gUMPFailures++;
        printf("FAIL %s: %s\n", name, detail);
    }
}

// The MIDI-CI 1.x classes, held to macOS (oracle/micicapability.m, micicapability-macos.txt).
static void check_mici_classes(void)
{
    charon_host_MIDICIDiscoveryManager *manager = [charon_host_MIDICIDiscoveryManager sharedInstance];
    __block int handlerCalls = 0;
    [manager discoverWithHandler:^(NSArray *nodes) { handlerCalls++; }];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
    check(handlerCalls == 0, "MIDI-CI discovery: the handler is never called, as macOS (refused client)", "");

    // A device info needs a destination and the four fixed sizes: manufacturer 3, family 2, model 2, revision 4 bytes.
    MIDIClientRef client = 0;
    MIDIClientCreateWithBlock(CFSTR("ci-check"), &client, NULL);
    MIDIEndpointRef destination = 0;
    CharonMIDIDestination(client, CFSTR("ci-destination"), kMIDIProtocol_2_0, &destination, ^(const MIDIEventList *l, void *r) {});
    NSData *man3 = [NSData dataWithBytes:"\x01\x02\x03" length:3], *man2 = [NSData dataWithBytes:"\x01\x02" length:2];
    NSData *fam2 = [NSData dataWithBytes:"\x04\x05" length:2], *mod2 = [NSData dataWithBytes:"\x06\x07" length:2];
    NSData *rev4 = [NSData dataWithBytes:"\x0a\x0b\x0c\x0d" length:4], *rev1 = [NSData dataWithBytes:"\x0a" length:1];
    charon_host_MIDICIDeviceInfo *info = [[charon_host_MIDICIDeviceInfo alloc] initWithDestination:destination manufacturer:man3
                                                                                              family:fam2 model:mod2 revision:rev4];
    check(info != nil && info.family.length == 2 && info.modelNumber.length == 2, "MIDI-CI device info made with 3/2/2/4 bytes, as macOS", "");
    check([[charon_host_MIDICIDeviceInfo alloc] initWithDestination:destination manufacturer:man2 family:fam2 model:mod2 revision:rev4] == nil,
          "MIDI-CI device info refused for a 2-byte manufacturer, as macOS", "");
    check([[charon_host_MIDICIDeviceInfo alloc] initWithDestination:destination manufacturer:man3 family:fam2 model:mod2 revision:rev1] == nil,
          "MIDI-CI device info refused for a 1-byte revision, as macOS", "");
    check([[charon_host_MIDICIDeviceInfo alloc] initWithDestination:0 manufacturer:man3 family:fam2 model:mod2 revision:rev4] == nil,
          "MIDI-CI device info refused for no destination, as macOS", "");

    // A profile made from the standard profile bytes is named from them, as macOS names it.
    charon_host_MIDICIProfile *profile = [[charon_host_MIDICIProfile alloc] initWithData:[NSData dataWithBytes:"\x7e\x00\x01\x02\x03" length:5]];
    check(profile != nil && [profile.name isEqualToString:@"Standard Profile Bank 0x00 Number 0x01, Version: 0x02 Level: 0x03"] &&
          profile.profileID.length == 5, "MIDI-CI profile named from its standard bytes, as macOS", "");

    // A responder with no profile delegate is not made, as macOS.
    check([[charon_host_MIDICIResponder alloc] initWithDeviceInfo:info profileDelegate:nil profileStates:@[] supportProperties:NO] == nil,
          "MIDI-CI responder with no delegate is not made, as macOS", "");
}

static void check_ump_classes(void)
{
    // The managers list no MIDI-CI device and, before anything is made, no endpoint.
    check([[charon_host_MIDICIDeviceManager sharedInstance] discoveredCIDevices].count == 0,
          "MIDI-CI: no device discovered, as macOS (umpclasses-macos.txt)", "");
    check([[charon_host_MIDIUMPEndpointManager sharedInstance] UMPEndpoints].count == 0,
          "UMP: no endpoint listed before one is made, as macOS", "");

    // A value object keeps what it was given.
    MIDI2DeviceManufacturer man = {{0x12, 0x34, 0x56}};
    MIDI2DeviceRevisionLevel rev = {{0x03, 0x04, 0x05, 0x06}};
    charon_host_MIDI2DeviceInfo *info = [[charon_host_MIDI2DeviceInfo alloc] initWithManufacturerID:man family:0x1234
                                                                                       modelNumber:0x0102 revisionLevel:rev];
    check(info.manufacturerID.sysExIDByte[2] == 0x56 && info.family == 0x1234 && info.modelNumber == 0x0102 &&
          info.revisionLevel.revisionLevel[3] == 0x06,
          "MIDI2DeviceInfo keeps its values, as macOS prints them", "");

    // A function block is made with any group, direction and stream values macOS was asked for, and answers NO to
    // its setters until an endpoint registers it.
    charon_host_MIDIUMPMutableFunctionBlock *fb = [[charon_host_MIDIUMPMutableFunctionBlock alloc]
        initWithName:@"fb" direction:kMIDIUMPFunctionBlockDirectionInput firstGroup:0 totalGroupsSpanned:1
        maxSysEx8Streams:0 MIDI1Info:kMIDIUMPFunctionBlockMIDI1InfoNotMIDI1 UIHint:kMIDIUMPFunctionBlockUIHintUnknown isEnabled:YES];
    check(fb != nil && [fb.name isEqualToString:@"fb"] && fb.firstGroup == 0 && fb.totalGroupsSpanned == 1 && fb.isEnabled,
          "function block made with the values macOS gives (umpclasses-macos.txt)", "");
    check(![fb setEnabled:YES error:NULL] && ![fb setName:@"x" error:NULL],
          "function block not registered: setters answer NO, as macOS (umpclasses2-macos.txt)", "");
    check(fb.UMPEndpoint == nil, "function block not registered has no endpoint", "");

    // A client-made endpoint is made disabled, is listed while disabled, and takes the setters macOS answers YES to.
    charon_host_MIDI2DeviceInfo *endpointInfo = info;
    charon_host_MIDIUMPMutableEndpoint *ep = [[charon_host_MIDIUMPMutableEndpoint alloc] initWithName:@"ep" deviceInfo:endpointInfo
        productInstanceID:@"pid" MIDIProtocol:kMIDIProtocol_2_0 destinationCallback:^(const MIDIEventList *list, void *ref) {}];
    check(ep != nil, "client endpoint made (macOS: created, umpclasses-macos.txt)", "");
    if (ep) {
        check(!ep.isEnabled && ep.MIDIProtocol == kMIDIProtocol_2_0 && [ep.name isEqualToString:@"ep"] &&
              ep.MIDIDestination != 0 && ep.MIDISource != 0, "client endpoint: disabled, protocol 2.0, named, has both ends", "");
        check([[charon_host_MIDIUMPEndpointManager sharedInstance] UMPEndpoints].count == 1,
              "the manager lists the disabled client endpoint, as macOS (umpclasses2-macos.txt: 1)", "");
        check([ep setName:@"renamed" error:NULL] && [ep.name isEqualToString:@"renamed"],
              "endpoint setName answers YES, as macOS", "");
        check([ep setEnabled:YES error:NULL] && ep.isEnabled, "endpoint setEnabled:YES answers YES, as macOS", "");
        check([ep registerFunctionBlocks:@[fb] markAsStatic:NO error:NULL] && ep.functionBlocks.count == 1,
              "endpoint registers a block and lists it, as macOS", "");
    }
}

int charon_ump_classes_run(int *checks)
{
    @autoreleasepool {
        check_mici_classes();
        check_ump_classes();
    }
    *checks = gUMPChecks;
    return gUMPFailures;
}
