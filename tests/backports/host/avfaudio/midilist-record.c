// Records each MusicDeviceMIDIEvent call made while the process runs: the status, data1 and data2 the call was given.
// Interposed through DYLD_INSERT_LIBRARIES (midilist.sh), so the host's own sendMIDIEvent: and the port's list decode
// both write here, and the probe compares the two. The call is not forwarded: there is no unit behind it to forward to.
#include <AudioToolbox/MusicDevice.h>

unsigned charon_midi_count = 0;
unsigned char charon_midi_record[256][3];

static OSStatus charon_record_MusicDeviceMIDIEvent(MusicDeviceComponent unit, UInt32 status, UInt32 data1, UInt32 data2, UInt32 offset)
{
    (void)unit;
    (void)offset;
    if (charon_midi_count < 256) {
        charon_midi_record[charon_midi_count][0] = (unsigned char)status;
        charon_midi_record[charon_midi_count][1] = (unsigned char)data1;
        charon_midi_record[charon_midi_count][2] = (unsigned char)data2;
    }
    charon_midi_count++;
    return noErr;
}

__attribute__((used)) static const struct { const void *replacement; const void *original; } charon_interposers[]
    __attribute__((section("__DATA,__interpose"))) = {
    { (const void *)charon_record_MusicDeviceMIDIEvent, (const void *)MusicDeviceMIDIEvent },
};
