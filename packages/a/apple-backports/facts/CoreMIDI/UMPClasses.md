# MIDI-UMP and MIDI-CI device classes of iOS 18: what each answers

Nine classes of the iOS 18 surface are implemented in `CoreMIDI/MIDIUMP18.m` over the declarations in `CoreMIDI/CharonMIDIUMP18.h`
(transcribed from the 26.2 headers; the 16.4 SDK has none of them). Measured on macOS on 2026-10-09 by
`tests/backports/host/coremidi/oracle/umpclasses.m` and `umpclasses2.m` (recorded in `umpclasses-macos.txt` and
`umpclasses2-macos.txt`); differential-ump.m holds the port to the answers below.

Measured and held to the port:

- MIDICIDeviceManager.sharedInstance.discoveredCIDevices has no device: 0 on the measured host.
- MIDIUMPEndpointManager.sharedInstance.UMPEndpoints has no endpoint before one is made: 0.
- A MIDIUMPMutableEndpoint is made with a name, a device info, a product instance ID, a protocol and a destination callback.
  Made with protocol 2.0 it has both ends (a destination and a source), is disabled, and reports protocol 2.0 and its name.
  The endpoint manager lists it while it is disabled: 1.
- setName: answers YES and changes the name; setEnabled:YES answers YES and enables; registerFunctionBlocks:markAsStatic:error:
  answers YES, and the endpoint's functionBlocks then lists the block (count 1).
- A MIDIUMPMutableFunctionBlock is made for each group, direction and stream value tried (the groups 0 + 17 and 15 + 2 included,
  a total of 0 included): the header's validation is not what macOS does here. Its name, first group, groups and enabled state
  are the ones given.
- A function block not registered to an endpoint answers NO to setEnabled:, setName: and reconfigureWithFirstGroup:, as macOS does.
- MIDI2DeviceInfo keeps its manufacturer ID, family, model and revision, as given.

Measured, not reproduced by a class that the port cannot reach:

- MIDICIDevice and MIDIUMPCIProfile describe a device that a MIDI-CI transport discovers. The port has no transport, so no
  such object is ever made; the classes exist, answer what a device without these properties answers (no profile, no
  supported capability), and are never returned.

Choices not measured:

- A function block registered to an endpoint answers its setters YES; the registered case was not measured on macOS.
- An endpoint made with protocol 1.0 has one end of each kind as made with 2.0; only the protocol 2.0 case was measured.
- The protocol outside 1.0 and 2.0 answers nil, as the endpoint's initialiser does not accept it on macOS either (not
  measured; the port's choice).
- The endpoints the manager lists are kept for the life of the process and are never disposed: a bounded leak, logged in
  coordination/crutches.md.

Not implemented: a MIDI-CI discovery (the MIDICIDeviceManager's and the old discovery manager's handlers), which needs the MIDI-CI
transport and is described in facts/CoreMIDI/MIDICI.md.
