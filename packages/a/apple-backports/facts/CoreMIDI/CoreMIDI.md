# CoreMIDI from iOS 9 to 14: blocks, properties and endpoints by protocol

iOS 9 gave CoreMIDI the block forms of its client and its ports, `MIDIClientCreateWithBlock`, `MIDIInputPortCreateWithBlock`
and `MIDIDestinationCreateWithBlock`, and iOS 14 gave it Universal MIDI Packets: the protocol-aware input ports, virtual
destinations and sources (`MIDIInputPortCreateWithProtocol`, `MIDIDestinationCreateWithProtocol`,
`MIDISourceCreateWithProtocol`), the lists those carry (`MIDIEventListInit`, `MIDIEventListAdd`, `MIDISendEventList`,
`MIDIReceivedEventList`) and the property that names an endpoint's protocol, `kMIDIPropertyProtocolID`. The release of this
port, iOS 6.1.3, has the function forms of the first and none of the second: its CoreMIDI is the one of iOS 4.2 and carries
MIDI 1.0 bytes only.

## What is built on what

- `MIDIClientCreateWithBlock` is the release's `MIDIClientCreate` with the block carried in its reference constant. The
  block is copied once and kept for as long as the client lives, which the release does not tell this library when it ends:
  the copy is not released (a bounded leak, one block per client, port or destination; logged in coordination/crutches.md). A NULL
  block is accepted and returns noErr, as macOS does (measured, oracle/nullargs.m: `0`). A protocol that is neither 1.0 nor
  2.0 answers `paramErr` here; macOS does not answer it, it terminates the process (measured, the same probe).
- `MIDIInputPortCreateWithBlock` and `MIDIDestinationCreateWithBlock` are the release's `MIDIInputPortCreate` and
  `MIDIDestinationCreate`, with the same carrying.
- The protocol-aware ports and endpoints are the release's own, with a read procedure of this library that converts the
  packets it receives to Universal MIDI Packets in the protocol asked for (facts/CoreMIDI/Translation.md). The protocol of a
  source or destination is kept as its `kMIDIPropertyProtocolID` property, which is a string key this release stores and
  reads with `MIDIObjectSetIntegerProperty`.
- `MIDISendEventList` and `MIDIReceivedEventList` convert the list to MIDI 1.0 packets and hand them to the release's
  `MIDISend` and `MIDIReceived`. A list that converts to no bytes is sent as nothing and answers `noErr`, as the
  function does for an empty list.
- The event list builders are a buffer this library fills (facts/CoreMIDI/EventList.md).

## Constants

Both string constants are the values macOS CoreMIDI gives them, read from the host's own framework by
`tests/backports/host/coremidi/differential.m` and recorded in `host/coremidi/oracle`:

- `kMIDIPropertyNameConfigurationDictionary` is `nameConfigurationDictionary` (iOS 13).
- `kMIDIPropertyProtocolID` is `protocol` (iOS 14).

## What is not built here

CoreMIDI of iOS 16 and 17 and the MIDI-CI and MIDI 2.0 endpoint classes of iOS 18 are not in this library yet: the UMP
sysex senders (`MIDISendUMPSysex`, `MIDISendUMPSysex8`), `MIDIEventListForEachEvent`, the Bluetooth driver calls, and the
MIDI-CI and `MIDIUMP*` classes. They stay missing in the registry until each is built.

## Evidence

The translation rules and every measurement behind them are in facts/CoreMIDI/Translation.md; the event list rules are in
facts/CoreMIDI/EventList.md. The host differential that holds the library to macOS is `tests/backports/host/coremidi/run.sh`.
