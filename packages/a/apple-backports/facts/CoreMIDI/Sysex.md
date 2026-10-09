# SysEx of Universal MIDI Packets, as MIDI 1.0 bytes and as sends (iOS 17)

## MIDIEventPacketSysexBytesForGroup

The function returns the MIDI 1.0 bytes of the SysEx a packet holds on one group. Measured on macOS on 2026-10-09 by
`tests/backports/host/coremidi/oracle/sysexbytes.m` (recorded in `sysexbytes-macos.txt`), and held to the port by
differential.m (check_sysex_bytes_for_group, 8 answers):

- A complete message (status 0) is `F0`, the data and `F7`: `30030102 03000000` gives `F0 01 02 03 F7`.
- A start (status 1) is `F0` and its data, with no `F7`: `30160102 03040506` gives `F0 01 02 03 04 05 06`.
- A continue (status 2) is its data alone: `30260708 090A0B0C` gives `07 08 09 0A 0B 0C`.
- An end (status 3) is its data and `F7`: `30310D00` gives `0D F7`; an end of no data is `F7`.
- A group other than the packet's answers paramErr (-50) and no data. A word that is not SysEx does the same, and so does
  a group of 15 when the packet is on group 0.
- The result is a new CFData, which the caller releases.

The port reads the packet's first word and the SysEx messages that follow it on the same group, and stops at the first word
that is not a SysEx on that group. macOS was measured on single messages, which is what the contract asks for; a packet
with two SysEx messages is not measured.

## MIDISendUMPSysex and MIDISendUMPSysex8

Not built in this revision. The request is `MIDISysexSendRequestUMP` (destination, words, word count, complete, completion
procedure and its refcon, from the 26.2 header). A 1.0 destination carries SysEx7 only, so a SysEx8 send has no 1.0 form;
its measured answer on a 2.0 destination is the next measurement, and the in-process route for 2.0 endpoints depends on
the answer to the emulator question in CoreMIDI.md.
