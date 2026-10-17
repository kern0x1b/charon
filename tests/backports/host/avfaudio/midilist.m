// -[AVAudioUnitMIDIInstrument sendMIDIEventList:]: the list's type-2 words decoded and sent as MusicDeviceMIDIEvent.
//
// The oracle is the MIDI 1.0 bytes each UMP type-2 word encodes (status = bits 23-16, data1 = 15-8, data2 = 7-0),
// written out below by hand. It is not the host: the host's sendMIDIEvent:data1:data2: does not reach
// MusicDeviceMIDIEvent on this host (AVFAudio imports AUAudioUnit's MIDI path, and an interposer on
// MusicDeviceMIDIEvent sees nothing from it), so there is no host call to record. The recorder
// (midilist-record.c) takes the MusicDeviceMIDIEvent calls the decode makes, and the probe compares them to the bytes.
// The decode is the body of the port's method; the probe runs the same block the method runs.
//
// A word that is not a type-2 message is in the list too: nothing may be sent for it.
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMIDI/MIDIServices.h>
#include <stdio.h>
#include "../../../../packages/a/apple-backports/AVFAudio/CharonMIDIEventList.h"

extern unsigned charon_midi_count;
extern unsigned char charon_midi_record[256][3];

static int failures = 0;

// Seven type-2 messages, one of each channel voice kind on different channels, and a type-4 word between them.
static const UInt32 kWords[] = {
    0x20903C64,   // note on, channel 0, note 60, velocity 100:       90 3C 64
    0x40900000,   // type 4: skipped
    0x20833C00,   // note off, channel 3, note 60, velocity 0:       83 3C 00
    0x20B1077F,   // controller, channel 1, controller 7, value 127: B1 07 7F
    0x20E20040,   // pitch bend, channel 2, low 0, high 64:          E2 00 40
    0x20C50900,   // program change, channel 5, program 9:           C5 09 00
    0x20D42100,   // channel pressure, channel 4, 33:                D4 21 00
    0x20A74032,   // poly pressure, channel 7, key 64, value 50:     A7 40 32
};
static const unsigned char kExpected[][3] = {
    { 0x90, 0x3C, 0x64 }, { 0x83, 0x3C, 0x00 }, { 0xB1, 0x07, 0x7F }, { 0xE2, 0x00, 0x40 },
    { 0xC5, 0x09, 0x00 }, { 0xD4, 0x21, 0x00 }, { 0xA7, 0x40, 0x32 },
};

int main(void)
{
    @autoreleasepool {
        // The unit the method would send to. The recorder does not forward, so any non-NULL value does; a
        // sampler is what the port's method has in practice.
        AVAudioUnitSampler *sampler = [[AVAudioUnitSampler alloc] init];
        MusicDeviceComponent unit = (MusicDeviceComponent)sampler.audioUnit;

        Byte buffer[1024];
        MIDIEventList *list = (MIDIEventList *)buffer;
        MIDIEventPacket *packet = MIDIEventListInit(list, kMIDIProtocol_1_0);
        packet = MIDIEventListAdd(list, sizeof(buffer), packet, 0, 2, kWords);
        packet = MIDIEventListAdd(list, sizeof(buffer), packet, 0, 6, kWords + 2);

        charon_midi_count = 0;
        CharonForEachMIDI1Message(list, ^(uint8_t status, uint8_t data1, uint8_t data2) {
            MusicDeviceMIDIEvent(unit, status, data1, data2, 0);
        });
        unsigned expected = sizeof(kExpected) / sizeof(kExpected[0]);
        if (charon_midi_count != expected) {
            printf("FAIL messages: %u != %u\n", charon_midi_count, expected);
            failures++;
        }
        for (unsigned i = 0; i < expected && i < charon_midi_count; i++) {
            for (int b = 0; b < 3; b++) {
                if (charon_midi_record[i][b] != kExpected[i][b]) {
                    printf("FAIL message %u byte %d: %02X != %02X\n", i, b, charon_midi_record[i][b], kExpected[i][b]);
                    failures++;
                }
            }
        }

        // A list with no type-2 word sends nothing, and a NULL list sends nothing.
        Byte other[256];
        MIDIEventList *none = (MIDIEventList *)other;
        MIDIEventPacket *np = MIDIEventListInit(none, kMIDIProtocol_2_0);
        UInt32 type4 = 0x40900000;
        MIDIEventListAdd(none, sizeof(other), np, 0, 1, &type4);
        charon_midi_count = 0;
        CharonForEachMIDI1Message(none, ^(uint8_t s, uint8_t a, uint8_t b) { MusicDeviceMIDIEvent(unit, s, a, b, 0); });
        CharonForEachMIDI1Message(NULL, ^(uint8_t s, uint8_t a, uint8_t b) { MusicDeviceMIDIEvent(unit, s, a, b, 0); });
        if (charon_midi_count != 0) {
            printf("FAIL a list with no type-2 word sent %u\n", charon_midi_count);
            failures++;
        }

        printf("messages=%u checks=midi-list-bytes failures=%d\n", expected, failures);
    }
    return failures == 0 ? 0 : 1;
}
