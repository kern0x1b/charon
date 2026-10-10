// The heap allocations the library's hot paths make, counted: the library's own malloc, calloc and realloc calls (run.sh renames
// them in CharonMIDIPorts.m and CharonCoreMIDI.c to the counting wrappers below), per operation, and the calls it makes to the
// release's property read. On a 4S (A5, 512 MB) every allocation on the read thread of the release or on an audio thread is
// a cost the release's own paths do not have: a short list is converted in stack storage, and only a list too big for it is
// allocated. The release's calls are stand-ins (no MIDI object is made): the port's read procedure is the one the library hands
// to MIDIInputPortCreate, called here with a packet list as the release would. Calls the frameworks make inside themselves (the
// copy of a block, the queue's continuation) are not the library's own calls and are not counted. Each line prints the counts;
// the same file is run against an earlier library (COREMIDI=<its folder>) for the "before" counts.
#import <CoreMIDI/CoreMIDI.h>
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#import "CharonCoreMIDI.h"

static int gFailures;
static long gMallocs;
static long gReads;

void *charon_count_malloc(size_t size)
{
    gMallocs++;
    return malloc(size);
}

void *charon_count_calloc(size_t count, size_t size)
{
    gMallocs++;
    return calloc(count, size);
}

void *charon_count_realloc(void *pointer, size_t size)
{
    gMallocs++;
    return realloc(pointer, size);
}

static MIDIReadProc gReadProc;
static void *gReadRefCon;
static int gDelivered;
static dispatch_semaphore_t gDeliveredSignal;

OSStatus charon_test_MIDIInputPortCreate(MIDIClientRef client, CFStringRef portName, MIDIReadProc readProc, void *refCon,
                                         MIDIPortRef *outPort)
{
    gReadProc = readProc;
    gReadRefCon = refCon;
    *outPort = 1;
    return noErr;
}

static MIDIReadProc gDestProc;

OSStatus charon_test_MIDIDestinationCreate(MIDIClientRef client, CFStringRef name, MIDIReadProc readProc, void *refCon,
                                           MIDIEndpointRef *outDest)
{
    gDestProc = readProc;
    *outDest = 2;
    return noErr;
}

// The properties the stand-in object holds: any key reads back what was written; an unwritten key is unknown.
static SInt32 gOwnerValue[8];
static int gOwnerSet[8];

OSStatus charon_test_MIDIObjectSetIntegerProperty(MIDIObjectRef object, CFStringRef propertyID, SInt32 value)
{
    if (object < 8 && propertyID && CFEqual(propertyID, CHARON_OWNER_KEY)) {
        gOwnerValue[object] = value;
        gOwnerSet[object] = 1;
    }
    return noErr;
}

OSStatus charon_test_MIDIObjectGetIntegerProperty(MIDIObjectRef object, CFStringRef propertyID, SInt32 *outValue)
{
    gReads++;
    if (object < 8 && propertyID && CFEqual(propertyID, CHARON_OWNER_KEY) && gOwnerSet[object]) {
        *outValue = gOwnerValue[object];
        return noErr;
    }
    return kMIDIUnknownProperty;
}

static int gSent;

OSStatus charon_test_MIDISend(MIDIPortRef port, MIDIEndpointRef dest, const MIDIPacketList *pktlist)
{
    gSent += (int)pktlist->numPackets;
    return noErr;
}

OSStatus charon_test_MIDIReceived(MIDIEndpointRef src, const MIDIPacketList *pktlist)
{
    gSent += (int)pktlist->numPackets;
    return noErr;
}

static void expect(int passed, const char *what, long allocations)
{
    printf("%s %s (%ld allocation(s), %ld property read(s))\n", passed ? "ok" : "FAIL", what, allocations, gReads);
    if (!passed)
        gFailures++;
}

