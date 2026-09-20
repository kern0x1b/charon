# Game controllers, mice and keyboards, iOS 7.0 to 14.5

The GameController framework came in iOS 7.0 with `GCController`, and in iOS 14.0 with
`GCMouse` and `GCKeyboard`. An application asks the class for the devices that are
attached, listens for the notifications that announce one, and reads the buttons of the
object it is given.

Source: GameController of the arm64 shared cache of iOS 12.0 -
`+[GCController controllers]` at `0x19e6883ec`, `+startWirelessControllerDiscoveryWithCompletionHandler:`
at `0x19e688e74`, its worker at `0x19e6888d0` and `+stopWirelessControllerDiscovery` at
`0x19e688e94` - and of the arm64e cache of iOS 16.0: `+[GCMouse mice]` at `0x1f0f6b99c`,
`+[GCMouse current]` at `0x1f0f6b8d0` and `+[GCKeyboard coalescedKeyboard]` at
`0x1f0fe3954`.

## What it is

Each class method asks a shared manager of the framework. `+controllers`, `+mice`,
`+current` and `+coalescedKeyboard` read the list, or the current device, that the
manager holds, which is empty, or nil, while nothing is attached. The discovery is a scan
object that is given the completion handler and started, and the handler is called when the
scan has ended; `+stopWirelessControllerDiscovery` stops the scan.

## Where iOS 6 differs

The release has no support for a game controller, a mouse or a keyboard reported through
these classes, no Bluetooth service that pairs one, and nothing that would announce it. So
what an application is told is what the framework tells it when nothing is attached: the
lists are empty, the current device is nil, and a scan ends at once with nothing found. The
handler of the scan is called once on the main queue; which queue the framework's own call
is made on was not read, and the main queue is the one an application that touches its
interface in the handler needs.

The notification names are there and are never posted. `shouldMonitorBackgroundEvents` keeps
the flag it is given and changes nothing.

No object of `GCController`, `GCMouse` or `GCKeyboard` is ever made, so the members of an
instance (the profiles, the motion, the battery, the light, the haptics, the player index, the
snapshot and the capture) are absent, and so are the classes of the profiles, the
elements and the snapshots, the inputs, the constants of their names and the functions of the
snapshot data. An application that reads the controller list gets nothing to read them from.
The rows are in `registry/GameController/`.
