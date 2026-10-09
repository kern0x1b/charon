# MIDIDeviceNewEntity, as an application sees it

MIDIDeviceNewEntity (iOS 14) adds an entity to a device. An application cannot make a device: MIDIDeviceCreate takes a
driver interface, and with NULL it answers paramErr (-50), measured on macOS (oracle/newentity.m, newentity-macos.txt).
So the devices an application can name are the setup's own.

Measured on macOS: MIDIDeviceNewEntity with device 0 answers -50 and leaves the entity at 0 (oracle/newentity.m). With the
first device of the setup it answered noErr (oracle/newentity2.m, newentity2-macos.txt). That call changed the host's MIDI
setup: it added an entity "x" (protocol 1, no sources or destinations) to the device "Network".

Revert (2026-10-10): the entity was removed with MIDIDeviceRemoveEntity, the public call that undoes an add. The setup read
back with a read-only enumerator now equals the capture taken after the revert; the only difference from the capture taken
before it is the removed entity. No capture exists from before the probes, so the pre-probe state is inferred from the
probe's single mutating call. The Bluetooth driver's "activate all devices" flag (1) has no baseline and is not reverted;
see coordination/wave-2026-10-03/v-coremidi-report.md, "Host state".

Rule for every probe: no probe creates or edits a persistent host MIDI object (devices, entities, endpoints, setup
preferences). A probe may create virtual endpoints only if it disposes them in the same process. oracle/newentity2.m is
kept for the record and must not be run.

The port answers device 0 with paramErr and no entity, as macOS does. A device that exists is the release's own; the
entity is added by the release's MIDIDeviceAddEntity, and its protocol is kept as the endpoint property the protocol API
reads. A protocol other than 1.0 and 2.0 answers paramErr; macOS was not measured for it.
