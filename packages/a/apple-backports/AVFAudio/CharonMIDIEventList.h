#import <CoreMIDI/MIDIServices.h>
#import <Foundation/Foundation.h>

// The list form of a MIDI send, for -[AVAudioUnitMIDIInstrument sendMIDIEventList:] (iOS 16).
//
// The list is Universal MIDI Packets: each word is a message whose type is in its top four bits. The
// release's only send for a channel message is MusicDeviceMIDIEvent, which takes the MIDI 1.0 status
// and its two data bytes, so the list is decoded to that and nothing else. A type-2 word (MIDI 1.0
// channel voice) is status = bits 23-16, data1 = bits 15-8, data2 = bits 7-0; every other message type
// is skipped, because the release has no call that could carry it. facts/AVFAudio/AVAudioUnitMIDI.md
// records that skip as the one difference from the list form.
static inline void CharonForEachMIDI1Message(const MIDIEventList *list, void (^send)(uint8_t status, uint8_t data1, uint8_t data2))
{
    if (list == NULL || send == nil) {
        return;
    }
    const MIDIEventPacket *packet = &list->packet[0];
    for (UInt32 p = 0; p < list->numPackets; p++) {
        for (UInt32 w = 0; w < packet->wordCount; w++) {
            UInt32 word = packet->words[w];
            if ((word >> 28) != 0x2) {
                continue;
            }
            send((uint8_t)(word >> 16), (uint8_t)(word >> 8), (uint8_t)word);
        }
        packet = MIDIEventPacketNext(packet);
    }
}
