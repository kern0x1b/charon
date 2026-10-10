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
  block is copied once and kept for as long as the client lives. The release does not tell this library when the client ends,
  so the copy is released when the object is found gone: the rows of CharonMIDIPorts.m are swept whenever the library makes
  another object, and a client that answers paramErr to a UniqueID read is gone (below). A NULL
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

## Disposed objects (macOS 27.0.1, oracle/removal-notify.m, removal-notify-macos.txt)

- A destination, a virtual source and an input port that are disposed answer a UniqueID read with paramErr (-50), as a
  reference that never existed does. A live destination or source answers noErr; a live input port answers -10835 (a
  port has no UniqueID). So a reference that answers -50 is gone. The status is the OSStatus of the read; the UniqueID
  value is meaningful only with noErr.
- A destination's and a source's removal is announced to the client's notify proc as kMIDIMsgObjectRemoved, after the dispose
  call has returned, on the main thread, followed by kMIDIMsgSetupChanged. An input port's dispose announces nothing.
- A send to a disposed destination delivers nothing to its block (0 calls; the live control gives 1).
- Measured on the emulated 6.1.3 (tests/backports/emulate/coremidi/app/main.m, built with CHARCOREMIDI_PROBE=1; the status of
  each read, the value only with noErr): a live client -10835 (it has no UniqueID), a live destination 0 and a live virtual
  source 0, a live input port -10835; each of the four after its dispose -50. The same answers as macOS where macOS was
  measured (a client's liveness was not measured on macOS: its dispose is only seen in the host differential, where the block
  a client held is released once the library has swept it). A destination's reference after a dispose was not reused by the
  next destination in the one run (first 372756, second 372757, with the references of the run before them in sequence).
- The removal notification is the other way the release says an object is gone, and it is measured on 6.1.3 too (the same
  probe): a destination (childType 3), a source (childType 2) and an entity (childType 1) post kMIDIMsgObjectRemoved to a
  client's notify proc, on the main run loop, and the release posts it to a client made after the object was disposed as well
  (all six removals of the run reached the one client that listened). An input port and a client announce nothing: the
  port (ref 372753) and the first client (372750) were disposed in that run and none of the six notifications names them, as an
  input port's dispose announces nothing on macOS. The library keeps the UniqueID sweep
  because it covers the objects the notification does not, and a second channel for the destinations and sources would only
  bring the release of a block forward to the moment of the dispose, which needs a client of the library's own and a running
  main run loop; neither is needed for the sweep.
- The owned row also keeps the UniqueID its object had when it was made, so a reference the release gives to a new object after
  a dispose is not taken for the old one (CharonMIDIPorts.m, charon_row_stale).
- The library learns of a dispose only by the read above, when it makes another object: the release gives it no call for a
  dispose, and the notification above goes to a client's notify proc, not to the library.

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
