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

## Virtual endpoints on the emulated iPhone 4S at 6.1.3: which processes the release lets make them

Measured with `tests/backports/emulate/coremidi` (`xmake emulate -d iPhone4,1 -r 6.1.3`, time scale 10):

- A daemon (`/usr/libexec/charoncoremidi`, started by launchd, no bundle) is refused: the release's own `MIDISourceCreate`
  returns -10844 (kMIDINotPermitted), and so do this library's protocol endpoints. The round trip is FAIL (7 failures,
  `run.sh`). The guest's MIDIServer runs (it is spawned by launchd at boot).
- The same probe as an application (`run-app.sh`: an installed bundle, launched through SpringBoard) passes:
  `roundtrip: PASS (0 failures)`, `application exit: 0`; the control `MIDISourceCreate` answers 0.
- Isolated, for the application:
  - without an active audio session (no AudioSessionSetActive): still PASS. The audio session is not needed.
  - without `UIBackgroundModes` = `audio` in its Info.plist: refused (-10844 for the source, the destination and the control).
    The declared audio background mode is what the release checks.
- Not isolated: whether the daemon is refused for having no bundle, for not having the mode, or for running outside SpringBoard.
  The daemon has neither the mode nor a bundle, so the two cases are not separated; both are missing in the daemon.

So the emulated release can give virtual endpoints, to an application that declares the audio background mode. A port daemon
cannot make one. An in-process substitute is therefore not needed for an application; a daemon of the port that needs an
endpoint has to be an application with the mode (the BLE central, for one, lives in the application that loads the library).

The 2026-10-09 result of the daemon run is the record of the first refusal; the application run is the one that answers the
question. On macOS a command-line tool creates virtual endpoints (oracle/*.m), and the MIDI-CI discovery client is refused
(-10844) there, as the MIDI-CI facts say.

## Evidence

The translation rules and every measurement behind them are in facts/CoreMIDI/Translation.md; the event list rules are in
facts/CoreMIDI/EventList.md. The host differential that holds the library to macOS is `tests/backports/host/coremidi/run.sh`.
