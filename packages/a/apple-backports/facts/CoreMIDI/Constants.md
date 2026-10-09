# The UMP and MIDI-CI constants of CoreMIDI, iOS 17 and 18

The constants of iOS 17 (`kMIDIPropertyUMPActiveGroupBitmap`, `kMIDIPropertyUMPCanTransmitGroupless`) and iOS 18
(`kMIDIPropertyAssociatedEndpoint`, the MIDI-CI and MIDI-UMP object keys and notification names) are read from the
host's own CoreMIDI by `tests/backports/host/coremidi/oracle/constants.m`, and the differential
(`tests/backports/host/coremidi/differential.m`, check_constants) holds the port's copies to those readings.

Measured on macOS, 2026-10-09:

- The twelve keys and notifications are their own names: `MIDICIDeviceObjectKey` is `MIDICIDeviceObjectKey`, and so on.
- `kMIDIPropertyUMPActiveGroupBitmap`, `kMIDIPropertyUMPCanTransmitGroupless` and `kMIDIPropertyAssociatedEndpoint` read
  as NULL through the linked symbol. The port's copies are NULL, so an application that reads one gets what macOS gives.
- A dlsym read of the same three gave the same NULL, but the dlsym read is not trusted here: the same read gave NULL for
  `kMIDIPropertyProtocolID`, which the linked read gives as `protocol`. The linked read is the one an application sees.

Release: `MIDIConstants17.m` holds the two UMP property constants, `MIDIConstants18.m` the rest, so each file defines the
API of one release.
