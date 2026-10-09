// Host probe: MIDIEventPacketSysexBytesForGroup on macOS, for the packets the contract names: a complete SysEx, a start,
// a continue and an end, a SysEx on another group, and a non-SysEx word. Prints the status and the returned bytes.
#import <CoreMIDI/CoreMIDI.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

static void show(const char *tag, const MIDIEventPacket *packet, UInt8 group) {
    CFDataRef data = NULL;
    OSStatus status = MIDIEventPacketSysexBytesForGroup(packet, group, &data);
    printf("%-34s group=%u status=%d ", tag, group, (int)status);
    if (data) {
        printf("bytes=");
        const UInt8 *b = CFDataGetBytePtr(data);
        for (CFIndex i = 0; i < CFDataGetLength(data); i++) printf("%02X", b[i]);
        CFRelease(data);
    } else {
        printf("bytes=(null)");
    }
    printf("\n");
}

static void run(const char *tag, const UInt32 *words, int count, UInt8 group) {
    Byte buf[256];
    MIDIEventList *list = (MIDIEventList *)buf;
    MIDIEventPacket *p = MIDIEventListInit(list, kMIDIProtocol_2_0);
    MIDIEventListAdd(list, sizeof(buf), p, 0, count, words);
    show(tag, &list->packet[0], group);
}

int main(void) {
    UInt32 complete[] = {0x30030102u, 0x03000000u};
    UInt32 start[] = {0x30160102u, 0x03040506u};
    UInt32 cont[] = {0x30260708u, 0x090A0B0Cu};
    UInt32 end[] = {0x30310D00u, 0x00000000u};
    UInt32 emptyEnd[] = {0x30300000u, 0x00000000u};
    UInt32 midi2[] = {0x40903C00u, 0xFFFF0000u};
    run("complete 3 bytes", complete, 2, 0);
    run("complete 3 bytes, group 1", complete, 2, 1);
    run("start 6 bytes", start, 2, 0);
    run("continue 6 bytes", cont, 2, 0);
    run("end 1 byte", end, 2, 0);
    run("end 0 bytes", emptyEnd, 2, 0);
    run("midi 2.0 note on", midi2, 2, 0);
    run("complete, group 15", complete, 2, 15);
    return 0;
}
