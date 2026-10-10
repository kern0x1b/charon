# MIDIEventListInit and MIDIEventListAdd: the packet rules, measured

A MIDIEventList is a header of its protocol and its packet count, eight bytes, then packets. A packet is its time stamp
(eight bytes), its word count (four bytes) and its words (four bytes each). The next packet begins after the last word of
this one, which is what `MIDIEventPacketNext` computes. `MIDIEventListInit` sets the protocol, makes the count zero and
returns the first packet's place. `MIDIEventListAdd` takes the place where the next packet would begin, and returns the place
after what it wrote, or NULL when the words do not fit in the buffer the caller gave it.

Measured on macOS on 2026-10-09 (probe2 and probe3 in `tests/backports/host/coremidi/oracle/`, recorded in probe2-macos.txt and
probe3-macos.txt; the results are also written in `tests/backports/host/coremidi/differential.m` beside each check):

- Two adds with one time stamp make one packet, with the words of both in order (2 + 2 words make a packet of 4).
- An add with a time stamp different from the last packet's starts a new packet (time stamps 7, 8, 8 make two packets, of
  1 and 2 words).
- An add of zero words writes nothing: the count stays zero and the place is returned unchanged.
- A word count above 64 is kept whole: 65, 70 and 80 words in one packet are accepted. The 64 of the structure's own array
  is not a limit of the builder.
- The buffer is counted in bytes. A list of 40 bytes holds two one-word packets of different times, and five one-word
  words of one time: 8 for the header, 16 for a one-word packet, 4 for each word added to a packet already there. A list of
  64 bytes holds three one-word packets.
- The protocol the caller gives is kept in the header, whatever the words are; the builder does not check them.

`CharonCoreMIDI.c`'s `CharonMIDIEventListAdd` implements these rules, and the two API functions of
`MIDIEventList14.m` call it. The packets it writes are the ones `MIDISendEventList` and the protocol-aware ports read.