int main(void)
{
    @autoreleasepool {
        gDeliveredSignal = dispatch_semaphore_create(0);
        MIDIPortRef port = 0;
        // A 2.0 input port with a block: the library's read procedure is registered with the release (the stand-in).
        OSStatus status = CharonMIDIInputPort(0, CFSTR("port"), kMIDIProtocol_2_0, &port, ^(const MIDIEventList *list, void *ref) {
            gDelivered += (int)list->numPackets;
        });
        if (status != noErr || !gReadProc) {
            printf("FAIL the library's input port was not registered with the release\n");
            return 1;
        }

        // The read callback of a list of three MIDI 1.0 packets: a note on, a controller, a channel pressure.
        Byte buffer[256];
        MIDIPacketList *packets = (MIDIPacketList *)buffer;
        MIDIPacket *packet = MIDIPacketListInit(packets);
        packet = MIDIPacketListAdd(packets, sizeof(buffer), packet, 1, 3, (const Byte[]){0x90, 0x3C, 0x7F});
        packet = MIDIPacketListAdd(packets, sizeof(buffer), packet, 2, 3, (const Byte[]){0xB0, 0x07, 0x64});
        MIDIPacketListAdd(packets, sizeof(buffer), packet, 3, 2, (const Byte[]){0xD0, 0x50});
        // The first list of a source makes the source's parser (the port's table of sources may grow: one allocation); the
        // lists after it make none.
        gMallocs = 0;
        gDelivered = 0;
        gReadProc(packets, gReadRefCon, (void *)1);
        long firstRead = gMallocs;
        expect(gDelivered == 3 && firstRead <= 1, "the first list of a source makes its parser", firstRead);
        gMallocs = 0;
        gReads = 0;
        gDelivered = 0;
        gReadProc(packets, gReadRefCon, (void *)1);
        long read = gMallocs;
        expect(gDelivered == 3 && read == 0 && gReads == 0,
               "a read callback of three short packets is converted without an allocation and without a property read", read);

        // A list too long for the stack storage still works, and allocates (the list, and the words past the stack words).
        static Byte big[4096];
        MIDIPacketList *bigList = (MIDIPacketList *)big;
        MIDIPacket *bigPacket = MIDIPacketListInit(bigList);
        for (int i = 0; i < 60; i++)
            bigPacket = MIDIPacketListAdd(bigList, sizeof(big), bigPacket, (MIDITimeStamp)(i + 1), 3, (const Byte[]){0x90, (Byte)i, 0x7F});
        gDelivered = 0;
        gMallocs = 0;
        gReadProc(bigList, gReadRefCon, (void *)1);
        expect(gDelivered == 60 && gMallocs > 0, "a list of sixty packets is converted whole (it needs the heap)", gMallocs);

        // A send of a short 2.0 list to an endpoint that is not this library's: converted to bytes in stack storage.
        Byte listBuffer[64];
        MIDIEventList *list = (MIDIEventList *)listBuffer;
        MIDIEventPacket *end = MIDIEventListInit(list, kMIDIProtocol_2_0);
        UInt32 words[2] = {0x40903C00u, 0x12340000u};
        CharonMIDIEventListAdd(list, sizeof(listBuffer), end, 0, 2, words);
        // The first send to an endpoint makes the endpoint's selection state (the table may grow: one allocation), and the
        // sends after it make none.
        gMallocs = 0;
        gReads = 0;
        gSent = 0;
        OSStatus sent = CharonMIDISend(0, 99, list);
        long firstSend = gMallocs;
        expect(sent == noErr && gSent == 1 && firstSend <= 1, "the first send to a release endpoint makes its selection state", firstSend);
        gMallocs = 0;
        gReads = 0;
        gSent = 0;
        sent = CharonMIDISend(0, 99, list);
        long send = gMallocs;
        expect(sent == noErr && gSent == 1 && send == 0 && gReads == 0,
               "a short 2.0 list sent to a release endpoint is converted without an allocation and without a property read", send);

        // The same list to a destination this library made: delivered verbatim on the queue, one allocation for the delivery.
        MIDIEndpointRef dest = 0;
        OSStatus destStatus = CharonMIDIDestination(0, CFSTR("dest"), kMIDIProtocol_2_0, &dest, ^(const MIDIEventList *received, void *ref) {
            gDelivered = (int)received->numPackets;
            dispatch_semaphore_signal(gDeliveredSignal);
        });
        gMallocs = 0;
        gReads = 0;
        gDelivered = 0;
        OSStatus inProcess = destStatus == noErr ? CharonMIDISend(0, dest, list) : destStatus;
        long delivery = gMallocs;
        int arrived = dispatch_semaphore_wait(gDeliveredSignal, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0;
        expect(inProcess == noErr && arrived && gDelivered == 1 && delivery == 1,
               "a list sent to the library's own destination is delivered with one allocation", delivery);
    }
    printf("allocations: %d failures\n", gFailures);
    return gFailures ? 1 : 0;
}
