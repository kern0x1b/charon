# The version of the system and the activities of a process, iOS 7 and 8

Source: the host's own Foundation, macOS 27, through the differential run of
`tests/backports/host/foundation2/run.sh`; the device test holds iOS 6 to the same records.

## The version

`-operatingSystemVersion` answers the three numbers of the release the process runs on - on the device the
`ProductVersion` of `/System/Library/CoreServices/SystemVersion.plist`, 6.1.3 as 6, 1, 3 and 6.0 as 6, 0, 0,
a missing part being 0. The differential compares the backport's answer on the host with the host's own.

`-isOperatingSystemAtLeastVersion:` compares the three numbers in order, major first, and answers YES
when the system is the asked version or later: all 27 versions one below, equal to and one above the
current one in each of the three places answer as the host's do. `{0, 0, 0}` is always reached,
`{NSIntegerMax, 0, 0}` never, and a negative minor number such as `{current major, -5, 99}` is reached,
because the minor number decides before the patch number is looked at.

## Activities

`-beginActivityWithOptions:reason:` answers a token that conforms to `NSObject` for every option,
including bits no option names, and for a nil or empty reason too; `-endActivity:` takes the token back,
and takes nil or an object that is no activity without complaint. Ending one token twice logs a warning,
as the host's does. `-performActivityWithOptions:reason:usingBlock:` runs the block once and ends the
activity after it, but raises `NSInvalidArgumentException` for a nil or empty reason before running
anything - the one place the three methods refuse a reason.

On iOS 7 and later an activity can hold a power assertion: `NSActivityIdleSystemSleepDisabled` and
`NSActivityIdleDisplaySleepDisabled` keep the device or its display awake while it lasts. iOS 6 has no such
assertion for a process to take - the idle timer of `UIApplication` decides - so the backport's activity
keeps nothing awake and says so once in the log when either option is asked for. Everything else an
activity does is what the host's does, which is why `-beginActivityWithOptions:reason:` and
`-endActivity:` are `inert` and `-performActivityWithOptions:reason:usingBlock:` is `implemented`.
