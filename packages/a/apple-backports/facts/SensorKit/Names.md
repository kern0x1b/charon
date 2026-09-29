# The names of SensorKit that arrived in iOS 14.0

39 names in one object: the 29 device-usage category keys of `SRDeviceUsageCategories.h:15-44` and
the ten `extern SRSensor const` of the same release. They are declared in
SensorKit.framework/Headers/SRAbsoluteTime.h and its neighbours in the SDK 16.4 this package compiles
against, and the release has no SensorKit at all, so a program that names one has a symbol nothing
provides.

**Every value was read out of the host's own SensorKit** and none was written from memory, by
`tests/backports/host/sensorkit-names`: one process links the port's object and prints what the port
defines, a second links a reader that opens the host's framework and prints what it holds, and a
comparator puts the two side by side. The two are different sources by construction - the first is
this repository's object, the second is Apple's own dylib - so a value that were wrong in the port
would have to be wrong in Apple's framework to pass.

**The two families have DIFFERENT value shapes, and a facts file that said "the value" would be hiding
that.** The 29 category keys each hold **the string equal to the constant's own name**:
`SRDeviceUsageCategoryBooks` holds `"SRDeviceUsageCategoryBooks"`. The ten sensor constants hold
**identifiers**: `SRSensorAccelerometer` holds `"com.apple.SensorKit.motion.accelerometer"`,
`SRSensorPedometerData` holds `"com.apple.SensorKit.pedometer.data"`, and so on. So the category family
restates its own names and the sensor family names a thing, and a reader that assumed either shape for
the other family would have written nonsense - the all-wrong plant in the harness is a check that the
comparison is not shape-blind.

**Two instrument facts, and both cost a round.**

  * **These are `const` object-pointer VARIABLES, not functions.** `dlsym` returns the ADDRESS OF THE
    VARIABLE, so the result is dereferenced once. Read straight through it is a pointer to a pointer,
    and the first attempt took SIGBUS - the ImageIO trap, which is why the reader carries a comment
    saying so.
  * **They are not classes.** `SRSensorAccelerometer` and its nine siblings are `SR_EXTERN SRSensor const
    ... API_AVAILABLE(ios(14.0)) API_UNAVAILABLE(watchos, macos)`, an `NSString` constant, and this
    registry's own row says `kind=constant`. Asking the runtime for a class of that name answers 0 of 10
    and says nothing at all about the name; the dlsym path answers all ten with their values.

**What is NOT measured.** What an iOS 14 device's SensorKit holds. No device has been asked and no
emulator run has been made, and the two could differ; the guest measurement is owed, and no row in
`registry/SensorKit/ios14.json` is a claim about a device. What IS measured here, for all 39: the host's
SensorKit exports the name, and the value it holds is the one this package defines.

**The reader's control** is `kCFAllocatorDefault`, a CoreFoundation constant VARIABLE read by the same
dlsym-and-deref path, so a reader that had the path wrong would be caught by the control rather than
believed: it prints `matches the host's own symbol`. The comparator's own control is an empty
`HOST` file, which must be red - a comparison of nothing is not a comparison.

Open source checked: swift-corelibs-foundation 6.x - not used. What is carried is Apple's own
SensorKit surface, which no permitted project implements, and the values are Apple's own; the only
honest source for them is Apple's framework.
