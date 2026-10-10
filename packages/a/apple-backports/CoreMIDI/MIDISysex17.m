// MIDIEventPacketSysexBytesForGroup, of iOS 17: the MIDI 1.0 bytes of the SysEx a packet of Universal MIDI Packets holds
// on one group. macOS CoreMIDI was measured for each part of a SysEx, and for the wrong group and a non-SysEx word
// (oracle/sysexbytes.m, sysexbytes-macos.txt, facts/CoreMIDI/Sysex.md): the bytes of a complete message are F0, the data
// and F7; a start is F0 and its data, a continue is its data alone, an end its data and F7; a group other than the
// packet's, or a word that is not SysEx, answers paramErr and no data.
#import <CoreMIDI/CoreMIDI.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#import "CharonCoreMIDI.h"

OSStatus MIDIEventPacketSysexBytesForGroup(const MIDIEventPacket *pkt, UInt8 groupIndex, CFDataRef *outData)
{
    *outData = NULL;
    if (groupIndex > 15 || pkt->wordCount < 2)
        return charon_paramErr;
    UInt32 first = pkt->words[0];
    if ((first >> 28) != 0x3 || ((first >> 24) & 0x0F) != groupIndex)
        return charon_paramErr;
    // Each two-word SysEx7 part holds at most six data bytes, with at most an F0 before and an F7 after: eight bytes.
    CFIndex capacity = (CFIndex)(pkt->wordCount / 2) * 8;
    CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, capacity);
    if (!data)
        return charon_memFullErr;
    CFDataSetLength(data, capacity);
    UInt8 *bytes = CFDataGetMutableBytePtr(data);
    CFIndex count = 0;
    for (UInt32 i = 0; i + 1 < pkt->wordCount; i += 2) {
        UInt32 word = pkt->words[i];
        if ((word >> 28) != 0x3 || ((word >> 24) & 0x0F) != groupIndex)
            break;
        UInt32 status = (word >> 20) & 0x0F;
        UInt32 n = (word >> 16) & 0x0F;
        UInt32 second = pkt->words[i + 1];
        UInt8 part[6] = {(UInt8)(word >> 8), (UInt8)word, (UInt8)(second >> 24), (UInt8)(second >> 16),
                         (UInt8)(second >> 8), (UInt8)second};
        if (n > 6)
            n = 6;
        if (status == 0x0 || status == 0x1)
            bytes[count++] = 0xF0;
        for (UInt32 k = 0; k < n; k++)
            bytes[count++] = part[k] & 0x7F;
        if (status == 0x0 || status == 0x3)
            bytes[count++] = 0xF7;
    }
    CFDataSetLength(data, count);
    *outData = data;
    return noErr;
}

// The release's completion of a MIDISendSysex this file queued: the UMP request is completed, and the bytes are released.
typedef struct charon_ump_send {
    MIDISysexSendRequest request;
    MIDISysexSendRequestUMP *umpRequest;
    UInt8 *bytes;
} charon_ump_send;

static void charon_ump_send_done(MIDISysexSendRequest *request)
{
    charon_ump_send *send = request->completionRefCon;
    MIDISysexSendRequestUMP *umpRequest = send->umpRequest;
    free(send->bytes);
    free(send);
    umpRequest->complete = YES;
    if (umpRequest->completionProc)
        umpRequest->completionProc(umpRequest);
}

// Sends the words of a UMP request, as macOS does: the words go to the destination unchanged, the request's word count is
// used up, it is marked complete, and its completion procedure is called. A destination this process made gets the words
// verbatim; another destination (the release's, which carries MIDI 1.0 only) gets the SysEx7 messages as MIDI 1.0 bytes, and
// a SysEx8 has no 1.0 form, so it is not sent to one. The answer is noErr whatever the destination, as macOS answers.
static OSStatus charon_send_ump(MIDISysexSendRequestUMP *umpRequest)
{
    if (!umpRequest)
        return charon_paramErr;
    UInt32 count = umpRequest->wordsToSend;
    int queued = 0;
    if (count > 0 && umpRequest->words && !CharonMIDIDeliverInProcess(umpRequest->destination, umpRequest->words, count)) {
        CharonMIDIRPN rpn[16];
        memset(rpn, 0, sizeof(rpn));
        CharonMIDIBytes bytes;
        memset(&bytes, 0, sizeof(bytes));
        CharonMIDIUMPToBytes(umpRequest->words, count, rpn, &bytes);
        if (bytes.count > 0 && !bytes.failed) {
            charon_ump_send *send = calloc(1, sizeof(charon_ump_send));
            if (send) {
                send->umpRequest = umpRequest;
                send->bytes = bytes.bytes;
                send->request.destination = umpRequest->destination;
                send->request.data = send->bytes;
                send->request.bytesToSend = (UInt32)bytes.count;
                send->request.completionProc = charon_ump_send_done;
                send->request.completionRefCon = send;
                bytes.bytes = NULL;
                if (MIDISendSysex(&send->request) == noErr) {
                    queued = 1;
                } else {
                    free(send->bytes);
                    free(send);
                }
            }
        }
        free(bytes.bytes);
    }
    umpRequest->wordsToSend = 0;
    if (!queued) {
        umpRequest->complete = YES;
        if (umpRequest->completionProc)
            umpRequest->completionProc(umpRequest);
    }
    return noErr;
}

OSStatus MIDISendUMPSysex(MIDISysexSendRequestUMP *umpRequest)
{
    return charon_send_ump(umpRequest);
}

OSStatus MIDISendUMPSysex8(MIDISysexSendRequestUMP *umpRequest)
{
    return charon_send_ump(umpRequest);
}
