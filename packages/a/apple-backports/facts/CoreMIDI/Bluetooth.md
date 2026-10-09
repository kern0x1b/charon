# The Bluetooth LE MIDI driver calls (iOS 16), over CoreBluetooth

`MIDIBluetoothDriverActivateAllConnections()` and `MIDIBluetoothDriverDisconnect(uuid)` return `OSStatus`. Measured on
macOS on 2026-10-09 (`tests/backports/host/coremidi/oracle/bluetooth.m`, `bluetooth-macos.txt`): the activation answers 0,
and so does a disconnect of an identifier that is not connected, and of an empty string. The port answers noErr to both.

What the port does:

- The central is a CoreBluetooth `CBCentralManager` (CoreBluetooth is in the 6.1.3 cache: `CBCentralManager`,
  `CBPeripheral`, `CBUUID`, `CBCharacteristic`, measured with tools/corpus/cache-exports.lua). The 4S has Bluetooth 4.0.
- Activation starts the central's scan for the BLE MIDI service `03B80E5A-EDE8-4B33-A751-6CE34EC4C700` once the radio is on,
  and connects to each device found. It reads the MIDI I/O characteristic `7772E5DB-3868-4112-A1A9-F2669D106BF3` and
  subscribes to it.
- Each BLE MIDI packet's header and timestamp bytes are dropped and its MIDI bytes are received by a virtual source the
  central makes for the device, through the release's MIDISourceCreate and MIDIReceived.
- Disconnect cancels the peripheral with that identifier.

What is not established:

- The virtual source depends on the release allowing a process one (see CoreMIDI.md). In the emulator the release refuses
  it (kMIDINotPermitted); then the device connects, its bytes are dropped, and the central logs the refusal. On a device
  the release may allow it; that is not measured here.
- The emulated 4S has no Bluetooth, so no BLE device was seen. The scan, connect and characteristic code is compiled for
  the iOS 16.4 SDK at iOS 6.0 and is not run.
- A timestamp byte and a real-time byte that follows it cannot be told apart by the byte alone: a real-time byte followed
  by a timestamp is dropped. The rule is the BLE MIDI specification's reading, not measured on a device.
- "Paired" devices: the central connects to any device advertising the service once activated, and keeps no list of paired
  devices across launches. macOS keeps such a list in the system's Bluetooth settings; that store is not reproduced.
