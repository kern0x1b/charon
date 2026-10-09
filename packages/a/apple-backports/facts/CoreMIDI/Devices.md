# MIDIDeviceNewEntity, as an application sees it

MIDIDeviceNewEntity (iOS 14) adds an entity to a device. An application cannot make a device: MIDIDeviceCreate takes a
driver interface, and with NULL it answers paramErr (-50), measured on macOS (oracle/newentity.m, newentity-macos.txt).
So the devices an application can name are the setup's own.

Measured on macOS: MIDIDeviceNewEntity with device 0 answers -50 and leaves the entity at 0 (oracle/newentity2.m,
newentity2-macos.txt). With the first device of the setup it answered noErr. That call changed the host's MIDI setup
(an entity was added to a device of this machine); the probe was run once, and the change was not reverted.

The port answers device 0 with paramErr and no entity, as macOS does. A device that exists is the release's own; the
entity is added by the release's MIDIDeviceAddEntity, and its protocol is kept as the endpoint property the protocol API
reads. A protocol other than 1.0 and 2.0 answers paramErr; macOS was not measured for it.
