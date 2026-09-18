# UIFeedbackGenerator

Introduced in iOS 10.0. Reconnaissance only - no implementation yet. The question
this answers is whether the iPhone 4S can vibrate at a chosen strength, and
whether what it produces can pass for the haptics the class stands for.

Sources: CoreMedia of the armv7 cache of iOS 6.0; the device tree and the
accelerometer of an iPhone4,1 running 6.1.3.

## The vibrator is reachable, and it takes a strength

CoreMedia 6.0 exports a whole vibrator interface: `FigVibratorInitialize`,
`FigVibratorIsVibratorAvailable`, `FigVibratorGetMinMaxDurations`,
`FigVibratorStartOneShot`, `FigVibratorStartRepeating`,
`FigVibratorPlayVibration`, `FigVibratorPlayVibrationWithDictionary`,
`FigVibratorStop`, `FigVibratorShutdown`, with the parameter keys
`kFigVibratorParamKey_Intensity`, `_OnDuration`, `_OffDuration`, `_Period`,
`_TotalDuration` and `_VibePattern`.

`FigVibratorStartOneShot` takes the strength as a float and refuses it outside
`[0, 1]` before doing anything else. It reaches the hardware like this:

- the strength becomes `(int32)(intensity * 65536)` - 16.16 fixed point - under
  the key `intensity` of a dictionary of its own;
- that dictionary is element 0 of a four element array, element 1 is the on
  duration in milliseconds, element 2 is `kCFBooleanFalse` (the off phase carries
  no strength) and element 3 is the off duration in milliseconds, both clamped
  to at least 1;
- the array goes under the key `hertz_millisecs`, beside `repeat` holding a
  boolean, and the pair is written with `IORegistryEntrySetCFProperties` to the
  IOService found by `IOServiceNameMatching("vibrator")`.

`FigVibratorPlayVibrationWithDictionary` reads `Intensity`, `VibePattern`,
`OnDuration`, `OffDuration`, `Period` and `TotalDuration` as CFNumbers, clamps
the intensity into `[0, 1]` the same way, and defaults to on 0.4 s, off 0.1 s,
period 0.5 s, total 0.5 s and **intensity 0.85** when a key is missing. A
`VibePattern` array replaces the durations.

None of this needs a daemon: the properties are written straight to the
IORegistry entry.

## The hardware says the strength is an amplitude

The `vibrator` node of the iPhone4,1 device tree:

| property | bytes | meaning |
|---|---|---|
| `device_type` | `pwm` | driven by a PWM codec; its parent node is `codec-pwm` |
| `intensity-config` | `ampl` | the strength is applied as an **amplitude** |
| `default-hz` | `0xaf` | 175 Hz |
| `enable-ms` | `0x64` | 100 ms |

## Measured on the phone

Writing the properties directly and reading the accelerometer at 100 Hz on the
iPhone4,1, as the RMS of the acceleration magnitude while the motor runs against
the same measure while it is still. Two runs, agreeing to within 4%:

| intensity | 16.16 value | still | running | ratio |
|---|---|---|---|---|
| 1.00 | 65536 | 0.0025 | 0.2532 | 100 |
| 0.75 | 49152 | 0.0029 | 0.2226 | 76 |
| 0.50 | 32768 | 0.0036 | 0.1396 | 39 |
| 0.25 | 16384 | 0.0032 | 0.0605 | 19 |
| 0.12 | 7864 | 0.0025 | 0.0277 | 11 |
| 0.08 | 5242 | 0.0025 | 0.0184 | 7 |
| 0.04 | 2621 | 0.0028 | 0.0093 | 3.3 |
| 0.02 | 1310 | 0.0027 | 0.0054 | 2.0 |
| 0.01 | 655 | 0.0026 | 0.0036 | 1.4 |
| 0.00 | 0 | 0.0033 | 0.0026 | 1.0 |

The strength is honoured, continuously and monotonically. It is close to linear
up to 0.5 and saturates above it - the last doubling, 0.5 to 1.0, buys 1.8 times
the amplitude, not twice. Zero is silence. Below about 0.02 the motor no longer
rises out of the noise, so the usable floor is 0.02 to 0.03.

## What it cannot do

It is an eccentric rotating mass, not a Taptic Engine, and it has to spin up.
At full strength, against the length of the pulse:

| on time | peak deviation |
|---|---|
| 20 ms | 0.0040 g - nothing, the motor never starts |
| 40 ms | 0.1461 g |
| 60 ms | 0.1878 g |
| 100 ms | 0.2684 g |
| 150 ms | 0.3380 g |
| 250 ms | 0.3586 g |
| 400 ms | 0.3856 g |

A pulse shorter than about 40 ms produces no movement at all, and full amplitude
needs upwards of 200 ms - which is what `enable-ms = 100` in the device tree is
about. So the crisp tap that `UIImpactFeedbackGenerator` and
`UISelectionFeedbackGenerator` stand for cannot be produced on this hardware.
What can be produced is a buzz of a chosen strength and length.
