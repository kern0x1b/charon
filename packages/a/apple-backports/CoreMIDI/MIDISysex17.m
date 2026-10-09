// MIDIEventPacketSysexBytesForGroup, of iOS 17: the MIDI 1.0 bytes of the SysEx a packet of Universal MIDI Packets holds
// on one group. macOS CoreMIDI was measured for each part of a SysEx, and for the wrong group and a non-SysEx word
// (oracle/sysexbytes.m, sysexbytes-macos.txt, facts/CoreMIDI/Sysex.md): the bytes of a complete message are F0, the data
// and F7; a start is F0 and its data, a continue is its data alone, an end its data and F7; a group other than the
// packet's, or a word that is not SysEx, answers paramErr and no data.
#import <CoreMIDI/CoreMIDI.h>

#include <stdint.h>

// The MacErrors value of paramErr (-50), which the iOS SDK does not declare; see MIDIProtocol14.m.
static const OSStatus charon_paramErr = -50;

OSStatus MIDIEventPacketSysexBytesForGroup(const MIDIEventPacket *pkt, UInt8 groupIndex, CFDataRef *outData)
{
    *outData = NULL;
    if (groupIndex > 15 || pkt->wordCount < 2)
        return charon_paramErr;
    UInt32 first = pkt->words[0];
    if ((first >> 28) != 0x3 || ((first >> 24) & 0x0F) != groupIndex)
        return charon_paramErr;
    UInt8 bytes[64];
    CFIndex count = 0;
    for (UInt32 i = 0; i + 1 < pkt->wordCount; i += 2) {
        UInt32 word = pkt->words[i];
        if ((word >> 28) != 0x3 || ((word >> 24) & 0x0F) != groupIndex)
            break;
        UInt32 status = (word >> 20) & 0x0F;
        UInt32 n = (word >> 16) & 0x0F;
        UInt32 second = pkt->words[i + 1];
        UInt8 data[6] = {(UInt8)(word >> 8), (UInt8)word, (UInt8)(second >> 24), (UInt8)(second >> 16),
                         (UInt8)(second >> 8), (UInt8)second};
        if (n > 6)
            n = 6;
        if (status == 0x0 || status == 0x1)
            bytes[count++] = 0xF0;
        for (UInt32 k = 0; k < n && count < (CFIndex)sizeof(bytes) - 1; k++)
            bytes[count++] = data[k] & 0x7F;
        if (status == 0x0 || status == 0x3)
            bytes[count++] = 0xF7;
    }
    *outData = CFDataCreate(kCFAllocatorDefault, bytes, count);
    return *outData ? noErr : charon_paramErr;
}
