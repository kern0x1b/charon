// The route of a reused endpoint reference (review r4 F4). A route keeps the parameter a 2.0 sender last selected on each channel,
// and a 1.0 translation of the next RPN on that channel sends the two selecting controllers only when the parameter differs. A new
// endpoint that the release gives a reference an old endpoint held must not inherit that selection, so the library drops the route
// when it makes the row for the reference (charon_own). The release is stood in for the calls CharonMIDIPorts.m makes to it (run.sh
// renames those calls in CharonMIDIPorts.m to the charon_test_ functions below): the destination the library makes takes the reference the test chooses,
// the owner stamp is kept per reference, and the 1.0 send of a route is recorded instead of sent. Nothing is linked from the
// release for these calls.
//
// The expectations are the answers macOS gave in oracle/probe2-macos.txt (lines 2 to 5, one destination): the first RPN a
// destination is sent selects its parameter (controllers 101 and 100) before the data entry (6); the same parameter sent again on
// the same destination is the data entry alone. A new destination is a new endpoint, so its first RPN selects again.
#import <CoreMIDI/CoreMIDI.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

#import "CharonCoreMIDI.h"

static int gFailures;

// The reference the stand-in gives the next destination: the test chooses it, as the release gives a reference again.
static MIDIEndpointRef gNextDestination = 2;

OSStatus charon_test_MIDIDestinationCreate(MIDIClientRef client, CFStringRef name, MIDIReadProc readProc, void *refCon,
                                           MIDIEndpointRef *outDest)
{
    *outDest = gNextDestination;
    return noErr;
}

// The owner stamp of each reference, as the library writes and reads it. Any other key is unknown to the stand-in.
#define REFERENCES 64
static SInt32 gOwnerValue[REFERENCES];
static int gOwnerSet[REFERENCES];

OSStatus charon_test_MIDIObjectSetIntegerProperty(MIDIObjectRef object, CFStringRef propertyID, SInt32 value)
{
    if (object < REFERENCES && propertyID && CFEqual(propertyID, CHARON_OWNER_KEY)) {
        gOwnerValue[object] = value;
        gOwnerSet[object] = 1;
    }
    return noErr;
}

OSStatus charon_test_MIDIObjectGetIntegerProperty(MIDIObjectRef object, CFStringRef propertyID, SInt32 *outValue)
{
    if (object < REFERENCES && propertyID && CFEqual(propertyID, CHARON_OWNER_KEY) && gOwnerSet[object]) {
        *outValue = gOwnerValue[object];
        return noErr;
    }
    return kMIDIUnknownProperty;
}

// The 1.0 bytes the last send of a route carried, and the reference it was sent to.
static unsigned char gBytes[256];
static size_t gByteCount;
static MIDIEndpointRef gSentTo;

OSStatus charon_test_MIDISend(MIDIPortRef port, MIDIEndpointRef dest, const MIDIPacketList *pktlist)
{
    gSentTo = dest;
    const MIDIPacket *packet = &pktlist->packet[0];
    for (UInt32 i = 0; i < pktlist->numPackets; i++) {
        for (UInt16 k = 0; k < packet->length && gByteCount < sizeof(gBytes); k++)
            gBytes[gByteCount++] = packet->data[k];
        packet = MIDIPacketNext(packet);
    }
    return noErr;
}

// One RPN of channel 0, parameter 0,0 (bank 0, index 0), with the given 32-bit value, sent to the destination as a 2.0 list.
static OSStatus send_rpn(MIDIEndpointRef dest, UInt32 value)
{
    uint8_t storage[64] __attribute__((aligned(8)));
    MIDIEventList *list = (MIDIEventList *)storage;
    MIDIEventPacket *end = MIDIEventListInit(list, kMIDIProtocol_2_0);
    UInt32 words[2] = {0x40200000u, value};
    CharonMIDIEventListAdd(list, sizeof(storage), end, 0, 2, words);
    gByteCount = 0;
    gSentTo = 0;
    return CharonMIDISend((MIDIPortRef)1, dest, list);
}

static void expect_bytes(const unsigned char *expected, size_t count, MIDIEndpointRef dest, const char *what)
{
    int passed = gSentTo == dest && gByteCount == count && memcmp(gBytes, expected, count) == 0;
    printf("%s %s: sent to %u, bytes", passed ? "ok  " : "FAIL", what, (unsigned int)gSentTo);
    for (size_t i = 0; i < gByteCount; i++)
        printf(" %02X", gBytes[i]);
    printf("\n");
    if (!passed)
        gFailures++;
}

static void expect(int passed, const char *what)
{
    printf("%s %s\n", passed ? "ok  " : "FAIL", what);
    if (!passed)
        gFailures++;
}

static const unsigned char kSelectAndData1[] = {0xB0, 0x65, 0x00, 0xB0, 0x64, 0x00, 0xB0, 0x06, 0x01};
static const unsigned char kDataOnly2[] = {0xB0, 0x06, 0x02};
static const unsigned char kSelectAndData3[] = {0xB0, 0x65, 0x00, 0xB0, 0x64, 0x00, 0xB0, 0x06, 0x03};

static MIDIReceiveBlock noBlock = ^(const MIDIEventList *list, void *refCon) {
};

int main(void)
{
    @autoreleasepool {
        // A 1.0 destination of this library at reference 5: a 2.0 list sent to it is translated by its route and sent to the reference.
        MIDIEndpointRef first = 0;
        gNextDestination = 5;
        expect(CharonMIDIDestination(0, CFSTR("first"), kMIDIProtocol_1_0, &first, noBlock) == noErr && first == 5,
               "the library makes a 1.0 destination at reference 5");
        expect(send_rpn(5, 1u << 25) == noErr, "the first RPN is sent to the destination");
        expect_bytes(kSelectAndData1, sizeof(kSelectAndData1), 5,
                     "the first RPN of a destination selects its parameter, then sends its data (macOS, probe2 line 3)");
        // The control: the same parameter on the same destination is the data entry alone, so the selection is kept while the
        // destination is the same. A dropped route would show here as the selection sent again.
        expect(send_rpn(5, 2u << 25) == noErr, "the same parameter is sent again to the same destination");
        expect_bytes(kDataOnly2, sizeof(kDataOnly2), 5,
                     "the same parameter again on the same destination sends its data alone (macOS, probe2 line 5)");
        // The release gives reference 5 to a new destination of this library: the old destination's selection must not be inherited.
        MIDIEndpointRef second = 0;
        gNextDestination = 5;
        expect(CharonMIDIDestination(0, CFSTR("second"), kMIDIProtocol_1_0, &second, noBlock) == noErr && second == 5,
               "the release gives reference 5 to a new destination, which the library makes");
        expect(send_rpn(5, 3u << 25) == noErr, "the first RPN is sent to the new destination");
        expect_bytes(kSelectAndData3, sizeof(kSelectAndData3), 5,
                     "the new destination's first RPN selects its parameter: the old route's selection is not inherited");
    }
    printf("%s\n", gFailures ? "reuse: FAIL" : "reuse: ok");
    return gFailures ? 1 : 0;
}
